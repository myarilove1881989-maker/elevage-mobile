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
    this.automaticSyncEnabled=true,this.networkChanges=androidNetworkChanges});
  final FoundationApi api;
  final OperatorSecretStore secrets;
  final http.Client Function()? transportClient;
  final bool automaticSyncEnabled;
  final Stream<bool?> Function() networkChanges;
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
    await _openFarm(context['farm_id'] as int,context['device_id'] as int,context['generation'] as int);
  }

  Future<void> _openFarm(int farm,int device,int writeGeneration) async {
    lock();
    if(farmId!=null && farmId!=farm) throw StateError('Cette tablette est préparée pour une autre exploitation.');
    cache=await openAndroidFarmDatabase(farmId:farm,server:Uri.parse(api.baseUrl));
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
        sync=SyncCoordinator(store:cache! as SyncStateStore,networkChanges:networkChanges,
          synchronize:() async {
            await engine.syncOnce();
            if(!_disposed) await refreshOutbox();
            return engine.lastRunContactedServer;
          });
        sync!.addListener(_notify);
        await sync!.refreshSummary();
        if(automaticSyncEnabled) sync!.setForeground(_foreground);
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
    if(automaticSyncEnabled) sync?.setForeground(value);
  }

  Future<void> signIn(String username,String password) async {
    lock();
    await api.logIn(username,password,expectedFarm:farmId);
    _notify();
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
