import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/outbox.dart';

Future<VerifiedOfflineGrant> testOutboxGrant(int user,DateTime now,{int farm=1}) async {
  final key=await Ed25519().newKeyPair();final public=await key.extractPublicKey();
  String encoded(dynamic value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
  final header=encoded({'alg':'EdDSA','kid':'outbox-test'});
  final claims=encoded({'iss':'elevage-offline','aud':'elevage-device','typ':'offline-authorization',
    'jti':'00000000-0000-4000-8000-${user.toString().padLeft(12,'0')}','sub':'$user',
    'membership_id':user,'exploitation_id':farm,'device_id':7,'rights_version':1,'write_generation':1,
    'capabilities':{'can_create_terrain_operation':true},'iat':now.subtract(const Duration(seconds:1)).millisecondsSinceEpoch~/1000,
    'exp':now.add(const Duration(days:3)).millisecondsSinceEpoch~/1000});
  final signature=await Ed25519().sign(utf8.encode('$header.$claims'),keyPair:key);
  final token='$header.$claims.${base64Url.encode(signature.bytes).replaceAll('=','')}';
  final pem='-----BEGIN PUBLIC KEY-----\n${base64.encode([0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00,...public.bytes])}\n-----END PUBLIC KEY-----';
  return VerifiedOfflineGrant.verify(token:token,publicKeyPem:pem,trustedKeyId:'outbox-test',
    farmId:farm,userId:user,deviceId:7,generation:1,rightsVersion:1,now:now);
}

void main() {
  late Directory directory;late File file;late String key;late FarmDatabase db;
  late DateTime clock;late VerifiedOfflineGrant jean,paul;
  FarmDatabase open()=>FarmDatabase(encryptedExecutor(file,key),farmId:1,serverNamespace:'outbox-test',clock:()=>clock);
  setUp(() async {
    directory=await Directory.systemTemp.createTemp('elevage-outbox-');file=File('${directory.path}/farm.db');
    key=List.generate(32,(_)=>Random.secure().nextInt(256)).map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    clock=DateTime.utc(2026,10,7);jean=await testOutboxGrant(2,clock);paul=await testOutboxGrant(3,clock);db=open();
  });
  tearDown(() async {await db.close();await directory.delete(recursive:true);});
  Future<OutboxEntry> enqueue({VerifiedOfflineGrant? grant,String? id,Map<String,dynamic>? payload,
    bool Function()? guard,Future<void> Function()? project,List<String> dependencies=const []})=>
    db.enqueue(grant:grant??jean,isSessionCurrent:guard??()=>true,entityType:'CLIENT',operationType:'CREATE',
      payload:payload??{'nom':'Fixture terrain'},businessOccurredAt:DateTime.utc(2026,10,6),operationId:id,
      project:project,dependencies:dependencies);

  test('original declaration remains Jean after Paul opens and caller changes nested payload',() async {
    final payload={'nom':'Jean client','details':{'ville':'Original'}};
    final original=await enqueue(payload:payload);
    (payload['details'] as Map)['ville']='Changed';
    await enqueue(grant:paul);
    final entries=await db.listOutbox();
    expect(entries.map((e)=>e.authorId),[3,2]);
    expect(original.declaration['offline_authorization_id'],jean.claims['jti']);
    expect((entries.last.declaration['payload'] as Map)['details'],{'ville':'Original'});
    expect(()=>((original.declaration['payload'] as Map)['details'] as Map)['ville']='Changed',throwsUnsupportedError);
    expect(canonicalDeclaration(entries.last.declaration),isNot(contains(jean.token)));
  });

  test('double submission uses one UUID and does not repeat local projection',() async {
    final id=newOperationUuid();var effects=0;
    final first=await enqueue(id:id,project:() async {effects++;});
    clock=clock.add(const Duration(seconds:1));
    final second=await enqueue(id:id,project:() async {effects++;});
    expect(second.sequence,first.sequence);expect(effects,1);expect(await db.listOutbox(),hasLength(1));
    await expectLater(enqueue(id:id,payload:{'nom':'Changed'}),throwsStateError);
  });

  test('outbox and projection rollback together, including sequence, on crash or lock',() async {
    await db.customStatement('CREATE TABLE synthetic_projection(id INTEGER PRIMARY KEY)');
    await expectLater(enqueue(project:() async {
      await db.customStatement('INSERT INTO synthetic_projection VALUES(1)');throw StateError('Synthetic crash');
    }),throwsStateError);
    expect(await db.listOutbox(),isEmpty);
    expect(await db.customSelect('SELECT * FROM synthetic_projection').get(),isEmpty);
    var opened=true;
    await expectLater(enqueue(guard:()=>opened,project:() async {
      await db.customStatement('INSERT INTO synthetic_projection VALUES(2)');opened=false;
    }),throwsStateError);
    expect(await db.listOutbox(),isEmpty);
    expect(await db.customSelect('SELECT * FROM synthetic_projection').get(),isEmpty);
    expect((await enqueue()).sequence,1);
  });

  test('SQL cannot rewrite or delete declaration; no JWT or another farm can be queued',() async {
    final entry=await enqueue();
    await expectLater(db.customStatement('UPDATE outbox SET declaration=declaration WHERE operation_id=?',[entry.operationId]),throwsA(anything));
    await expectLater(db.customStatement('DELETE FROM outbox WHERE operation_id=?',[entry.operationId]),throwsA(anything));
    await expectLater(enqueue(payload:{'nested':{'refresh_token':'secret'}}),throwsArgumentError);
    final other=await testOutboxGrant(2,clock,farm:2);
    await expectLater(enqueue(grant:other),throwsStateError);
    expect(await db.listOutbox(),hasLength(1));
  });

  test('lease is exclusive and interrupted request survives encrypted reopen with original author',() async {
    final original=await enqueue();
    final leases=await Future.wait([db.leasePending(),db.leasePending()]);
    expect(leases.expand((list)=>list),hasLength(1));
    expect((await db.listOutbox()).single.attemptCount,1);
    await db.close();db=open();
    final recovered=(await db.listOutbox()).single;
    expect(recovered.operationId,original.operationId);expect(recovered.authorId,2);
    expect(recovered.transportStatus,'RETRY_WAIT');expect(recovered.lastError,'INTERRUPTED_REQUEST');
    expect((await db.leasePending()).single.attemptCount,2);
    expect((await file.readAsBytes()).take(16).toList(),isNot(utf8.encode('SQLite format 3\u0000')));
  });

  test('receipt is separate from confirmation and invalid batch rolls back all receipt changes',() async {
    final entry=await enqueue();await db.leasePending();
    Map<String,dynamic> receipt({String state='UNREVIEWED'})=>{
      'client_operation_id':entry.operationId,'transport_status':'SERVER_RECEIVED','business_status':state,
      'author_user_id':2,'received_at':clock.toIso8601String(),'applied_at':null,'reason_code':'',
      'server_entity_id':'','server_version':''};
    await expectLater(db.acceptReceipts([receipt(),{...receipt(),'client_operation_id':newOperationUuid()}]),throwsStateError);
    expect((await db.listOutbox()).single.transportStatus,'IN_FLIGHT');
    await db.acceptReceipts([receipt()]);
    final received=(await db.listOutbox()).single;
    expect(received.transportStatus,'SERVER_RECEIVED');expect(received.businessStatus,'UNREVIEWED');
    expect(await db.awaitingReceipts(),hasLength(1));
    await expectLater(db.acceptReceipts([receipt(state:'CONFIRMED')]),throwsStateError);
    expect((await db.listOutbox()).single.businessStatus,'UNREVIEWED');
  });

  test('backoff preserves payload and blocked device never loses original declaration',() async {
    final entry=await enqueue();await db.leasePending();
    await db.transportFailure([entry.operationId],code:'NETWORK_FAILURE');
    expect(await db.leasePending(),isEmpty);
    clock=clock.add(const Duration(minutes:1));
    await db.leasePending();await db.transportFailure([entry.operationId],code:'HTTP_403',blocked:true);
    final preserved=(await db.listOutbox()).single;
    expect(preserved.transportStatus,'TRANSPORT_BLOCKED');expect(preserved.attemptCount,2);
    expect(preserved.declaration,entry.declaration);
  });

  test('schema 2 upgrades additively preserving confirmed cache and profiles',() async {
    await db.replaceConfirmedCache('clients',[{'id':1,'nom':'Retained'}]);
    await db.saveOperatorProfile(jean,'Jean');
    await db.customStatement('DROP TABLE outbox');await db.customStatement('DROP TABLE local_sequence_counter');
    await db.customStatement('PRAGMA user_version=2');await db.close();db=open();
    expect((await db.cachedPage('clients')).single['data'],{'id':1,'nom':'Retained'});
    expect((await db.operatorProfiles()).single['display_name'],'Jean');
    expect((await enqueue()).sequence,1);
  });
}
