import 'dart:async';
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
class SevenDayHarness {
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
  int version=1;
  bool down=false,lost=false,disabled=false,refuseGrant=false;
  bool expiredPersonal=false;
  Completer<void>? grantEntered,grantRelease;
  String businessState='CONFIRMED';
  List<String> codes=List.from(rights);
  VerifiedOfflineGrant? initial;
  static const base='https://seven-day.invalid/api';

  Map<String,dynamic> capabilities(int user)=>{
    'user':user,'exploitation':1,'role':'OPERATEUR','offline_policy_enabled':true,
    'membership':{'id':user,'version':version,'username':'Employé fictif $user'},
    'write_generation':1,'primary_device':{'id':7,'installation_uuid':'test-installation'},
    'offline_permission_contract':{'supported_versions':[2],'issuance_enabled':true},
    'permission_contract':{'version':1,'user':user,'exploitation':1,'role':'OPERATEUR',
      'rights_version':version,'permissions':codes},
  };

  Future<http.Response> personal(http.Request request) async {
    if(down) throw http.ClientException('Synthetic offline');
    final user=api.personal?.userId??2;
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
      await fineGrant(user:user,expectedUser:user,codes:codes,rightsVersion:version,
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
    initial=await fineGrant(codes:rights,now:now,duration:const Duration(days:7));
    await db.saveOperatorProfile(initial!,'Employé fictif 2');
    await enroll(initial!,'123456');
    secrets.values['tablet_context_${Uri.encodeComponent(base)}']=jsonEncode({
      'farm_id':1,'device_id':7,'generation':1,'installation_uuid':'test-installation'});
    await controller();
    // Advance the injected clock beyond the existing 15-second startup cooldown.
    // No wall-clock sleep, no OS clock changes and no seven-day wait.
    now=now.add(const Duration(seconds:16));
    await tablet.unlockProfile(2,'Employé fictif 2','123456');
  }
  FarmDatabase openDatabase()=>FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),
    List.filled(32,'a7').join()),farmId:1,serverNamespace:'seven-day-test',clock:()=>now);
  Future<void> enroll(VerifiedOfflineGrant grant,String pin) async {
    final sessions=LocalOperatorSessions(store:secrets,namespace:Uri.encodeComponent(base),
      farmId:1,deviceId:7,generation:1,clock:()=>now);
    await sessions.enroll(grant,pin);
    // Install only a verified synthetic response, as normal preparation would.
    late Map<String,dynamic> response;
    final verified=await fineGrant(user:grant.userId,expectedUser:grant.userId,codes:rights,
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
  Future<void> close() async {
    tablet.dispose();api.close();await network!.close();await db.close();await directory.delete(recursive:true);
  }
}

void main() {
  late SevenDayHarness h;
  setUp(() async {h=SevenDayHarness();await h.start();});
  tearDown(() async {await h.close();});

  for(final delay in [const Duration(minutes:10),const Duration(hours:3),const Duration(days:1),
      const Duration(days:3),const Duration(days:6)]) {
    test('integrated encrypted four-operation restart and automatic return after $delay',() async {
      await h.fourOperations();
      final before=(await h.db.listOutbox()).map((e)=>e.declaration).toList();
      h.now=h.now.add(delay);await h.reopen();
      expect(h.tablet.operators!.session,isNull);
      await h.tablet.unlockProfile(2,'Employé fictif 2','123456');
      expect((await h.db.listOutbox()).map((e)=>e.declaration).toList(),before);
      await h.reconnect();
      final rows=await h.db.listOutbox();
      expect(rows,hasLength(4));expect(rows.every((e)=>e.businessStatus=='CONFIRMED'),isTrue);
      expect(h.effects,hasLength(4));expect(h.originals,hasLength(4));expect(h.posts,1);
      expect(rows.map((e)=>e.declaration).toList(),before);
      final lots=await h.db.projectedPage('lots');
      expect((lots.single['data'] as Map)['stock'],7);
      expect(h.api.personal,isNull); // Personal renewal cannot gate admissible transport.
    });
  }

  test('PIN opens just before seven days; exact expiry blocks writes but originals still transmit',() async {
    await h.expense();h.now=h.initial!.expiresAt.subtract(const Duration(milliseconds:1));
    await h.reopen();await h.tablet.unlockProfile(2,'Employé fictif 2','123456');
    expect(h.tablet.operators!.session,isNotNull);
    h.now=h.initial!.expiresAt;
    expect(h.tablet.operators!.session,isNull);
    await expectLater(h.tablet.unlockProfile(2,'Employé fictif 2','123456'),throwsStateError);
    await expectLater(h.expense(),throwsStateError);
    h.now=h.now.add(const Duration(seconds:1));await h.reconnect();
    expect((await h.db.listOutbox()).single.businessStatus,'CONFIRMED');
  });

  test('server failure and lost response retry automatically without duplicate effects',() async {
    await h.fourOperations();h.down=true;await h.reconnect();
    expect(await h.db.listOutbox(),hasLength(4));expect(h.effects,isEmpty);
    h.network!.add(false);h.now=h.now.add(const Duration(minutes:6));h.down=false;h.lost=true;
    await h.reconnect();expect(h.effects,hasLength(4));
    expect((await h.db.listOutbox()).every((e)=>e.transportStatus=='RETRY_WAIT'),isTrue);
    h.network!.add(false);h.now=h.now.add(const Duration(minutes:6));await h.reconnect();
    expect(h.posts,2);expect(h.effects,hasLength(4));expect(h.originals,hasLength(4));
    expect((await h.db.listOutbox()).every((e)=>e.businessStatus=='CONFIRMED'),isTrue);
  });

  test('simultaneous automatic triggers share one transport flight',() async {
    await h.expense();
    h.now=h.now.add(const Duration(minutes:1));
    h.network!.add(true);
    final one=h.tablet.sync!.trigger(),two=h.tablet.sync!.trigger();
    await Future.wait([one,two]);await h.tablet.sync!.waitForIdle();
    expect(h.posts,1);expect(h.effects,hasLength(1));
  });

  test('automatic renewal after a day extends only verified rights and preserves original authorization',() async {
    await h.expense();final original=(await h.db.listOutbox()).single.declaration;
    h.authenticate();h.now=h.now.add(const Duration(days:1));await h.reconnect();
    expect(h.grants,1);expect(h.tablet.authorizationStatus,contains('renouvelés'));
    final grant=h.tablet.operators!.session!.grant;
    expect(grant.claims['jti'],isNot(original['offline_authorization_id']));
    expect(grant.expiresAt.difference(h.now),const Duration(days:7));
    expect((await h.db.listOutbox()).single.declaration,original);
    await h.tablet.renewPersonalAuthorization();expect(h.grants,1);
  });

  test('confirmed removed right installs reduced grant and requires PIN without erasing originals',() async {
    await h.expense();final before=(await h.db.listOutbox()).single.declaration;
    h.codes=['finance.read','purchases.create'];h.version=2;h.authenticate();
    await h.reconnect();expect(h.grants,1);expect(h.tablet.operators!.session,isNull);
    await h.tablet.unlockProfile(2,'Employé fictif 2','123456');
    await expectLater(h.expense(),throwsStateError);
    expect(h.tablet.operators!.session!.grant.rightsVersion,2);
    expect((await h.db.listOutbox()).single.declaration,before);
  });

  test('known rights change remains blocked across restart if grant issuance fails',() async {
    h.codes=['finance.read'];h.version=2;h.authenticate();h.refuseGrant=true;
    await h.reconnect();expect(h.tablet.operators!.session,isNull);
    await h.reopen();
    await expectLater(h.tablet.unlockProfile(2,'Employé fictif 2','123456'),throwsStateError);
    expect(h.grants,0);
  });

  test('disabled employee cannot renew; old operations transmit and denied marker survives restart',() async {
    await h.expense();h.authenticate();h.disabled=true;await h.reconnect();
    expect(h.grants,0);expect(h.tablet.operators!.session,isNull);
    expect(h.tablet.authorizationStatus,contains('refusé'));
    expect((await h.db.listOutbox()).single.transportStatus,'SERVER_RECEIVED');
    await h.reopen();
    await expectLater(h.tablet.unlockProfile(2,'Employé fictif 2','123456'),throwsStateError);
  });

  test('another employee cannot renew or replace the current PIN identity',() async {
    final before=h.tablet.operators!.session!.grant.token;
    h.authenticate(3);await h.reconnect();
    expect(h.grants,0);expect(h.capabilityReads,0);
    expect(h.tablet.operators!.session!.userId,2);
    expect(h.tablet.operators!.session!.grant.token,before);
    expect(h.tablet.authorizationStatus,contains('Reconnectez'));
  });

  test('two real PIN profiles retain separate authors and cannot use each other PIN',() async {
    await h.expense();
    final paul=await fineGrant(user:3,expectedUser:3,codes:rights,now:h.now,duration:const Duration(days:7));
    await h.db.saveOperatorProfile(paul,'Employé fictif 3');await h.enroll(paul,'654321');
    h.tablet.profiles=await h.db.operatorProfiles();
    await expectLater(h.tablet.unlockProfile(3,'Employé fictif 3','123456'),throwsStateError);
    await h.tablet.unlockProfile(3,'Employé fictif 3','654321');await h.expense();
    final before=await h.db.listOutbox();expect(before.map((e)=>e.authorId).toSet(),{2,3});
    h.now=h.now.add(const Duration(minutes:1));await h.reconnect();
    final after=await h.db.listOutbox();expect(after.map((e)=>e.declaration).toList(),before.map((e)=>e.declaration).toList());
    expect(after.every((e)=>e.businessStatus=='CONFIRMED'),isTrue);
  });

  test('renewal server failure cannot gate transport or extend an unverified grant',() async {
    await h.expense();h.authenticate();h.refuseGrant=true;h.now=h.now.add(const Duration(days:1));
    final token=h.tablet.operators!.session!.grant.token;
    await h.reconnect();expect(h.grants,0);
    expect(h.tablet.operators!.session!.grant.token,token);
    expect((await h.db.listOutbox()).single.transportStatus,'SERVER_RECEIVED');
    expect(h.tablet.authorizationStatus,contains('indisponible'));
  });

  test('expired personal authentication explicitly requires reconnection without losing originals',() async {
    await h.expense();h.authenticate();h.expiredPersonal=true;await h.reconnect();
    expect(h.api.personal,isNull);expect(h.grants,0);
    expect(h.tablet.operators!.session,isNull);
    expect((await h.db.listOutbox()).single.transportStatus,'SERVER_RECEIVED');
    expect(h.tablet.authorizationStatus,contains('Reconnectez'));
  });

  test('a late renewal response cannot reopen a PIN locked during the request',() async {
    h.authenticate();h.now=h.now.add(const Duration(days:1));
    h.grantEntered=Completer<void>();h.grantRelease=Completer<void>();
    final pending=h.reconnect();await h.grantEntered!.future;
    h.tablet.lock();h.grantRelease!.complete();await pending;
    expect(h.tablet.operators!.session,isNull);expect(h.tablet.selectedName,isNull);
  });

  test('an expired profile renews only through authenticated server and still requires PIN',() async {
    await h.expense();final original=(await h.db.listOutbox()).single.declaration;
    h.now=h.initial!.expiresAt.add(const Duration(seconds:1));h.authenticate();
    await h.reconnect();expect(h.grants,1);expect(h.tablet.operators!.session,isNull);
    await h.tablet.unlockProfile(2,'Employé fictif 2','123456');
    expect(h.tablet.operators!.session!.grant.expiresAt.difference(h.now),const Duration(days:7));
    expect((await h.db.listOutbox()).single.declaration,original);
  });

  test('a locked profile cannot reopen stale rights after a known change and failed renewal',() async {
    h.tablet.lock();h.authenticate();h.version=2;h.codes=['finance.read'];h.refuseGrant=true;
    await h.reconnect();await h.reopen();
    await expectLater(h.tablet.unlockProfile(2,'Employé fictif 2','123456'),throwsStateError);
    expect(h.grants,0);
  });

  test('received is distinct from confirmed and reconciliation remains visible',() async {
    await h.expense();h.businessState='UNREVIEWED';await h.reconnect();
    expect((await h.db.listOutbox()).single.transportStatus,'SERVER_RECEIVED');
    expect((await h.db.listOutbox()).single.businessStatus,'UNREVIEWED');
    expect(h.tablet.sync!.summary.awaitingValidation,1);
    h.network!.add(false);h.now=h.now.add(const Duration(minutes:6));
    h.businessState='NEEDS_RECONCILIATION';await h.reconnect();
    expect((await h.db.listOutbox()).single.businessStatus,'NEEDS_RECONCILIATION');
    expect(h.tablet.sync!.summary.conflicts,1);
  });
}
