import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/dashboard_kpi_card.dart';
import 'package:app_elevage/widgets/physical_stock_cards.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'package:app_elevage/screens/vaccination_screen.dart';
import 'package:app_elevage/screens/health_agenda_screen.dart';
import 'auth_connection_test.dart' show AuthApiFake, authApp;
import 'physical_stock_summary_test.dart' show feedData, vaccines;
import 'health_agenda_form_test.dart' show healthTask;

class ConsumablesApi extends AuthApiFake {
  bool empty = false,
      fail = false,
      pending = false,
      review = false,
      foreign = false,
      mutations = true;
  bool cacheFeed = false;
  Completer<void>? pause;
  final calls = <String>[];
  Map<String, dynamic>? patchData;
  @override
  Future<dynamic> get(String path) async {
    calls.add(path);
    if (path == '/farm-profile/') return {'id': 1, 'nom': 'Ferme test'};
    if (path == '/me/capabilities/') {
      if (pause != null) await pause!.future;
      return {
        'user': 2,
        'exploitation': 1,
        'role': 'OWNER',
        'offline_policy_enabled': true,
        'membership': {'version': 1},
        'permission_contract': {
          'version': 2,
          'user': 2,
          'exploitation': 1,
          'role': 'OWNER',
          'rights_version': 1,
          'permissions': mutations
              ? [
                  'finance.read',
                  'stocks.read',
                  'history.read',
                  'lots.read',
                  'species.read',
                  'expenses.read',
                  'expenses.create',
                  'feed.read',
                  'feed.create',
                  'vaccinations.read',
                  'vaccinations.create',
                  'vaccinations.update',
                  'vaccinations.delete',
                  'agenda.read',
                  'agenda.plan',
                ]
              : ['finance.read', 'stocks.read'],
        },
      };
    }
    if (path == '/feed-supplies/?presentation=1') {
      lastReadWasCached = cacheFeed;
      if (fail) throw StateError('synthetic offline');
      return {
        ...feedData(),
        'confirmed': true,
        'as_of': '2026-11-03T12:00:00Z',
        'exploitation': foreign ? 9 : 1,
        'species': [
          {'id': 4, 'nom': 'Poules'},
          {'id': 5, 'nom': 'Canards'},
        ],
        'lots': [
          {'id': 10, 'nom': 'Lot A', 'espece_id': 4},
          {'id': 11, 'nom': 'Lot B', 'espece_id': 4},
        ],
        if (empty) 'products': [],
        'pending_operations': pending ? ['private-uuid'] : [],
        'review_operations': review ? ['private-review'] : [],
      };
    }
    if (path == '/vaccine-supplies/') {
      lastReadWasCached = false;
      final d = vaccines();
      for (final v in d['vials']) {
        v['usable_until'] = '2099-12-31T23:00:00Z';
        v['expires_on'] = '2099-12-31';
      }
      return {
        ...d,
        'as_of': '2026-11-03T12:00:00Z',
        if (empty) 'products': [],
        if (empty) 'vials': [],
      };
    }
    if (path == '/tasks/') return [healthTask()];
    if (path.startsWith('/vaccinations/'))
      return [
        {
          'id': 1,
          'lot': 10,
          'vaccine': 'Vaccin historique',
          'vaccinated_at': '2026-11-02T10:00:00Z',
          'animals': 10,
          'voided': false,
          'allocations': [],
        },
      ];
    if (path.contains('/history/'))
      return {
        'results': [
          {
            'kind': 'ENTRY',
            'quantity': '500.000',
            'at': '2026-11-03T10:23:45Z',
            'operator': 42,
            'reason': 'Achat initial',
            'lot': 10,
            'vial': 'private-vial-uuid',
          },
        ],
        'next_before': null,
      };
    if (path == '/categories-depenses/') return [];
    throw StateError('Unmocked synthetic request: $path');
  }

  @override
  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    patchData = body;
    return body;
  }

  @override
  Future<Map<String, dynamic>> getLotDetail(int lotId) async => {
    'id': lotId,
    'depenses': [],
  };
  @override
  Future<List<dynamic>> getLots() async => [
    {'id': 10, 'nom': 'Lot A', 'espece_id': 4},
  ];
  @override
  Future<List<dynamic>> getEspeces() async => [
    {'id': 4, 'nom': 'Poules'},
  ];
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = 'synthetic-ux';
    globalToken = ApiService.token;
  });
  tearDown(() {
    ApiService.token = null;
    globalToken = null;
    ApiService.clearLocalPresentationIdentity();
  });
  test(
    'levels use configured product thresholds, without invented percentages',
    () {
      List p(Object? threshold, Object quantity) => [
        {'alert_threshold': threshold, 'confirmed': quantity},
      ];
      expect(
        consumableLevel(p(null, '0'), feed: true),
        ConsumableLevel.neutral,
      );
      expect(consumableLevel(p('0', '0'), feed: true), ConsumableLevel.neutral);
      expect(
        consumableLevel(p('50', '0'), feed: true),
        ConsumableLevel.critical,
      );
      expect(consumableLevel(p('50', '50'), feed: true), ConsumableLevel.low);
      expect(consumableLevel(p('50', '51'), feed: true), ConsumableLevel.good);
      expect(
        consumableLevel(p('50', '51'), feed: true, filtered: true),
        ConsumableLevel.neutral,
      );
      expect(
        consumableLevel(p('50', '51'), feed: true, uncertain: true),
        ConsumableLevel.neutral,
      );
      expect(
        consumableLevel([...p('50', '51'), ...p(null, '100')], feed: true),
        ConsumableLevel.neutral,
      );
    },
  );
  test('quantity display removes only unnecessary decimals', () {
    expect(consumableQuantity('0.000'), '0');
    expect(consumableQuantity('12.500'), '12.5');
    expect(consumableQuantity('550.125'), '550.125');
    expect(consumableQuantity('-0.080'), '-0.08');
  });
  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('dashboard has exactly five equal KPI cards at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = ConsumablesApi();
      await t.pumpWidget(authApp(DashboardScreen(apiService: api)));
      await t.pumpAndSettle();
      final cards = find.byType(DashboardKpiCard);
      expect(cards, findsNWidgets(5));
      final rects = [for (var i = 0; i < 5; i++) t.getRect(cards.at(i))];
      for (final r in rects) {
        expect(r.size, rects.first.size);
      }
      if (width == 1440) {
        for (final r in rects) {
          expect(r.top, closeTo(rects.first.top, .1));
        }
      }
      if (width == 360) expect(rects.last.top, greaterThan(rects.first.top));
      expect(find.text('Stock d’aliments'), findsNothing);
      expect(find.text('Stock de vaccins'), findsNothing);
      expect(find.text('Consommables'), findsOneWidget);
      expect(find.textContaining('710.125'), findsNothing);
      expect(t.takeException(), null);
      await t.pumpWidget(const SizedBox());
      api.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
  testWidgets('compact card opens the two distinct tracking routes', (t) async {
    final api = ConsumablesApi();
    await t.pumpWidget(
      authApp(
        Scaffold(
          body: SizedBox(
            width: 220,
            height: 190,
            child: PhysicalStockCards(api: api, compact: true),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.vaccines_outlined), findsOneWidget);
    await t.tap(find.byKey(const Key('consumables-kpi')));
    await t.pumpAndSettle();
    expect(find.text('Suivi des consommables'), findsOneWidget);
    await t.tap(find.byKey(const Key('consumables-food')));
    await t.pumpAndSettle();
    expect(find.text('Suivi des aliments'), findsOneWidget);
    expect(find.text('710.125 kg'), findsOneWidget);
    await t.tap(find.byType(BackButton).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('consumables-vaccines')));
    await t.pumpAndSettle();
    expect(find.text('Suivi des vaccins'), findsOneWidget);
    expect(find.text('Vaccin historique'), findsOneWidget);
    expect(t.takeException(), null);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'species and lot filters preserve shared stock and can be cleared',
    (t) async {
      final api = ConsumablesApi();
      await t.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: true)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('consumables-species-null')));
      await t.pumpAndSettle();
      await t.tap(find.text('Poules').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('consumables-lot-null')));
      await t.pumpAndSettle();
      await t.tap(find.text('Lot A').last);
      await t.pumpAndSettle();
      expect(find.text('550.125 kg'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('consumables-lot-10')));
      await t.pumpAndSettle();
      await t.tap(find.text('Tous les lots').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('consumables-species-4')));
      await t.pumpAndSettle();
      await t.tap(find.text('Toutes les espèces').last);
      await t.pumpAndSettle();
      expect(find.text('710.125 kg'), findsOneWidget);
      expect(t.takeException(), null);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'history hides transport identifiers and formats quantities and dates',
    (t) async {
      final api = ConsumablesApi()
        ..pending = true
        ..review = true;
      await t.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: true, lot: 10)),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Une opération nécessite votre attention'),
        findsWidgets,
      );
      expect(find.textContaining('Estimation après'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('consumable-history')));
      await t.tap(find.byKey(const Key('consumable-history')));
      await t.pumpAndSettle();
      await t.tap(find.text('Croissance').last);
      await t.pumpAndSettle();
      expect(find.text('Entrée — Croissance — 500 kg'), findsOneWidget);
      expect(find.textContaining('03/11/2026'), findsOneWidget);
      expect(find.textContaining('private-'), findsNothing);
      expect(find.textContaining('opérateur 42'), findsNothing);
      expect(find.textContaining('Confirmé au'), findsNothing);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets('threshold still updates only the existing configuration', (
    t,
  ) async {
    final api = ConsumablesApi();
    await t.pumpWidget(
      authApp(ConsumableTrackingScreen(api: api, isFeed: true)),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Configurer le seuil').first);
    await t.tap(find.text('Configurer le seuil').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '75.125');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(api.patchData, {
      'alert_threshold': '75.125',
      'expected_threshold': '450.000',
    });
    expect(find.text('Suivi des aliments'), findsOneWidget);
    expect(t.takeException(), null);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'record actions reuse existing distribution and vaccination forms',
    (t) async {
      final api = ConsumablesApi();
      await t.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: true, lot: 10)),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('consumable-record')));
      await t.tap(find.byKey(const Key('consumable-record')));
      await t.pumpAndSettle();
      expect(find.byType(FeedDistributionFormScreen), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: false, lot: 10)),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('consumable-record')));
      await t.tap(find.byKey(const Key('consumable-record')));
      await t.pumpAndSettle();
      expect(find.byType(VaccinationForm), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'purchase action reuses Expenses and sanitary reminders reuse Agenda',
    (t) async {
      final api = ConsumablesApi();
      await t.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: true)),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('consumable-purchase')));
      await t.tap(find.byKey(const Key('consumable-purchase')));
      await t.pumpAndSettle();
      expect(find.byType(AddDepenseScreen), findsOneWidget);
      expect(
        t
            .widget<AddDepenseScreen>(find.byType(AddDepenseScreen))
            .procurementKind,
        'FEED',
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: false)),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Rappels sanitaires'));
      await t.tap(find.text('Rappels sanitaires'));
      await t.pumpAndSettle();
      expect(find.byType(HealthAgendaScreen), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'empty state, unavailable state and access isolation remain explicit',
    (t) async {
      for (final api in [
        ConsumablesApi()..empty = true,
        ConsumablesApi()..fail = true,
        ConsumablesApi()..foreign = true,
      ]) {
        await t.pumpWidget(
          authApp(ConsumableTrackingScreen(api: api, isFeed: true)),
        );
        await t.pumpAndSettle();
        if (api.empty)
          expect(
            find.textContaining('Aucun aliment enregistré'),
            findsOneWidget,
          );
        else
          expect(find.textContaining('Stocks indisponibles'), findsOneWidget);
        expect(t.takeException(), null);
        await t.pumpWidget(const SizedBox());
        api.close();
      }
    },
  );
  testWidgets('read-only rights do not reveal write actions', (t) async {
    final api = ConsumablesApi()..mutations = false;
    await t.pumpWidget(
      authApp(ConsumableTrackingScreen(api: api, isFeed: true)),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('consumable-record')), findsNothing);
    expect(find.byKey(const Key('consumable-purchase')), findsNothing);
    expect(find.byKey(const Key('consumable-history')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets(
    'loading indicators stay neutral and the card remains navigable',
    (t) async {
      final api = ConsumablesApi()..pause = Completer<void>();
      await t.pumpWidget(
        authApp(
          Scaffold(
            body: SizedBox(
              height: 190,
              width: 240,
              child: PhysicalStockCards(api: api, compact: true),
            ),
          ),
        ),
      );
      await t.pump();
      final dot = t.widget<Container>(find.byKey(const Key('feed-level')));
      expect((dot.decoration as BoxDecoration).color, Colors.blueGrey);
      await t.tap(find.byKey(const Key('consumables-kpi')));
      await t.pumpAndSettle();
      expect(find.text('Suivi des consommables'), findsOneWidget);
      api.pause!.complete();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('tracking screens fit width $width without overflow', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = ConsumablesApi();
      for (final feed in [true, false]) {
        await t.pumpWidget(
          authApp(ConsumableTrackingScreen(api: api, isFeed: feed)),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), null);
        await t.pumpWidget(const SizedBox());
      }
      api.close();
    });
  }
  testWidgets(
    'a cached food read stays neutral even when the vaccine read is fresh',
    (t) async {
      final api = ConsumablesApi()..cacheFeed = true;
      await t.pumpWidget(
        authApp(
          Scaffold(
            body: SizedBox(
              height: 190,
              width: 240,
              child: PhysicalStockCards(api: api, compact: true),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final dot = t.widget<Container>(find.byKey(const Key('feed-level')));
      expect((dot.decoration as BoxDecoration).color, Colors.blueGrey);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        authApp(ConsumableTrackingScreen(api: api, isFeed: true)),
      );
      await t.pumpAndSettle();
      expect(find.text('Stock à actualiser'), findsOneWidget);
      expect(find.text('Stock actualisé'), findsNothing);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
