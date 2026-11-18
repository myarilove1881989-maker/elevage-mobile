import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/owner_operation_history_screen.dart';
import 'package:app_elevage/screens/operation_history_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'ux_9a1_test.dart' show DisplayApiFake;
import 'dashboard_history_route_test.dart' show HistoryRouteApi;
import 'production_tracking_test.dart' show testApp;
void main(){
  setUpAll(tz.initializeTimeZones);
  setUp((){SharedPreferences.setMockInitialValues({});AppSettings.instance.languageCode='fr';ApiService.token='synthetic-behavior';});
  tearDown(()=>ApiService.token=null);
  for(final owner in [true,false]){
    testWidgets('history through Web drawer keeps owner/operator routing $owner',(tester)async{
      final api=HistoryRouteApi(owner);
      await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Historique'));await tester.tap(find.text('Historique'));await tester.pumpAndSettle();
      expect(find.byType(owner?OwnerOperationHistoryScreen:OperationHistoryScreen),findsOneWidget);
      expect(api.requests.any((p)=>p.startsWith('/history/') && p.contains(owner?'view=operations':'page=1')),isTrue);
      expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());api.close();
    });
  }
  testWidgets('failed refresh preserves complete confirmed snapshot',(tester)async{
    final api=DisplayApiFake();await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
    expect(find.text('81'),findsOneWidget);api.stock=99;api.fail=true;
    await tester.tap(find.byIcon(Icons.refresh).first);await tester.pumpAndSettle();
    expect(find.text('81'),findsOneWidget);expect(find.text('99'),findsNothing);
    expect(find.textContaining('Actualisation impossible'),findsOneWidget);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('failed species selection restores confirmed filter',(tester)async{
    final api=DisplayApiFake();await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();api.failDashboard=true;
    await tester.tap(find.byKey(const ValueKey('dashboardSpecies:null')));await tester.pumpAndSettle();
    await tester.tap(find.text('Poulet').last);await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboardSpecies:null')),findsOneWidget);expect(find.byKey(const ValueKey('dashboardSpecies:1')),findsNothing);
    expect(find.text('81'),findsOneWidget);expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('initial error exposes no invented zero or internal diagnostic',(tester)async{
    final api=DisplayApiFake()..failDashboard=true;await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pumpAndSettle();
    expect(find.textContaining('Chargement incomplet : bilan du tableau de bord'),findsOneWidget);expect(find.textContaining('HTTP 500'),findsNothing);expect(find.text('0'),findsNothing);
    api.failDashboard=false;await tester.tap(find.text('Réessayer'));await tester.pumpAndSettle();expect(find.text('81'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('late dashboard response after dispose is harmless',(tester)async{
    final api=DisplayApiFake()..holdDashboard=Completer<Map<String,dynamic>>();await tester.pumpWidget(testApp(DashboardScreen(apiService:api)));await tester.pump();
    await tester.pumpWidget(const SizedBox());api.holdDashboard!.complete({'kpis':{'stock':81}});await tester.pump();expect(tester.takeException(),isNull);api.close();
  });
}
