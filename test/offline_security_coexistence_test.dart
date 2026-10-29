import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;
import 'outbox_test.dart' show testOutboxGrant, seedHistoricalV1;

class InterruptedStore extends TestSecretStore {
  String? failurePrefix;
  String? holdPrefix;
  final entered=Completer<void>(), release=Completer<void>();
  @override Future<void> write(String key,String value) async {
    if(holdPrefix!=null && key.startsWith(holdPrefix!)) {
      if(!entered.isCompleted) entered.complete();
      await release.future;
    }
    if(failurePrefix!=null && key.startsWith(failurePrefix!)) {
      failurePrefix=null;
      throw StateError('Synthetic secure write interrupted before persistence');
    }
    await super.write(key,value);
  }
}

Map<String,dynamic> capabilities(bool enabled)=>{
  'user':2,'exploitation':1,'role':'OPERATEUR','membership':{'version':1},
  'offline_policy_enabled':true,'write_generation':1,
  'primary_device':{'id':7,'installation_uuid':'test-installation'},
  'offline_permission_contract':{'supported_versions':[2],'issuance_enabled':enabled},
};

FoundationApi apiFor(TestSecretStore secrets,Map<String,dynamic> response,
    {bool enabled=true,void Function()? grantPosted}) {
  final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
    clock:()=>syntheticNow,client:MockClient((request) async {
      if(request.url.path.endsWith('/capabilities/')) {
        return http.Response(jsonEncode(capabilities(enabled)),200);
      }
      if(request.url.path.endsWith('/challenge/')) {
        return http.Response(jsonEncode({
          'id':'challenge','device_id':7,'user_id':2,'purpose':'GRANT','signature_contract':'ELEVAGE-DEVICE-V1'}),201);
      }
      grantPosted?.call();
      expect(jsonDecode(request.body),{'permission_contract_version':2});
      return http.Response(jsonEncode(response),201);
    }));
  api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',
    capabilities:capabilities(enabled),access:'synthetic-a',refresh:'synthetic-r');
  return api;
}

void main() {
  test('signed fine duration over 7 days is refused but historical V1 duration stays compatible',() async {
    await expectLater(fineGrant(duration:const Duration(days:7,seconds:1)),throwsStateError);
    final fine=await fineGrant();
    expect(fine.expiresAt.difference(DateTime.fromMillisecondsSinceEpoch(
      (fine.claims['iat'] as int)*1000,isUtc:true)),const Duration(hours:24));
    final legacy=await testOutboxGrant(2,syntheticNow,legacy:true);
    expect(legacy.hasFineContract,isFalse);
    expect(legacy.permitsOperation('CLIENT','CREATE',syntheticNow.add(const Duration(days:2))),isFalse);
  });

  test('UTC offsets and DST labels do not alter signed instants or half-open expiry',() async {
    final grant=await fineGrant();
    final same=DateTime.parse('2026-10-12T14:00:00+02:00');
    expect(same,syntheticNow);
    expect(grant.permitsOperation('CLIENT','CREATE',same),isTrue);
    expect(grant.permitsOperation('CLIENT','CREATE',grant.expiresAt),isFalse);
    expect(grant.permitsOperation('CLIENT','CREATE',syntheticNow.subtract(const Duration(minutes:5))),isFalse);
    expect(DateTime.parse('2026-10-25T02:30:00+01:00').difference(
      DateTime.parse('2026-10-25T02:30:00+02:00')),const Duration(hours:1));
  });

  for(final stage in ['offline_grant_history_','offline_grant_https']) {
    test('partial $stage write retains denial marker and retries explicitly without V1',() async {
      late Map<String,dynamic> response;
      await fineGrant(issued:(value)=>response=value);
      final secrets=InterruptedStore()..failurePrefix=stage;
      secrets.values['historical-original']='retained';
      final api=apiFor(secrets,response);
      await expectLater(api.provisionGrant(),throwsStateError);
      final markerKeys=secrets.values.keys.where((key)=>key.startsWith('offline_fine_required_'));
      expect(markerKeys,hasLength(1));expect(secrets.values[markerKeys.single],'2');
      final currentKey='offline_grant_${Uri.encodeComponent('https://test.invalid/api')}_1_2';
      expect(secrets.values.containsKey(currentKey),isFalse);
      api.close();
      var posts=0;
      final old=apiFor(secrets,response,enabled:false,grantPosted:()=>posts++);
      await expectLater(old.provisionGrant(),throwsStateError);
      expect(posts,0);expect(secrets.values['historical-original'],'retained');old.close();
      final retry=apiFor(secrets,response);
      expect((await retry.provisionGrant()).hasFineContract,isTrue);
      expect(secrets.values.containsKey(currentKey),isTrue);
      expect(secrets.values['historical-original'],'retained');retry.close();
    });
  }

  test('marker interruption cannot install a current grant or erase previous V1',() async {
    late Map<String,dynamic> response;await fineGrant(issued:(value)=>response=value);
    final secrets=InterruptedStore()..failurePrefix='offline_fine_required_';
    final previous=await testOutboxGrant(2,syntheticNow,legacy:true);
    final currentKey='offline_grant_${Uri.encodeComponent('https://test.invalid/api')}_1_2';
    secrets.values[currentKey]=jsonEncode({'token':previous.token});
    final before=Map<String,String>.from(secrets.values),api=apiFor(secrets,response);
    await expectLater(api.provisionGrant(),throwsStateError);
    expect(secrets.values,before);api.close();
  });

  test('locking during an uncancellable secure write never reopens a personal profile',() async {
    late Map<String,dynamic> response;await fineGrant(issued:(value)=>response=value);
    final secrets=InterruptedStore()..holdPrefix='offline_grant_history_';
    final api=apiFor(secrets,response);
    final pending=api.provisionGrant();final rejected=expectLater(pending,throwsStateError);
    await secrets.entered.future;api.invalidatePendingPersonalWork();api.personal=null;
    secrets.release.complete();await rejected;
    expect(api.personal,isNull);
    expect(secrets.values.keys.where((key)=>key.startsWith('offline_fine_required_')),hasLength(1));
    expect(secrets.values.keys.where((key)=>key.startsWith('offline_grant_history_')),hasLength(1));
    expect(secrets.values.keys.where((key)=>key.startsWith('offline_grant_https')),isEmpty);
    api.close();
  });

  test('encrypted restart and software rollback preserve both original V1 and V2 intents',() async {
    final directory=await Directory.systemTemp.createTemp('c112b-synthetic-restart-');
    final file=File('${directory.path}/farm.db'),key=List.filled(32,'b2').join();
    var now=syntheticNow;
    FarmDatabase open()=>FarmDatabase(encryptedExecutor(file,key),farmId:1,
      serverNamespace:'c112b-test',clock:()=>now);
    var db=open();
    try {
      final legacy=await testOutboxGrant(2,now,legacy:true),fine=await fineGrant(
        grantId:'00000000-0000-4000-8000-999999999999');
      expect(fine.claims['jti'],isNot(legacy.claims['jti']));
      final originals=[];
      for(final grant in [legacy,fine]) {
        final row=grant.hasFineContract
          ? await db.enqueue(grant:grant,isSessionCurrent:()=>true,entityType:'CLIENT',
              operationType:'CREATE',payload:{'nom':'V2'},businessOccurredAt:now)
          : await seedHistoricalV1(db,grant,now);
        originals.add(row.declaration);
      }
      await db.close();now=now.add(const Duration(days:4));db=open();
      final pending=await db.leasePending();expect(pending,hasLength(2));
      expect(pending.map((row)=>row.declaration).toList(),originals);
      expect(pending.map((row)=>row.sequence),[1,2]);
      // Existing V1 transport carries immutable originals without interpreting grant v2.
      for(final row in pending) {
        expect(row.declaration.containsKey('permission_contract'),isFalse);
        expect(row.declaration['offline_authorization_id'],row==pending.first?legacy.claims['jti']:fine.claims['jti']);
      }
      await expectLater(db.enqueue(grant:fine,isSessionCurrent:()=>true,entityType:'CLIENT',
        operationType:'CREATE',payload:{},businessOccurredAt:now),throwsStateError);
      expect(await db.listOutbox(),hasLength(2));
    } finally {await db.close();await directory.delete(recursive:true);}
  });

  test('existing PIN clock floor blocks rollback and partial enrollment recovers explicitly',() async {
    final grant=await fineGrant();final secrets=InterruptedStore();var now=syntheticNow;
    final sessions=LocalOperatorSessions(store:secrets,namespace:'c112b-test',farmId:1,
      deviceId:7,generation:1,clock:()=>now);
    await sessions.enroll(grant,'123456');
    expect(sessions.session,isNull);
    // A persisted PIN with no active profile is a safe recoverable partial preparation.
    await expectLater(sessions.enroll(grant,'654321'),throwsStateError);
    expect(await sessions.unlock(grant,'123456'),isTrue);
    final pin=secrets.values.keys.single;final before=jsonDecode(secrets.values[pin]!) as Map;
    now=now.subtract(const Duration(seconds:1));
    expect(sessions.session,isNull);
    expect(await sessions.unlock(grant,'123456'),isFalse);
    expect(jsonDecode(secrets.values[pin]!),before);
    now=syntheticNow.add(const Duration(seconds:1));
    expect(await sessions.unlock(grant,'123456'),isTrue);
    sessions.lock();expect(sessions.session,isNull);
  },timeout:const Timeout(Duration(minutes:2)));
}
