import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/services/health_notifications.dart';
import 'foundation_api_test.dart' show TestIdentity,TestSecretStore;
import 'offline_fine_permissions_test.dart' show fineGrant,syntheticNow,SyntheticUnlocked;
import 'vaccine_projection_test.dart' show vaccineSnapshot,vaccine,vialA;
import 'health_agenda_form_test.dart' show healthTask;
import 'health_notifications_test.dart' show FakeHealthSink;
void main(){
  test('a rejected receipt batch cannot cancel a native reminder before rollback',()async{
    SharedPreferences.setMockInitialValues({});
    final directory=await Directory.systemTemp.createTemp('health-receipt-atomic-');
    final db=FarmDatabase(encryptedExecutor(File('${directory.path}/farm.db'),'ab'*32),farmId:1,serverNamespace:'synthetic',clock:()=>syntheticNow);
    final secrets=TestSecretStore();
    final grant=await fineGrant(vaccineStock:true,healthAgenda:true,credentialVersion:1,codes:['finance.read','agenda.read','agenda.progress','vaccinations.create']);
    final tablet=TabletController(api:FoundationApi(baseUrl:'https://synthetic.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,client:MockClient((_)=>throw StateError('NO_HTTP_ALLOWED'))),secrets:secrets,clock:()=>syntheticNow,automaticSyncEnabled:false);
    tablet.farmId=1;tablet.deviceId=7;tablet.generation=1;tablet.cache=db;tablet.operators=SyntheticUnlocked(grant,secrets);
    final sink=FakeHealthSink(),service=HealthReminderCoordinator(sink:FakeHealthSink(),preferences:SharedPreferences.getInstance(),clock:()=>syntheticNow);
    final reminders=HealthReminderCoordinator(sink:sink,preferences:service.preferences,clock:()=>syntheticNow);
    HealthReminderCoordinator.current=reminders;
    try {
      final task=healthTask(status:'IN_PROGRESS');task['health']['planned_at']=syntheticNow.add(const Duration(hours:1)).toIso8601String();
      await db.replaceConfirmedCache('tasks',[task]);await db.replaceConfirmedCache('vaccine_stock',[vaccineSnapshot()]);
      await reminders.setEnabled(1,2,true);await reminders.sync(farm:1,user:2,tasks:[task],isCurrent:()=>true,validUntil:grant.expiresAt);
      final reminderId=sink.scheduled.keys.single;
      final row=await tablet.declare(entityType:'VACCINATION',operationType:'CREATE',payload:{'vaccine_version':1,'lot_ref':{'server_id':10},'product':vaccine,'animals':1,'allocations':[{'vial':vialA,'doses':1}],'task_id':10,'task_version':1},businessOccurredAt:syntheticNow);
      final actual=healthTask(version:2,status:'DONE',fulfilled:true);
      final stock=vaccineSnapshot(revision:2,coverage:{'7':[[1,1]]});stock['vials'][0]['physical']=19;
      final receipt=<String,dynamic>{'client_operation_id':row.operationId,'author_user_id':2,'transport_status':'SERVER_RECEIVED','business_status':'CONFIRMED','reason_code':'','received_at':syntheticNow.toIso8601String(),'applied_at':syntheticNow.toIso8601String(),'server_entity_id':'55','server_version':'farm:2','vaccine_stock_snapshot':stock,'health_task_snapshot':actual,'vaccination_snapshot':{'id':55,'exploitation':1,'lot':10,'version':'vac:2','voided':false,'planned_task':{'id':10,'version':2},'animals':1,'allocations':[]}};
      await expectLater(db.acceptReceipts([receipt,{'client_operation_id':'INVALID'}]),throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect((await db.cachedPage('tasks')).single['data']['health']['fulfilled'],false);
      expect(sink.scheduled.containsKey(reminderId),true,reason:'native reminders must reflect committed receipts only');
      expect((await db.listOutbox()).single.declaration,row.declaration);
      await db.acceptReceipts([receipt]);await Future<void>.delayed(Duration.zero);
      expect((await db.cachedPage('tasks')).single['data']['health']['fulfilled'],true);
      expect(sink.scheduled,isEmpty);expect(sink.cancelled,contains(reminderId));
    }finally{
      HealthReminderCoordinator.current=null;await reminders.suspend();tablet.cache=null;tablet.dispose();await db.close();
      expect(directory.absolute.path.startsWith('${Directory.systemTemp.absolute.path}${Platform.pathSeparator}'),true);
      expect(directory.path.split(Platform.pathSeparator).last.startsWith('health-receipt-atomic-'),true);await directory.delete(recursive:true);
    }
  });
}
