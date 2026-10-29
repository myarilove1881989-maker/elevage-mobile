import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/main.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/screens/farmer_access_screen.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/token_service.dart';
import 'unified_ux_test.dart' show VisualRuntime, testApp;
import 'auth_connection_test.dart' show AuthApiFake;
class OwnerApi extends AuthApiFake {
  @override Future<void> logout()=>ApiService(tokenStore:TokenService(useSecureStorage:false)).logout();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'session_kind':'farmer','username':'synthetic',
      'offline_marker':'preserved','pending_operations_marker':'preserved'});
    tzdata.initializeTimeZones();
    ApiService.token=null;globalToken=null;ApiService.farmerSession=false;
  });
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.farmerSession=false;});

  testWidgets('legacy farmer startup opens public owner and operator choices', (tester) async {
    final api=ApiService(tokenStore:TokenService(useSecureStorage:false));
    await tester.pumpWidget(ElevageApp(apiService:api,startFarmer:true));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen),findsOneWidget);
    expect(find.byType(FarmerAccessScreen),findsNothing);
    expect(find.textContaining('Espace éleveur'),findsOneWidget);
    expect(find.text('Connexion propriétaire'),findsOneWidget);
    await tester.tap(find.textContaining('Espace éleveur'));await tester.pumpAndSettle();
    expect(find.byType(FarmerAccessScreen),findsOneWidget);
    await tester.binding.handlePopRoute();await tester.pumpAndSettle();
    expect(find.byType(LoginScreen),findsOneWidget);
    expect(ApiService.token,isNull);
    await tester.pumpWidget(const SizedBox());api.close();
  });

  testWidgets('owner login then Quitter returns to both public choices', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280,800));
    final api=OwnerApi()..offline=false..succeeds=true;
    await tester.pumpWidget(testApp(LoginScreen(apiService:api)));
    await tester.enterText(find.byType(TextField).first,'synthetic-owner');
    await tester.enterText(find.byType(TextField).at(1),'synthetic');
    await tester.tap(find.text('Se connecter'));await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen),findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('session_kind'),'owner');
    await tester.tap(find.text('Quitter').last);await tester.pumpAndSettle();
    expect(find.byType(LoginScreen),findsOneWidget);
    expect(find.text('Connexion propriétaire'),findsOneWidget);
    expect(find.text('Espace éleveur'),findsOneWidget);
    expect(ApiService.farmerSession,isFalse);
    expect((await SharedPreferences.getInstance()).getString('session_kind'),isNull);
    await tester.pumpWidget(const SizedBox());api.close();await tester.binding.setSurfaceSize(null);
  });

  for(final exit in ['Quitter','Android back','lock']) {
    testWidgets('$exit removes private stack and role; restart stays public', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280,800));
      final runtime=VisualRuntime();
      final api=await runtime.signIn('synthetic','synthetic');
      ApiService.farmerSession=true;
      await tester.pumpWidget(testApp(FarmerSessionHost(runtime:runtime,api:api)));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen),findsOneWidget);
      if(exit=='Quitter') {
        await tester.tap(find.text('Quitter').last);
      } else if(exit=='Android back') {
        await tester.binding.handlePopRoute();
      } else {
        runtime.lock();
      }
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen),findsOneWidget);
      expect(find.byType(DashboardScreen),findsNothing);
      expect(find.byType(FarmerAccessScreen),findsNothing);
      expect(ApiService.farmerSession,isFalse);expect(ApiService.token,isNull);expect(globalToken,isNull);
      final prefs=await SharedPreferences.getInstance();
      expect(prefs.getString('session_kind'),isNull);expect(prefs.getString('username'),isNull);
      expect(prefs.getString('offline_marker'),'preserved');
      expect(prefs.getString('pending_operations_marker'),'preserved');
      expect(Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),isFalse);
      await tester.binding.handlePopRoute();await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen),findsNothing);
      final fresh=ApiService(tokenStore:TokenService(useSecureStorage:false));
      await fresh.loadToken();
      await tester.pumpWidget(ElevageApp(key:UniqueKey(),apiService:fresh));await tester.pumpAndSettle();
      expect(find.byType(LoginScreen),findsOneWidget);
      expect(find.textContaining('Espace éleveur'),findsOneWidget);
    expect(find.text('Connexion propriétaire'),findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,isEmpty);
      await tester.pumpWidget(const SizedBox());fresh.close();await tester.binding.setSurfaceSize(null);
    });
  }
}
