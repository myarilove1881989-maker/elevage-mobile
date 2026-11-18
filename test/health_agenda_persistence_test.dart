import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/health_task_state.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:http/testing.dart';
import 'foundation_api_test.dart' show TestIdentity,TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant,syntheticNow,SyntheticUnlocked;
import 'vaccine_projection_test.dart' show vaccineSnapshot,vaccine,vialA;
import 'health_agenda_form_test.dart' show healthTask;
void main(){
  test('existing encrypted TASK and vaccination declarations survive reboot and only server proof fulfils the task',()async{
    final directory=await Directory.systemTemp.createTemp('phase5-health-test-'),file=File('${directory.path}/farm.db'),secrets=TestSecretStore();
    final grant=await fineGrant(vaccineStock:true,healthAgenda:true,credentialVersion:1,codes:['finance.read','agenda.read','agenda.progress','vaccinations.create']);
    var db=FarmDatabase(encryptedExecutor(file,'ab'*32),farmId:1,serverNamespace:'synthetic',clock:()=>syntheticNow);
    final tablet=TabletController(api:FoundationApi(baseUrl:'https://synthetic.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,client:MockClient((_)=>throw StateError('NO_HTTP_ALLOWED'))),secrets:secrets,clock:()=>syntheticNow,automaticSyncEnabled:false);
    tablet.farmId=1;tablet.deviceId=7;tablet.generation=1;tablet.cache=db;tablet.operators=SyntheticUnlocked(grant,secrets);
    await db.replaceConfirmedCache('tasks',[healthTask(status:'IN_PROGRESS')]);await db.replaceConfirmedCache('vaccine_stock',[vaccineSnapshot()]);
    final progress=await tablet.declare(entityType:'TASK',operationType:'UPDATE',payload:{'task_id':10,'status':'DONE','report':'Avancement logistique'},expectedServerVersion:'1',businessOccurredAt:syntheticNow);
    final pending=projectHealthTasks([healthTask(status:'DONE')],await db.listOutbox(),1,2).single;
    expect(pending['_health_pending'],true);expect(pending['health']['fulfilled'],false);
    Map<String,dynamic> receipt(OutboxEntry row,String id)=>{'client_operation_id':row.operationId,'author_user_id':2,'transport_status':'SERVER_RECEIVED','business_status':'CONFIRMED','reason_code':'',
      'received_at':syntheticNow.toIso8601String(),'applied_at':syntheticNow.toIso8601String(),'server_entity_id':id,'server_version':'farm:2'};
    final done=healthTask(version:2,status:'DONE')..['report']='Avancement logistique';
    final legacy={...done,'exploitation':1}..remove('health');
    await db.acceptReceipts([{...receipt(progress,'10'),'task_snapshot':legacy,'health_task_snapshot':done}]);
    final vaccination=await tablet.declare(entityType:'VACCINATION',operationType:'CREATE',payload:{'vaccine_version':1,'lot_ref':{'server_id':10},'product':vaccine,'animals':1,
      'allocations':[{'vial':vialA,'doses':1}],'task_id':10,'task_version':2},businessOccurredAt:syntheticNow);
    final before=projectHealthTasks([done],await db.listOutbox(),1,2).single;expect(before['_health_vaccination_pending'],true);expect(before['health']['actual'],null);
    await db.leasePending();await db.close();db=FarmDatabase(encryptedExecutor(file,'ab'*32),farmId:1,serverNamespace:'synthetic',clock:()=>syntheticNow);tablet.cache=db;
    expect((await db.listOutbox()).every((r)=>r.transportStatus!='IN_FLIGHT'),true);
    final actual=healthTask(version:3,status:'DONE',fulfilled:true)..['report']='Avancement logistique';
    final stock=vaccineSnapshot(revision:3,coverage:{'7':[[1,2]]});stock['vials'][0]['physical']=19;
    final proof={...receipt(vaccination,'55'),'vaccine_stock_snapshot':stock,'health_task_snapshot':actual,
      'vaccination_snapshot':{'id':55,'exploitation':1,'lot':10,'version':'vac:20','voided':false,'planned_task':{'id':10,'version':3},'animals':1,'allocations':[]}};
    await db.acceptReceipts([proof]);await db.acceptReceipts([proof]);
    var cached=(await db.cachedPage('tasks')).single['data'] as Map;expect(cached['health']['fulfilled'],true);expect(cached['version'],3);
    await db.replaceConfirmedCache('tasks',[done]);cached=(await db.cachedPage('tasks')).single['data'] as Map;
    expect(cached['version'],3,reason:'A delayed cache refresh must not erase a newer confirmed clinical link');
    expect((await db.listOutbox()).singleWhere((r)=>r.operationId==vaccination.operationId).declaration,vaccination.declaration);
    final denied=await fineGrant(vaccineStock:true,healthAgenda:true,credentialVersion:1,codes:['finance.read']);tablet.operators=SyntheticUnlocked(denied,secrets);
    await expectLater(tablet.declare(entityType:'TASK',operationType:'UPDATE',payload:{'task_id':10,'status':'DONE'},expectedServerVersion:'3',businessOccurredAt:syntheticNow),throwsStateError);
    expect(await db.listOutbox(),hasLength(2));tablet.cache=null;tablet.dispose();await db.close();
    expect(directory.absolute.path.startsWith('${Directory.systemTemp.absolute.path}${Platform.pathSeparator}'),true);expect(directory.path.split(Platform.pathSeparator).last.startsWith('phase5-health-test-'),true);await directory.delete(recursive:true);
  });
}
