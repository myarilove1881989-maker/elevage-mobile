import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/prepared_operation_policy.dart';
import 'package:app_elevage/services/farm_session.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'outbox_test.dart' show testOutboxGrant, seedHistoricalV1;

final syntheticNow=DateTime.utc(2026,10,12,12);

Future<VerifiedOfflineGrant> fineGrant({int user=2, int farm=1, String role='OPERATEUR',
  List<String> codes=const ['clients.create','finance.read'],
  Map<String,dynamic>? changed, bool tamper=false, DateTime? now,
  int? credentialVersion,
  int expectedUser=2,int expectedFarm=1,int expectedGeneration=1, bool legacy=false,
  DateTime? issuedAt,int rightsVersion=1,
  Duration duration=const Duration(hours:24), String? grantId,
  void Function(Map<String,dynamic>)? issued}) async {
  final key=await Ed25519().newKeyPair();final public=await key.extractPublicKey();
  String encoded(dynamic value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
  final iat=(issuedAt??syntheticNow.subtract(const Duration(seconds:1))).millisecondsSinceEpoch~/1000;
  final exp=iat+duration.inSeconds;
  final id=grantId??'00000000-0000-4000-8000-${user.toString().padLeft(12,'0')}';
  final contract={'version':2,'grant_id':id,'grant_version':1,'user':user,'membership_id':user,
    'exploitation':farm,'role':role,'device_id':7,'write_generation':1,'rights_version':rightsVersion,
    'permissions':codes,'iat':iat,'exp':exp,...?changed};
  final header=encoded({'alg':'EdDSA','kid':'fine-test'});
  final claims=encoded({'iss':'elevage-offline','aud':'elevage-device','typ':'offline-authorization',
    'jti':id,'sub':'$user','membership_id':user,'exploitation_id':farm,'device_id':7,
    'rights_version':rightsVersion,'write_generation':1,'iat':iat,'exp':exp,
    if(credentialVersion!=null) 'credential_version':credentialVersion,
    'capabilities':{'can_create_terrain_operation':true,if(!legacy)'permission_contract':contract}});
  final signature=await Ed25519().sign(utf8.encode('$header.$claims'),keyPair:key);
  if(tamper) signature.bytes[0]^=1;
  final token='$header.$claims.${base64Url.encode(signature.bytes).replaceAll('=','')}';
  final pem='-----BEGIN PUBLIC KEY-----\n${base64.encode([0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00,...public.bytes])}\n-----END PUBLIC KEY-----';
  issued?.call({'authorization':token,'public_key':pem,'key_id':'fine-test'});
  return VerifiedOfflineGrant.verify(token:token,publicKeyPem:pem,trustedKeyId:'fine-test',
    farmId:expectedFarm,userId:expectedUser,deviceId:7,generation:expectedGeneration,rightsVersion:rightsVersion,
    now:now??syntheticNow);
}

class SyntheticUnlocked extends LocalOperatorSessions {
  SyntheticUnlocked(VerifiedOfflineGrant grant, TestSecretStore secrets)
    : active=LocalOperatorSession(grant:grant,openedAt:syntheticNow),
      super(store:secrets,namespace:'fine-test',farmId:1,deviceId:7,generation:1);
  LocalOperatorSession? active;
  @override LocalOperatorSession? get session => active;
  @override void lock() { active=null; }
}

void main() {
  test('exact signed codes govern every supported local action',() async {
    final grant=await fineGrant();
    const mapping={'ACHAT':'purchases','VENTE':'animal_sales','VENTE_ANIMAUX':'animal_sales',
      'VENTE_OEUFS':'egg_sales','DEPENSE':'expenses','MORTALITE':'mortality','NAISSANCE':'births',
      'DON':'donations','VOL':'thefts','CLIENT':'clients','COLLECTE_OEUFS':'egg_collections',
      'ENCAISSEMENT':'cash','ALIMENTATION':'feed','PESEE':'weights'};
    for(final item in mapping.entries) {
      expect(grant.permitsOperation(item.key,'CREATE',syntheticNow),item.key=='CLIENT');
      final permitted=await fineGrant(codes:['finance.read','${item.value}.create']);
      expect(permitted.permitsOperation(item.key,'CREATE',syntheticNow),isTrue);
      expect(permitted.permitsOperation(item.key,'CANCEL',syntheticNow),isFalse);
      expect(permitted.permitsOperation(item.key,'REVERSE',syntheticNow),isFalse);
    }
    final task=await fineGrant(codes:['finance.read','agenda.progress','agenda.plan']);
    expect(task.permitsOperation('TASK','UPDATE',syntheticNow),isTrue);
    expect(task.permitsOperation('TASK','CANCEL',syntheticNow),isFalse);
    expect(task.permitsOperation('TASK','CREATE',syntheticNow),isFalse);
  });

  test('contract bytes and nested codes are immutable after signature verification',() async {
    final grant=await fineGrant();
    final value=(grant.claims['capabilities'] as Map)['permission_contract'] as Map;
    expect(()=>value['role']='OWNER',throwsUnsupportedError);
    expect(()=>(value['permissions'] as List).add('purchases.create'),throwsUnsupportedError);
    expect(grant.permitsOperation('ACHAT','CREATE',syntheticNow),isFalse);
    expect(grant.finePermissions!.allows('finance.read'),isTrue);
    expect(preparedOperationDecision(grant,'CLIENT','CREATE',syntheticNow),PreparedOperationDecision.allowed);
    expect(preparedOperationDecision(grant,'ACHAT','CREATE',syntheticNow),PreparedOperationDecision.denied);
  });

  for(final entry in <String,dynamic>{'version':99,'grant_version':true,'user':3,'membership_id':3,
    'exploitation':2,'role':'OWNER','device_id':8,'write_generation':2,'rights_version':2,
    'grant_id':'foreign','iat':0,'exp':0,'permissions':['invented.write']}.entries) {
    test('signed but invalid ${entry.key} is refused rather than V1 fallback',() async {
      await expectLater(fineGrant(changed:{entry.key:entry.value}),throwsStateError);
    });
  }
  test('OWNER ordinary writes and privileged employee codes are refused',() async {
    await expectLater(fineGrant(role:'OWNER'),throwsStateError);
    await expectLater(fineGrant(codes:['finance.read','users.manage']),throwsStateError);
    await expectLater(fineGrant(codes:['finance.read','finance.read']),throwsStateError);
    await expectLater(fineGrant(codes:['clients.create']),throwsStateError);
  });
  test('bad signature, foreign identity/farm/generation, expiry and clock before issuance',() async {
    await expectLater(fineGrant(tamper:true),throwsStateError);
    await expectLater(fineGrant(expectedUser:3),throwsStateError);
    await expectLater(fineGrant(expectedFarm:2),throwsStateError);
    await expectLater(fineGrant(expectedGeneration:2),throwsStateError);
    await expectLater(fineGrant(now:syntheticNow.add(const Duration(hours:24))),throwsStateError);
    await expectLater(fineGrant(now:syntheticNow.subtract(const Duration(seconds:2))),throwsStateError);
  });

  group('existing encrypted outbox',() {
    late Directory directory;late FarmDatabase db;late DateTime now;
    setUp(() async {
      now=syntheticNow;directory=await Directory.systemTemp.createTemp('fine-synthetic-');
      db=FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),List.filled(32,'a1').join()),
        farmId:1,serverNamespace:'fine-test',clock:()=>now);
    });
    tearDown(() async {await db.close();await directory.delete(recursive:true);});

    test('sale permission denial is safe and creates no original or projection',() async {
      final grant=await fineGrant(codes:['finance.read']);
      final secrets=TestSecretStore();
      final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),
        secrets:secrets,client:MockClient((_) async=>throw StateError('No HTTP expected')));
      final tablet=TabletController(api:api,secrets:secrets,automaticSyncEnabled:false,clock:()=>now)
        ..cache=db ..farmId=1 ..deviceId=7 ..generation=1 ..operators=SyntheticUnlocked(grant,secrets);
      var projections=0;
      for(final kind in ['VENTE_ANIMAUX','VENTE_OEUFS']) {
        await expectLater(tablet.declare(entityType:kind,operationType:'CREATE',payload:{},businessOccurredAt:now,
          project:() async {projections++;}),throwsA(isA<StateError>().having((e)=>e.message,'safe permission message',
            'La vente n’est pas autorisée avec vos permissions actuelles. Reconnectez votre compte ou contactez le propriétaire.')));
      }
      expect(await db.listOutbox(),isEmpty);expect(projections,0);
      tablet.dispose();api.close();
    });

    test('denied exact code has no sequence, projection or declaration effect',() async {
      final grant=await fineGrant();var projected=0;
      await expectLater(db.enqueue(grant:grant,isSessionCurrent:()=>true,entityType:'ACHAT',operationType:'CREATE',
        payload:{},businessOccurredAt:now,project:() async {projected++;}),throwsStateError);
      expect(await db.listOutbox(),isEmpty);expect(projected,0);
      final row=await db.enqueue(grant:grant,isSessionCurrent:()=>true,entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Jean'},businessOccurredAt:now);
      expect(row.sequence,1);
    });

    test('fine and V1 originals coexist across two employees, rights change and expiry',() async {
      final fine=await fineGrant();final legacy=await testOutboxGrant(3,now,legacy:true);
      final original=await db.enqueue(grant:fine,isSessionCurrent:()=>true,entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Jean'},businessOccurredAt:now);
      final repeat=await db.enqueue(grant:fine,isSessionCurrent:()=>true,entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Jean'},businessOccurredAt:now,operationId:original.operationId);
      expect(repeat.declaration,original.declaration);
      await expectLater(db.enqueue(grant:legacy,isSessionCurrent:()=>true,entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Paul'},businessOccurredAt:now),throwsStateError);
      await seedHistoricalV1(db,legacy,now,payload:{'nom':'Paul'});
      now=now.add(const Duration(hours:25));
      await expectLater(db.enqueue(grant:fine,isSessionCurrent:()=>true,entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Expired'},businessOccurredAt:now),throwsStateError);
      final pending=await db.leasePending();expect(pending,hasLength(2));
      expect(pending.first.declaration,original.declaration);
      expect(pending.map((row)=>row.authorId),[2,3]);
      expect(original.declaration.keys, isNot(contains('permission_contract')));
      expect(jsonEncode(original.declaration),isNot(contains(fine.token)));
      final changed=await fineGrant(codes:['finance.read']);
      expect(changed.permitsOperation('CLIENT','CREATE',syntheticNow),isFalse);
      expect((await db.listOutbox()).last.declaration,original.declaration);
    });

    test('controller rejects farm/device/generation changes and a switched author during enqueue',() async {
      final secrets=TestSecretStore();
      final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
        client:MockClient((request) async => throw StateError('No HTTP expected')));
      final grant=await fineGrant();
      final tablet=TabletController(api:api,secrets:secrets,automaticSyncEnabled:false,clock:()=>now)
        ..cache=db ..farmId=1 ..deviceId=7 ..generation=1 ..operators=SyntheticUnlocked(grant,secrets);
      expect(tablet.sessionTransitionLabel,contains('droits individuels signés'));
      expect(FarmSession.fromTablet(tablet)!.fineOfflineRightsActivated,isTrue);
      expect(FarmSession.fromTablet(tablet)!.permissions!.allows('purchases.create'),isFalse);
      for(final change in <void Function()>[
        ()=>tablet.generation=2, ()=>tablet.farmId=2, ()=>tablet.deviceId=8,
        ()=>tablet.operators=SyntheticUnlocked(grant,secrets), ()=>tablet.lock(),
      ]) {
        tablet.farmId=1;tablet.deviceId=7;tablet.generation=1;tablet.operators=SyntheticUnlocked(grant,secrets);
        await expectLater(tablet.declare(entityType:'CLIENT',operationType:'CREATE',payload:{'nom':'Interrupted'},
          businessOccurredAt:now,project:() async {change();}),throwsStateError);
        expect(await db.listOutbox(),isEmpty);
      }
      tablet.dispose();api.close();
    });

    test('preparation rejects a foreign personal session before any device or grant request',() async {
      var requests=0;final secrets=TestSecretStore();
      final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
        client:MockClient((request) async {requests++;return http.Response('{}',500);}));
      final grant=await fineGrant();
      final tablet=TabletController(api:api,secrets:secrets,automaticSyncEnabled:false)
        ..cache=db ..farmId=1 ..deviceId=7 ..generation=1 ..operators=SyntheticUnlocked(grant,secrets);
      for(final role in ['OWNER','OPERATEUR']) {
        api.personal=OnlineOperatorIdentity(userId:3,farmId:2,role:role,capabilities:{},access:'a',refresh:'r');
        if(role=='OWNER') {
          await expectLater(tablet.preparePrimaryTablet(),throwsStateError);
        } else {
          await expectLater(tablet.prepareOperator('123456'),throwsStateError);
        }
      }
      expect(requests,0);expect(secrets.values,isEmpty);expect(await db.listOutbox(),isEmpty);
      tablet.dispose();api.close();
    });

    test('lock, profile switch or context change during projection rolls back the transaction',() async {
      final grant=await fineGrant();var current=true;
      await expectLater(db.enqueue(grant:grant,isSessionCurrent:()=>current,entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Interrupted'},businessOccurredAt:now,project:() async {
          current=false;
        }),throwsStateError);
      expect(await db.listOutbox(),isEmpty);
      final foreign=await fineGrant(farm:2,expectedFarm:2);
      await expectLater(db.enqueue(grant:foreign,isSessionCurrent:()=>true,entityType:'CLIENT',operationType:'CREATE',
        payload:{},businessOccurredAt:now),throwsStateError);
    });
  });

  test('fine grant negotiation is explicit and a server downgrade is refused before persistence',() async {
    for(final downgrade in [false,true]) {
      late Map<String,dynamic> response;
      await fineGrant(legacy:downgrade,issued:(value)=>response=value);
      final secrets=TestSecretStore();secrets.values['historical-original']='retained';
      var posts=0;
      final capabilities={'user':2,'exploitation':1,'role':'OPERATEUR',
        'membership':{'version':1,'username':'Jean'},'offline_policy_enabled':true,'write_generation':1,
        'primary_device':{'id':7,'installation_uuid':'test-installation'},
        'offline_permission_contract':{'supported_versions':[2],'issuance_enabled':true}};
      final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
        clock:()=>syntheticNow,client:MockClient((request) async {
          if(request.url.path.endsWith('/capabilities/')) return http.Response(jsonEncode(capabilities),200);
          if(request.url.path.endsWith('/challenge/')) { return http.Response(jsonEncode({
            'id':'challenge','device_id':7,'user_id':2,'purpose':'GRANT','signature_contract':'ELEVAGE-DEVICE-V1'}),201); }
          expect(jsonDecode(request.body),{'permission_contract_version':2});posts++;
          return http.Response(jsonEncode(response),201);
        }));
      api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',capabilities:capabilities,access:'a',refresh:'r');
      if(downgrade) {
        await expectLater(api.provisionGrant(),throwsStateError);
        expect(secrets.values,{'historical-original':'retained'});
      } else {
        expect((await api.provisionGrant()).hasFineContract,isTrue);
        expect(secrets.values.keys.where((key)=>key.startsWith('offline_grant_history_')),hasLength(1));
      }
      expect(secrets.values['historical-original'],'retained');expect(posts,1);api.close();
    }
  });

  test('a prepared fine profile cannot silently renew as V1 on an old or disabled server',() async {
    final previous=await fineGrant();final secrets=TestSecretStore();
    final key='offline_grant_${Uri.encodeComponent('https://test.invalid/api')}_1_2';
    final original=jsonEncode({'token':previous.token});secrets.values[key]=original;
    var requests=0;
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
      clock:()=>syntheticNow,client:MockClient((request) async {
        requests++;expect(request.url.path.endsWith('/capabilities/'),isTrue);
        return http.Response(jsonEncode({'user':2,'exploitation':1,'role':'OPERATEUR',
          'offline_policy_enabled':true,'membership':{'version':1},
          'write_generation':1,'primary_device':{'id':7,'installation_uuid':'test-installation'},
          'offline_permission_contract':{'supported_versions':[2],'issuance_enabled':false}}),200);
      }));
    api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',capabilities:{},access:'a',refresh:'r');
    await expectLater(api.provisionGrant(),throwsStateError);
    expect(requests,1);expect(secrets.values,{key:original});api.close();
  });

  test('late login cannot restore a session invalidated by locking',() async {
    final response=Completer<http.Response>(),started=Completer<void>();final secrets=TestSecretStore();
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
      client:MockClient((request) {started.complete();return response.future;}));
    final tablet=TabletController(api:api,secrets:secrets,automaticSyncEnabled:false);
    final login=tablet.signIn('Jean','synthetic-only');
    final check=expectLater(login,throwsStateError);
    await started.future;tablet.lock();response.complete(http.Response('{"access":"a","refresh":"r"}',200));
    await check;expect(api.personal,isNull);expect(secrets.values,isEmpty);
    tablet.dispose();api.close();
  });

  test('stale personal HTTP reply is refused after profile lock',() async {
    final hold=Completer<http.Response>(),started=Completer<void>();
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:TestSecretStore(),
      client:MockClient((request) {started.complete();return hold.future;}));
    api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',capabilities:{},access:'a',refresh:'r');
    final request=api.request('GET','/cache-page/');final check=expectLater(request,throwsStateError);
    await started.future;api.invalidatePendingPersonalWork();hold.complete(http.Response('{"results":[]}',200));
    await check;api.close();
  });

  test('session transition is visible and HTTP login alone never creates a profile or grant',() {
    var requests=0;final secrets=TestSecretStore();
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
      client:MockClient((request) async {requests++;return http.Response('{}',500);}));
    final tablet=TabletController(api:api,secrets:secrets,automaticSyncEnabled:false);
    expect(tablet.sessionTransitionLabel,contains('Connexion HTTP'));
    api.personal=OnlineOperatorIdentity(userId:1,farmId:1,role:'OWNER',capabilities:{},access:'a',refresh:'r');
    expect(tablet.sessionTransitionLabel,contains('dispositif à préparer explicitement'));
    tablet.farmId=1;expect(tablet.sessionTransitionLabel,contains('profil personnel à préparer'));
    tablet.profiles=[{'user':2}];expect(tablet.sessionTransitionLabel,contains('PIN requis'));
    tablet.knownDeviceRevoked=true;expect(tablet.sessionTransitionLabel,contains('saisie bloquée'));
    expect(requests,0);expect(secrets.values,isEmpty);expect(tablet.operators,isNull);
    tablet.dispose();api.close();
  });
}
