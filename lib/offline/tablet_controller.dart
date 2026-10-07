import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'farm_cache.dart';
import 'foundation_api.dart';
import 'local_operator_session.dart';
import 'offline_database.dart';

class TabletController extends ChangeNotifier {
  TabletController({required this.api,required this.secrets});
  final FoundationApi api;
  final OperatorSecretStore secrets;
  FarmCache? cache;
  LocalOperatorSessions? operators;
  int? farmId,deviceId,generation;
  List<Map<String,dynamic>> profiles=[];
  String? selectedName;
  bool _refreshInProgress=false;
  bool _disposed=false;
  void _notify() { if(!_disposed) notifyListeners(); }
  @override
  void dispose() {
    operators?.lock();
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
    operators=LocalOperatorSessions(store:secrets,namespace:Uri.encodeComponent(api.baseUrl),
      farmId:farm,deviceId:device,generation:writeGeneration);
    profiles=await cache!.operatorProfiles();
    _notify();
  }

  void lock() {operators?.lock();selectedName=null;_notify();}

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
    if(farmId==null || operators==null) throw StateError('Tablette non préparée.');
    final grant=await api.loadLocalGrant(farmId:farmId!,userId:user);
    if(!await operators!.unlock(grant,pin)) throw StateError('PIN incorrect ou temporairement bloqué.');
    selectedName=name;
    _notify();
  }

  Future<void> refreshCache() async {
    if(_refreshInProgress) throw StateError('Le chargement est déjà en cours.');
    final personal=api.personal;
    if(personal==null || cache==null || personal.farmId!=farmId) throw const FoundationApiException(401);
    _refreshInProgress=true;
    try { for(final collection in ['lots','clients','species','tasks']) {
      var after=0;
      await cache!.beginCacheRefresh(collection);
      while(true) {
        if(!identical(personal,api.personal)) throw const FoundationApiException(401);
        final page=await api.request('GET','/cache-page/?collection=$collection&after=$after&limit=50');
        final rows=(page['results'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
        if(!identical(personal,api.personal)) throw const FoundationApiException(401);
        await cache!.stageConfirmedPage(collection,rows);
        final next=page['next_cursor'];
        if(next==null) break;
        if(next is! int || next<=after) throw StateError('Page serveur invalide.');
        after=next;
      }
      await cache!.commitCacheRefresh(collection,taskUserId:personal.role=='OPERATEUR'?personal.userId:null);
    } } finally { _refreshInProgress=false; }
    _notify();
  }

  Future<List<Map<String,dynamic>>> readPage(String collection,{int offset=0}) async {
    final session=operators?.session;
    if(session==null || cache==null) throw StateError('Déverrouiller un profil personnel.');
    final rows=await cache!.cachedPage(collection,offset:offset,limit:50,
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
