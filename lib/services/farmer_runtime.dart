import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

import '../offline/tablet_controller.dart';

import '../offline/foundation_api.dart';

import '../offline/offline_grant.dart';

import '../offline/outbox.dart';

import '../offline/screen_snapshot_store.dart';

import 'api_service.dart';

import 'classic_terrain_command.dart';

import 'guarded_api_client.dart';

import 'server_connection.dart';

import 'token_service.dart';

import 'package:timezone/timezone.dart' as tz;



// Locally reconstructed JSON must have the same UTF-8 contract as the API.

http.Response _localJson(Object? payload,int status,{Map<String,String> headers=const {}})=>

  http.Response.bytes(utf8.encode(jsonEncode(payload)),status,

    headers:{...headers,'content-type':'application/json; charset=utf-8'});



bool isTransportFailure(Object error)=>error is TimeoutException || error is http.ClientException;



/// Lifetime belongs to the authenticated UI host, not to the login page. Grants,

/// identity and context remain authoritative in TabletController and backend.

class FarmerRuntime extends ChangeNotifier {

  FarmerRuntime({required this.tablet,required this.connection,this.networkHints,this.tokenStore,http.Client? onlineClient})

    :_online=GuardedApiClient(onlineClient) {

    tablet.addListener(_changed);connection.addListener(_changed);

  }

  final Stream<bool?>? networkHints;

  final TokenStore? tokenStore;

  bool _profileRequired=false;

  final TabletController tablet;

  final ServerConnection connection;

  final http.Client _online;

  bool _disposed=false,_initialized=false;

  String? username;

  String? warning;

  Map<String,dynamic>? _onlineCaps;

  Future<void>? _checking;

  DateTime? _lastCheck;

  FarmerApiService? api;

  void _changed() {if(!_disposed) notifyListeners();}

  bool get prepared=>tablet.operators?.session!=null && !tablet.knownDeviceRevoked && !tablet.recovering;

  VerifiedOfflineGrant? get grant=>prepared?tablet.operators!.session!.grant:null;

  bool get signedIn=>username!=null && (_profileRequired ? prepared : tablet.api.personal?.role=='OPERATEUR');

  String get identity=>prepared

    ?'local:${grant!.farmId}:${grant!.userId}:${grant!.credentialVersion}:${tablet.sessionEpoch}'

    :'online:${tablet.api.personal?.farmId}:${tablet.api.personal?.userId}';

  Future<void> initialize() async {

    if(_initialized) return;

    await tablet.initialize();_initialized=true;

    connection.start(networkHints:networkHints);

  }

  Future<FarmerApiService> signIn(String account,String code) async {

    await initialize();warning=null;username=null;_profileRequired=false;

    try {

      await tablet.signIn(account,code);

    } catch(error) {

      // A rejection, role failure, or invalid signature is never an offline login.

      if(!isTransportFailure(error)) {

        if(error is FoundationApiException && {401,403}.contains(error.status) && tablet.farmId!=null) {

          for(final profile in tablet.profiles.where((p)=>p['display_name']==account)) {

            await tablet.api.requirePersonalRevalidation(tablet.farmId!,profile['user_id'] as int);

          }

        }

        rethrow;

      }

      tablet.api.personal=null;

      final matches=tablet.profiles.where((p)=>p['display_name']==account).toList();

      if(matches.length!=1) throw StateError('Ce compte doit d’abord être préparé avec Internet.');

      await tablet.unlockProfile(matches.single['user_id'] as int,account,code,personalCode:true);

      if(!prepared) throw StateError('Accès indisponible. Contactez le propriétaire.');

      final old=ApiService(tokenStore:tokenStore);await old.logout();old.close();

      _profileRequired=true;

      username=account;

      ApiService.farmerSession=true;

      ApiService.setLocalPresentationIdentity(identity);

      final prefs=await SharedPreferences.getInstance();await prefs.setString('username',account);await prefs.setString('session_kind','farmer');

      return api=FarmerApiService(this);

    }

    final personal=tablet.api.personal;

    if(personal==null || personal.role!='OPERATEUR') {

      tablet.lock();tablet.api.personal=null;

      throw StateError('Utilisez l’accès propriétaire pour ce compte.');

    }

    _onlineCaps=Map<String,dynamic>.from(personal.capabilities);

    if(tablet.offlinePolicyEnabled) {

      final caps=personal.capabilities;

      final contract=caps['offline_permission_contract'];

      final supported=caps['credential_version'] is int &&

        contract is Map && contract['issuance_enabled']==true &&

        contract['supported_versions'] is List && (contract['supported_versions'] as List).contains(2);

      if(tablet.farmId!=null && supported) {

        // The authenticated online session remains usable when fine issuance is

        // explicitly unavailable. Invalid signatures/context still fail closed.

        try {

          await tablet.preparePersonalCode(code);

          await tablet.refreshCache();

          _profileRequired=true;

        } on FoundationApiException catch(error) {

          if(error.status!=503) rethrow;

          tablet.lock();

          warning='Accès en ligne disponible. Le propriétaire doit préparer l’accès sans Internet.';

        }

      } else {

        warning='Accès en ligne disponible. Le propriétaire doit préparer l’accès sans Internet.';

      }

    }

    username=account;

    api=FarmerApiService(this);

    ApiService.farmerSession=true;

    final prefs=await SharedPreferences.getInstance();await prefs.setString('session_kind','farmer');

    await api!.usePersonalOnlineSession(personal.access,account);

    tablet.userActivity();

    if(prepared) {

      await connection.probe();

      await _prepareDashboard();

      await _prepareLotDetails();

    }

    return api!;

  }

  Future<void> _prepareDashboard() async {

    // The home screen commits these reads together. Prepare them before the

    // login completes, rather than relying on a previous visit of that screen.

    final paths=['/dashboard/','/clients/total-dettes/'];

    if(grant?.finePermissions?.allows('agenda.read')==true) paths.add('/tasks/?active=true');

    for(final path in paths) {

      try {

        final response=await request(http.Request('GET',Uri.parse('${Config.apiUrl}$path')));

        if(response.statusCode!=200) {

          if(!signedIn) throw StateError('La session a changé.');

          warning='Le tableau de bord n’est pas entièrement préparé sans Internet. Reconnectez-vous pour terminer son chargement.';

        }

      } catch(error) {

        if(!isTransportFailure(error)) rethrow;

        warning='Chargement du tableau de bord interrompu. Les données déjà conservées restent disponibles.';

        return;

      }

    }

  }

  Future<void> _prepareLotDetails() async {

    // A list row is not a complete detail view. Prepare the real authenticated

    // response, bound by request() to this user's credential epoch and farm.

    final captured=identity;

    for(var offset=0;offset<10000;offset+=50) {

      final rows=await tablet.cache!.cachedPage('lots',offset:offset,limit:50);

      if(!signedIn || identity!=captured) throw StateError('La session a changé.');

      for(final row in rows) {

        final id=(row['data'] as Map)['id'];

        if(id is! int || id<1) continue;

        try {

          final response=await request(http.Request('GET',Uri.parse('${Config.apiUrl}/lots/$id/')));

          if(response.statusCode!=200) {

            if(!signedIn) throw StateError('La session a changé.');

            warning='Certaines fiches de lots ne sont pas encore disponibles sans Internet.';

          }

        } catch(error) {

          if(!isTransportFailure(error)) rethrow;

          warning='Chargement des fiches interrompu. Reconnectez-vous avec Internet pour le terminer.';

          return;

        }

      }

      if(rows.length<50) break;

    }

  }

  Future<void> _deny() async {

    final current=grant;

    if(current!=null) await tablet.api.requirePersonalRevalidation(current.farmId,current.userId);

    tablet.lock();tablet.api.personal=null;username=null;

    ApiService.clearLocalPresentationIdentity();_changed();

  }

  Future<void> _checkOnline() async {

    if(_checking!=null) return _checking!;

    final task=_checkOnlineOnce();_checking=task;

    try {await task;} finally {_checking=null;}

  }

  Future<void> _checkOnlineOnce() async {

    final now=tablet.clock().toUtc();

    if(_lastCheck!=null && now.difference(_lastCheck!)<const Duration(seconds:15) && tablet.api.personal!=null) return;

    try {

      if(tablet.api.personal==null && grant!=null) await tablet.api.restoreAfterPersonalCode(grant!);

      final caps=await tablet.api.personalCapabilities();

      final current=grant;

      if(current!=null && (caps['user']!=current.userId || caps['exploitation']!=current.farmId ||

          caps['role']!='OPERATEUR' || caps['credential_version']!=current.credentialVersion ||

          caps['membership']['version']!=current.rightsVersion)) {

        await _deny();throw const FoundationApiException(403);

      }

      _onlineCaps=Map<String,dynamic>.from(caps);_lastCheck=now;

    } on FoundationApiException catch(error) {

      if({401,403}.contains(error.status)) await _deny();

      rethrow;

    }

  }

  Map<String,dynamic> _offlineCaps() {

    final current=grant;

    if(current==null || !current.hasFineContract || !current.validAt(tablet.clock())) {

      throw StateError('Reconnectez-vous pour continuer.');

    }

    final rights=current.finePermissions!;

    return {'user':current.userId,'exploitation':current.farmId,'role':'OPERATEUR',

      'offline_policy_enabled':true,'credential_version':current.credentialVersion,

      'membership':{'id':current.claims['membership_id'],'version':current.rightsVersion,'username':username},

      'permission_contract':{'version':1,'user':rights.userId,'exploitation':rights.farmId,

        'role':'OPERATEUR','rights_version':rights.rightsVersion,'permissions':rights.permissions.toList()}};

  }

  Future<Object> capabilities() async {

    if(connection.available!=false) {

      try {await _checkOnline();return _onlineCaps!;}

      catch(error) {if(!isTransportFailure(error)) rethrow;}

    }

    return _offlineCaps();

  }

  String _path(Uri uri) {

    final base=Uri.parse(Config.apiUrl);

    if(uri.scheme!=base.scheme || uri.host!=base.host || uri.port!=base.port || !uri.path.startsWith('${base.path}/')) {

      throw const NetworkDestinationException();

    }

    return uri.path.substring(base.path.length)+(uri.hasQuery?'?${uri.query}':'');

  }

  Future<List<Map<String,dynamic>>?> _bootstrapRead(String path) async {

    const collections={'/lots/':'lots','/clients/':'clients','/especes/':'species',

      '/categories-depense/':'expense_categories','/tasks/':'tasks'};

    final uri=Uri.parse(path),collection=collections[Uri.parse(path).path];

    if(!prepared || collection==null || (uri.hasQuery && !(collection=='tasks' && uri.query=='active=true'))) return null;

    final result=<Map<String,dynamic>>[];

    for(var offset=0;offset<10000;offset+=50) {

      final rows=await tablet.readPage(collection,offset:offset);

      for(final row in rows) {

        final data=Map<String,dynamic>.from(row['data'] as Map);

        // Classic id-based forms can select confirmed references. Pending local

        // lots remain in the encrypted ledger and the typed expense selector.

        if(data['id'] is int && (collection!='tasks' || data['status']!='CANCELLED')) result.add(data);

      }

      if(rows.length<50) break;

    }

    return result;

  }



  Future<ClassicTerrainCommand?> _decodeCommand(String method,String endpoint,Map<String,dynamic> body) async {

    if(endpoint!='/payments/create/') return ClassicTerrainCommand.decode(method,endpoint,body);

    if(method!='POST' || body.keys.any((key)=>!{'client','vente','montant','mode'}.contains(key)) ||

       !{'ESPECES','MOBILE_MONEY','VIREMENT','CHEQUE'}.contains(body['mode'])) return null;

    final captured=identity;

    if(connection.available!=false) {

      try {

        await _checkOnline();

        await tablet.refreshCache(collections:const ['sales']);

      } catch(error) {if(!isTransportFailure(error)) rethrow;}

    }

    if(!signedIn || identity!=captured) throw StateError('La session a changé.');

    // The legacy sale id is a Vente id. For eggs the signed declaration needs

    // VenteOeufs.reference_id: only the authenticated cache can resolve it.

    for(var offset=0;offset<10000;offset+=50) {

      final rows=await tablet.cache!.cachedPage('sales',offset:offset,limit:50);

      final matches=rows.where((row)=>(row['data'] as Map)['id']==body['vente']).toList();

      if(matches.isNotEmpty) {

        final sale=matches.single['data'] as Map;

        if(sale['client_id']!=body['client'] || !{'VENTE_ANIMAUX','VENTE_OEUFS'}.contains(sale['entity_type'])) {

          throw StateError('Cette vente ne correspond pas au client sélectionné.');

        }

        final store=tablet.cache;

        if(store is OutboxStore) {

          for(var offset=0;offset<10000;offset+=50) {

            final entries=await (store as OutboxStore).listOutbox(authorId:grant!.userId,offset:offset);

            if(entries.any((row)=>row.declaration['entity_type']=='ENCAISSEMENT' &&

              !{'CONFIRMED','NOT_APPLIED','SUPERSEDED'}.contains(row.businessStatus) &&

              row.declaration['payload']['vente_type']==sale['entity_type'] &&

              row.declaration['payload']['vente_ref']['server_id']==sale['reference_id'])) {

              throw StateError('Un paiement de cette vente attend déjà sa confirmation. Vérifiez l’historique avant de recommencer.');

            }

            if(entries.length<50) break;

          }

        }

        if(!signedIn || identity!=captured) throw StateError('La session a changé.');

        return ClassicTerrainCommand('ENCAISSEMENT',{

          'client_ref':ClassicTerrainCommand.reference(body['client']),

          'vente_ref':ClassicTerrainCommand.reference(sale['reference_id']),

          'vente_type':sale['entity_type'],'montant_recu':ClassicTerrainCommand.decimal(body['montant'],2),

          'mode':body['mode'],'note':''});

      }

      if(rows.length<50) break;

    }

    throw StateError('Chargez cette vente avec Internet avant de saisir son paiement.');

  }



  Future<http.Response> request(http.BaseRequest request) async {

    if(!signedIn) throw StateError('Reconnectez-vous pour continuer.');

    final captured=identity;

    final path=_path(request.url),endpoint=path.split('?').first;

    void check() {if(!signedIn || identity!=captured) throw StateError('La session a changé.');}

    if(request.method=='GET' && endpoint=='/me/capabilities/') {

      final caps=await capabilities();check();return _localJson(caps,200);

    }

    if(prepared && request.method!='GET') {

      final command=request is http.Request && request.method=='POST'

        ?await _decodeCommand(request.method,endpoint,Map<String,dynamic>.from(jsonDecode(request.body) as Map)):null;

      if(command!=null) {

      check();

      if(connection.available==true) {try {await _checkOnline();} catch(error) {if(!isTransportFailure(error)) rethrow;}}

      check();

      final id=newOperationUuid();

      final day=command.at;

      final at=day==null?tablet.clock().toUtc():day.length==10

        ?tz.TZDateTime(tz.getLocation('Europe/Paris'),int.parse(day.substring(0,4)),int.parse(day.substring(5,7)),int.parse(day.substring(8,10)),12).toUtc()

        :DateTime.parse(day).toUtc();

      final entry=await tablet.declare(entityType:command.kind,operationType:command.operation,

        payload:command.payload,businessOccurredAt:at,operationId:id,localEntityId:id,

        expectedServerVersion:command.expectedVersion,

        project:{'VENTE_ANIMAUX','VENTE_OEUFS'}.contains(command.kind)?() async {

          final lotId=(command.payload['lot_ref'] as Map)['server_id'];

          for(var offset=0;offset<10000;offset+=50) {

            final rows=await tablet.readPage('lots',offset:offset);

            final matches=rows.where((r)=>(r['data'] as Map)['id']==lotId).toList();

            if(matches.isNotEmpty) {

              final row=matches.single,data=row['data'] as Map;

              final stock=data[command.kind=='VENTE_OEUFS'?'projected_egg_stock':'projected_stock'];

              if(stock is! int || stock<0 || row['stock_checkpoint_pending']==true) throw StateError('Rechargez le lot et vérifiez son stock disponible.');

              return;

            }

            if(rows.length<50) break;

          }

          throw StateError('Rechargez le lot avant de saisir cette vente.');

        }:null);

      check();

      return _localJson({'local_only':true,'operation_id':entry.operationId,

        'transport_status':entry.transportStatus,'business_status':entry.businessStatus},202,

        headers:{'x-elevage-outbox-id':entry.operationId});

      }

      // Unsupported offline commands keep their existing authenticated online

      // path. They are never queued, retried or reported as locally saved.

      if(connection.available==false) return _localJson({'message':'Cette action nécessite Internet. Aucun enregistrement local effectué.'},409);

    }

    final snapshot=tablet.cache is ScreenSnapshotStore?tablet.cache as ScreenSnapshotStore:null;

    final current=grant;

    final canCache=request.method=='GET' && snapshot!=null && current?.credentialVersion!=null &&

      !RegExp(r'(token|password|devices|memberships|capabilities|audit)').hasMatch(path);

    if(connection.available!=false || !prepared) {

      try {

        await _checkOnline();check();

        request.headers['Authorization']='Bearer ${tablet.api.personal!.access}';

        final response=await http.Response.fromStream(await _online.send(request).timeout(const Duration(seconds:5))).timeout(const Duration(seconds:5));

        check();

        if({401,403}.contains(response.statusCode)) {await _deny();return response;}

        if(canCache && response.statusCode==200) {

          final payload=jsonDecode(response.body);

          if(payload is Map || payload is List) await snapshot.saveScreenSnapshot(userId:current!.userId,

            credentialVersion:current.credentialVersion!,path:path,payload:payload);

        }

        return response;

      } catch(error) {if(!isTransportFailure(error) || request.method!='GET') rethrow;}

    }

    check();

    if(canCache) {

      final payload=await snapshot.screenSnapshot(userId:current!.userId,credentialVersion:current.credentialVersion!,path:path);

      check();

      if(payload!=null) return _localJson(payload,200,headers:{'x-elevage-cached':'1'});

    }

    final bootstrap=await _bootstrapRead(path);

    check();

    if(bootstrap!=null) return _localJson(bootstrap,200,headers:{'x-elevage-cached':'1'});

    return _localJson({'message':'Ces données ne sont pas encore disponibles sur cet appareil. Reconnectez-vous pour les charger.'},503);

  }

  void handleAppLifecycleState(AppLifecycleState state) {

    if(state==AppLifecycleState.detached) {

      connection.pause();lock();return;

    }

    final foreground=state==AppLifecycleState.resumed;

    tablet.setForeground(foreground);

    if(foreground) {

      if(signedIn) connection.start(networkHints:networkHints);

    } else {

      connection.pause();

    }

  }

  void lock() {

    username=null;tablet.setForeground(false);tablet.lock();tablet.api.personal=null;

    ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();_changed();

  }

  Future<void> logout() async {

    username=null;tablet.lock();tablet.api.personal=null;

    ApiService.clearLocalPresentationIdentity();_changed();

  }

  @override

  void dispose() {

    if(_disposed) return;

    _disposed=true;tablet.removeListener(_changed);connection.removeListener(_changed);

    connection.dispose();tablet.api.close();tablet.dispose();_online.close();super.dispose();

  }

}



class _FarmerHttpClient extends http.BaseClient {

  _FarmerHttpClient(this.runtime);

  final FarmerRuntime runtime;

  @override

  Future<http.StreamedResponse> send(http.BaseRequest request) async {

    final response=await runtime.request(request);

    return http.StreamedResponse(Stream.value(response.bodyBytes),response.statusCode,headers:response.headers,request:request);

  }

  @override

  void close() {} // Runtime is owned by the authenticated host.

}

class FarmerApiService extends ApiService {

  FarmerApiService(this.runtime):super(client:_FarmerHttpClient(runtime),tokenStore:runtime.tokenStore);

  final FarmerRuntime runtime;

  @override

  Listenable get sessionChanges=>runtime;

  @override

  bool get hasUnifiedOfflineSession=>runtime.prepared;

  @override

  List<OutboxEntry> get localOperations=>runtime.tablet.outboxRows;

  @override

  Future<void> logout() async {await runtime.logout();await super.logout();}

}

