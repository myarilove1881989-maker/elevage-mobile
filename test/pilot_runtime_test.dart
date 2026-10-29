import 'package:app_elevage/config.dart';
import 'package:app_elevage/main.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/outbox_transport.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;

// Run this file a second time with explicit pilot Dart definitions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('compiled pilot integration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'token': 'legacy-production',
        'auth_token': 'legacy-production',
      });
      ApiService.token = null;
      globalToken = null;
    });

    test('all transports reject redirects before following them', () async {
      var sent = 0;
      http.Client mock() => MockClient((request) async {
        sent++;
        expect(request.url.host, 'backend-elevage-pilot.onrender.com');
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          307,
          headers: {'location': EnvironmentConfig.productionApi},
        );
      });
      final online = ApiService(client: mock());
      final foundation = FoundationApi(
        baseUrl: Config.apiUrl,
        deviceIdentity: TestIdentity(),
        secrets: TestSecretStore(),
        client: mock(),
      );
      final outbox = DeviceOutboxApi(
        baseUrl: Config.apiUrl,
        identity: TestIdentity(),
        deviceId: 1,
        farmId: 1,
        generation: 1,
        client: mock(),
      );
      await expectLater(
        online.login('synthetic', 'synthetic'),
        throwsA(isA<NetworkDestinationException>()),
      );
      await expectLater(
        foundation.logIn('synthetic', 'synthetic'),
        throwsA(isA<NetworkDestinationException>()),
      );
      await expectLater(
        outbox.status(['00000000-0000-4000-8000-000000000001']),
        throwsA(isA<NetworkDestinationException>()),
      );
      expect(sent, 3);
      online.close();
      foundation.close();
      outbox.close();
    });

    test('offline constructor overrides cannot select production', () {
      expect(
        () => FoundationApi(
          baseUrl: EnvironmentConfig.productionApi,
          deviceIdentity: TestIdentity(),
          secrets: TestSecretStore(),
          client: MockClient((_) async => http.Response('', 200)),
        ),
        throwsA(isA<NetworkDestinationException>()),
      );
      expect(
        () => DeviceOutboxApi(
          baseUrl: EnvironmentConfig.productionApi,
          identity: TestIdentity(),
          deviceId: 1,
          farmId: 1,
          generation: 1,
          client: MockClient((_) async => http.Response('', 200)),
        ),
        throwsA(isA<NetworkDestinationException>()),
      );
    });

    test('pilot never migrates production JWT and does not clear it', () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final encrypted = <String, String>{'token': 'production-secret'};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map;
            final key = args['key'] as String;
            if (call.method == 'read') return encrypted[key];
            if (call.method == 'write') {
              encrypted[key] = args['value'] as String;
            }
            if (call.method == 'delete') encrypted.remove(key);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final store = TokenService(useSecureStorage: true);
      expect(await store.getToken(), isNull);
      await store.saveToken('pilot-secret');
      expect(encrypted[Config.current.tokenKey], 'pilot-secret');
      expect(await store.getToken(), 'pilot-secret');
      await store.clearToken();
      expect(encrypted['token'], 'production-secret');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), 'legacy-production');
      expect(prefs.getString('auth_token'), 'legacy-production');
    });

    testWidgets('pilot has persistent visible marker on login', (tester) async {
      final api = ApiService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(api.close);
      await tester.pumpWidget(ElevageApp(apiService: api));
      expect(find.text('PILOTE — DONNÉES FICTIVES'), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'Élev’Age PILOTE',
      );
      expect(tester.takeException(), isNull);
    });
  }, skip: !Config.isPilot);
}
