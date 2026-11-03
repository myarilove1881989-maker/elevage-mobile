import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/feed_local_catalog.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/expense_form_controller.dart';
import 'package:app_elevage/offline/expense_business_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:http/testing.dart';
import 'foundation_api_test.dart' show TestIdentity,TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant,syntheticNow,SyntheticUnlocked;
import 'feed_stock_projection_test.dart' show baseline,product;

void main(){
  test('one encrypted outbox survives interruption and reboot, folds receipts and retains conflicts',()async{
    final directory=await Directory.systemTemp.createTemp('phase3-feed-test-');
    final file=File('${directory.path}/farm.db');
    tzdata.initializeTimeZones();
    final grant=await fineGrant(feedStock:true,credentialVersion:1,codes:['finance.read','expenses.create','feed.create']);
    final secrets=TestSecretStore();
    var db=FarmDatabase(encryptedExecutor(file,'ab'*32),farmId:1,serverNamespace:'synthetic',clock:()=>syntheticNow);
    final tablet=TabletController(api:FoundationApi(baseUrl:'https://synthetic.invalid/api',secrets:secrets,deviceIdentity:TestIdentity(),client:MockClient((_)async=>throw StateError('NO_HTTP_ALLOWED'))),
      secrets:secrets,clock:()=>syntheticNow,automaticSyncEnabled:false);
    tablet.farmId=1;tablet.deviceId=7;tablet.generation=1;tablet.cache=db;tablet.operators=SyntheticUnlocked(grant,secrets);
    await db.saveOperatorProfile(grant,'Synthétique');
    tablet.profiles=await db.operatorProfiles();tablet.selectedName='Synthétique';
    await db.replaceConfirmedCache('feed_stock',[baseline(kg:'0',revision:0)]);
    await db.replaceConfirmedCache('lots',[{'id':10,'espece':4,'exploitation':1,'nom':'Lot','stock':10}]);
    await db.replaceConfirmedCache('species',[{'id':4,'exploitation':1,'nom':'Poulet'}]);
    await db.replaceConfirmedCache('expense_categories',[{'id':3,'nom':'Aliment','exploitation':1,'stock_purpose':'FEED'}]);
    final form=ExpenseFormController(tablet,ExpenseBusinessDate(tz.getLocation('Europe/Paris')));
    await form.load();expect(form.editable,isTrue,reason:form.error);
    await form.submit(lot:form.lots.single,categoryId:3,amount:'1000.00',note:'Achat local réel',
      day:form.dates.businessDayOf(syntheticNow),feedSupply:{'product':product,'species':4,'kg':'500','received_on':'2026-10-12'});
    final purchase=(await db.listOutbox()).single;
    expect(purchase.declaration['payload']['feed_supply']['kg'],'500');form.dispose();
    final out=await tablet.declare(entityType:'ALIMENTATION',operationType:'CREATE',payload:{'stock_version':1,'lot_ref':{'server_id':10},
      'product':product,'species':4,'source_lot':null,'quantite_kg':'80','supply_parent_uuid':purchase.operationId},dependencies:[purchase.operationId],businessOccurredAt:syntheticNow);
    expect((await localFeedCatalog(tablet))['products'][0]['positions'][0]['estimated_kg'],'420.000');
    await db.leasePending();await db.close();
    db=FarmDatabase(encryptedExecutor(file,'ab'*32),farmId:1,serverNamespace:'synthetic',clock:()=>syntheticNow);
    tablet.cache=db;
    final rows=await db.listOutbox();expect(rows,hasLength(2));expect(rows.every((r)=>r.transportStatus!='IN_FLIGHT'),isTrue);
    expect(rows.singleWhere((r)=>r.operationId==out.operationId).declaration['dependencies'],[purchase.operationId]);
    // Receipt loss: a cache refresh may include both effects before their receipts arrive.
    await db.replaceConfirmedCache('feed_stock',[baseline(kg:'420',revision:3,coverage:{'7':[[1,2]]})]);
    expect((await localFeedCatalog(tablet))['products'][0]['positions'][0]['estimated_kg'],'420');
    Map<String,dynamic> receipt(OutboxEntry r,String id)=>{'client_operation_id':r.operationId,'author_user_id':2,'transport_status':'SERVER_RECEIVED',
      'business_status':'CONFIRMED','reason_code':'','received_at':syntheticNow.toIso8601String(),'applied_at':syntheticNow.toIso8601String(),
      'server_entity_id':id,'server_version':'farm:3','feed_stock_snapshot':baseline(kg:'420',revision:3,coverage:{'7':[[1,2]]})};
    await db.acceptReceipts([receipt(purchase,'1'),receipt(out,'2')]);
    await db.acceptReceipts([receipt(out,'2')]);
    expect((await localFeedCatalog(tablet))['products'][0]['positions'][0]['estimated_kg'],'420');
    final original=(await db.listOutbox()).singleWhere((r)=>r.operationId==out.operationId).declaration;
    expect(original,out.declaration);
    final conflict=await tablet.declare(entityType:'ALIMENTATION',operationType:'CREATE',payload:{'stock_version':1,'lot_ref':{'server_id':10},'product':product,'species':4,'quantite_kg':'900'},businessOccurredAt:syntheticNow);
    await db.acceptReceipts([{...receipt(conflict,'3'),'business_status':'NEEDS_RECONCILIATION','reason_code':'BUSINESS_VALIDATION_REQUIRED','applied_at':null}]);
    expect((await localFeedCatalog(tablet))['review_operations'],[conflict.operationId]);
    expect(await db.listOutbox(),hasLength(3));
    // An owner cancellation arriving later must not resurrect the original in local history.
    await db.acceptReceipts([{...receipt(out,'2'),'server_version':'farm:4',
      'feed_stock_snapshot':baseline(kg:'500',revision:4,coverage:{'7':[[1,2]]}),
      'feed_distribution_snapshot':{'id':2,'exploitation':1,'lot':10,'voided':true,'quantite_kg':'80',
        'physical_stock':{'product':product,'distribution_version':'feed:11'}}}]);
    final history=await localFeedHistory(tablet,Uri.parse('/alimentation/distributions/?lot=10'),null);
    expect(history.where((row)=>row['id']==2),isEmpty);
    tablet.cache=null;tablet.dispose();await db.close();
    expect(directory.absolute.path.startsWith('${Directory.systemTemp.absolute.path}${Platform.pathSeparator}'),isTrue);
    expect(directory.path.split(Platform.pathSeparator).last.startsWith('phase3-feed-test-'),isTrue);
    await directory.delete(recursive:true);
  });
}
