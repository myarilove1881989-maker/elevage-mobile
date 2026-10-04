import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/screens/register_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthApiFake extends ApiService {
  bool offline = true;
  bool succeeds = false;

  @override
  Future<bool> login(String username, String password) async {
    if (offline) throw const ApiConnectionException();
    if (succeeds) return true;
    throw Exception('Identifiants invalides');
  }

  @override
  Future<dynamic> register(String username, String email, String password) async {
    if (offline) throw const ApiConnectionException();
    if (succeeds) return {'message': 'Compte créé'};
    throw Exception('Cette adresse e-mail est déjà utilisée.');
  }

  @override
  Future<Map<String, dynamic>> getDashboard({int? especeId}) async => {
    'kpis': <String, dynamic>{},
  };

  @override
  Future<List<dynamic>> getLots() async => [];

  @override
  Future<List<dynamic>> getEspeces() async => [];

  @override
  Future<List<dynamic>> getTasks() async => [];

  @override
  Future<double> getTotalDettes() async => 0;
}

Widget authApp(Widget screen) => MaterialApp(
  locale: const Locale('fr'),
  supportedLocales: const [Locale('fr'), Locale('en')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: screen,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Connexion distingue serveur inaccessible et mauvais identifiants',
      (tester) async {
    final api = AuthApiFake();
    await tester.pumpWidget(authApp(LoginScreen(apiService: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'eleveur');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Se connecter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossible de joindre le serveur'), findsOneWidget);
    expect(find.text('Identifiants invalides'), findsNothing);

    api.offline = false;
    await tester.tap(find.widgetWithText(ElevatedButton, 'Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Identifiants invalides'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inscription explique la panne et garde les erreurs du serveur',
      (tester) async {
    final api = AuthApiFake();
    await tester.pumpWidget(authApp(RegisterScreen(apiService: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'eleveur');
    await tester.enterText(find.byType(TextField).at(1), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret123');
    await tester.enterText(find.byType(TextField).at(3), 'secret123');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Créer mon compte'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Créer mon compte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossible de joindre le serveur'), findsOneWidget);

    api.offline = false;
    await tester.tap(find.widgetWithText(ElevatedButton, 'Créer mon compte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cette adresse e-mail est déjà utilisée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connexion réussie ouvre le Dashboard avec le même service',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = AuthApiFake()
      ..offline = false
      ..succeeds = true;
    await tester.pumpWidget(authApp(LoginScreen(apiService: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'eleveur');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Se connecter'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.widget<DashboardScreen>(find.byType(DashboardScreen)).apiService,
        same(api));
    expect(find.byKey(const Key('topProductionTrackingButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inscription réussie revient à la connexion', (tester) async {
    final api = AuthApiFake()
      ..offline = false
      ..succeeds = true;
    await tester.pumpWidget(authApp(LoginScreen(apiService: api)));
    await tester.pumpAndSettle();
    final registerLink = find.text('Créer un compte');
    await tester.ensureVisible(registerLink);
    await tester.tap(registerLink);
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'eleveur');
    await tester.enterText(find.byType(TextField).at(1), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret123');
    await tester.enterText(find.byType(TextField).at(3), 'secret123');
    final submit = find.widgetWithText(ElevatedButton, 'Créer mon compte');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
