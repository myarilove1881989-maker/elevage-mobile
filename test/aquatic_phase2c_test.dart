import 'dart:io';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/feeding_panel.dart';
import 'package:app_elevage/services/api_service.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic, installations, cohorts;
import 'production_tracking_test.dart' show testApp;

const productId = '60000000-0000-4000-8000-000000000001';
Map<String, dynamic> feedCatalog() => {
  'can_purchase': true,
  'can_read_purchases': true,
  'can_manage_reserves': true,
  'products': <Map<String, dynamic>>[
    {
      'id': productId,
      'name': 'Granulés partagés',
      'unit': 'kg',
      'common_kg': '65.000',
      'physical_kg': '85.000',
      'archived': false,
      'aquatic_used': true,
      'reserves': [
        {
          'species': null,
          'lot': null,
          'quantity_kg': '65.000',
          'label': 'Commun à l’exploitation',
        },
        {
          'species': 42,
          'lot': null,
          'quantity_kg': '20.000',
          'label': 'Réserve Tilapia',
        },
      ],
    },
  ],
  'categories': [
    {'id': 7, 'name': 'Aliments'},
  ],
  'species': [
    {'id': 42, 'name': 'Tilapia'},
  ],
  'lots': <dynamic>[],
};
Map<String, dynamic> feedSummary() => {
  'from': '2026-11-06T00:00:00Z',
  'to': '2026-11-12T23:59:59Z',
  'distributed_kg': '35.000',
  'common_stock_kg': '65.000',
  'estimated_consumed_kg': null,
  'consumption_status': 'PARTIAL',
  'known_consumed_kg': '20.000',
  'unassigned_distributed_kg': '15.000',
  'biomass_comparison': {'status': 'INSUFFICIENT_DATA', 'feed_percent': null},
  'by_day': [
    {'date': '2026-11-11', 'quantity_kg': '15.000'},
    {'date': '2026-11-12', 'quantity_kg': '20.000'},
  ],
  'by_product': [
    {'name': 'Granulés partagés', 'quantity_kg': '35.000'},
  ],
};
Map<String, dynamic> distribution({bool zero = false}) => {
  'id': 'd',
  'product': productId,
  'product_name': 'Granulés partagés',
  'quantity_kg': zero ? '20.000' : '15.000',
  'installation': installations.first['id'],
  'cohort': null,
  'leftovers_kg': zero ? '0.000' : null,
  'estimated_consumed_kg': zero ? '20.000' : null,
  'analysis': {'status': 'INSUFFICIENT_DATA'},
  'actor': 1,
  'occurred_at': '2026-11-12T10:00:00Z',
  'recorded_at': '2026-11-12T10:01:00Z',
  'note': '',
};

class FakeFeeding extends FakeAquatic {
  final paths = <String>[];
  bool interrupt = false, refuse = false;
  @override
  Future<Map<String, dynamic>> read(String path) async {
    paths.add(path);
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('feed-products/')) return feedCatalog();
    if (path.startsWith('feed-summary/')) return feedSummary();
    if (path.startsWith('dashboard')) {
      final result = await super.read(path);
      return {...result, 'feeding_overview': feedSummary()};
    }
    return super.read(path);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    paths.add(path);
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('feed-distributions/')) {
      return [distribution(), distribution(zero: true)];
    }
    if (path.startsWith('feed-purchases/')) {
      return [
        {
          'id': 'p',
          'product_name': 'Granulés partagés',
          'quantity_kg': '100.000',
          'expense_id': 11,
          'amount': '1200.00',
          'actor': 1,
          'occurred_at': '2026-11-12T09:00:00Z',
          'note': '',
        },
      ];
    }
    if (path.startsWith('feed-stock-history/')) {
      return [
        {
          'id': 1,
          'product_name': 'Granulés partagés',
          'quantity_kg': '-15.000',
          'scope': 'FARM_COMMON',
          'operation_kind': 'AQUA_FEED_DISTRIB',
          'occurred_at': '2026-11-12T10:00:00Z',
          'actor': 1,
        },
      ];
    }
    return super.list(path);
  }

  @override
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body,
  ) async {
    writes.add(Map<String, dynamic>.from(body));
    paths.add(path);
    if (interrupt) {
      interrupt = false;
      throw const ApiConnectionException();
    }
    if (refuse) throw const ApiHttpException(409, 'Stock insuffisant');
    return {'id': 'new'};
  }
}

Future<void> choose(WidgetTester t, String label, String choice) async {
  final field = find.widgetWithText(DropdownButtonFormField<String>, label);
  await t.ensureVisible(field);
  await t.tap(field);
  await t.pumpAndSettle();
  await t.tap(find.text(choice).last);
  await t.pumpAndSettle();
}

Future<void> fill(WidgetTester t, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

Future<void> save(WidgetTester t, [String label = 'Enregistrer']) async {
  final f = find.text(label);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Widget editor(FakeFeeding fake, String kind, {bool owner = true}) => testApp(
  Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => FeedEditor(
            service: fake,
            kind: kind,
            owner: owner,
            catalog: feedCatalog(),
            installations: installations,
            cohorts: cohorts,
          ),
        ),
        child: const Text('Ouvrir'),
      ),
    ),
  ),
);
Future<void> open(
  WidgetTester t,
  FakeFeeding fake,
  String kind, {
  bool owner = true,
}) async {
  await t.pumpWidget(editor(fake, kind, owner: owner));
  await t.tap(find.text('Ouvrir'));
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, GlobalKey key, String file) async {
  final folder = Platform.environment['ELEVAGE_PHASE2C_CAPTURES'];
  if (folder == null) return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$folder/$file.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    final roboto = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            ).readAsBytes(),
          ),
        ),
      );
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final zero in [false, true]) {
    testWidgets(
      'distribution explicit nullable leftovers $zero and no cohort allocation',
      (t) async {
        final fake = FakeFeeding();
        await open(t, fake, 'DISTRIBUTION');
        await choose(t, 'Aliment existant', 'Granulés partagés');
        await choose(t, 'Bassin concerné', 'Bassin Nord');
        await fill(t, 'quantity', '15,125');
        if (zero) await fill(t, 'leftovers', '0');
        await save(t);
        expect(fake.writes.single['quantity_kg'], '15.125');
        expect(fake.writes.single['leftovers_kg'], zero ? '0' : null);
        expect(fake.writes.single['cohort'], isNull);
        expect(fake.paths.last, 'feed-distributions/');
        expect(t.takeException(), isNull);
        fake.api.close();
      },
    );
  }
  testWidgets(
    'purchase reuses catalog and financial category with exact amount',
    (t) async {
      final f = FakeFeeding();
      await open(t, f, 'PURCHASE');
      await choose(t, 'Aliment existant', 'Granulés partagés');
      await choose(t, 'Catégorie alimentaire', 'Aliments');
      await fill(t, 'amount', '1200,50');
      await fill(t, 'quantity', '100');
      await save(t);
      expect(f.writes.single['product'], productId);
      expect(f.writes.single['amount'], '1200.50');
      expect(f.writes.single['category'], 7);
      expect(f.writes.single.containsKey('lot'), false);
      f.api.close();
    },
  );
  testWidgets(
    'owner explicitly releases a reserve without inventing common stock',
    (t) async {
      final f = FakeFeeding();
      await open(t, f, 'RESERVE');
      await choose(t, 'Aliment existant', 'Granulés partagés');
      await choose(t, 'Réserve de départ', 'Réserve Tilapia (20.000 kg)');
      await choose(t, 'Destination autorisée', 'Commun à l’exploitation');
      await fill(t, 'reason', 'Libération autorisée');
      await fill(t, 'quantity', '10');
      await save(t);
      expect(f.writes.single['source'], {'species': 42, 'lot': null});
      expect(f.writes.single['target'], {'species': null, 'lot': null});
      expect(f.writes.single['reason'], 'Libération autorisée');
      f.api.close();
    },
  );
  testWidgets('date only stays explicit and never invents known hour', (
    t,
  ) async {
    final f = FakeFeeding();
    await open(t, f, 'DISTRIBUTION');
    await choose(t, 'Aliment existant', 'Granulés partagés');
    await choose(t, 'Bassin concerné', 'Bassin Nord');
    await fill(t, 'quantity', '1');
    await t.ensureVisible(find.text('Heure connue'));
    await t.tap(find.text('Heure connue'));
    await t.pumpAndSettle();
    await save(t);
    expect(f.writes.single['time_precision'], 'DATE');
    expect(
      f.writes.single['occurred_at'],
      startsWith('${f.writes.single['business_date']}T00:00:00'),
    );
    f.api.close();
  });
  testWidgets('network retry freezes and reuses identical UUID and body', (
    t,
  ) async {
    final f = FakeFeeding()..interrupt = true;
    await open(t, f, 'DISTRIBUTION');
    await choose(t, 'Aliment existant', 'Granulés partagés');
    await choose(t, 'Bassin concerné', 'Bassin Nord');
    await fill(t, 'quantity', '15');
    await save(t);
    expect(find.text('Réessayer la même opération'), findsOneWidget);
    expect(
      t.widget<TextFormField>(find.byKey(const ValueKey('quantity'))).enabled,
      false,
    );
    await save(t, 'Réessayer la même opération');
    expect(f.writes.length, 2);
    expect(f.writes.first, f.writes.last);
    f.api.close();
  });
  testWidgets('deterministic refusal allows correcting values', (t) async {
    final f = FakeFeeding()..refuse = true;
    await open(t, f, 'DISTRIBUTION');
    await choose(t, 'Aliment existant', 'Granulés partagés');
    await choose(t, 'Bassin concerné', 'Bassin Nord');
    await fill(t, 'quantity', '150');
    await save(t);
    expect(
      t.widget<TextFormField>(find.byKey(const ValueKey('quantity'))).enabled,
      true,
    );
    f.refuse = false;
    await fill(t, 'quantity', '15');
    await save(t);
    expect(f.writes.last['quantity_kg'], '15');
    expect(
      f.writes.last['operation_uuid'],
      isNot(f.writes.first['operation_uuid']),
    );
    f.api.close();
  });
  testWidgets(
    'invalid numbers never send and employee cannot create products',
    (t) async {
      final f = FakeFeeding();
      await open(t, f, 'PURCHASE', owner: false);
      expect(find.text('Créer un nouvel aliment'), findsNothing);
      await choose(t, 'Aliment existant', 'Granulés partagés');
      await choose(t, 'Catégorie alimentaire', 'Aliments');
      await fill(t, 'amount', '2.001');
      await fill(t, 'quantity', '0');
      await save(t);
      expect(f.writes, isEmpty);
      f.api.close();
    },
  );
  testWidgets('owner creates one named food and explicit expense category', (
    t,
  ) async {
    final f = FakeFeeding();
    await open(t, f, 'PURCHASE');
    await t.tap(find.text('Créer un nouvel aliment'));
    await t.pumpAndSettle();
    await fill(t, 'name', 'Aliment nouveau');
    await t.ensureVisible(find.text('Créer une catégorie de dépense'));
    await t.tap(find.text('Créer une catégorie de dépense'));
    await t.pumpAndSettle();
    await fill(t, 'category_name', 'Aliments communs');
    await fill(t, 'amount', '75.25');
    await fill(t, 'quantity', '100');
    await save(t);
    expect(f.writes.single['new_product']['name'], 'Aliment nouveau');
    expect(f.writes.single['new_category'], 'Aliments communs');
    expect(f.writes.single.containsKey('product'), false);
    f.api.close();
  });
  testWidgets('read only operator has no distribution or reserve action', (
    t,
  ) async {
    final f = FakeFeeding();
    await t.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: FeedingPanel(
              service: f,
              owner: false,
              rights: const [],
              installations: installations,
              cohorts: cohorts,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Distribuer un aliment'), findsNothing);
    await t.ensureVisible(find.text('Stock'));
    await t.tap(find.text('Stock'));
    await t.pumpAndSettle();
    expect(find.text('Gérer les réserves'), findsNothing);
    await t.pumpWidget(const SizedBox());
    f.api.close();
  });
  for (final width in [360.0, 1080.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('feeding page preserves overview $width scale$scale', (t) async {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = FakeFeeding();
        final workspace=GlobalKey<AquaticWorkspaceState>();
        await t.pumpWidget(
          testApp(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: AquaticWorkspace(
                  key:workspace,
                  service: f,
                  capabilities: const {'write': <String>[], 'can_enable': true},
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        workspace.currentState!.showPage('feeding');await t.pumpAndSettle();
        expect(find.textContaining('35.000 kg distribués'), findsOneWidget);
        expect(
          find.textContaining('Stock commun actuel : 65.000 kg'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        f.api.close();
      });
    }
  }
  for (final width in [360.0, 1080.0]) {
    for (final kind in ['PURCHASE', 'DISTRIBUTION', 'RESERVE']) {
      testWidgets('V2 $kind $width layout and capture', (t) async {
        t.view.physicalSize = Size(width, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = FakeFeeding(), key = GlobalKey();
        await t.pumpWidget(
          testApp(
            RepaintBoundary(
              key: key,
              child: Scaffold(
                body: FeedEditor(
                  service: f,
                  kind: kind,
                  owner: true,
                  catalog: feedCatalog(),
                  installations: installations,
                  cohorts: cohorts,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await capture(t, key, '$kind-${width.toInt()}');
        await t.pumpWidget(const SizedBox());
        f.api.close();
      });
    }
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'panel $width scale$scale real filters unknown consumption and stale clearing',
        (t) async {
          t.view.physicalSize = Size(width, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final f = FakeFeeding(), key = GlobalKey();
          await t.pumpWidget(
            testApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: FeedingPanel(
                        service: f,
                        owner: true,
                        rights: const ['aquatic.feed.distribute'],
                        installations: installations,
                        cohorts: cohorts,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(find.textContaining('Données insuffisantes'), findsWidgets);
          expect(
            find.textContaining('Restes : non renseignés'),
            findsOneWidget,
          );
          expect(find.textContaining('Restes : 0.000 kg'), findsOneWidget);
          expect(t.takeException(), isNull);
          if (scale == 1) await capture(t, key, 'panel-${width.toInt()}');
          await choose(t, 'Cohorte', 'Novembre');
          expect(
            Uri.parse(
              f.paths.where((p) => p.startsWith('feed-distributions/')).last,
            ).queryParameters['cohort'],
            cohorts.first['id'],
          );
          expect(
            Uri.parse(
              f.paths.where((p) => p.startsWith('feed-purchases/')).last,
            ).queryParameters.containsKey('cohort'),
            false,
          );
          final stock = find.text('Stock');
          await t.ensureVisible(stock);
          await t.tap(stock);
          await t.pumpAndSettle();
          expect(find.text('Gérer les réserves'), findsOneWidget);
          if (scale == 1) await capture(t, key, 'stock-${width.toInt()}');
          expect(t.takeException(), isNull);
          f.offline = true;
          await t.ensureVisible(find.text('Actualiser'));
          await t.tap(find.text('Actualiser'));
          await t.pumpAndSettle();
          expect(
            find.textContaining('Alimentation indisponible'),
            findsOneWidget,
          );
          expect(find.textContaining('Disponible commun :'), findsNothing);
          await t.pumpWidget(const SizedBox());
          f.api.close();
        },
      );
    }
  }
}
