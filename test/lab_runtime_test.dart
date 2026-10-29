import 'dart:io';
import 'package:app_elevage/main.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_elevage/offline/farm_database.dart';
import 'outbox_test.dart' show testOutboxGrant;
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/outbox_transport.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:app_elevage/services/lab_network_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('lab is visibly marked on the initial login screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = null;
    globalToken = null;
    final api = ApiService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(api.close);
    await tester.pumpWidget(ElevageApp(apiService: api));
    expect(
      find.text(
        'LABORATOIRE — DONNÉES SYNTHÉTIQUES — réseau bloqué par défaut',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Élev’Age LABORATOIRE',
    );
    expect(tester.takeException(), isNull);
  }, skip: !Config.current.isLab);
  test(
    'lab never reads, migrates or erases legacy production credential',
    () async {
      SharedPreferences.setMockInitialValues({
        'token': 'synthetic-old-token',
        'auth_token': 'synthetic-old-auth',
      });
      final calls = <String>[];
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map;
            calls.add(args['key'] as String);
            expect(args['key'], startsWith('lab_token_'));
            return null;
          });
      final store = TokenService(
        useSecureStorage: true,
        secureStorage: const FlutterSecureStorage(),
      );
      expect(await store.getToken(), isNull);
      await store.saveToken('synthetic-lab-token');
      await store.clearToken();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), 'synthetic-old-token');
      expect(prefs.getString('auth_token'), 'synthetic-old-auth');
      expect(calls, isNotEmpty);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
    skip: !Config.current.isLab,
  );

  test(
    'compiled lab all real entry transports default closed without real secrets',
    () async {
      expect(Config.current.isLab, isTrue);
      expect(Config.current.apiUrl, 'https://lab.example.test/api');
      expect(LabNetworkGate.instance.enabled, isFalse);
      var calls = 0;
      http.Client mock() => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      final api = ApiService(client: mock());
      final foundation = FoundationApi(
        baseUrl: Config.apiUrl,
        deviceIdentity: TestIdentity(),
        secrets: TestSecretStore(),
        client: mock(),
      );
      final transport = DeviceOutboxApi(
        baseUrl: Config.apiUrl,
        identity: TestIdentity(),
        deviceId: 1,
        farmId: 1,
        generation: 1,
        client: mock(),
      );
      await expectLater(
        api.login('synthetic', 'synthetic'),
        throwsA(isA<NetworkDestinationException>()),
      );
      await expectLater(
        foundation.logIn('synthetic', 'synthetic'),
        throwsA(isA<NetworkDestinationException>()),
      );
      await expectLater(
        transport.status(['00000000-0000-4000-8000-000000000001']),
        throwsA(isA<NetworkDestinationException>()),
      );
      for (final path in [
        '/devices/',
        '/offline/recovery/',
        '/cache-page/?collection=expense_categories',
        '/offline-authorizations/',
        '/lots/',
      ]) {
        await expectLater(
          foundation.client.get(Uri.parse('${Config.apiUrl}$path')),
          throwsA(isA<NetworkDestinationException>()),
        );
      }
      final tablet = TabletController(
        api: foundation,
        secrets: TestSecretStore(),
        automaticSyncEnabled: true,
      );
      expect(tablet.automaticSyncEnabled, isFalse);
      final folder = await Directory.systemTemp.createTemp(
        'elevage-e2-synthetic-',
      );
      final now = DateTime.utc(2026, 10, 7);
      final db = FarmDatabase(
        encryptedExecutor(File('${folder.path}/farm.db'), 'c' * 64),
        farmId: 1,
        serverNamespace: 'e2-synthetic',
        clock: () => now,
      );
      try {
        final original = await db.enqueue(
          grant: await testOutboxGrant(2, now),
          isSessionCurrent: () => true,
          entityType: 'CLIENT',
          operationType: 'CREATE',
          payload: {'nom': 'Synthetic'},
          businessOccurredAt: now,
        );
        final syncApi = DeviceOutboxApi(
          baseUrl: Config.apiUrl,
          identity: TestIdentity(),
          deviceId: 7,
          farmId: 1,
          generation: 1,
          client: mock(),
        );
        tablet.transport = OutboxTransport(store: db, api: syncApi);
        await expectLater(
          tablet.syncOutbox(),
          throwsA(isA<DeviceTransportException>()),
        );
        expect(
          (await db.listOutbox(authorId: 2)).single.operationId,
          original.operationId,
        );
        expect(calls, 0);
        syncApi.close();
        tablet.transport = null;
      } finally {
        await db.close();
        expect(
          folder.path.split(Platform.pathSeparator).last,
          startsWith('elevage-e2-synthetic-'),
        );
        await folder.delete(recursive: true);
      }
      expect(calls, 0);
      tablet.lock();
      expect(LabNetworkGate.instance.enabled, isFalse);
      tablet.dispose();
      foundation.close();
      transport.close();
      api.close();
    },
    skip: !Config.current.isLab,
  );
}
