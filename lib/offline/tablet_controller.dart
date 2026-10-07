import 'dart:convert';
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

class TabletController extends ChangeNotifier {
  TabletController({required this.api,required this.secrets,this.transportClient,
    this.automaticSyncEnabled=true,this.networkChanges=androidNetworkChanges,
    this.cacheOpener=openAndroidFarmDatabase,DateTime Function()? clock}) : clock=clock??DateTime.now;
  final FoundationApi api;
  final OperatorSecretStore secrets;
  final http.Client Function()? transportClient;
  final bool automaticSyncEnabled;
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
  bool _refreshInProgress=false;
  bool _disposed=false;
  int _lockEpoch=0;
  void _notify() { if(!_disposed) notifyListeners(); }
  @override
  void dispose() {
    _lockEpoch++;
    operators?.lock();
    sync?.removeListener(_notify);sync?.dispose();
    transport?.api.close();
    _disposed=true;
    super.dispose();
  }
  String get _contextKey=>'tablet_context_${Uri.encodeComponent(api.baseUrl)}';

  Future<void> initialize() async {
    final encoded=await secrets.read(_contextKey);
    if(encoded==null) return;
    final context=jsonDecode(encoded) as Map<String,dynamic>;
    final identity=await api.deviceIdentity.publicIdentity();
    if(identity['installation_uuid']!=context['installation_uuid']) {
      throw StateError('Cette préparation appartient à une autre installation.');
    }
    knownDeviceRevoked=context['revoked']==true;
    await _openFarm(context['farm_id'] as int,context['device_id'] as int,context['generation'] as int);
  }

  Future<void> _openFarm(int farm,int device,int writeGeneration) async {
    lock();
    if(farmId!=null && farmId!=farm) throw StateError('Cette tablette est préparée pour une autre exploitation.');
    cache=await cacheOpener(farmId:farm,server:Uri.parse(api.baseUrl));
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
            await engine.syncOnce();
            if(!_disposed) await refreshOutbox();
            return engine.lastRunContactedServer;
          });
        sync!.addListener(_notify);
        await sync!.refreshSummary();
        if(automaticSyncEnabled && !knownDeviceRevoked) sync!.setForeground(_foreground);
      }
    }
    operators=LocalOperatorSessions(store:secrets,namespace:Uri.encodeComponent(api.baseUrl),
      farmId:farm,deviceId:device,generation:writeGeneration);
    profiles=await cache!.operatorProfiles();
    _notify();
  }

  void lock() {_lockEpoch++;operators?.lock();selectedName=null;outboxRows=[];_notify();}

  void setForeground(bool value) {
    _foreground=value;
    if(automaticSyncEnabled) sync?.setForeground(value && !knownDeviceRevoked && !recovering);
  }

  Future<void> signIn(String username,String password) async {
    lock();
    await api.logIn(username,password,expectedFarm:farmId);
    if(api.personal?.role=='OWNER' && deviceId!=null) await inspectDeviceStatus();
    _notify();
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

  Future<void> preparePrimaryTablet() async {
    final owner=api.personal;
    if(owner==null || owner.role!='OWNER') throw const FoundationApiException(403);
    final local=await api.deviceIdentity.publicIdentity();
    final listing=await api.request('GET','/devices/');
    final devices=List<Map<String,dynamic>>.from((listing['results'] as List).map((r)=>Map<String,dynamic>.from(r as Map)));
    Map<String,dynamic>? device;
    for(final candidate in devices) {
      if(candidate['installation_uuid']==local['installation_uuid']) device=candidate;
    }
    device ??= await api.registerInstallation('Tablette exploitation');
    if(device['status']=='REVOKED') throw StateError('Tablette révoquée : récupération explicite requise.');
    if(device['status']=='PENDING') {
      // Replacement never happens as a side effect of preparation.
      if(devices.any((d)=>d['status']=='ACTIVE' && d['is_primary_writer']==true)) {
        throw StateError('Une autre tablette est principale. Son remplacement doit être décidé explicitement.');
      }
      device=await api.signedRequest('/devices/${device['id']}/activate/',deviceId:device['id'] as int,purpose:'ACTIVATE');
    }
    if(device['status']!='ACTIVE' || device['is_primary_writer']!=true) throw StateError('Tablette principale active requise.');
    final capabilities=await api.request('GET','/me/capabilities/');
    final context={'farm_id':owner.farmId,'device_id':device['id'],
      'generation':capabilities['write_generation'],'installation_uuid':local['installation_uuid']};
    await secrets.write(_contextKey,jsonEncode(context));
    await _openFarm(owner.farmId,device['id'] as int,capabilities['write_generation'] as int);
  }

  Future<void> prepareOperator(String pin) async {
    final personal=api.personal;
    if(personal==null || personal.role!='OPERATEUR' || cache==null || operators==null) {
      throw StateError('Préparer la tablette et connecter un opérateur personnel.');
    }
    final grant=await api.provisionGrant();
    if(grant.farmId!=farmId || grant.deviceId!=deviceId || grant.generation!=generation) {
      throw StateError('La préparation de tablette doit être actualisée par le propriétaire.');
    }
    final pinKey='operator_pin_${Uri.encodeComponent(api.baseUrl)}_${grant.farmId}_${grant.deviceId}_${grant.userId}';
    if(await secrets.read(pinKey)==null) {
      await operators!.enroll(grant,pin);
    } else if(!await operators!.unlock(grant,pin)) {
      throw StateError('PIN incorrect ou temporairement bloqué.');
    }
    operators!.lock();
    final member=personal.capabilities['membership'] as Map<String,dynamic>;
    await cache!.saveOperatorProfile(grant,member['username'] as String);
    profiles=await cache!.operatorProfiles();
    _notify();
  }

  Future<void> unlockProfile(int user,String name,String pin) async {
    lock();
    if(knownDeviceRevoked) throw StateError('Tablette révoquée : récupération par le propriétaire requise.');
    final epoch=_lockEpoch;
    if(farmId==null || operators==null) throw StateError('Tablette non préparée.');
    final grant=await api.loadLocalGrant(farmId:farmId!,userId:user);
    if(_disposed || epoch!=_lockEpoch) throw StateError('La tablette a été verrouillée.');
    if(!await operators!.unlock(grant,pin)) throw StateError('PIN incorrect ou temporairement bloqué.');
    if(_disposed || epoch!=_lockEpoch) {
      operators!.lock();
      throw StateError('La tablette a été verrouillée.');
    }
    selectedName=name;
    await refreshOutbox();
    _notify();
  }

  Future<void> refreshOutbox() async {
    final current=operators?.session;
    if(current==null || cache is! OutboxStore) {outboxRows=[];return;}
    final rows=await (cache! as OutboxStore).listOutbox(authorId:current.userId);
    if(_disposed || !identical(current,operators?.session)) return;
    outboxRows=rows;_notify();
  }

  Future<OutboxEntry> declare({required String entityType,required String operationType,
    required Map<String,dynamic> payload,required DateTime businessOccurredAt,String? operationId,
    String? localEntityId,List<String> dependencies=const [],String expectedServerVersion='',
    Future<void> Function()? project}) async {
    if(knownDeviceRevoked || recovering) throw StateError('Cette tablette ne peut plus créer de déclaration.');
    final current=operators?.session;
    if(current==null || cache is! OutboxStore) throw StateError('Profil personnel ouvert requis.');
    final entry=await (cache! as OutboxStore).enqueue(grant:current.grant,
      isSessionCurrent:()=>!_disposed && identical(current,operators?.session),entityType:entityType,
      operationType:operationType,payload:payload,businessOccurredAt:businessOccurredAt,
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

  Future<void> refreshCache() async {
    if(_refreshInProgress) throw StateError('Le chargement est déjà en cours.');
    final personal=api.personal;
    if(personal==null || cache==null || personal.farmId!=farmId) throw const FoundationApiException(401);
    _refreshInProgress=true;
    try { for(final collection in ['lots','clients','species','tasks','expense_categories','sales']) {
      var after=0;
      var businessRevision=0;
      await cache!.beginCacheRefresh(collection);
      while(true) {
        if(!identical(personal,api.personal)) throw const FoundationApiException(401);
        final page=await api.request('GET','/cache-page/?collection=$collection&after=$after&limit=50');
        final revision=page['confirmed_business_revision'];
        if(revision!=null && (revision is! int || revision<0)) {throw StateError('Révision serveur invalide.');}
        if(revision is int && revision>businessRevision) {businessRevision=revision;}
        final rows=(page['results'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
        if(!identical(personal,api.personal)) throw const FoundationApiException(401);
        await cache!.stageConfirmedPage(collection,rows);
        final next=page['next_cursor'];
        if(next==null) break;
        if(next is! int || next<=after) throw StateError('Page serveur invalide.');
        after=next;
      }
      await cache!.commitCacheRefresh(collection,taskUserId:personal.role=='OPERATEUR'?personal.userId:null,
        businessRevision:businessRevision);
    } } finally { _refreshInProgress=false; }
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
