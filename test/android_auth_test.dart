import 'dart:convert';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/main.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_connection_test.dart' show AuthApiFake;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final encrypted = <String, String>{};
  bool failWrite = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = null;
    globalToken = null;
    encrypted.clear();
    failWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return encrypted[key];
            case 'write':
              if (failWrite) throw PlatformException(code: 'write_failed');
              encrypted[key] = args['value'] as String;
              return null;
            case 'delete':
              encrypted.remove(key);
              return null;
            default:
              throw MissingPluginException();
          }
        });
  });

  tearDown(() {
    ApiService.token = null;
    globalToken = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Release refuse HTTP, localhost et une URL contenant des identifiants',
    () {
      expect(
        Config.validatedApiUrl('${Config.apiUrl}/', release: true),
        'https://backend-elevage.onrender.com/api',
      );
      for (final url in [
        'http://example.com/api',
        'https://localhost/api',
        'https://127.0.0.1/api',
        'https://10.0.2.2/api',
        'https://[::1]/api',
        'https://user:password@example.com/api',
        'not-a-url',
      ]) {
        expect(
          () => Config.validatedApiUrl(url, release: true),
          throwsStateError,
        );
      }
      expect(
        Config.validatedApiUrl('http://127.0.0.1:8002/api', release: false),
        'http://127.0.0.1:8002/api',
      );
    },
  );

  test(
    'Android écrit par le plugin sécurisé et ne garde aucun jeton en clair',
    () async {
      SharedPreferences.setMockInitialValues({
        'token': 'ancien',
        'auth_token': 'ancien',
      });
      final store = TokenService(useSecureStorage: true);
      await store.saveToken('nouveau');
      expect(encrypted['token'], 'nouveau');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), isNull);
      expect(prefs.getString('auth_token'), isNull);
      expect(await TokenService(useSecureStorage: true).getToken(), 'nouveau');
      await store.clearToken();
      expect(encrypted, isEmpty);
    },
  );

  test(
    'Android migre le jeton hérité puis supprime sa copie en clair',
    () async {
      SharedPreferences.setMockInitialValues({'token': 'hérité'});
      expect(await TokenService(useSecureStorage: true).getToken(), 'hérité');
      expect(encrypted['token'], 'hérité');
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        isNull,
      );
    },
  );

  test(
    'Une migration interrompue préserve le jeton hérité pour un nouvel essai',
    () async {
      SharedPreferences.setMockInitialValues({'token': 'hérité'});
      failWrite = true;
      await expectLater(
        TokenService(useSecureStorage: true).getToken(),
        throwsA(isA<PlatformException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        'hérité',
      );
      expect(encrypted, isEmpty);
    },
  );

  test(
    'Le stockage Web historique demeure compatible avec la relance et la déconnexion',
    () async {
      final store = TokenService(useSecureStorage: false);
      await store.saveToken('web');
      expect((await SharedPreferences.getInstance()).getString('token'), 'web');
      expect(await TokenService(useSecureStorage: false).getToken(), 'web');
      await store.clearToken();
      expect(await store.getToken(), isNull);
      expect(encrypted, isEmpty);
    },
  );

  test(
    'Connexion, relance, authentification Bearer et déconnexion Android',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/token/')) {
          expect(jsonDecode(request.body)['password'], ' mot de passe ');
          return http.Response('{"access":"access-test"}', 200);
        }
        expect(request.headers['Authorization'], 'Bearer access-test');
        return http.Response('[]', 200);
      });
      final store = TokenService(useSecureStorage: true);
      final api = ApiService(client: client, tokenStore: store);
      expect(await api.login('test', ' mot de passe '), isTrue);
      ApiService.token = null;
      globalToken = null;
      final restarted = ApiService(
        client: client,
        tokenStore: TokenService(useSecureStorage: true),
      );
      await restarted.loadToken();
      expect(ApiService.token, 'access-test');
      await restarted.getLots();
      await restarted.logout();
      expect(ApiService.token, isNull);
      expect(globalToken, isNull);
      expect(encrypted, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString('username'),
        isNull,
      );
      api.close();
    },
  );

  test(
    'Une connexion refusée affiche l’erreur et ne crée pas de session',
    () async {
      final api = ApiService(
        client: MockClient(
          (_) async =>
              http.Response('{"detail":"Identifiants invalides"}', 401),
        ),
      );
      await expectLater(api.login('test', 'bad'), throwsException);
      expect(ApiService.token, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        isNull,
      );
      api.close();
    },
  );

  test(
    'Plusieurs réponses 401 nettoient la session et ne déclenchent qu’un retour',
    () async {
      final store = TokenService(useSecureStorage: true);
      await store.saveToken('expiré');
      final api = ApiService(
        tokenStore: store,
        client: MockClient(
          (_) async => http.Response('{"detail":"expired"}', 401),
        ),
      );
      await api.loadToken();
      final before = ApiService.sessionExpired.value;
      await Future.wait(
        List.generate(
          3,
          (_) => api.getLots().then<void>(
            (_) {},
            onError: (Object e) {
              expect(e.toString(), contains('Session expirée'));
            },
          ),
        ),
      );
      expect(ApiService.sessionExpired.value, before + 1);
      expect(ApiService.token, isNull);
      expect(encrypted, isEmpty);
      api.close();
    },
  );

  test(
    'Une panne réseau conserve la session et produit une erreur compréhensible',
    () async {
      ApiService.token = 'conservé';
      final api = ApiService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(api.getLots(), throwsA(isA<ApiConnectionException>()));
      expect(ApiService.token, 'conservé');
      api.close();
    },
  );

  test('Un délai dépassé borne la requête sans répéter une écriture', () async {
    var calls = 0;
    final api = ApiService(
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response('{}', 201);
      }),
    );
    await expectLater(
      api.register('test', 'test@example.invalid', 'x'),
      throwsA(isA<ApiConnectionException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 1);
    api.close();
  });

  testWidgets('La relance ouvre le dashboard si un jeton est chargé', (
    tester,
  ) async {
    ApiService.token = 'chargé';
    await tester.pumpWidget(ElevageApp(apiService: AuthApiFake()));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'La session expirée ferme les routes protégées et affiche la connexion',
    (tester) async {
      ApiService.token = 'chargé';
      await tester.pumpWidget(ElevageApp(apiService: AuthApiFake()));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(DashboardScreen));
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Route protégée')),
        ),
      );
      await tester.pumpAndSettle();
      ApiService.token = null;
      ApiService.sessionExpired.value++;
      ApiService.sessionExpired.value++;
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('Votre session a expiré. Reconnectez-vous.'),
        findsOneWidget,
      );
      expect(find.text('Route protégée'), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
