import 'dart:async';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/farmer_runtime.dart';
import 'package:app_elevage/services/server_connection.dart';
import 'package:app_elevage/services/token_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;

const rights=['finance.read','purchases.create','animal_sales.create','expenses.create','mortality.create'];

/// Real controller, PIN KDF and encrypted file; every network entry is a MockClient.
/// The simulated server retains originals and idempotent receipts across restarts.
class UnifiedAccessHarness {
  DateTime now=syntheticNow;
  late Directory directory;
  late FarmDatabase db;
  late FoundationApi api;
  late TabletController tablet;
  final secrets=TestSecretStore();
  StreamController<bool?>? network;
  final originals=<String,Map<String,dynamic>>{};
  final effects=<String>{};
  int posts=0,grants=0,capabilityReads=0;
  List<Map<String,dynamic>>? serverSales;
  final onlineWrites=<String>[];
  final preparedReads=<String>[];
  bool layingFixture=false;
  int version=1;
  bool down=false,lost=false,disabled=false,refuseGrant=false;
  bool expiredPersonal=false;
  bool includeCredentialVersion=true,issuanceEnabled=true;
  Completer<void>? grantEntered,grantRelease;
  String businessState='CONFIRMED';
  List<String> codes=List.from(rights);
  VerifiedOfflineGrant? initial;
  static final base=Config.apiUrl;

  Map<String,dynamic> capabilities(int user)=>{
    'user':user,'exploitation':1,'role':'OPERATEUR','offline_policy_enabled':true,
    if(includeCredentialVersion) 'credential_version':1,
    'membership':{'id':user,'version':version,'username':'synthetic'},
    'write_generation':1,'primary_device':{'id':7,'installation_uuid':'test-installation'},
    'offline_permission_contract':{'supported_versions':[2],'issuance_enabled':issuanceEnabled},
    'permission_contract':{'version':1,'user':user,'exploitation':1,'role':'OPERATEUR',
      'rights_version':version,'permissions':codes},
  };

  Future<http.Response> personal(http.Request request) async {
    if(down) throw http.ClientException('Synthetic offline');
    final user=api.personal?.userId??2;
    if(request.url.path.endsWith('/token/')) {
      final values=jsonDecode(request.body) as Map;
      return http.Response(jsonEncode(values['username']=='synthetic' && values['password']=='1234'
        ?{'access':'synthetic-access','refresh':'synthetic-refresh'}:{'detail':'DENIED'}),
        values['username']=='synthetic' && values['password']=='1234'?200:403);
    }
    if(request.url.path.endsWith('/token/refresh/')) return http.Response('{"access":"synthetic-access","refresh":"synthetic-refresh"}',200);
    if(request.url.path.endsWith('/cache-page/')) {
      return http.Response(jsonEncode({'results':request.url.queryParameters['collection']=='sales' && serverSales!=null?serverSales!:[for(final row in await db.cachedPage(request.url.queryParameters['collection']!)) row['data']],
        'next_cursor':null,'confirmed_business_revision':0}),200,headers:{'content-type':'application/json; charset=utf-8'});
    }
    if(request.url.path.endsWith('/capabilities/')) {
      capabilityReads++;
      if(expiredPersonal) return http.Response('{}',401);
      return http.Response(jsonEncode(disabled?{'detail':'MEMBERSHIP_INACTIVE'}:capabilities(user)),disabled?403:200);
    }
    if(request.url.path.endsWith('/challenge/')) {
      return http.Response(jsonEncode({'id':'synthetic','device_id':7,'user_id':user,
        'purpose':'GRANT','signature_contract':'ELEVAGE-DEVICE-V1'}),201);
    }
    if(request.url.path.endsWith('/offline-authorizations/')) {
      expect(jsonDecode(request.body),{'permission_contract_version':2});
      if(refuseGrant) return http.Response('{}',503);
      if(grantEntered!=null) {
        grantEntered!.complete();await grantRelease!.future;
      }
      grants++;
      late Map<String,dynamic> response;
      await fineGrant(credentialVersion:1,user:user,expectedUser:user,codes:codes,rightsVersion:version,
        issuedAt:now,now:now,duration:const Duration(days:7),
        grantId:'00000000-0000-4000-8000-${(1000+grants).toString().padLeft(12,'0')}',
        issued:(value)=>response=value);
      return http.Response(jsonEncode(response),201);
    }
    if(request.url.path.endsWith('/token/refresh/')) return http.Response('{}',401);
    throw StateError('Unexpected personal request ${request.url.path}');
  }

  Map<String,dynamic> receipt(Map<String,dynamic> operation) {
    final kind=operation['entity_type'];
    final confirmed=businessState=='CONFIRMED';
    if(confirmed) effects.add(operation['client_operation_id'] as String);
    final sequence=operation['local_sequence'] as int;
    final result=<String,dynamic>{
      'client_operation_id':operation['client_operation_id'],'author_user_id':operation['author_user_id'],
      'transport_status':'SERVER_RECEIVED','business_status':businessState,
      'received_at':now.toIso8601String(),'applied_at':confirmed?now.toIso8601String():null,
      'server_entity_id':confirmed?'${100+sequence}':'','server_version':confirmed?'farm:$sequence':'',
      'reason_code':businessState=='NEEDS_RECONCILIATION'?'OFFLINE_PERMISSION_DENIED':'',
    };
    if(confirmed && {'ACHAT','VENTE_ANIMAUX','MORTALITE'}.contains(kind)) {
      result['stock_snapshots']=[{'id':42,'nom':'Lot fictif','exploitation':1,'type_production':'CHAIR',
        'stock':kind=='ACHAT'?10:kind=='VENTE_ANIMAUX'?8:7,'stock_oeufs':0,
        'confirmed_business_revision':sequence}];
    }
    if(confirmed && kind=='ACHAT') {
      result['entity_mappings']=[{'entity_type':'LOT','local_entity_id':operation['local_entity_id'],
        'server_entity_id':42}];
    }
    return result;
  }

  Future<http.Response> transport(http.Request request) async {
    expect(request.headers.keys.map((s)=>s.toLowerCase()),isNot(contains('authorization')));
    if(down) return http.Response('{}',503);
    final data=jsonDecode(request.body) as Map;
    if(request.url.path.endsWith('/transport-challenge/')) {
      return http.Response(jsonEncode({'id':'00000000-0000-4000-8000-000000000099','device_id':7,
        'exploitation_id':1,'device_generation':1,'purpose':data['purpose'],'method':'POST',
        'path':data['purpose']=='RECEIVE'?'/api/offline/submissions/':'/api/offline/submissions/status/',
        'signature_contract':'ELEVAGE-DEVICE-TRANSPORT-V1'}),201);
    }
    if(request.url.path.endsWith('/submissions/')) {
      posts++;
      for(final raw in data['operations'] as List) {
        final operation=Map<String,dynamic>.from(raw as Map);
        final id=operation['client_operation_id'] as String;
        if(originals.containsKey(id)) expect(operation,originals[id]);
        for(final dependency in operation['dependencies'] as List) {
          expect(originals.containsKey(dependency),isTrue);
        }
        originals.putIfAbsent(id,()=>operation);
      }
      final responses=(data['operations'] as List).map((op)=>receipt(originals[op['client_operation_id']]!)).toList();
      if(lost) {lost=false;throw http.ClientException('Synthetic lost response after durable server receipt');}
      return http.Response(jsonEncode({'receipts':responses}),200);
    }
    if(request.url.path.endsWith('/status/')) {
      return http.Response(jsonEncode({'receipts':[for(final id in data['operation_ids'] as List)
        if(originals.containsKey(id)) receipt(originals[id]!)],
        'profiles':[for(final profile in await db.operatorProfiles()) {
          'user_id':profile['user_id'],'rights_version':profile['user_id']==2?version:1,
          'active':profile['user_id']!=2 || !disabled,
          'permissions':profile['user_id']==2?codes:['finance.read','expenses.create'],
        }]}),200);
    }
    throw StateError('Unexpected transport request');
  }

  Future<void> start() async {
    directory=await Directory.systemTemp.createTemp('elevage-seven-day-');
    db=openDatabase();
    initial=await fineGrant(credentialVersion:1,codes:rights,now:now,duration:const Duration(days:7));
    await db.saveOperatorProfile(initial!,'synthetic');
    await enroll(initial!,'123456');
    secrets.values['tablet_context_${Uri.encodeComponent(base)}']=jsonEncode({
      'farm_id':1,'device_id':7,'generation':1,'installation_uuid':'test-installation'});
    await controller();
    // Advance the injected clock beyond the existing 15-second startup cooldown.
    // No wall-clock sleep, no OS clock changes and no seven-day wait.
    now=now.add(const Duration(seconds:16));
    await tablet.unlockProfile(2,'synthetic','123456');
  }
  FarmDatabase openDatabase()=>FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),
    List.filled(32,'a7').join()),farmId:1,serverNamespace:'seven-day-test',clock:()=>now);
  Future<void> enroll(VerifiedOfflineGrant grant,String pin) async {
    final sessions=LocalOperatorSessions(store:secrets,namespace:Uri.encodeComponent(base),
      farmId:1,deviceId:7,generation:1,clock:()=>now);
    await sessions.enroll(grant,pin);
    // Install only a verified synthetic response, as normal preparation would.
    late Map<String,dynamic> response;
    final verified=await fineGrant(credentialVersion:1,user:grant.userId,expectedUser:grant.userId,codes:rights,
      now:now,duration:const Duration(days:7),issued:(value)=>response=value);
    secrets.values['offline_grant_${Uri.encodeComponent(base)}_1_${grant.userId}']=jsonEncode({
      'token':verified.token,'public_key':response['public_key'],'key_id':response['key_id'],
      'device_id':7,'generation':1,'rights_version':1});
    if(grant.userId==2) initial=verified;
  }
  Future<void> controller() async {
    network=StreamController<bool?>.broadcast(sync:true);
    api=FoundationApi(baseUrl:base,deviceIdentity:TestIdentity(),secrets:secrets,
      clock:()=>now,client:MockClient(personal));
    tablet=TabletController(api:api,secrets:secrets,clock:()=>now,automaticSyncEnabled:true,
      networkChanges:()=>network!.stream,transportClient:()=>MockClient(transport),
      cacheOpener:({required farmId,required server}) async=>db);
    await tablet.initialize();network!.add(false);await tablet.sync!.waitForIdle();
  }
  void authenticate([int user=2]) {
    api.personal=OnlineOperatorIdentity(userId:user,farmId:1,role:'OPERATEUR',
      capabilities:capabilities(user),access:'synthetic-access',refresh:'synthetic-refresh');
  }
  Future<void> expense() async {
    await tablet.declare(entityType:'DEPENSE',operationType:'CREATE',
      payload:{'lot_ref':{'server_id':7},'categorie_id':1,'montant':'12.34'},businessOccurredAt:now);
  }
  Future<void> fourOperations() async {
    final purchase=await tablet.declare(entityType:'ACHAT',operationType:'CREATE',payload:{
      'nom_lot':'Lot fictif','espece':1,'quantite':10,'prix_total':'100.00','prix_unitaire':'10.00'},businessOccurredAt:now);
    final ref={'local_uuid':purchase.declaration['local_entity_id']};
    await tablet.declare(entityType:'VENTE_ANIMAUX',operationType:'CREATE',payload:{
      'lot_ref':ref,'client_ref':{'server_id':11},'quantite':2,'prix_unitaire':'15.00'},
      dependencies:[purchase.operationId],businessOccurredAt:now);
    await tablet.declare(entityType:'DEPENSE',operationType:'CREATE',payload:{
      'lot_ref':ref,'categorie_id':1,'montant':'12.34'},dependencies:[purchase.operationId],businessOccurredAt:now);
    await tablet.declare(entityType:'MORTALITE',operationType:'CREATE',payload:{'lot_ref':ref,'quantite':1},
      dependencies:[purchase.operationId],businessOccurredAt:now);
  }
  Future<void> reconnect() async {network!.add(true);await tablet.sync!.waitForIdle();}
  Future<void> reopen() async {
    tablet.dispose();api.close();await network!.close();await db.close();db=openDatabase();await controller();
  }
  Future<FarmerRuntime> runtime() async {
    tablet.dispose();api.close();await network!.close();
    final connection=ServerConnection(baseUrl:base,clock:()=>now,interval:const Duration(days:1),
      client:MockClient((request) async {
        if(down) throw http.ClientException('Synthetic health offline');
        return http.Response('{"status":"ok"}',200);
      }));
    api=FoundationApi(baseUrl:base,deviceIdentity:TestIdentity(),secrets:secrets,clock:()=>now,client:MockClient(personal));
    tablet=TabletController(api:api,secrets:secrets,clock:()=>now,automaticSyncEnabled:true,
      networkChanges:connection.changes,transportClient:()=>MockClient(transport),
      cacheOpener:({required farmId,required server}) async=>db);
    return FarmerRuntime(tablet:tablet,connection:connection,tokenStore:TokenService(useSecureStorage:false),
      onlineClient:MockClient((request) async {
        if(down) throw http.ClientException('Synthetic read offline');
        preparedReads.add(request.url.toString());
        if(layingFixture) {
          if(request.url.path.endsWith('/farm-profile/')) return http.Response('{"id":1,"nom":"Ferme partagée"}',200,headers:{'content-type':'application/json; charset=utf-8'});
          if(request.url.path.endsWith('/oeufs/collectes/')) return http.Response('[{"id":90,"nombre_collecte":40}]',200);
          if(request.url.path.endsWith('/oeufs/statistiques/')) return http.Response('{"stock_oeufs":38}',200);
          if(request.url.path.endsWith('/oeufs/stock-date/')) return http.Response('{"stock_global":38}',200);
          if(request.url.path.endsWith('/oeufs/kpi/')) return http.Response('{"production_jour":40}',200);
        }
        if(request.method!='GET') onlineWrites.add('${request.method} ${request.url.path}');
        if(request.url.path.endsWith('/dashboard/')) return http.Response('{"stock_total":10}',200);
        if(request.url.path.endsWith('/clients/total-dettes/')) return http.Response('{"total_dettes":25.50}',200);
        if(request.url.path.endsWith('/lots/')) return http.Response('[{"id":7,"nom":"Lot fictif","stock":10}]',200);
        if(RegExp(r'/lots/[0-9]+/$').hasMatch(request.url.path)) {
          final id=int.parse(request.url.path.split('/').where((part)=>part.isNotEmpty).last);
          return http.Response(jsonEncode({'id':id,'nom':'Lot fictif','stock':10,
            'achats':[{'id':1,'quantite':10,'prix_total':'100.00'}],
            'mouvements':[],'depenses':[],'ventes_oeufs':[],'naissances_issues':[],
            'kpis':{'stock':10,'depenses':'0.00','chiffre_affaires':'0.00','marge':'0.00'}}),200);
        }
        return http.Response('[]',200);
      }));
  }
  Future<void> close() async {
    tablet.dispose();api.close();await network!.close();await db.close();await directory.delete(recursive:true);
  }
}
