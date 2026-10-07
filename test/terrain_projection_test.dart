import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'outbox_test.dart' show testOutboxGrant;

void main() {
  late Directory directory;late FarmDatabase db;late VerifiedOfflineGrant jean,paul;
  final now=DateTime.utc(2026,10,7);final key=List.filled(64,'b').join();
  FarmDatabase open()=>FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),key),farmId:1,serverNamespace:'terrain-test',clock:()=>now);
  setUp(() async {directory=await Directory.systemTemp.createTemp('elevage-terrain-');db=open();jean=await testOutboxGrant(2,now);paul=await testOutboxGrant(3,now);});
  tearDown(() async {await db.close();await directory.delete(recursive:true);});
  Future<OutboxEntry> client(VerifiedOfflineGrant grant,String name)=>db.enqueue(grant:grant,isSessionCurrent:()=>true,
    entityType:'CLIENT',operationType:'CREATE',payload:{'nom':name},businessOccurredAt:now);
  Map<String,dynamic> receipt(OutboxEntry entry,{int serverId=42,String? localId})=>{
    'client_operation_id':entry.operationId,'author_user_id':entry.authorId,'transport_status':'SERVER_RECEIVED',
    'business_status':'CONFIRMED','received_at':now.toIso8601String(),'applied_at':now.toIso8601String(),
    'server_entity_id':'$serverId','entity_mappings':[{'entity_type':'CLIENT',
      'local_entity_id':localId??entry.declaration['local_entity_id'],'server_entity_id':serverId}]};

  test('shared client projection survives encrypted reopen and retains separate personal authors',() async {
    final first=await client(jean,'Client Jean');await client(paul,'Client Paul');
    final rows=await db.projectedPage('clients');expect(rows,hasLength(2));
    expect(rows.map((r)=>(r['data'] as Map)['nom']),containsAll(['Client Jean','Client Paul']));
    expect(rows.every((r)=>r['state']=='UNREVIEWED'),isTrue);
    await db.close();db=open();
    expect(await db.projectedPage('clients'),hasLength(2));
    expect((await db.listOutbox(authorId:2)).single.operationId,first.operationId);
  });

  test('mapping and receipt commit atomically then confirmed cache removes duplicate projection',() async {
    final entry=await client(jean,'Client Jean');
    await db.acceptReceipts([receipt(entry)]);
    final rows=await db.projectedPage('clients');expect((rows.single['data'] as Map)['id'],42);
    expect(rows.single['state'],'CONFIRMED');
    await db.replaceConfirmedCache('clients',[{'id':42,'nom':'Client Jean serveur'}]);
    final merged=await db.projectedPage('clients');expect(merged,hasLength(1));
    expect((merged.single['data'] as Map)['nom'],'Client Jean serveur');
    expect(await db.listOutbox(),hasLength(1));
  });

  test('foreign local UUID mapping cannot confirm or mutate original projection',() async {
    final entry=await client(jean,'Client Jean');
    await expectLater(db.acceptReceipts([receipt(entry,localId:newOperationUuid())]),throwsStateError);
    expect((await db.listOutbox()).single.transportStatus,'LOCAL_PENDING');
    expect(await db.customSelect('SELECT * FROM terrain_entity_mapping').get(),isEmpty);
    expect((await db.projectedPage('clients')).single['state'],'UNREVIEWED');
  });

  test('contradictory server mapping is refused without losing confirmed history',() async {
    final entry=await client(jean,'Client Jean');await db.acceptReceipts([receipt(entry)]);
    await expectLater(db.acceptReceipts([receipt(entry,serverId:43)]),throwsStateError);
    expect((await db.listOutbox()).single.serverEntityId,'42');
    expect((await db.projectedPage('clients')).single['data'],containsPair('id',42));
  });

  test('task projection advances local version and dependency without exposing another operator task',() async {
    await db.replaceConfirmedCache('tasks',[
      {'id':10,'title':'Visite','assigned_to':2,'status':'TODO','version':1,'report':''},
      {'id':11,'title':'Paul seulement','assigned_to':3,'status':'TODO','version':1,'report':''},
    ]);
    final first=await db.enqueue(grant:jean,isSessionCurrent:()=>true,entityType:'TASK',operationType:'UPDATE',
      payload:{'task_id':10,'status':'IN_PROGRESS','report':'Commencé'},expectedServerVersion:'1',businessOccurredAt:now);
    final rows=await db.projectedPage('tasks',taskUserId:2);expect(rows,hasLength(1));
    expect(rows.single['data'],containsPair('version',2));expect(rows.single['dependency'],first.operationId);
    await db.enqueue(grant:jean,isSessionCurrent:()=>true,entityType:'TASK',operationType:'UPDATE',
      payload:{'task_id':10,'status':'DONE','report':'Fait'},expectedServerVersion:'2',dependencies:[first.operationId],businessOccurredAt:now);
    await db.close();db=open();
    final reopened=await db.projectedPage('tasks',taskUserId:2);
    expect(reopened.single['data'],containsPair('status','DONE'));expect(reopened.single['data'],containsPair('version',3));
    expect((await db.projectedPage('tasks',taskUserId:3)).single['data'],containsPair('id',11));
  });

  test('schema 3 queue survives additive mapping migration',() async {
    final entry=await client(jean,'Client Jean');
    await db.customStatement('DROP TABLE terrain_entity_mapping');await db.customStatement('PRAGMA user_version=3');
    await db.close();db=open();
    expect((await db.listOutbox()).single.operationId,entry.operationId);
    expect((await db.projectedPage('clients')).single['data'],containsPair('nom','Client Jean'));
    await db.acceptReceipts([receipt(entry)]);
    expect((await db.projectedPage('clients')).single['data'],containsPair('id',42));
  });
}
