import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'outbox_test.dart' show testOutboxGrant;

void main() {
  late Directory directory;late FarmDatabase db;late VerifiedOfflineGrant grant;
  final now=DateTime.utc(2026,10,7);final key=List.filled(64,'d').join();
  FarmDatabase open()=>FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),key),farmId:1,serverNamespace:'sales-test',clock:()=>now);
  setUp(() async {directory=await Directory.systemTemp.createTemp('elevage-sales-');db=open();grant=await testOutboxGrant(2,now);});
  tearDown(() async {await db.close();await directory.delete(recursive:true);});
  Future<OutboxEntry> enqueue(String kind,Map<String,dynamic> payload,{List<String> dependencies=const []})=>db.enqueue(
    grant:grant,isSessionCurrent:()=>true,entityType:kind,operationType:'CREATE',payload:payload,businessOccurredAt:now,dependencies:dependencies);
  Map<String,dynamic> lot(int stock,{int eggs=0,int revision=0})=>{'id':7,'nom':'Lot test','exploitation':1,
    'stock':stock,'stock_oeufs':eggs,'type_production':'OEUFS','confirmed_business_revision':revision};
  Map<String,dynamic> receipt(OutboxEntry entry,{String status='CONFIRMED',int revision=1})=>{
    'client_operation_id':entry.operationId,'author_user_id':2,'transport_status':'SERVER_RECEIVED',
    'business_status':status,'server_entity_id':'42','received_at':now.toIso8601String(),
    'applied_at':now.toIso8601String(),'server_version':'farm:$revision','stock_snapshots':[],
    'entity_mappings':[]};
  Map<String,dynamic> recognition({String assigned='30000.00',String remaining='20000.00',int payment=42})=>{
    'montant_recu':'50000.00','montant_affecte':assigned,'montant_a_rapprocher':remaining,'payment_id':payment,'mode':'ESPECES'};

  test('local client sale cash chain survives encrypted reopen with original Jean attribution and exact cents',() async {
    await db.replaceConfirmedCache('lots',[lot(20)]);
    final client=await enqueue('CLIENT',{'nom':'Client sans réseau'});
    final sale=await enqueue('VENTE_ANIMAUX',{'lot_ref':{'server_id':7},'client_ref':{'local_uuid':client.declaration['local_entity_id']},
      'quantite':3,'prix_unitaire':'13.01'},dependencies:[client.operationId]);
    final cash=await enqueue('ENCAISSEMENT',{'client_ref':{'local_uuid':client.declaration['local_entity_id']},
      'vente_ref':{'local_uuid':sale.declaration['local_entity_id']},'montant_recu':'39.03','mode':'ESPECES'},dependencies:[client.operationId,sale.operationId]);
    await db.close();db=open();
    final entries=await db.listOutbox();expect(entries,hasLength(3));expect(entries.every((entry)=>entry.authorId==2),isTrue);
    expect(entries.last.operationId,cash.operationId);expect(entries.last.declaration['dependencies'],containsAll([client.operationId,sale.operationId]));
    expect((await db.projectedPage('sales',search:client.declaration['local_entity_id'] as String)).single['data'],containsPair('montant_total','39.03'));
    expect((await db.projectedPage('lots')).single['data'],containsPair('projected_stock',17));
  });

  test('oversale remains a physical declaration while confirmed stock stays nonnegative',() async {
    await db.replaceConfirmedCache('lots',[lot(2)]);
    await enqueue('VENTE_ANIMAUX',{'lot_ref':{'server_id':7},'client_ref':{'server_id':9},'quantite':3,'prix_unitaire':'1.00'});
    final data=(await db.projectedPage('lots')).single['data'] as Map;
    expect(data['stock'],2);expect(data['projected_stock'],-1);expect(await db.listOutbox(),hasLength(1));
  });

  test('egg conditioning projects quantities and confirmation removes local delta exactly once',() async {
    await db.replaceConfirmedCache('lots',[lot(20,eggs:100)]);
    final sale=await enqueue('VENTE_OEUFS',{'lot_ref':{'server_id':7},'client_ref':{'server_id':9},
      'conditionnement':'PLATEAU','nombre_conditionnements':2,'prix_unitaire_conditionnement':'13.01'});
    expect((await db.projectedPage('lots')).single['data'],containsPair('projected_egg_stock',40));
    final confirmed=receipt(sale)..['stock_snapshots']=[lot(20,eggs:40,revision:1)]
      ..['entity_mappings']=[{'entity_type':'VENTE_OEUFS','local_entity_id':sale.declaration['local_entity_id'],'server_entity_id':42}];
    await db.acceptReceipts([confirmed]);await db.acceptReceipts([confirmed]);
    expect((await db.projectedPage('lots')).single['data'],containsPair('local_egg_delta',0));
    expect((await db.projectedPage('sales',search:'9')).single['data'],containsPair('montant_total','26.02'));
    await db.replaceConfirmedCache('sales',[{'id':70,'reference_id':42,'entity_type':'VENTE_OEUFS','client_id':9,'montant_total':'26.02'}]);
    expect(await db.projectedPage('sales'),hasLength(1));
  });

  test('50000 receipt keeps 30000 allocation and 20000 reconciliation across encrypted reopen',() async {
    final cash=await enqueue('ENCAISSEMENT',{'client_ref':{'server_id':9},'montant_recu':'50000.00','mode':'ESPECES'});
    await db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION')..['cash_recognition']=recognition()]);
    await db.close();db=open();
    final data=(await db.projectedPage('cash')).single['data'] as Map;
    expect(data['montant_recu'],'50000.00');expect(data['montant_affecte'],'30000.00');expect(data['montant_a_rapprocher'],'20000.00');
    expect((await db.listOutbox()).single.declaration['payload'],containsPair('montant_recu','50000.00'));
  });

  test('cash contradiction secret field and duplicate payment identity roll back the whole receipt',() async {
    final cash=await enqueue('ENCAISSEMENT',{'client_ref':{'server_id':9},'montant_recu':'50000.00','mode':'ESPECES'});
    await expectLater(db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION')..['cash_recognition']=recognition(remaining:'20000.01')]),throwsStateError);
    await expectLater(db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION')..['cash_recognition']=(recognition()..['jwt']='secret')]),throwsStateError);
    expect((await db.listOutbox()).single.transportStatus,'LOCAL_PENDING');
    await db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION')..['cash_recognition']=recognition()]);
    await expectLater(db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION')..['cash_recognition']=recognition(assigned:'29999.00',remaining:'20001.00')]),throwsStateError);
    await expectLater(db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION',revision:2)..['cash_recognition']=recognition(payment:43)]),throwsStateError);
    expect(((await db.projectedPage('cash')).single['data'] as Map)['payment_id'],42);
  });

  test('older cash status cannot undo a later reconciliation and confirmed cash needs recognition',() async {
    final cash=await enqueue('ENCAISSEMENT',{'client_ref':{'server_id':9},'montant_recu':'50000.00','mode':'ESPECES'});
    await expectLater(db.acceptReceipts([receipt(cash)]),throwsStateError);
    await db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION')..['cash_recognition']=recognition()]);
    await db.acceptReceipts([receipt(cash,revision:2)..['cash_recognition']=recognition(assigned:'50000.00',remaining:'0.00')]);
    await db.acceptReceipts([receipt(cash,status:'NEEDS_RECONCILIATION')..['cash_recognition']=recognition()]);
    expect((await db.listOutbox()).single.businessStatus,'CONFIRMED');
    expect(((await db.projectedPage('cash')).single['data'] as Map)['montant_a_rapprocher'],'0.00');
  });

  test('schema four upgrade adds recognition without deleting pending sale and literal client search is bounded',() async {
    final sale=await enqueue('VENTE_ANIMAUX',{'lot_ref':{'server_id':7},'client_ref':{'server_id':9},'quantite':1,'prix_unitaire':'1.00'});
    await db.customStatement('DROP TABLE terrain_cash_recognition');await db.customStatement('PRAGMA user_version=4');
    await db.close();db=open();expect((await db.listOutbox()).single.operationId,sale.operationId);
    await db.replaceConfirmedCache('clients',[{'id':1,'nom':'100% exact'},{'id':2,'nom':'100 autre'}]);
    expect((await db.projectedPage('clients',search:'100%')).single['data'],containsPair('id',1));
    expect(await db.projectedPage('cash'),isEmpty);
  });
}
