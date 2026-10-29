import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/settings_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'production_tracking_test.dart' show ProductionTrackingApiFake, testApp;

class FarmApi extends ProductionTrackingApiFake {
  String name = 'Ferme La Gloire';
  String role = 'OWNER';
  int writes = 0;
  bool missing=false;
  @override
  Future<dynamic> get(String endpoint) async {
    if (endpoint == '/farm-profile/') { if(missing) throw const ApiHttpException(404,'missing'); return {'id': 1, 'nom': name}; }
    final result = await super.get(endpoint);
    result['role'] = role;
    result['permission_contract']['role'] = role;
    return result;
  }
  @override
  Future<dynamic> patch(String endpoint, Map<String, dynamic> data) async {
    expect(endpoint, '/farm-profile/');
    writes++; name = data['nom'] as String;
    return {'id': 1, 'nom': name};
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'username': 'compte personnel'});
    ApiService.token = 'synthetic-farm-profile';
  });
  tearDown(() => ApiService.token = null);
  for (final role in ['OWNER', 'OPERATEUR']) {
    testWidgets('shared dashboard farm identity for $role', (tester) async {
      final api = FarmApi()..role = role;
      await tester.pumpWidget(testApp(DashboardScreen(apiService: api)));
      await tester.pumpAndSettle();
      final heading = tester.widget<RichText>(find.byKey(const Key('dashboardHeading'))).text.toPlainText();
      expect(heading, contains('Ferme La Gloire'));
      expect(heading, isNot(contains('compte personnel')));
    });
  }
  testWidgets('owner saves shared farm name in settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FarmApi();
    await tester.pumpWidget(testApp(SettingsScreen(apiService: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Ferme La Gloire'), 'Ferme du Centre');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final save = find.byType(FilledButton);
    await tester.scrollUntilVisible(save, 300, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.name, 'Ferme du Centre');
    expect(api.writes, 1);
  });
  testWidgets('operator sees shared name but cannot edit it', (tester) async {
    final api = FarmApi()..role = 'OPERATEUR';
    await tester.pumpWidget(testApp(SettingsScreen(apiService: api)));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Ferme La Gloire'));
    expect(field.enabled, false);
    expect(api.writes, 0);
  });
  testWidgets('absent profile API explains backend dependency without inventing a farm name',(tester) async {
    final api=FarmApi()..missing=true;
    await tester.pumpWidget(testApp(SettingsScreen(apiService:api)));await tester.pumpAndSettle();
    expect(find.textContaining('Une mise à jour du serveur est nécessaire'),findsOneWidget);
    expect(find.textContaining('Reconnectez-vous puis réessayez'),findsNothing);
    expect(api.writes,0);
  });

}
