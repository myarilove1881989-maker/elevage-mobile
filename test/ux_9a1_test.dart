import 'dart:async';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/main.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/screens/lot_list_screen.dart';
import 'package:app_elevage/screens/lot_detail_screen.dart';
import 'package:app_elevage/widgets/connection_indicator.dart';
import 'package:app_elevage/widgets/operation_status.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'production_tracking_test.dart' show ProductionTrackingApiFake, testApp;
import 'birth_lot_detail_test.dart' show BirthLotApiFake;

class DetailDisplayApiFake extends BirthLotApiFake {
  bool fail = false;
  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async {
    if (fail) {
      throw const ApiConnectionException();
    }
    return super.getLotDetail(lotId);
  }
}

class DisplayApiFake extends ProductionTrackingApiFake {
  bool fail = false;
  bool failDashboard = false, emptyLots = false, failLots = false;
  int stock = 81;
  Completer<Map<String, dynamic>>? holdDashboard;
  @override
  Future<Map<String, dynamic>> getDashboard({int? especeId}) async {
    if (holdDashboard != null) {
      return holdDashboard!.future;
    }
    if (failDashboard) {
      throw StateError('HTTP 500 secret-diagnostic-test');
    }
    return {
      'kpis': {'stock': stock, 'chiffre_affaires': 123, 'depenses': 12},
    };
  }

  @override
  Future<List<dynamic>> getLots() async {
    if (failLots) {
      throw const ApiConnectionException();
    }
    return emptyLots ? [] : super.getLots();
  }

  @override
  Future<double> getTotalDettes() async {
    if (fail) throw const ApiConnectionException();
    return 37;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'username': 'pilot-operator'});
    AppSettings.instance.languageCode = 'fr';
    ApiService.token = 'widget-test-only';
  });
  tearDown(() => ApiService.token = null);

  for (final ratio in [1.0, 1.5, 2.0]) {
    testWidgets('Pilot landscape 1280x800 physical, DPR $ratio', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = ratio;
      tester.view.padding = FakeViewPadding(
        top: 24 * ratio,
        bottom: 24 * ratio,
      );
      addTearDown(tester.view.reset);
      final api = DisplayApiFake();
      addTearDown(api.close);
      await tester.pumpWidget(ElevageApp(apiService: api));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(
        find.text('PILOTE — DONNÉES FICTIVES'),
        Config.isPilot ? findsOneWidget : findsNothing,
      );
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith('Tableau de bord'),
      );
      expect(title, findsOneWidget);
      expect(
        tester.getRect(title).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(tester.getRect(title).bottom, lessThan(800 / ratio - 24));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(1280, 800), const Size(800, 1280)]) {
    testWidgets('tablet orientation $size with enlarged text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.5;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = DisplayApiFake();
      addTearDown(api.close);
      await tester.pumpWidget(ElevageApp(apiService: api));
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('dashboardHeading'));
      expect(
        tester.getRect(title).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(tester.getRect(title).right, lessThanOrEqualTo(size.width / 1.5));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      final logout = find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Quitter'),
      );
      await tester.scrollUntilVisible(
        logout,
        150,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(logout.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed refresh stops loading and preserves dashboard', (
    tester,
  ) async {
    final api = DisplayApiFake();
    addTearDown(api.close);
    await tester.pumpWidget(ElevageApp(apiService: api));
    await tester.pumpAndSettle();
    expect(find.text('81'), findsOneWidget);
    api.stock = 99;
    api.fail = true;
    await tester.tap(find.byIcon(Icons.refresh).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Données mises à jour'), findsNothing);
    expect(find.text('81'), findsOneWidget);
    expect(find.text('99'), findsNothing);
    expect(
      find.text(
        'Actualisation impossible. Les dernières données affichées sont conservées.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('initial error shows unavailable without invented KPIs', (
    tester,
  ) async {
    final api = DisplayApiFake()..failDashboard = true;
    addTearDown(api.close);
    await tester.pumpWidget(ElevageApp(apiService: api));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chargement incomplet : bilan du tableau de bord'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('HTTP 500'), findsNothing);
    expect(find.byIcon(Icons.inventory_2), findsNothing);
    expect(find.text('0'), findsNothing);
    api.failDashboard = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('81'), findsOneWidget);
  });

  testWidgets('failed filter restores the scope of preserved data', (
    tester,
  ) async {
    final api = DisplayApiFake();
    addTearDown(api.close);
    await tester.pumpWidget(ElevageApp(apiService: api));
    await tester.pumpAndSettle();
    api.failDashboard = true;
    await tester.tap(find.byKey(const ValueKey('dashboardSpecies:null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poulet').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboardSpecies:null')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboardSpecies:1')), findsNothing);
    expect(find.text('81'), findsOneWidget);
    expect(find.textContaining('Actualisation impossible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lot detail error offers retry and preserves confirmed detail on refresh failure',
    (tester) async {
      final api = DetailDisplayApiFake()..fail = true;
      addTearDown(api.close);
      await tester.pumpWidget(
        testApp(LotDetailScreen(apiService: api, lotId: 1)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Lot indisponible'), findsOneWidget);
      expect(find.text('Truies'), findsNothing);
      api.fail = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Truies'), findsWidgets);
      api.fail = true;
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.text('Truies'), findsWidgets);
      expect(
        find.text(
          'Actualisation impossible. Les données du lot sont conservées.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh keeps content visible while awaiting server', (
    tester,
  ) async {
    final api = DisplayApiFake();
    addTearDown(api.close);
    await tester.pumpWidget(ElevageApp(apiService: api));
    await tester.pumpAndSettle();
    api.holdDashboard = Completer<Map<String, dynamic>>();
    await tester.tap(find.byIcon(Icons.refresh).first);
    await tester.pump();
    expect(find.text('81'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    api.holdDashboard!.completeError(const ApiConnectionException());
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('81'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late response after leaving dashboard is harmless', (
    tester,
  ) async {
    final api = DisplayApiFake()
      ..holdDashboard = Completer<Map<String, dynamic>>();
    addTearDown(api.close);
    await tester.pumpWidget(ElevageApp(apiService: api));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    api.holdDashboard!.complete({
      'kpis': {'stock': 81},
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty lots and unavailable lots are distinct; retry works', (
    tester,
  ) async {
    final api = DisplayApiFake()..failLots = true;
    addTearDown(api.close);
    await tester.pumpWidget(testApp(LotListScreen(apiService: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lots indisponibles'), findsOneWidget);
    expect(find.text('Aucun lot enregistré.'), findsNothing);
    api.failLots = false;
    api.emptyLots = true;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun lot enregistré.'), findsOneWidget);
    expect(find.textContaining('Lots indisponibles'), findsNothing);
  });

  testWidgets('failed lot refresh preserves loaded lots', (tester) async {
    final api = DisplayApiFake();
    addTearDown(api.close);
    await tester.pumpWidget(testApp(LotListScreen(apiService: api)));
    await tester.pumpAndSettle();
    expect(find.text('Pondeuses'), findsOneWidget);
    api.failLots = true;
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.text('Pondeuses'), findsOneWidget);
    expect(
      find.text('Actualisation impossible. Les lots affichés sont conservés.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('offline network overrides even a recent successful exchange', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          appBar: AppBar(
            actions: [
              ConnectionIndicator(
                networkAvailable: false,
                lastSuccess: DateTime.now(),
                showLabel: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Hors ligne'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byKey(const Key('connectionStateIcon'))).color,
      isNot(Colors.green.shade700),
    );
  });

  testWidgets('network alone never claims server availability', (tester) async {
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: ConnectionIndicator(networkAvailable: true, showLabel: true),
        ),
      ),
    );
    expect(find.text('Serveur non vérifié'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byKey(const Key('connectionStateIcon'))).color,
      Colors.grey,
    );
  });

  testWidgets('recent success expires without any network request', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 11);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: ConnectionIndicator(
            networkAvailable: true,
            lastSuccess: now,
            clock: () => now,
            showLabel: true,
          ),
        ),
      ),
    );
    expect(find.text('Échange serveur récent'), findsOneWidget);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Serveur non vérifié'), findsOneWidget);
  });

  testWidgets(
    'server failure suppresses green; badges have device scope and action',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: ConnectionIndicator(
              networkAvailable: true,
              lastSuccess: DateTime.now(),
              serverUnavailable: true,
              pending: 3,
              conflicts: 1,
              showLabel: true,
              onSummary: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.text('Serveur indisponible'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      final action = find.byTooltip(
        'Sur cette tablette, tous profils : 3 déclarations à transmettre, 1 opérations à vérifier',
      );
      await tester.tap(action);
      expect(opened, isTrue);
    },
  );

  testWidgets('sync activity never blocks surrounding work', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Column(
            children: [
              const ConnectionIndicator(syncing: true),
              TextButton(
                onPressed: () => tapped = true,
                child: const Text('Continuer'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Continuer'));
    expect(tapped, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('operation messages distinguish every transport and business stage', () {
    for (final pair in {
      'LOCAL_PENDING': 'En attente de synchronisation',
      'RETRY_WAIT': 'En attente de synchronisation',
      'IN_FLIGHT': 'Transmission en cours',
      'SERVER_RECEIVED': 'Reçue par le serveur — confirmation en attente',
      'TRANSPORT_BLOCKED': 'Transmission bloquée : contactez le responsable',
    }.entries) {
      expect(
        operationStatus(transport: pair.key, business: 'UNREVIEWED'),
        pair.value,
      );
    }
    expect(
      operationStatus(
        transport: 'SERVER_RECEIVED',
        business: 'WAITING_DEPENDENCY',
      ),
      'Reçue par le serveur — confirmation en attente',
    );
    expect(
      operationStatus(transport: 'SERVER_RECEIVED', business: 'CONFIRMED'),
      'Confirmé par le serveur',
    );
    expect(
      operationStatus(
        transport: 'SERVER_RECEIVED',
        business: 'NEEDS_RECONCILIATION',
      ),
      'Cette opération nécessite une vérification',
    );
    expect(
      operationStatus(transport: 'SERVER_RECEIVED', business: 'NOT_APPLIED'),
      "Cette opération n'a pas été appliquée",
    );
    expect(
      operationStatus(transport: 'SERVER_RECEIVED', business: 'SUPERSEDED'),
      'Opération remplacée — historique conservé',
    );
    expect(
      operationStatus(transport: 'UNKNOWN', business: 'UNKNOWN'),
      isNot('Confirmé par le serveur'),
    );
  });

  test(
    'technical errors are hidden without weakening authentication messages',
    () {
      expect(
        tabletErrorMessage(StateError('secret-test HTTP 500 UUID conflict')),
        'Action indisponible. Les données déjà enregistrées restent conservées.',
      );
      expect(
        tabletErrorMessage(const FoundationApiException(500)),
        isNot(contains('500')),
      );
      expect(
        tabletErrorMessage(const FoundationApiException(401)),
        'Connexion personnelle requise.',
      );
      expect(
        tabletErrorMessage(
          StateError('PIN incorrect ou temporairement bloqué.'),
        ),
        'PIN incorrect ou temporairement bloqué.',
      );
    },
  );
}
