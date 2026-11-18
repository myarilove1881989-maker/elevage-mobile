import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_elevage/widgets/android_consumables_kpi.dart';
import 'package:app_elevage/widgets/dashboard_task_dialog.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'android120_stock_test.dart' show Stocks,session;
import 'dashboard_parity_capture_test.dart' show ParityApi;
import 'production_tracking_test.dart' show testApp;
import 'online_expense_form_test.dart' show OnlineExpenseServer,selectExpense;
import 'package:app_elevage/screens/add_depense_screen.dart';

class TaskApi extends ParityApi {
  int writes=0;
  @override Future<dynamic> get(String path) async {
    if(path=='/memberships/') return [{'user':2,'role':'OPERATEUR','is_active':true,'exploitation':1,'username':'Fictif'}];
    return super.get(path);
  }
  @override Future<void> createTask(String title,DateTime date,{int? assignedTo})async{writes++;}
}
void main(){
  setUpAll(tz.initializeTimeZones);
  setUp((){ApiService.token='synthetic-functional';SharedPreferences.setMockInitialValues({});AppSettings.instance.languageCode='fr';});
  tearDown(()=>ApiService.token=null);
  testWidgets('new expense is a separate explicit entry after server confirmation',(tester)async{
    ApiService.token='synthetic-employee';final server=OnlineExpenseServer();
    await tester.pumpWidget(testApp(AddDepenseScreen(apiService:server.api,stayAfterSuccess:true)));await tester.pumpAndSettle();await selectExpense(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('expense-submit')),150,scrollable:find.byType(Scrollable).first);await tester.tap(find.byKey(const Key('expense-submit')));await tester.pumpAndSettle();
    expect(server.posts,1);await tester.ensureVisible(find.byKey(const Key('expense-next')));await tester.tap(find.byKey(const Key('expense-next')));await tester.pumpAndSettle();
    expect(server.posts,1);expect(find.byKey(const Key('expense-next')),findsNothing);expect(tester.widget<TextField>(find.byKey(const Key('expense-amount'))).controller!.text,isEmpty);
    expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());server.api.close();
  });
  testWidgets('details preserve shared/reserved quantities, expiry and clear after profile change',(tester)async{
    final api=Stocks();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:300,height:190,child:AndroidConsumablesKpi(api:api,session:session(),sessionIdentity:ApiService.sessionIdentity,species:4,lot:10,revision:1)))));
    await tester.pumpAndSettle();await tester.tap(find.text('Consommables'));await tester.pumpAndSettle();
    expect(find.text('Confirmé : 550.125 kg'),findsOneWidget);
    expect(find.text('Partagé : 500.000 kg · Réservé : 50.125 kg'),findsOneWidget);
    await tester.tap(find.text('Vaccins'));await tester.pumpAndSettle();
    expect(find.text('Physique : 45 doses · Utilisable : 0 doses'),findsOneWidget);
    ApiService.token='other-profile';await tester.pump(const Duration(seconds:1));
    expect(find.textContaining('Physique :'),findsNothing);expect(find.textContaining('Stocks indisponibles.'),findsOneWidget);
    expect(api.reads.length,2);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('dirty task cancellation prompts once and retains input when refused',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>TextButton(onPressed:()=>showDialog<void>(context:context,builder:(dialog)=>DashboardTaskDialog(title:const Text('Test'),content:const DashboardTaskField(child:TextField()),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler'))])),child:const Text('Open')))));
    await tester.tap(find.text('Open'));await tester.pumpAndSettle();await tester.tap(find.byType(TextField));await tester.enterText(find.byType(TextField),'Fictif');await tester.pump();
    await tester.tap(find.text('Annuler'));await tester.pumpAndSettle();expect(find.text('Quitter la saisie ?'),findsOneWidget);
    await tester.tap(find.text('Continuer la saisie'));await tester.pumpAndSettle();expect(find.text('Fictif'),findsOneWidget);
    await tester.tap(find.text('Annuler'));await tester.pumpAndSettle();await tester.tap(find.text('Quitter'));await tester.pumpAndSettle();
    expect(find.byType(DashboardTaskDialog),findsNothing);expect(tester.takeException(),isNull);
  });
  testWidgets('confirmed task closes dialog with exactly one write',(tester)async{
    final api=TaskApi();await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));await tester.pumpAndSettle();await tester.ensureVisible(find.text('Agenda'));await tester.tap(find.text('Agenda'));await tester.pumpAndSettle();
    await tester.tap(find.text('Attribuer une tâche'));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agendaTaskTitle')),'Tâche fictive');
    await tester.tap(find.byKey(const Key('agendaAssignee')));await tester.pumpAndSettle();await tester.tap(find.text('Fictif').last);await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter').last);await tester.pumpAndSettle();
    expect(api.writes,1);expect(find.byKey(const Key('agendaTaskTitle')),findsNothing);expect(find.text('Quitter la saisie ?'),findsNothing);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());api.close();
  });
}
