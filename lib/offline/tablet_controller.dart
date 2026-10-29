import 'dart:convert';
import '../config.dart';
import '../services/lab_network_gate.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'farm_cache.dart';
import 'foundation_api.dart';
import 'local_operator_session.dart';
import 'offline_database.dart';
import 'outbox.dart';
import 'outbox_transport.dart';
import 'terrain_store.dart';
import 'sync_coordinator.dart';
import 'package:http/http.dart' as http;
import '../services/permission_contract.dart';

class TabletController extends ChangeNotifier {
  TabletController({required this.api,required this.secrets,this.transportClient,
    bool? automaticSyncEnabled,Stream<bool?> Function()? networkChanges,
    this.cacheOpener=openAndroidFarmDatabase,DateTime Function()? clock,
    EnvironmentConfig? configuration, LabNetworkGate? labGate})
      : _automaticSyncRequested=automaticSyncEnabled??true,
        _configuration=configuration??Config.current, _labGate=labGate??LabNetworkGate.instance,
        networkChanges=networkChanges ?? ((configuration??Config.current).isLab
          ? () => (labGate??LabNetworkGate.instance).serverAvailability(configuration??Config.current)
          : androidNetworkChanges),
        clock=clock??DateTime.now {
    if(_configuration.isLab) _labGate.addListener(_labIsolationChanged);
  }
  final FoundationApi api;
  final OperatorSecretStore secrets;
  final http.Client Function()? transportClient;
  final bool _automaticSyncRequested;
  final EnvironmentConfig _configuration;
  final LabNetworkGate _labGate;
  bool get automaticSyncEnabled => _automaticSyncRequested &&
    (!_configuration.isLab || _labGate.isApprovedFor(_configuration));
  void _labIsolationChanged() {
    if(_disposed) return;
    sync?.setForeground(automaticSyncEnabled && _foreground && !knownDeviceRevoked && !recovering);
    _notify();
  }
  final Stream<bool?> Function() networkChanges;
  final Future<FarmCache> Function({required int farmId,required Uri server}) cacheOpener;
  final DateTime Function() clock;
  bool knownDeviceRevoked=false;
  bool recovering=false;
  SyncCoordinator? sync;
  bool _foreground=true;
  FarmCache? cache;
  LocalOperatorSessions? operators;
  int? farmId,deviceId,generation;
  List<Map<String,dynamic>> profiles=[];
  String? selectedName;
  OutboxTransport? transport;
  List<OutboxEntry> outboxRows=[];
  int outboxOffset=0;
  Future<void> showOutboxPage(int offset) async {
    if(offset<0) return;
    outboxOffset=offset;await refreshOutbox();
  }
  Future<void>? _cacheRefresh;
  bool _disposed=false;
  int _lockEpoch=0;
  int? _renewalUserId;
  DateTime? _lastGrantCheck;
  OnlineOperatorIdentity? _checkedIdentity;
  Future<void>? _grantRenewal;
  String? authorizationStatus;
  Timer? _inactivityTimer;
  DateTime? _lastActivityAt;
  DateTime? _inactivityDeadline;
  bool checkInactivity() {
    final last=_lastActivityAt, deadline=_inactivityDeadline;
    if(_disposed || last==null || deadline==null) return false;
    final now=clock().toUtc();
    if(now.isBefore(last) || !now.isBefore(deadline)) {
      api.personal=null;
      lock();
      return true;
    }
    return false;
  }
  void _armInactivityTimer() {
    _inactivityTimer?.cancel();
    final deadline=_inactivityDeadline;
    if(deadline==null || _disposed) return;
    _inactivityTimer=Timer(deadline.difference(clock().toUtc()),() {
      if(!checkInactivity()) _armInactivityTimer();
    });
  }
  void userActivity() {
    if(_disposed || !_foreground || checkInactivity() ||
        (operators?.session==null && api.personal?.role!='OPERATEUR')) return;
    _lastActivityAt=clock().toUtc();
    _inactivityDeadline=_lastActivityAt!.add(const Duration(minutes:5));
    _armInactivityTimer();
  }
  /// Read-only observation of existing lifecycle guards.
  int get sessionEpoch => _lockEpoch;
  bool get isDisposed => _disposed;
  void _notify() { if(!_disposed) notifyListeners(); }
  @override
  void dispose() {
    if(_configuration.isLab) _labGate.removeListener(_labIsolationChanged);
    _inactivityTimer?.cancel();
    _lockEpoch++;
    api.invalidatePendingPersonalWork();
    operators?.lock();
    sync?.removeListener(_notify);sync?.dispose();
    transport?.api.close();
    _disposed=true;
    super.dispose();
  }
  String get sessionTransitionLabel {
    final profile=operators?.session;
    if(knownDeviceRevoked) return 'Dispositif révoqué — saisie bloquée';
    if(profile!=null) {
      if(!profile.grant.permits('can_create_terrain_operation',clock())) return 'Profil déverrouillé — autorisation expirée';
      return profile.grant.hasFineContract
        ? 'Profil déverrouillé — droits individuels signés, saisie selon permission'
        : 'Profil déverrouillé — consultation et synchronisation disponibles ; reconnectez-vous pour renouveler les droits de saisie';
    }
    if(farmId!=null) { return profiles.isEmpty ? 'Dispositif préparé — profil personnel à préparer'
      : 'Profils personnels préparés — déverrouillage par PIN requis'; }
    return api.personal==null ? 'Connexion HTTP personnelle requise'
      : 'Session HTTP personnelle — dispositif à préparer explicitement';
  }
  void _checkPreparation(int epoch, OnlineOperatorIdentity? identity, {FarmCache? preparedCache,
      LocalOperatorSessions? preparedOperators}) {
    if(_disposed || epoch!=_lockEpoch || !identical(identity,api.personal) ||
        (preparedCache!=null && !identical(preparedCache,cache)) ||
        (preparedOperators!=null && !identical(preparedOperators,operators))) {
      throw StateError('La session ou le dispositif a changé. Recommencer explicitement.');
    }
  }
  String get _contextKey=>'tablet_context_${Uri.encodeComponent(api.baseUrl)}';

  Future<void> initialize() async {
    final epoch=_lockEpoch;
    final encoded=await secrets.read(_contextKey);
    if(_disposed || epoch!=_lockEpoch) throw StateError('Initialisation interrompue.');
    if(encoded==null) return;
    final context=jsonDecode(encoded) as Map<String,dynamic>;
    final identity=await api.deviceIdentity.publicIdentity();
    if(_disposed || epoch!=_lockEpoch) throw StateError('Initialisation interrompue.');
    if(identity['installation_uuid']!=context['installation_uuid']) {
      throw StateError('Cette préparation appartient à une autre installation.');
    }
    knownDeviceRevoked=context['revoked']==true;
    await _openFarm(context['farm_id'] as int,context['device_id'] as int,context['generation'] as int);
  }

  Future<void> _openFarm(int farm,int device,int writeGeneration) async {
    lock();
    if(farmId!=null && farmId!=farm) throw StateError('Cette tablette est préparée pour une autre exploitation.');
    final epoch=_lockEpoch;
    final opened=await cacheOpener(farmId:farm,server:Uri.parse(api.baseUrl));
    if(_disposed || epoch!=_lockEpoch) throw StateError('Préparation interrompue par un verrouillage.');
    cache=opened;
    farmId=farm;deviceId=device;generation=writeGeneration;
    if(cache is OutboxStore && (transport==null || transport!.api.deviceId!=device ||
        transport!.api.farmId!=farm || transport!.api.generation!=writeGeneration)) {
      transport?.api.close();
      sync?.removeListener(_notify);sync?.dispose();
      transport=OutboxTransport(store:cache! as OutboxStore,api:DeviceOutboxApi(
        baseUrl:api.baseUrl,identity:api.deviceIdentity,deviceId:device,farmId:farm,generation:writeGeneration,
        client:transportClient?.call()));
      if(cache is SyncStateStore) {
        final engine=transport!;
        sync=SyncCoordinator(store:cache! as SyncStateStore,networkChanges:networkChanges,clock:clock,
          synchronize:() async {
            // Originals are transmitted first, independently of personal renewal.
            try {
              await engine.syncOnce();
              await _refreshPreparedRights(engine.api);
              return true;
            } finally {
              if(!_disposed) {
                await refreshOutbox();
                await renewPersonalAuthorization();
              }
            }
          });
        sync!.addListener(_notify);
        await sync!.refreshSummary();
        if(_disposed || epoch!=_lockEpoch) throw StateError('Préparation interrompue.');
        if(automaticSyncEnabled && !knownDeviceRevoked) sync!.setForeground(_foreground);
      }
    }
    operators=LocalOperatorSessions(store:secrets,namespace:Uri.encodeComponent(api.baseUrl),
      farmId:farm,deviceId:device,generation:writeGeneration,clock:clock);
    final restored=await cache!.operatorProfiles();
    if(_disposed || epoch!=_lockEpoch) throw StateError('Préparation interrompue.');
    profiles=restored;
    _notify();
  }

  void lock() {_inactivityTimer?.cancel();_inactivityTimer=null;_lastActivityAt=null;_inactivityDeadline=null;outboxOffset=0;_lockEpoch++;api.invalidatePendingPersonalWork();operators?.lock();selectedName=null;outboxRows=[];_notify();}

  Future<void> _refreshPreparedRights(DeviceOutboxApi deviceApi) async {
    final states=await deviceApi.permissionStates();
    if(_disposed || !identical(transport?.api,deviceApi)) return;
    for(final profile in profiles) {
      final user=profile['user_id'] as int;
      final matches=states.where((state)=>state['user_id']==user).toList();
      var changed=matches.length!=1;
      try {
        final stored=await api.loadLocalGrant(farmId:farmId!,userId:user);
        if(_disposed || !identical(transport?.api,deviceApi)) return;
        final state=matches.single;
        if(state['rights_version'] is int && (state['rights_version'] as int)<stored.rightsVersion) continue;
        final permissions=state['permissions'];
        changed=state['active']!=true || state['rights_version']!=stored.rightsVersion ||
          permissions is! List || !setEquals(stored.finePermissions?.permissions,permissions.cast<String>().toSet());
      } catch (_) {changed=true;}
      if(changed) {
        // Denial only: this response can never issue a grant or open a PIN.
        if(operators?.session?.userId==user) lock();
        await api.requirePersonalRevalidation(farmId!,user);
        _lastGrantCheck=null;
      }
    }
  }

  void setForeground(bool value) {
    _foreground=value;
    // Background time counts; Android may suspend timers, so check before resume.
    if(value && !checkInactivity()) _armInactivityTimer();
    if(automaticSyncEnabled) sync?.setForeground(value && !knownDeviceRevoked && !recovering);
  }

  Future<void> signIn(String username,String password) async {
    lastCompleteCacheRefresh=null;
    lock();
    final epoch=_lockEpoch;
    final identity=await api.logIn(username,password,expectedFarm:farmId);
    _checkPreparation(epoch,identity);
    offlinePolicyEnabled=identity.capabilities['offline_policy_enabled']==true;
    _renewalUserId=identity.role=='OPERATEUR'?identity.userId:null;
    _lastGrantCheck=null;
    authorizationStatus=null;
    if(api.personal?.role=='OWNER' && deviceId!=null) await inspectDeviceStatus();
    _notify();
    if(automaticSyncEnabled && identity.role=='OPERATEUR' && sync!=null) {
      unawaited(sync!.trigger());
    }
  }

  /// A bounded personal check, separate from the device's immutable outbox.
  /// Never restores credentials, opens a PIN or renews a colleague's profile.
  Future<void> renewPersonalAuthorization() {
    if(_grantRenewal!=null) return _grantRenewal!;
    final task=_renewPersonalAuthorization().whenComplete(()=>_grantRenewal=null);
    _grantRenewal=task;
    return task;
  }

  Future<void> _renewPersonalAuthorization() async {
    final current=operators?.session;
    final user=current?.userId ?? _renewalUserId;
    if(_disposed || knownDeviceRevoked || recovering || user==null || cache==null ||
        !profiles.any((profile)=>profile['user_id']==user)) {return;}
    final identity=api.personal;
    if(identity==null || identity.role!='OPERATEUR' || identity.userId!=user || identity.farmId!=farmId) {
      authorizationStatus='Reconnectez votre compte personnel pour renouveler vos droits. Les opérations conservées restent transmissibles.';
      _notify();return;
    }
    final now=clock().toUtc();
    if(identical(_checkedIdentity,identity) && _lastGrantCheck!=null &&
        now.difference(_lastGrantCheck!)<const Duration(minutes:5)) {return;}
    _checkedIdentity=identity;_lastGrantCheck=now;
    var epoch=_lockEpoch;
    final preparedCache=cache, preparedOperators=operators;
    bool sameContext() => !_disposed && !knownDeviceRevoked && !recovering && epoch==_lockEpoch &&
      identical(cache,preparedCache) && identical(operators,preparedOperators);
    bool same() => sameContext() && identical(api.personal,identity);
    void restrict() {
      if(!sameContext() || (api.personal!=null && !identical(api.personal,identity))) return;
      if(operators?.session?.userId==user) {
        operators!.lock();_lockEpoch++;epoch=_lockEpoch;selectedName=null;outboxRows=[];
      }
      _notify();
    }
    bool changed=false;
    void observe(Map<String,dynamic> caps) {
      if(!same()) throw StateError('Session personnelle modifiée.');
      final member=caps['membership'], raw=caps['permission_contract'];
      if(caps['offline_policy_enabled']!=true || member is! Map ||
          member['version'] is! int || raw is! Map<String,dynamic>) {
        throw const FoundationApiException(403);
      }
      final rights=PermissionContract.decode(raw,userId:user,farmId:farmId!,
        role:'OPERATEUR',rightsVersion:member['version'] as int);
      final open=operators?.session;
      if(open!=null && open.userId==user && (open.grant.rightsVersion!=rights.rightsVersion ||
          !setEquals(open.grant.finePermissions?.permissions,rights.permissions))) {
        changed=true;restrict();
      }
    }
    try {
      final caps=await api.personalCapabilities();
      if(!same()) return;
      observe(caps);
      // Persist a denial before any renewal which might fail after known changes.
      if(changed) {
        await api.requirePersonalRevalidation(farmId!,user);
        if(!same()) return;
      }
      final member=caps['membership'] as Map;
      final device=caps['primary_device'];
      if(device is! Map || device['id']!=deviceId || caps['write_generation']!=generation) {
        throw const FoundationApiException(403);
      }
      var needsRenewal=true;
      try {
        final stored=await api.loadLocalGrant(farmId:farmId!,userId:user);
        if(!same()) return;
        final rightsDiffer=stored.rightsVersion!=member['version'] ||
          !setEquals(stored.finePermissions?.permissions,
            PermissionContract.decode(caps['permission_contract'] as Map<String,dynamic>,
              userId:user,farmId:farmId!,role:'OPERATEUR',rightsVersion:member['version'] as int).permissions);
        if(rightsDiffer) {
          changed=true;restrict();
          await api.requirePersonalRevalidation(identity.farmId,user);
          if(!same()) return;
        }
        needsRenewal=changed || !stored.hasFineContract ||
          stored.expiresAt.difference(now)<=const Duration(days:6);
      } catch (_) { if(!same()) return; }
      if(!needsRenewal) {authorizationStatus='Droits personnels vérifiés.';_notify();return;}
      final grant=await api.provisionGrant(requireFine:true,onCapabilities:(caps) async {
        observe(caps);
        if(changed) await api.requirePersonalRevalidation(identity.farmId,user);
      },onVerifiedGrant:(grant) async {
        if(!same()) throw StateError('Session personnelle modifiée.');
        final open=operators?.session;
        if(open!=null && (open.grant.rightsVersion!=grant.rightsVersion ||
            !setEquals(open.grant.finePermissions?.permissions,grant.finePermissions?.permissions))) {
          changed=true;restrict();
          await api.requirePersonalRevalidation(identity.farmId,user);
        }
      });
      if(!same()) return;
      if(grant.farmId!=farmId || grant.deviceId!=deviceId || grant.generation!=generation || grant.userId!=user) {
        throw const FoundationApiException(403);
      }
      await preparedCache!.saveOperatorProfile(grant,identity.capabilities['membership']?['username'] as String? ?? 'Opérateur');
      if(!same()) return;
      if(!changed && operators?.session?.userId==user) operators!.replaceAuthorization(grant);
      profiles=await preparedCache.operatorProfiles();
      if(!same()) return;
      authorizationStatus=operators?.session==null
        ? 'Droits renouvelés. Ouvrez votre profil avec votre PIN.' : 'Droits personnels renouvelés.';
      _notify();
    } catch(error) {
      if(!sameContext() || (api.personal!=null && !identical(api.personal,identity))) return;
      final denied=error is FoundationApiException && {401,403}.contains(error.status);
      if(denied || error is StateError) {
        restrict();
        try {await api.requirePersonalRevalidation(identity.farmId,user);} catch (_) {}
        if(_disposed || epoch!=_lockEpoch) return;
        authorizationStatus='Renouvellement refusé. Reconnectez votre compte pour vérifier vos droits ; les opérations restent conservées.';
      } else {
        authorizationStatus='Renouvellement indisponible. Vos opérations restent conservées ; nouvelle tentative automatique.';
      }
      _notify();
    }
  }

  Future<void> inspectDeviceStatus() async {
    if(api.personal?.role!='OWNER' || api.personal?.farmId!=farmId || deviceId==null) {
      throw const FoundationApiException(403);
    }
    final listing=await api.request('GET','/devices/');
    final devices=listing['results'];
    if(devices is! List) throw StateError('Liste des appareils invalide.');
    final matches=devices.whereType<Map>().where((d)=>d['id']==deviceId).toList();
    if(matches.length!=1) throw StateError('Appareil introuvable dans cette exploitation.');
    if(matches.single['status']=='REVOKED') {
      knownDeviceRevoked=true;lock();sync?.setForeground(false);
      final encoded=await secrets.read(_contextKey);
      if(encoded==null) throw StateError('Préparation de tablette manquante.');
      final context=Map<String,dynamic>.from(jsonDecode(encoded) as Map);
      context['revoked']=true;
      await secrets.write(_contextKey,jsonEncode(context));
      _notify();
    }
  }

  Future<int> recoverPending(String reason) async {
    if(recovering) throw StateError('Une récupération est déjà en cours.');
    final owner=api.personal;
    if(owner==null || owner.role!='OWNER' || owner.farmId!=farmId || deviceId==null || cache is! OutboxStore) {
      throw const FoundationApiException(403);
    }
    final motif=reason.trim();
    if(motif.length<3 || motif.length>10000) throw StateError('Un motif explicite est requis.');
    recovering=true;sync?.setForeground(false);_notify();
    try {
      await sync?.waitForIdle();
      await inspectDeviceStatus();
      if(!knownDeviceRevoked) throw StateError('La récupération concerne uniquement une tablette révoquée.');
      final store=cache! as OutboxStore;
      final entries=await store.recoveryBatch();
      if(entries.isEmpty) return 0;
      if(!identical(owner,api.personal)) throw const FoundationApiException(401);
      final result=await api.signedRequest('/offline/recovery/',deviceId:deviceId!,purpose:'RECOVER',
        data:{'reason':motif,'operations':entries.map((e)=>e.declaration).toList()});
      final raw=result['receipts'];
      if(raw is! List || raw.length!=entries.length) throw StateError('Reçus de récupération incomplets.');
      final receipts=raw.map((r)=>Map<String,dynamic>.from(r as Map)).toList();
      final ids=entries.map((e)=>e.operationId).toSet();
      final received=receipts.map((r)=>r['client_operation_id']).toSet();
      if(received.length!=ids.length || !received.containsAll(ids)) throw StateError('Reçus de récupération hors contexte.');
      await store.acceptReceipts(receipts);
      if(cache is SyncStateStore) await (cache! as SyncStateStore).recordSyncSuccess(clock().toUtc());
      await sync?.refreshSummary();
      return entries.length;
    } finally {
      recovering=false;
      if(automaticSyncEnabled && !knownDeviceRevoked) sync?.setForeground(_foreground);
      _notify();
    }
  }

  bool offlinePolicyEnabled=false;
  DateTime? lastCompleteCacheRefresh;

  Future<void> enableOfflinePolicy() async {
    final owner=api.personal;
    if(owner==null || owner.role!='OWNER' || owner.farmId!=farmId || deviceId==null || knownDeviceRevoked) {
      throw const FoundationApiException(403);
    }
    final epoch=_lockEpoch;
    final result=await api.request('POST','/offline-policy/enable/');
    _checkPreparation(epoch,owner);
    if(result['offline_policy_enabled']!=true) throw StateError('Activation hors ligne non confirmée.');
    offlinePolicyEnabled=true;
    _notify();
  }

  Future<void> preparePrimaryTablet() async {
    final owner=api.personal;
    if(owner==null || owner.role!='OWNER') throw const FoundationApiException(403);
    if(farmId!=null && owner.farmId!=farmId) throw StateError('Cette session appartient à une autre exploitation.');
    final epoch=_lockEpoch, farm=farmId, currentDevice=deviceId, currentGeneration=generation;
    void check() {
      _checkPreparation(epoch,owner);
      if(farmId!=farm || deviceId!=currentDevice || generation!=currentGeneration) {
        throw StateError('Le contexte de tablette a changé.');
      }
    }
    final local=await api.deviceIdentity.publicIdentity();
    check();
    final listing=await api.request('GET','/devices/');
    check();
    final devices=List<Map<String,dynamic>>.from((listing['results'] as List).map((r)=>Map<String,dynamic>.from(r as Map)));
    Map<String,dynamic>? device;
    for(final candidate in devices) {
      if(candidate['installation_uuid']==local['installation_uuid']) device=candidate;
    }
    device ??= await api.registerInstallation('Tablette exploitation');
    check();
    if(device['status']=='REVOKED') throw StateError('Tablette révoquée : récupération explicite requise.');
    if(device['status']=='PENDING') {
      // Replacement never happens as a side effect of preparation.
      if(devices.any((d)=>d['status']=='ACTIVE' && d['is_primary_writer']==true)) {
        throw StateError('Une autre tablette est principale. Son remplacement doit être décidé explicitement.');
      }
      device=await api.signedRequest('/devices/${device['id']}/activate/',deviceId:device['id'] as int,purpose:'ACTIVATE');
      check();
    }
    if(device['status']!='ACTIVE' || device['is_primary_writer']!=true) throw StateError('Tablette principale active requise.');
    final capabilities=await api.request('GET','/me/capabilities/');
    check();
    offlinePolicyEnabled=capabilities['offline_policy_enabled']==true;
    final context={'farm_id':owner.farmId,'device_id':device['id'],
      'generation':capabilities['write_generation'],'installation_uuid':local['installation_uuid']};
    await secrets.write(_contextKey,jsonEncode(context));
    check();
    await _openFarm(owner.farmId,device['id'] as int,capabilities['write_generation'] as int);
  }

  Future<void> prepareOperator(String pin) async {
    final personal=api.personal;
    if(personal==null || personal.role!='OPERATEUR' || personal.farmId!=farmId || cache==null || operators==null ||
        operators!.farmId!=farmId || operators!.deviceId!=deviceId || operators!.generation!=generation) {
      throw StateError('Préparer la tablette et connecter un opérateur personnel.');
    }
    final epoch=_lockEpoch, preparedCache=cache!, preparedOperators=operators!;
    final farm=farmId, device=deviceId, writeGeneration=generation;
    void check() {
      _checkPreparation(epoch,personal,preparedCache:preparedCache,preparedOperators:preparedOperators);
      if(farm!=farmId || device!=deviceId || writeGeneration!=generation) {
        throw StateError('Le contexte de tablette a changé.');
      }
    }
    final grant=await api.provisionGrant();
    check();
    if(grant.farmId!=farmId || grant.deviceId!=deviceId || grant.generation!=generation) {
      throw StateError('La préparation de tablette doit être actualisée par le propriétaire.');
    }
    final pinKey='operator_pin_${Uri.encodeComponent(api.baseUrl)}_${grant.farmId}_${grant.deviceId}_${grant.userId}';
    final existing=await secrets.read(pinKey);
    check();
    if(existing==null) {
      await preparedOperators.enroll(grant,pin);
    } else if(!await preparedOperators.unlock(grant,pin)) {
      throw StateError('PIN incorrect ou temporairement bloqué.');
    }
    preparedOperators.lock();
    check();
    final member=personal.capabilities['membership'] as Map<String,dynamic>;
    await preparedCache.saveOperatorProfile(grant,member['username'] as String);
    check();
    final preparedProfiles=await preparedCache.operatorProfiles();
    check();
    profiles=preparedProfiles;
    _notify();
  }

  Future<void> preparePersonalCode(String code) async {
    final identity=api.personal;
    if(identity==null || identity.role!='OPERATEUR' || identity.farmId!=farmId ||
       cache==null || operators==null || knownDeviceRevoked) {
      throw StateError('Demandez au propriétaire de préparer cette tablette.');
    }
    final epoch=_lockEpoch,preparedCache=cache!,preparedOperators=operators!;
    final grant=await api.provisionGrant(requireFine:true);
    _checkPreparation(epoch,identity,preparedCache:preparedCache,preparedOperators:preparedOperators);
    final version=identity.capabilities['credential_version'];
    if(version is! int || grant.credentialVersion!=version || grant.userId!=identity.userId ||
       grant.deviceId!=deviceId || grant.generation!=generation || grant.farmId!=farmId) {
      throw StateError('La préparation de cet accès doit être actualisée.');
    }
    await preparedOperators.enrollPersonalCode(grant,code,authenticatedCredentialVersion:version);
    _checkPreparation(epoch,identity,preparedCache:preparedCache,preparedOperators:preparedOperators);
    await preparedCache.saveOperatorProfile(grant,identity.capabilities['membership']['username'] as String);
    _checkPreparation(epoch,identity,preparedCache:preparedCache,preparedOperators:preparedOperators);
    profiles=await preparedCache.operatorProfiles();
    _checkPreparation(epoch,identity,preparedCache:preparedCache,preparedOperators:preparedOperators);
    await unlockProfile(grant.userId,identity.capabilities['membership']['username'] as String,code,personalCode:true);
  }

  Future<void> unlockProfile(int user,String name,String pin,{bool personalCode=false}) async {
    lock();
    if(knownDeviceRevoked) throw StateError('Tablette révoquée : récupération par le propriétaire requise.');
    final epoch=_lockEpoch;
    if(farmId==null || operators==null) throw StateError('Tablette non préparée.');
    final grant=await api.loadLocalGrant(farmId:farmId!,userId:user);
    if(_disposed || epoch!=_lockEpoch) throw StateError('La tablette a été verrouillée.');
    final unlocked=personalCode ? await operators!.unlockPersonalCode(grant,pin) : await operators!.unlock(grant,pin);
    if(!unlocked) throw StateError(personalCode?'Code incorrect ou accès temporairement bloqué.':'PIN incorrect ou temporairement bloqué.');
    if(_disposed || epoch!=_lockEpoch) {
      operators!.lock();
      throw StateError('La tablette a été verrouillée.');
    }
    // A PIN authenticates local work only. It never transfers another user's
    // HTTP credentials or creates a new HTTP login for the unlocked employee.
    final httpIdentity=api.personal;
    if(httpIdentity!=null && (httpIdentity.userId!=grant.userId ||
        httpIdentity.farmId!=grant.farmId || httpIdentity.role!='OPERATEUR')) {
      api.invalidatePendingPersonalWork();
      api.personal=null;
      authorizationStatus='Reconnectez-vous avec votre compte pour les actions en ligne.';
    }
    selectedName=name;
    userActivity();
    _renewalUserId=user;
    await refreshOutbox();
    _notify();
  }

  Future<void> refreshOutbox() async {
    final current=operators?.session;
    if(current==null || cache is! OutboxStore) {outboxRows=[];return;}
    final offset=outboxOffset;
    final rows=await (cache! as OutboxStore).listOutbox(authorId:current.userId,offset:offset);
    if(_disposed || !identical(current,operators?.session) || offset!=outboxOffset) return;
    outboxRows=rows;_notify();
  }

  Future<OutboxEntry> declare({required String entityType,required String operationType,
    required Map<String,dynamic> payload,required DateTime businessOccurredAt,String? operationId,
    String? localEntityId,List<String> dependencies=const [],String expectedServerVersion='',
    Future<void> Function()? project}) async {
    if(knownDeviceRevoked || recovering) throw StateError('Cette tablette ne peut plus créer de déclaration.');
    final current=operators?.session;
    if(current==null || cache is! OutboxStore) throw StateError('Profil personnel ouvert requis.');
    if ({'VENTE_ANIMAUX','VENTE_OEUFS'}.contains(entityType) && operationType=='CREATE' &&
        current.grant.validAt(clock()) && !current.grant.permitsOperation(entityType,operationType,clock())) {
      throw StateError('La vente n’est pas autorisée avec vos permissions actuelles. Reconnectez votre compte ou contactez le propriétaire.');
    }
    final epoch=_lockEpoch, preparedCache=cache;
    bool currentContext() => !_disposed && epoch==_lockEpoch && !knownDeviceRevoked && !recovering &&
      identical(current,operators?.session) && identical(preparedCache,cache) &&
      current.grant.farmId==farmId && current.grant.deviceId==deviceId && current.grant.generation==generation;
    final entry=await (cache! as OutboxStore).enqueue(grant:current.grant,
      isSessionCurrent:currentContext,entityType:entityType,
      operationType:operationType,payload:payload,businessOccurredAt:operationId==null?clock().toUtc():businessOccurredAt,
      operationId:operationId,localEntityId:localEntityId,dependencies:dependencies,
      expectedServerVersion:expectedServerVersion,project:project);
    if(!_disposed && identical(current,operators?.session)) {
      outboxRows=[entry,...outboxRows.where((row)=>row.operationId!=entry.operationId)].take(50).toList();
      _notify();
    }
    await sync?.refreshSummary();
    if(automaticSyncEnabled && sync!=null) unawaited(sync!.trigger());
    return entry;
  }

  Future<void> syncOutbox() async {
    if(knownDeviceRevoked || recovering) throw StateError('Tablette révoquée : récupération explicite requise.');
    if(sync!=null) {await sync!.trigger(manual:true);return;}
    final engine=transport;
    if(engine==null) throw StateError('Tablette non préparée.');
    try {await engine.syncOnce();} finally {if(!_disposed) await refreshOutbox();}
  }

  Future<void> refreshCache({List<String> collections=const ['lots','clients','species','tasks','expense_categories','sales']}) async {
    while(_cacheRefresh!=null) {await _cacheRefresh;}
    final done=Completer<void>();
    _cacheRefresh=done.future;
    try {await _refreshCollections(collections);} finally {
      _cacheRefresh=null;done.complete();
    }
  }

  Future<void> _refreshCollections(List<String> collections) async {
    final personal=api.personal;
    if(personal==null || cache==null || personal.farmId!=farmId) throw const FoundationApiException(401);
    if(collections.length==6) lastCompleteCacheRefresh=null;
    final epoch=_lockEpoch;
    void check() {if(_disposed || epoch!=_lockEpoch || !identical(personal,api.personal)) throw const FoundationApiException(401);}
    for(final collection in collections) {
      var after=0;
      var businessRevision=0;
      await cache!.beginCacheRefresh(collection);
      while(true) {
        check();
        final page=await api.request('GET','/cache-page/?collection=$collection&after=$after&limit=50');
        final revision=page['confirmed_business_revision'];
        if(revision!=null && (revision is! int || revision<0)) {throw StateError('Révision serveur invalide.');}
        if(revision is int && revision>businessRevision) {businessRevision=revision;}
        final rows=(page['results'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
        check();
        await cache!.stageConfirmedPage(collection,rows);
        final next=page['next_cursor'];
        if(next==null) break;
        if(next is! int || next<=after) throw StateError('Page serveur invalide.');
        after=next;
      }
      check();
      await cache!.commitCacheRefresh(collection,taskUserId:personal.role=='OPERATEUR'?personal.userId:null,
        businessRevision:businessRevision);
    }
    check();
    if(collections.length==6) lastCompleteCacheRefresh=clock();
    _notify();
  }

  Future<List<Map<String,dynamic>>> readPage(String collection,{int offset=0,String search=''}) async {
    final session=operators?.session;
    if(session==null || cache==null) throw StateError('Déverrouiller un profil personnel.');
    final rows=cache is TerrainStore && {'clients','tasks','lots','sales','cash'}.contains(collection)
      ? await (cache! as TerrainStore).projectedPage(collection,offset:offset,limit:50,
          taskUserId:collection=='tasks'?session.userId:null,search:search)
      : await cache!.cachedPage(collection,offset:offset,limit:50,
          taskUserId:collection=='tasks'?session.userId:null);
    if(_disposed || !identical(session,operators?.session)) {
      throw StateError('Le profil a été verrouillé pendant la lecture.');
    }
    if(collection=='tasks') {
      return rows.where((row) {
        final task=row['data'] as Map<String,dynamic>;
        return task['assigned_to']==null || task['assigned_to']==session.userId;
      }).toList();
    }
    return rows;
  }
}
