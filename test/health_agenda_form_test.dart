import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/health_agenda_screen.dart';
import 'package:app_elevage/screens/vaccination_screen.dart';
import 'production_tracking_test.dart' show testApp;
import 'vaccine_projection_test.dart' show vaccineSnapshot,vaccine,vialA;

Map<String,dynamic> healthTask({int version=1,bool fulfilled=false,String status='TODO'})=>{
  'id':10,'title':'Rendez-vous sanitaire prévu','date':'2026-10-13','description':'Observation explicite','priority':'NORMAL',
  'status':status,'assigned_to':2,'version':version,'report':'','created_by':1,'created_at':'2026-10-12T12:00:00Z','updated_at':'2026-10-12T12:00:00Z',
  'completed_by':null,'completed_at':null,'cancelled_by':null,'cancelled_at':null,'cancellation_reason':'',
  'health':{'exploitation':1,'product':vaccine,'vaccine':'Vaccin test','lot':10,'lot_name':'Lot','species':4,'planned_time':null,'planned_at':null,'timezone':'Europe/Paris',
    'original_date':'2026-10-13','original_time':null,'interval_days':null,'series_end':null,'series_uuid':'00000000-0000-4000-8000-000000000001',
    'fulfilled':fulfilled,'overdue':false,'actual':fulfilled?{'vaccination':55,'date':'2026-10-12T12:00:00Z','operator':2,'operator_name':'Jean','difference_days':-1}:null}};
class HealthAgendaApi extends ApiService {
  bool lose=false,planner=true,owner=false;final requests=<Map<String,dynamic>>[];List<Map<String,dynamic>> tasks=[];
  @override Future<dynamic> get(String path)async {
    if(path=='/me/capabilities/')return {'user':2,'exploitation':1,'role':owner?'OWNER':'OPERATEUR','offline_policy_enabled':false,'membership':{'version':1},
      'permission_contract':{'version':owner?2:1,'user':2,'exploitation':1,'role':owner?'OWNER':'OPERATEUR','rights_version':1,
        'permissions':['finance.read','agenda.read',if(!owner)'agenda.progress','vaccinations.create',if(planner)'agenda.plan']}};
    if(path=='/vaccine-supplies/') {
      final data=vaccineSnapshot();for(final vial in data['vials'] as List)vial['usable_until']=DateTime.now().toUtc().add(const Duration(days:1)).toIso8601String();return data;
    }
    if(path=='/tasks/health-assignees/')return [{'user':2,'name':'Jean'}];
    if(path=='/tasks/?active=true' || path=='/tasks/')return tasks;
    throw StateError('Unmocked test path $path');
  }
  @override Future<dynamic> patch(String path,Map<String,dynamic> data)async {
    requests.add({...data});final task=tasks.single;task['status']=data['status'];task['cancellation_reason']=data['cancellation_reason'];task['version']=(task['version'] as int)+1;return task;
  }
  @override Future<List<dynamic>> getTasks()async=>tasks;
  @override Future<dynamic> post(String path,Map<String,dynamic> data)async {
    requests.add({...data});if(lose)throw const ApiConnectionException();
    if(path=='/tasks/health-plan/')return [healthTask()];
    return {'id':55,'operation_uuid':data['operation_uuid']};
  }
}
Future<void> revealHealth(WidgetTester tester,String key)async {
  final finder=find.byKey(Key(key));if(finder.evaluate().isEmpty)await tester.scrollUntilVisible(finder,250,scrollable:find.byType(Scrollable).first);
  await tester.ensureVisible(finder);await tester.pumpAndSettle();
}
Future<void> chooseHealth(WidgetTester tester)async {
  await tester.tap(find.byKey(const Key('health-product')));await tester.pumpAndSettle();await tester.tap(find.text('Vaccin test').last);await tester.pumpAndSettle();
  await revealHealth(tester,'health-assignee');await tester.tap(find.byKey(const Key('health-assignee')));await tester.pumpAndSettle();await tester.tap(find.text('Jean').last);await tester.pumpAndSettle();
}
void main(){
  setUp(() {ApiService.token='synthetic-health-session';globalToken=null;});
  tearDown(() {ApiService.token=null;globalToken=null;});
  testWidgets('planning without interval invents no recurrence and lost response retries same intent',(tester)async{
    final api=HealthAgendaApi()..lose=true;await tester.pumpWidget(testApp(HealthPlanForm(api:api,lotId:10)));await tester.pumpAndSettle();
    await chooseHealth(tester);await revealHealth(tester,'health-save');await tester.tap(find.byKey(const Key('health-save')));await tester.pumpAndSettle();
    expect(api.requests,hasLength(1));expect(api.requests.first.containsKey('interval_days'),false);expect(api.requests.first['planned_time'],null);
    api.lose=false;await revealHealth(tester,'health-save');await tester.tap(find.byKey(const Key('health-save')));await tester.pumpAndSettle();
    expect(api.requests,hasLength(2));expect(api.requests[0],api.requests[1]);await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('explicit interval and end are the only source of recurrence',(tester)async{
    final api=HealthAgendaApi();await tester.pumpWidget(testApp(HealthPlanForm(api:api,lotId:10)));await tester.pumpAndSettle();await chooseHealth(tester);
    await revealHealth(tester,'health-date');await tester.enterText(find.byKey(const Key('health-date')),'2030-05-01');
    await revealHealth(tester,'health-interval');await tester.enterText(find.byKey(const Key('health-interval')),'7');
    await revealHealth(tester,'health-end');await tester.enterText(find.byKey(const Key('health-end')),'2030-05-22');
    await revealHealth(tester,'health-save');await tester.tap(find.byKey(const Key('health-save')));await tester.pumpAndSettle();
    expect(api.requests.single['interval_days'],7);expect(api.requests.single['end_date'],'2030-05-22');
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('DONE and a local vaccination remain visibly unconfirmed',(tester)async{
    final task=healthTask(status:'DONE')..['_health_vaccination_pending']=true;final api=HealthAgendaApi()..planner=false..tasks=[task];
    await tester.pumpWidget(testApp(HealthAgendaScreen(api:api)));await tester.pumpAndSettle();
    expect(find.text('Aucune vaccination confirmée pour ce rendez-vous.'),findsOneWidget);
    expect(find.text('Vaccination locale : confirmation serveur en attente.'),findsOneWidget);expect(find.byKey(const Key('health-plan-create')),findsNothing);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('actual vaccination attached to existing task carries version and only one vaccine command',(tester)async{
    final task=healthTask(version:2),api=HealthAgendaApi()..tasks=[healthTask(version:2)];
    await tester.pumpWidget(testApp(VaccinationForm(api:api,lotId:10,plannedTask:task)));await tester.pumpAndSettle();
    await revealHealth(tester,'vaccination-animals');await tester.enterText(find.byKey(const Key('vaccination-animals')),'1');
    await revealHealth(tester,'used-$vialA');await tester.enterText(find.byKey(Key('used-$vialA')),'1');
    await revealHealth(tester,'save-vaccination');await tester.tap(find.byKey(const Key('save-vaccination')));await tester.pumpAndSettle();
    expect(api.requests,hasLength(1));expect(api.requests.single['task_id'],10);expect(api.requests.single['task_version'],2);
    expect(api.requests.single['allocations'][0]['doses'],1);await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('cancelled sanitary appointments remain visible with their reason and history',(tester)async{
    final api=HealthAgendaApi()..owner=true..tasks=[healthTask()];
    await tester.pumpWidget(testApp(HealthAgendaScreen(api:api)));await tester.pumpAndSettle();
    final cancel=find.text('Annuler avec motif');if(cancel.evaluate().isEmpty)await tester.scrollUntilVisible(cancel,250,scrollable:find.byType(Scrollable).first);
    await tester.ensureVisible(cancel);await tester.tap(cancel);await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Annulation explicite');await tester.tap(find.text('Confirmer'));await tester.pumpAndSettle();
    expect(api.requests.single['status'],'CANCELLED');expect(find.textContaining('Annulée'),findsOneWidget);
    expect(find.text('Motif : Annulation explicite'),findsOneWidget);expect(find.text('Historique'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('a switched profile cannot resend an earlier planning intention',(tester)async{
    final api=HealthAgendaApi()..lose=true;
    await tester.pumpWidget(testApp(HealthPlanForm(api:api,lotId:10)));await tester.pumpAndSettle();await chooseHealth(tester);
    await revealHealth(tester,'health-save');await tester.tap(find.byKey(const Key('health-save')));await tester.pumpAndSettle();expect(api.requests,hasLength(1));
    ApiService.token='another-synthetic-profile';api.lose=false;
    await revealHealth(tester,'health-save');await tester.tap(find.byKey(const Key('health-save')));await tester.pumpAndSettle();
    expect(api.requests,hasLength(1));await tester.pumpWidget(const SizedBox());api.close();
  });

}
