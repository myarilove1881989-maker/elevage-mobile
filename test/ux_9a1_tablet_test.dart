import 'dart:async';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/sync_coordinator.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'package:app_elevage/widgets/connection_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'production_tracking_test.dart' show testApp;
import 'sync_coordinator_test.dart' show MemorySyncState;

class DisplayTabletFake extends TabletController {
  DisplayTabletFake({required super.api, required super.secrets});
  void attachSync(SyncCoordinator coordinator) {
    sync = coordinator;
    coordinator.addListener(notifyListeners);
  }

  @override
  Future<void> initialize() async {}
}

void main() {
  testWidgets(
    'manual sync leaves other UI actions enabled and uses one existing flight',
    (tester) async {
      final secrets = TestSecretStore();
      var requests = 0, flights = 0;
      final api = FoundationApi(
        baseUrl: Config.apiUrl,
        deviceIdentity: TestIdentity(),
        secrets: secrets,
        client: MockClient((request) async {
          requests++;
          throw StateError('No HTTP request expected');
        }),
      );
      final response = Completer<bool>();
      final sync = SyncCoordinator(
        store: MemorySyncState(),
        networkChanges: () => const Stream<bool?>.empty(),
        synchronize: () {
          flights++;
          return response.future;
        },
      );
      final tablet = DisplayTabletFake(api: api, secrets: secrets)..farmId = 1;
      tablet.attachSync(sync);
      await tester.pumpWidget(testApp(OfflineTabletScreen(controller: tablet)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synchroniser maintenant'));
      await tester.pump();
      expect(sync.busy, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Me connecter'),
            )
            .onPressed,
        isNotNull,
      );
      expect(flights, 1);
      expect(requests, 0);
      response.complete(false);
      await tester.pumpAndSettle();
      expect(sync.busy, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('device badge opens existing summary, without route or request', (
    tester,
  ) async {
    var requests = 0, synchronizations = 0;
    final secrets = TestSecretStore();
    final api = FoundationApi(
      baseUrl: Config.apiUrl,
      deviceIdentity: TestIdentity(),
      secrets: secrets,
      client: MockClient((request) async {
        requests++;
        throw StateError('No HTTP request expected for this presentation test');
      }),
    );
    final tablet = DisplayTabletFake(api: api, secrets: secrets)..farmId = 1;
    final store = MemorySyncState()
      ..value = const SyncSummary(
        pending: 4,
        conflicts: 1,
        awaitingValidation: 2,
      );
    final sync = SyncCoordinator(
      store: store,
      networkChanges: () => const Stream<bool?>.empty(),
      synchronize: () async {
        synchronizations++;
        return false;
      },
    );
    sync.summary = store.value;
    sync.networkAvailable = false;
    tablet.sync = sync;
    await tester.pumpWidget(testApp(OfflineTabletScreen(controller: tablet)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(find.byType(ConnectionIndicator), findsOneWidget);
    await tester.tap(
      find.byTooltip(
        'Sur cette tablette, tous profils : 4 déclarations à transmettre, 1 opérations à vérifier',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('État de cette tablette • tous profils').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.text('4 déclarations à transmettre • 1 opérations à vérifier'),
      findsOneWidget,
    );
    expect(find.text('2 reçues • confirmation en attente'), findsOneWidget);
    expect(find.byType(OfflineTabletScreen), findsOneWidget);
    expect(requests, 0);
    expect(synchronizations, 0);
    expect(sync.foreground, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing sync state never fabricates zero counters', (
    tester,
  ) async {
    final secrets = TestSecretStore();
    final api = FoundationApi(
      baseUrl: Config.apiUrl,
      deviceIdentity: TestIdentity(),
      secrets: secrets,
      client: MockClient((request) async {
        throw StateError('No HTTP request expected');
      }),
    );
    final tablet = DisplayTabletFake(api: api, secrets: secrets)..farmId = 1;
    await tester.pumpWidget(testApp(OfflineTabletScreen(controller: tablet)));
    await tester.pumpAndSettle();
    expect(
      find.text('Compteurs de synchronisation indisponibles'),
      findsOneWidget,
    );
    expect(find.textContaining('0 déclarations'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unclassified sync error cannot assert API unavailability', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: ConnectionIndicator(
            networkAvailable: true,
            syncUnavailable: true,
            showLabel: true,
          ),
        ),
      ),
    );
    expect(find.text('Synchronisation indisponible'), findsOneWidget);
    expect(find.text('Serveur indisponible'), findsNothing);
  });
}
