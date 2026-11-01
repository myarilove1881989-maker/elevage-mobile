@TestOn('browser')
library;
import 'package:test/test.dart' show TestOn;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'auth_connection_test.dart' show authApp;
import 'web_j1_qualification_test.dart' show WebQualificationApi;

class RepeatApi extends WebQualificationApi {
  int repeats=0; List<int>? days;
  @override Future<Map<String,dynamic>> createRepeatedTasks(String title,DateTime start,
      DateTime end,{required int assignedTo,required List<int> weekdays}) async {
    repeats++; days=weekdays; assigned=assignedTo;
    return {'created':1,'skipped':0,'tasks':[]};
  }
}
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-repeat-test';globalToken=ApiService.token;});
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();});
  testWidgets('repeat dialog validates days and submits chosen operator without duplicate single request', (tester) async {
    tester.view.physicalSize=const Size(1440,1100);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final api=RepeatApi();
    await tester.pumpWidget(authApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu).first);await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('navigation-users')),findsNothing);
    await tester.tap(find.byKey(const ValueKey('navigation-agenda')));await tester.pumpAndSettle();
    await tester.tap(find.text('Attribuer une tâche'));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agendaTaskTitle')),'Soins répétés');
    await tester.tap(find.byKey(const Key('agendaAssignee')));await tester.pumpAndSettle();
    await tester.tap(find.text('qa_operator').last);await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));await tester.pumpAndSettle();
    expect(find.text('Date de fin (incluse)'),findsOneWidget);
    for(final chip in ['Lun','Mar','Mer','Jeu','Ven','Sam','Dim']) {
      await tester.tap(find.widgetWithText(FilterChip,chip));await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton,'Ajouter'));await tester.pumpAndSettle();
    expect(find.textContaining('au moins un jour'),findsOneWidget);expect(api.repeats,0);
    final today=['Lun','Mar','Mer','Jeu','Ven','Sam','Dim'][DateTime.now().weekday-1];
    await tester.tap(find.widgetWithText(FilterChip,today));await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'Ajouter'));await tester.pumpAndSettle();
    expect(api.repeats,1);expect(api.days,[DateTime.now().weekday]);expect(api.assigned,23);
    expect(api.assignedTitle,isNull);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('settings retain user administration for owner and hide it for operator', (tester) async {
    final api=RepeatApi();
    await tester.pumpWidget(authApp(SettingsScreen(apiService:api)));await tester.pumpAndSettle();
    expect(find.text('Gestion des utilisateurs'),findsOneWidget);
    expect(find.text('Création des utilisateurs'),findsNothing);
    await tester.pumpWidget(const SizedBox());api.role='OPERATEUR';
    await tester.pumpWidget(authApp(SettingsScreen(apiService:api)));await tester.pumpAndSettle();
    expect(find.text('Gestion des utilisateurs'),findsNothing);
    expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());api.close();
  });
}
