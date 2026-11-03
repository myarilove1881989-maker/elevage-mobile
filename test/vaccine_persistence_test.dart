import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/vaccine_local.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/expense_form_controller.dart';
import 'package:app_elevage/offline/expense_business_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:http/testing.dart';
import 'foundation_api_test.dart' show TestIdentity,TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant,syntheticNow,SyntheticUnlocked;
import 'vaccine_projection_test.dart' show vaccineSnapshot,vaccine,vialA,vialB;
void main(){
  test('vaccine expense and vaccination survive encrypted reopen and receipt loss in the existing outbox',() async {
    final directory=await Directory.systemTemp.createTemp('phase4-vaccine-test-'),file=File('${directory.path}/farm.db');
    tzdata.initializeTimeZones();final secrets=TestSecretStore();
    final grant=await fineGrant(vaccineStock:true,credentialVersion:1,codes:['finance.read','expenses.create','vaccinations.create','vaccinations.loss']);
    var db=FarmDatabase(encryptedExecutor(file,'ab'*32),farmId:1,serverNamespace:'synthetic',clock:()=>syntheticNow);
    final tablet=TabletController(api:FoundationApi(baseUrl:'https://synthetic.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,client:MockClient((_)=>throw StateError('NO_HTTP_ALLOWED'))),secrets:secrets,clock:()=>syntheticNow,automaticSyncEnabled:false);
    tablet.farmId=1;tablet.deviceId=7;tablet.generation=1;tablet.cache=db;tablet.operators=SyntheticUnlocked(grant,secrets);
    await db.saveOperatorProfile(grant,'Synthétique');tablet.profiles=await db.operatorProfiles();tablet.selectedName='Synthétique';
    final empty=vaccineSnapshot()..['vials']=<dynamic>[];
    await db.replaceConfirmedCache('vaccine_stock',[empty]);
    await db.replaceConfirmedCache('lots',[{'id':10,'espece':4,'exploitation':1,'nom':'Lot','stock':10}]);
    await db.replaceConfirmedCache('expense_categories',[{'id':3,'nom':'Vaccin renommé','exploitation':1,'stock_purpose':'VACCINE'}]);
    final form=ExpenseFormController(tablet,ExpenseBusinessDate(tz.getLocation('Europe/Paris')));await form.load();expect(form.editable,true,reason:form.error);
    await form.submit(lot:form.lots.single,categoryId:3,amount:'1000.00',note:'Achat vaccins',day:form.dates.businessDayOf(syntheticNow),
      vaccineSupply:{'product':vaccine,'species':4,'vial_count':10,'doses_per_vial':20,'manufacturer_batch':'SYNTHETIQUE','expires_on':'2026-11-30','received_on':'2026-10-12'});
    final purchase=(await db.listOutbox()).single;expect(purchase.declaration['entity_type'],'DEPENSE');
    expect(purchase.declaration['payload']['vaccine_supply']['vial_count'],10);form.dispose();
    expect((await localVaccineCatalog(tablet))['vials'],isEmpty,reason:'No unconfirmed vial may be selected');
    Map<String,dynamic> receipt(OutboxEntry row,String id,Map<String,dynamic> snapshot)=>{
      'client_operation_id':row.operationId,'author_user_id':2,'transport_status':'SERVER_RECEIVED','business_status':'CONFIRMED','reason_code':'',
      'received_at':syntheticNow.toIso8601String(),'applied_at':syntheticNow.toIso8601String(),'server_entity_id':id,'server_version':'farm:${snapshot['confirmed_business_revision']}',
      'vaccine_stock_snapshot':snapshot};
    await db.acceptReceipts([receipt(purchase,'1',vaccineSnapshot(revision:2,coverage:{'7':[[1,1]]}))]);
    final vaccination=await tablet.declare(entityType:'VACCINATION',operationType:'CREATE',businessOccurredAt:syntheticNow,
      payload:{'vaccine_version':1,'lot_ref':{'server_id':10},'product':vaccine,'animals':35,'allocations':[{'vial':vialA,'doses':20},{'vial':vialB,'doses':15}]});
    expect((await localVaccineCatalog(tablet))['vials'][1]['estimated_usable'],5);
    await db.leasePending();await db.close();db=FarmDatabase(encryptedExecutor(file,'ab'*32),farmId:1,serverNamespace:'synthetic',clock:()=>syntheticNow);tablet.cache=db;
    expect((await db.listOutbox()).every((r)=>r.transportStatus!='IN_FLIGHT'),true);
    final confirmed=vaccineSnapshot(revision:3,coverage:{'7':[[1,2]]});confirmed['vials'][0]['physical']=0;confirmed['vials'][1]['physical']=5;
    await db.replaceConfirmedCache('vaccine_stock',[confirmed]);
    expect((await localVaccineCatalog(tablet))['vials'][1]['estimated_usable'],5);
    final accepted=receipt(vaccination,'2',confirmed)..['vaccination_snapshot']={'id':2,'exploitation':1,'lot':10,'version':'vac:10','voided':false,'vaccine':'Synthétique','animals':35,'allocations':[]};
    await db.acceptReceipts([accepted]);await db.acceptReceipts([accepted]);
    expect((await db.listOutbox()).singleWhere((r)=>r.operationId==vaccination.operationId).declaration,vaccination.declaration);
    final conflict=await tablet.declare(entityType:'VACCINATION',operationType:'CREATE',businessOccurredAt:syntheticNow,payload:{'vaccine_version':1,'lot_ref':{'server_id':10},'product':vaccine,'animals':1,'allocations':[{'vial':vialA,'doses':1}]});
    await db.acceptReceipts([{...receipt(conflict,'',confirmed),'business_status':'NEEDS_RECONCILIATION','applied_at':null,'reason_code':'STOCK_CONFLICT'}]);
    expect((await localVaccineCatalog(tablet))['review_operations'],[conflict.operationId]);expect(await db.listOutbox(),hasLength(3));
    expect((await localVaccinationHistory(tablet,'10',null)).any((row)=>row['state']=='NEEDS_RECONCILIATION'),true);
    final unauthorized=await fineGrant(vaccineStock:true,credentialVersion:1,codes:['finance.read','vaccinations.create']);
    tablet.operators=SyntheticUnlocked(unauthorized,secrets);
    await expectLater(tablet.declare(entityType:'VACCINATION',operationType:'CREATE',businessOccurredAt:syntheticNow,
      payload:{'vaccine_version':1,'allocations':[{'vial':vialB,'doses':0,'lost':1}]}),throwsStateError);
    final oldGrant=await fineGrant(credentialVersion:1,codes:['finance.read','vaccinations.create']);
    tablet.operators=SyntheticUnlocked(oldGrant,secrets);
    await expectLater(tablet.declare(entityType:'VACCINATION',operationType:'CREATE',businessOccurredAt:syntheticNow,
      payload:{'vaccine_version':1,'allocations':[{'vial':vialB,'doses':1}]}),throwsStateError);
    expect(await db.listOutbox(),hasLength(3));
    tablet.cache=null;tablet.dispose();await db.close();
    expect(directory.absolute.path.startsWith('${Directory.systemTemp.absolute.path}${Platform.pathSeparator}'),true);
    expect(directory.path.split(Platform.pathSeparator).last.startsWith('phase4-vaccine-test-'),true);await directory.delete(recursive:true);
  });
}
