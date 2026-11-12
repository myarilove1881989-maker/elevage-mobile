import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/stock_panel.dart';
import 'package:app_elevage/pisciculture/observation_panel.dart';
import 'package:app_elevage/services/api_service.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic, installations, cohorts;
import 'aquatic_phase2a_test.dart' show fakeWeight;
import 'production_tracking_test.dart' show testApp;

final stockCohorts = <Map<String, dynamic>>[
  cohorts.first,
  {
    'id': '30000000-0000-4000-8000-000000000002',
    'name': 'Décembre',
    'status': 'OPEN',
    'species': 42,
  },
];
final pending = <String, dynamic>{
  'id': '40000000-0000-4000-8000-000000000001',
  'installation': installations.first['id'],
  'eligible': stockCohorts.map((c) => c['id']).toList(),
  'quantity': 10,
  'remaining': 10,
  'kind': 'MORTALITY',
  'occurred_at': '2026-11-12T10:00:00Z',
};
final credit = <String, dynamic>{
  'id': '50000000-0000-4000-8000-000000000001',
  'installation': installations.first['id'],
  'quantity': 10,
  'remaining': 10,
  'occurred_at': '2026-11-12T10:00:00Z',
};
final stockHistory = <String, dynamic>{
  'id': pending['id'],
  'kind': 'MORTALITY',
  'installation': installations.first['id'],
  'cohort': null,
  'quantity': 10,
  'occurred_at': '2026-11-12T10:00:00Z',
  'recorded_at': '2026-11-12T10:01:00Z',
  'actor': 1,
  'reason': 'Constat confirmé',
  'note': 'Données fictives de qualification',
  'payload': {'eligible': pending['eligible']},
  'canceled': false,
  'remaining': 10,
  'reverses': null,
};
Map<String, dynamic> stockState() => {
  'business_revision': 42,
  'can_reconcile': true,
  'live_count': 990,
  'unassigned_losses': 10,
  'unassigned_credits': 0,
  'installations': [
    {
      'id': installations.first['id'],
      'name': 'Bassin Nord',
      'gross_count': 1000,
      'pending_count': 10,
      'unassigned_credit': 0,
      'allocated_live_count': 990,
      'live_count': 990,
    },
  ],
  'positions': [
    {
      'id': 'p-a',
      'cohort': stockCohorts.first['id'],
      'cohort_name': 'Novembre',
      'installation': installations.first['id'],
      'installation_name': 'Bassin Nord',
      'gross_count': 600,
      'reserved_count': 10,
      'available_count': 590,
      'version': 2,
    },
    {
      'id': 'p-b',
      'cohort': stockCohorts.last['id'],
      'cohort_name': 'Décembre',
      'installation': installations.first['id'],
      'installation_name': 'Bassin Nord',
      'gross_count': 400,
      'reserved_count': 10,
      'available_count': 390,
      'version': 2,
    },
  ],
  'pending': [pending],
  'credits': <dynamic>[],
};

class FakeStock extends FakeAquatic {
  bool interrupt = false, uncertainDashboard = false;
  final paths = <String>[];
  Map<String, dynamic> state = stockState();
  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('stock-state')) return state;
    if (path.startsWith('dashboard') && uncertainDashboard) {
      final result = await super.read(path);
      result['metrics'] = {
        ...Map<String, dynamic>.from(result['metrics'] as Map),
        'live_count': {
          'value': 600,
          'quality': 'UNRECONCILED',
          'lower': 590,
          'upper': 600,
        },
      };
      result['unassigned_losses'] = 10;
      result['unassigned_credits'] = 0;
      return result;
    }
    return super.read(path);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('stock-history')) return [stockHistory];
    if (path.startsWith('weights')) {
      return [
        {...fakeWeight, 'current_effectif_quality': 'UNRECONCILED'},
      ];
    }
    return super.list(path);
  }

  @override
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body,
  ) async {
    paths.add(path);
    writes.add(Map.from(body));
    if (interrupt) {
      interrupt = false;
      throw const ApiConnectionException();
    }
    return {
      'business_revision': 43,
      'fact': {'id': 'new'},
    };
  }
}

Future<void> editor(
  WidgetTester tester,
  FakeStock fake,
  String kind, {
  Map<String, dynamic>? target,
}) async {
  await tester.pumpWidget(
    testApp(
      Scaffold(
        body: StockEditor(
          service: fake,
          kind: kind,
          state: fake.state,
          installations: installations,
          cohorts: stockCohorts,
          target: target,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Enregistrer');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> panel(
  WidgetTester tester,
  FakeStock fake, {
  bool owner = true,
  List<String> rights = const ['aquatic.losses.create'],
}) async {
  await tester.pumpWidget(
    testApp(
      Scaffold(
        body: SingleChildScrollView(
          child: StockPanel(
            service: fake,
            owner: owner,
            rights: rights,
            installations: installations,
            cohorts: stockCohorts,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Mortality requires justification and sends unassigned integer count',
    (tester) async {
      final fake = FakeStock();
      await editor(tester, fake, 'MORTALITY');
      await save(tester);
      expect(fake.writes, isEmpty);
      await fill(tester, 'Nombre de poissons concernés', '10');
      await fill(
        tester,
        'Motif / justification obligatoire',
        'Constat du jour',
      );
      await save(tester);
      expect(fake.paths.single, 'mortalities/');
      expect(fake.writes.single['quantity'], 10);
      expect(fake.writes.single.containsKey('cohort'), false);
      expect(fake.writes.single['suspected'], false);
      fake.api.close();
    },
  );
  testWidgets('Suspicion is explicit and zero or fractional count rejected', (
    tester,
  ) async {
    final fake = FakeStock();
    await editor(tester, fake, 'MORTALITY');
    await fill(tester, 'Motif / justification obligatoire', 'À vérifier');
    await fill(tester, 'Nombre de poissons concernés', '0');
    await save(tester);
    expect(fake.writes, isEmpty);
    await fill(tester, 'Nombre de poissons concernés', '1.5');
    await save(tester);
    expect(fake.writes, isEmpty);
    await fill(tester, 'Nombre de poissons concernés', '10');
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await save(tester);
    expect(fake.writes.single['suspected'], true);
    fake.api.close();
  });
  testWidgets('Reconciliation is partial and never sends a new mortality', (
    tester,
  ) async {
    final fake = FakeStock();
    await editor(tester, fake, 'RECONCILE', target: pending);
    await fill(tester, 'Attribution à Novembre', '6');
    await fill(tester, 'Motif / justification obligatoire', 'Identification');
    await save(tester);
    expect(fake.paths.single, 'loss-reconciliations/');
    expect(fake.writes.single['allocations'], [
      {'cohort': stockCohorts.first['id'], 'quantity': 6},
    ]);
    expect(fake.writes.single.containsKey('installation'), false);
    fake.api.close();
  });
  testWidgets('Empty reconciliation is refused', (tester) async {
    final fake = FakeStock();
    await editor(tester, fake, 'RECONCILE', target: pending);
    await fill(tester, 'Motif / justification obligatoire', 'Identification');
    await save(tester);
    expect(fake.writes, isEmpty);
    expect(find.text('Renseignez au moins une attribution.'), findsOneWidget);
    fake.api.close();
  });
  testWidgets('Inventory allows zero and preserves reference revision', (
    tester,
  ) async {
    final fake = FakeStock();
    await editor(tester, fake, 'INVENTORY');
    await fill(tester, 'Nombre réellement constaté', '0');
    await fill(tester, 'Motif / justification obligatoire', 'Comptage complet');
    await save(tester);
    expect(fake.paths.single, 'inventories/');
    expect(fake.writes.single['observed_count'], 0);
    expect(fake.writes.single['expected_revision'], 42);
    fake.api.close();
  });
  testWidgets('Credit assignment selects an explicit cohort', (tester) async {
    final fake = FakeStock();
    await editor(tester, fake, 'ASSIGN_CREDIT', target: credit);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novembre').last);
    await tester.pumpAndSettle();
    await fill(tester, 'Nombre à affecter', '6');
    await fill(
      tester,
      'Motif / justification obligatoire',
      'Poissons identifiés',
    );
    await save(tester);
    expect(fake.paths.single, 'inventory-credits/assign/');
    expect(fake.writes.single['cohort'], stockCohorts.first['id']);
    expect(fake.writes.single['credit'], credit['id']);
    fake.api.close();
  });
  testWidgets('Cancellation is a dated compensating command with reason', (
    tester,
  ) async {
    final fake = FakeStock();
    await editor(tester, fake, 'CANCEL', target: stockHistory);
    await fill(
      tester,
      'Motif / justification obligatoire',
      'Erreur de constat',
    );
    await save(tester);
    expect(fake.paths.single, 'stock-cancellations/');
    expect(fake.writes.single['target'], stockHistory['id']);
    expect(fake.writes.single['occurred_at'], isNotNull);
    fake.api.close();
  });
  testWidgets(
    'Only owner sees sensitive actions even when death creation is allowed',
    (tester) async {
      final fake = FakeStock();
      await panel(tester, fake, owner: false);
      expect(find.text('Enregistrer une mortalité'), findsOneWidget);
      expect(find.text('Réaliser un inventaire'), findsNothing);
      expect(find.text('Rapprocher cette perte'), findsNothing);
      await tester.tap(find.text('Historique des corrections'));
      await tester.pumpAndSettle();
      expect(find.text('Annuler par compensation'), findsNothing);
      fake.api.close();
    },
  );
  testWidgets('Owner sees pending and immutable correction history', (
    tester,
  ) async {
    final fake = FakeStock();
    await panel(tester, fake);
    expect(find.text('À rapprocher : 10 sur 10 poissons'), findsOneWidget);
    expect(find.text('Rapprocher cette perte'), findsOneWidget);
    await tester.tap(find.text('Historique des corrections'));
    await tester.pumpAndSettle();
    expect(find.text('Motif : Constat confirmé'), findsOneWidget);
    expect(find.text('Annuler par compensation'), findsOneWidget);
    fake.api.close();
  });
  testWidgets('Uncertain response keeps exact UUID and payload', (
    tester,
  ) async {
    final fake = FakeStock()..interrupt = true;
    await editor(tester, fake, 'MORTALITY');
    await fill(tester, 'Nombre de poissons concernés', '10');
    await fill(tester, 'Motif / justification obligatoire', 'Constat');
    await save(tester);
    await tester.ensureVisible(find.text('Réessayer la même opération'));
    await tester.tap(find.text('Réessayer la même opération'));
    await tester.pumpAndSettle();
    expect(fake.writes.length, 2);
    expect(fake.writes.first, fake.writes.last);
    expect(fake.paths.first, fake.paths.last);
    fake.api.close();
  });
  testWidgets('Offline failure clears stale counts and disables mutation', (
    tester,
  ) async {
    final fake = FakeStock();
    await panel(tester, fake);
    fake.offline = true;
    await tester.tap(find.text('Actualiser les effectifs'));
    await tester.pumpAndSettle();
    expect(find.text('À rapprocher : 10 sur 10 poissons'), findsNothing);
    expect(find.textContaining('Effectifs indisponibles'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enregistrer une mortalité'),
          )
          .onPressed,
      isNull,
    );
    fake.api.close();
  });
  testWidgets('Old biomass snapshot is visibly marked uncertain', (
    tester,
  ) async {
    final fake = FakeStock();
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: ObservationPanel(
              service: fake,
              kind: 'WEIGHT',
              rights: const [],
              installations: installations,
              cohorts: stockCohorts,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Effectif actuel incertain'), findsOneWidget);
    expect(find.text('Poids moyen : 250 g'), findsOneWidget);
    fake.api.close();
  });
  for (final width in [360.0, 1080.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Uncertain dashboard fits width $width text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = FakeStock()..uncertainDashboard = true;
        await tester.pumpWidget(
          testApp(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1100),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: AquaticWorkspace(
                  service: fake,
                  capabilities: const {'write': <String>[], 'can_enable': true},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Brut non rapproché'), findsOneWidget);
        expect(find.text('Plage 590 à 600'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        fake.api.close();
      });
    }
  }
  for (final width in [360.0, 1080.0]) {
    for (final kind in [
      'MORTALITY',
      'RECONCILE',
      'INVENTORY',
      'ASSIGN_CREDIT',
      'CANCEL',
    ]) {
      testWidgets('V2 $kind fits $width and captures', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = FakeStock(), key = GlobalKey();
        final target = kind == 'RECONCILE'
            ? pending
            : kind == 'ASSIGN_CREDIT'
            ? credit
            : kind == 'CANCEL'
            ? stockHistory
            : null;
        await tester.pumpWidget(
          testApp(
            RepaintBoundary(
              key: key,
              child: Scaffold(
                body: StockEditor(
                  service: fake,
                  kind: kind,
                  state: fake.state,
                  installations: installations,
                  cohorts: stockCohorts,
                  target: target,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final folder = Platform.environment['ELEVAGE_PHASE2B_CAPTURES'];
        if (folder != null) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$folder/$kind-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        fake.api.close();
      });
    }
    testWidgets('V2 suspense panel fits $width and captures', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakeStock(), key = GlobalKey();
      await tester.pumpWidget(
        testApp(
          RepaintBoundary(
            key: key,
            child: Scaffold(
              body: SingleChildScrollView(
                child: StockPanel(
                  service: fake,
                  owner: true,
                  rights: const ['aquatic.losses.create'],
                  installations: installations,
                  cohorts: stockCohorts,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final folder = Platform.environment['ELEVAGE_PHASE2B_CAPTURES'];
      if (folder != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$folder/pending-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      fake.api.close();
    });
  }
}
