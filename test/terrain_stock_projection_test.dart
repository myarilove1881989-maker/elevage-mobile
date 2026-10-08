import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'outbox_test.dart' show testOutboxGrant;

void main() {
  late Directory directory;late FarmDatabase db;late VerifiedOfflineGrant grant;
  final now=DateTime.utc(2026,10,7);final key=List.filled(64,'c').join();
  FarmDatabase open()=>FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),key),farmId:1,serverNamespace:'stock-test',clock:()=>now);
  setUp(() async {directory=await Directory.systemTemp.createTemp('elevage-stock-');db=open();grant=await testOutboxGrant(2,now);});
  tearDown(() async {await db.close();await directory.delete(recursive:true);});
  Future<OutboxEntry> enqueue(String kind,Map<String,dynamic> payload,{List<String> dependencies=const []})=>db.enqueue(
    grant:grant,isSessionCurrent:()=>true,entityType:kind,operationType:'CREATE',payload:payload,businessOccurredAt:now,dependencies:dependencies);
  Map<String,dynamic> lot(int id,int stock,int revision,{int eggs=0})=>{'id':id,'nom':'Lot $id','exploitation':1,
    'stock':stock,'stock_oeufs':eggs,'type_production':'CHAIR','confirmed_business_revision':revision};
  Map<String,dynamic> receipt(OutboxEntry entry,int entityId,Map<String,dynamic> snapshot,{List<Map<String,dynamic>> mappings=const []})=>{
    'client_operation_id':entry.operationId,'author_user_id':2,'transport_status':'SERVER_RECEIVED',
    'business_status':'CONFIRMED','server_entity_id':'$entityId','received_at':now.toIso8601String(),
    'applied_at':now.toIso8601String(),'stock_snapshots':[snapshot],'entity_mappings':mappings};

  test('purchase mapping preserves pending local references and avoids double stock after confirmation',() async {
    await db.replaceConfirmedCache('lots',[lot(7,20,0)]);
    final purchase=await enqueue('ACHAT',{'nom_lot':'Provisoire','espece':1,'quantite':10,'prix_total':'30.00','prix_unitaire':'3.00'});
    final loss=await enqueue('MORTALITE',{'lot_ref':{'local_uuid':purchase.declaration['local_entity_id']},'quantite':2},dependencies:[purchase.operationId]);
    var rows=await db.projectedPage('lots');
    expect(rows.first['data'],containsPair('stock',20));expect(rows.last['data'],containsPair('projected_stock',8));
    await db.acceptReceipts([receipt(purchase,30,lot(42,10,1),mappings:[
      {'entity_type':'LOT','local_entity_id':purchase.declaration['local_entity_id'],'server_entity_id':42},
      {'entity_type':'ACHAT','local_entity_id':purchase.declaration['local_entity_id'],'server_entity_id':30},
    ])]);
    rows=await db.projectedPage('lots');final child=rows.firstWhere((row)=>(row['data'] as Map)['id']==42);
    expect(child['data'],containsPair('stock',10));expect(child['data'],containsPair('local_delta',-2));expect(child['data'],containsPair('projected_stock',8));
    await db.acceptReceipts([receipt(loss,31,lot(42,8,2))]);
    await db.close();db=open();rows=await db.projectedPage('lots');
    expect(rows.firstWhere((row)=>(row['data'] as Map)['id']==42)['data'],containsPair('local_delta',0));
    expect(rows.firstWhere((row)=>(row['data'] as Map)['id']==42)['data'],containsPair('projected_stock',8));
    expect(await db.listOutbox(),hasLength(2));
  });

  test('birth projects only living child and never changes parent or creates an all-stillborn stock',() async {
    await db.replaceConfirmedCache('lots',[lot(7,20,0)]);
    await enqueue('NAISSANCE',{'lot_ref':{'server_id':7},'total_naissances':5,'mort_nes':2,'nom_nouveau_lot':'Vivants'});
    await enqueue('NAISSANCE',{'lot_ref':{'server_id':7},'total_naissances':2,'mort_nes':2,'nom_nouveau_lot':'Mort-nés'});
    final rows=await db.projectedPage('lots');expect(rows,hasLength(2));
    expect(rows.first['data'],containsPair('projected_stock',20));expect(rows.last['data'],containsPair('projected_stock',3));
    expect(await db.listOutbox(),hasLength(2));
  });

  test('receipt stock wins over an earlier in-flight cache refresh and pending eggs are counted once',() async {
    await db.replaceConfirmedCache('lots',[lot(7,20,1,eggs:10)]);
    final collection=await enqueue('COLLECTE_OEUFS',{'lot_ref':{'server_id':7},'nombre_collecte':4,'nombre_casses':1});
    expect((await db.projectedPage('lots')).single['data'],containsPair('projected_egg_stock',13));
    await db.beginCacheRefresh('lots');await db.stageConfirmedPage('lots',[lot(7,20,1,eggs:10)]);
    await db.acceptReceipts([receipt(collection,50,lot(7,20,2,eggs:13))]);
    await db.commitCacheRefresh('lots',businessRevision:1);
    var data=(await db.projectedPage('lots')).single['data'];
    expect(data,containsPair('stock_oeufs',13));expect(data,containsPair('local_egg_delta',0));expect(data,containsPair('projected_egg_stock',13));
    await db.replaceConfirmedCache('lots',[lot(7,20,3,eggs:12)]);
    data=(await db.projectedPage('lots')).single['data'];expect(data,containsPair('projected_egg_stock',12));
    await db.acceptReceipts([receipt(collection,50,lot(7,20,2,eggs:13))]);
    expect((await db.projectedPage('lots')).single['data'],containsPair('stock_oeufs',12));
  });

  test('foreign or contradictory stock snapshot cannot confirm or rewrite local history',() async {
    await db.replaceConfirmedCache('lots',[lot(7,10,0)]);
    final loss=await enqueue('VOL',{'lot_ref':{'server_id':7},'quantite':2});
    await expectLater(db.acceptReceipts([receipt(loss,30,lot(8,8,1))]),throwsStateError);
    expect((await db.listOutbox()).single.transportStatus,'LOCAL_PENDING');
    await db.acceptReceipts([receipt(loss,30,lot(7,8,1))]);
    await expectLater(db.acceptReceipts([receipt(loss,30,lot(7,9,1))]),throwsStateError);
    expect((await db.projectedPage('lots')).single['data'],containsPair('stock',8));
    expect((await db.listOutbox()).single.declaration['payload'],containsPair('quantite',2));
  });

  test('unknown secret-bearing stock fields are refused before SQL persistence',() async {
    final loss=await enqueue('VOL',{'lot_ref':{'server_id':7},'quantite':1});
    final snapshot=lot(7,8,1)..['refresh_token']='synthetic-secret';
    await expectLater(db.acceptReceipts([receipt(loss,30,snapshot)]),throwsStateError);
    expect(await db.cachedPage('lots'),isEmpty);expect((await db.listOutbox()).single.businessStatus,'UNREVIEWED');
  });

  test('bounded search finds a lot beyond the first page and treats percent as literal',() async {
    await db.beginCacheRefresh('lots');
    await db.stageConfirmedPage('lots',[for(var i=1;i<=150;i++)lot(i,10,1)]);
    await db.stageConfirmedPage('lots',[for(var i=151;i<=250;i++)lot(i,10,1)]);
    await db.commitCacheRefresh('lots',businessRevision:1);
    expect(await db.projectedPage('lots'),hasLength(50));
    expect((await db.projectedPage('lots',search:'Lot 250')).single['data'],containsPair('id',250));
    await enqueue('ACHAT',{'nom_lot':'Lot % rare','quantite':2,'prix_unitaire':'1.00','prix_total':'2.00','espece':1});
    expect((await db.projectedPage('lots',search:'%')).single['data'],containsPair('nom','Lot % rare'));
  });

  final payloads=<String,Map<String,dynamic>>{
    'DEPENSE':{'lot_ref':{'server_id':7},'montant':'123.45'},
    'ALIMENTATION':{'lot_ref':{'server_id':7},'aliment':'Aliment','quantite_kg':'1.234','prix_kg':'10.00'},
    'PESEE':{'lot_ref':{'server_id':7},'nombre_animaux_peses':2,'poids_total_kg':'1.234'},
    'COLLECTE_OEUFS':{'lot_ref':{'server_id':7},'nombre_collecte':12,'nombre_casses':2},
    'MORTALITE':{'lot_ref':{'server_id':7},'quantite':2,'note':'Constat terrain'},
    'DON':{'lot_ref':{'server_id':7},'quantite':2,'note':'Don réalisé'},
    'VOL':{'lot_ref':{'server_id':7},'quantite':2,'note':'Vol constaté'},
    'ACHAT':{'nom_lot':'Lot acheté','espece':1,'quantite':10,'prix_unitaire':'3.00','prix_total':'30.00'},
    'NAISSANCE':{'lot_ref':{'server_id':7},'total_naissances':5,'mort_nes':2,'nom_nouveau_lot':'Enfant'},
  };
  for(final item in payloads.entries) {
    test('${item.key} declaration survives encrypted reopen with author date UUID and exact payload',() async {
      final entry=await enqueue(item.key,item.value);
      await db.close();db=open();
      final restored=(await db.listOutbox()).single;
      expect(restored.operationId,entry.operationId);expect(restored.authorId,2);
      expect(restored.transportStatus,'LOCAL_PENDING');expect(restored.businessStatus,'UNREVIEWED');
      expect(restored.declaration['payload'],item.value);expect(restored.declaration['business_occurred_at'],now.toIso8601String());
      expect(canonicalDeclaration(restored.declaration),isNot(contains(grant.token)));
    });
  }
}
