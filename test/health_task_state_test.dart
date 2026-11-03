import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/offline/health_task_state.dart';
import 'package:app_elevage/services/classic_terrain_command.dart';
import 'package:app_elevage/offline/outbox.dart';
void main(){
  test('pending vaccination and completed logistics never fabricate confirmed clinical evidence',(){
    final original=OutboxEntry(declaration:{'exploitation_id':1,'author_user_id':2,'entity_type':'VACCINATION','payload':{'task_id':10}},transportStatus:'LOCAL_PENDING',businessStatus:'UNREVIEWED',attemptCount:0,lastError:'');
    final data=projectHealthTasks([{'id':10,'status':'DONE','health':{'exploitation':1,'fulfilled':false,'actual':null}}],[original],1,2).single;
    expect(data['health']['fulfilled'],false);expect(data['_health_vaccination_pending'],true);expect(data['health']['actual'],null);
    expect(()=>projectHealthTasks([{'id':10,'health':{'exploitation':2}}],[],1,2),throwsStateError);
  });
  test('task progress uses the existing signed TASK contract and freezes occurrence and UUID',(){
    const uuid='00000000-0000-4000-8000-000000000001';
    final command=ClassicTerrainCommand.decode('PATCH','/tasks/10/',{'status':'IN_PROGRESS','report':'Avancement seulement','expected_version':2,'operation_uuid':uuid,'reported_at':'2026-11-03T12:00:00Z'})!;
    expect(command.kind,'TASK');expect(command.operation,'UPDATE');expect(command.expectedVersion,'2');expect(command.operationId,uuid);
    expect(command.at,'2026-11-03T12:00:00Z');expect(command.payload,{'task_id':10,'status':'IN_PROGRESS','report':'Avancement seulement'});
    expect(ClassicTerrainCommand.decode('PATCH','/tasks/10/',{'status':'CANCELLED','cancellation_reason':'Annulation','expected_version':2}),null);
  });
  test('same-version derived overdue time is not a contradictory task but real changes are',(){
    expect(sameTaskField('health',{'overdue':false,'fulfilled':false},{'overdue':true,'fulfilled':false}),true);
    expect(sameTaskField('health',{'fulfilled':false},{'fulfilled':true}),false);
    expect(sameTaskField('date','2026-11-03','2026-11-04'),false);
  });  test('offline date-only lateness is recomputed in the explicit agenda timezone',(){
    tzdata.initializeTimeZones();
    final task={'status':'DONE','date':'2026-10-13','health':{'timezone':'Europe/Paris','fulfilled':false,'planned_at':null,'overdue':false}};
    expect(healthTaskOverdue(task,DateTime.utc(2026,10,13,10)),false);
    expect(healthTaskOverdue(task,DateTime.utc(2026,10,13,23)),true);
    task['status']='CANCELLED';expect(healthTaskOverdue(task,DateTime.utc(2026,10,15)),false);
  });
}
