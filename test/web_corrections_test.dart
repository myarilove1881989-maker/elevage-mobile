import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/dettes_screen.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';

void main() {
  setUp(() { SharedPreferences.setMockInitialValues({}); });
  test('balances use canonical slash and retain partial/paid amounts', () async {
    final api=ApiService(client:MockClient((request) async {
      expect(request.url.path,'/api/dettes-clients/');
      return http.Response(jsonEncode([
        {'id':1,'nom':'Partiel','total_facture':150,'total_paye':50,'reste':100,'statut':'PARTIEL'},
        {'id':2,'nom':'Réglé','total_facture':100,'total_paye':100,'reste':0,'statut':'PAYE'},
      ]),200);
    }));
    final result=await api.getDettesClients();
    expect(result[0].reste,100);expect(result[1].reste,0);expect(result[1].statut,'PAYE');api.close();
  });
  testWidgets('API failure hides financial totals and empty list, retry recovers', (tester) async {
    var failed=true;
    final api=ApiService(client:MockClient((request) async => failed
      ? http.Response('{"error":"Unavailable"}',503)
      : http.Response('[]',200)));
    await tester.pumpWidget(MaterialApp(home:DettesScreen(apiService:api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossible de charger'),findsOneWidget);
    expect(find.text('Total facturé'),findsNothing);
    expect(find.text('Aucun solde client trouvé'),findsNothing);
    failed=false;await tester.tap(find.text('Réessayer'));await tester.pumpAndSettle();
    expect(find.textContaining('Impossible de charger'),findsNothing);
    expect(find.text('Aucun solde client trouvé'),findsOneWidget);api.close();
  });
  test('repeat posts selected dates and days in one atomic request', () async {
    final api=ApiService(client:MockClient((request) async {
      expect(request.url.path,'/api/tasks/repeat/');
      expect(jsonDecode(request.body),{'title':'Soins','start_date':'2026-11-02',
        'end_date':'2026-11-08','assigned_to':23,'weekdays':[1,3,5]});
      return http.Response('{"created":3,"skipped":0,"tasks":[]}',201);
    }));
    final result=await api.createRepeatedTasks('Soins',DateTime(2026,11,2),DateTime(2026,11,8),
      assignedTo:23,weekdays:[1,3,5]);
    expect(result['created'],3);api.close();
  });
  testWidgets('sidebar omits duplicate users entry and keeps settings', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FarmNavigation(actions:{
      FarmDestination.settings:(){},FarmDestination.users:(){},
    }))));
    expect(find.byKey(const ValueKey('navigation-users')),findsNothing);
    expect(find.byKey(const ValueKey('navigation-settings')),findsOneWidget);
  });
}
