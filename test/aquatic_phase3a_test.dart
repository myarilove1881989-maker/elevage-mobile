import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/health_panel.dart';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'package:app_elevage/services/api_service.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic, installations, cohorts;
import 'production_tracking_test.dart' show testApp;

const vaccine = '61000000-0000-4000-8000-000000000001';
const medicine = '62000000-0000-4000-8000-000000000001';
const obsId = '63000000-0000-4000-8000-000000000001';
Map<String, dynamic> healthCatalog() => {
  'products': <Map<String, dynamic>>[
    {
      'id': vaccine,
      'source': 'SUPPLY',
      'name': 'Produit existant',
      'type': 'VACCINE',
      'unit': 'dose',
      'information': '',
      'archived': false,
    },
    {
      'id': medicine,
      'source': 'SANITARY',
      'name': 'Produit liquide déclaré',
      'type': 'TREATMENT',
      'unit': 'mL',
      'information': 'Information saisie par le propriétaire',
      'archived': false,
    },
  ],
  'can_manage': true,
  'photo_supported': false,
  'planning_supported': false,
  'stock_automation': false,
};
Map<String, dynamic> healthObservation() => {
  'id': obsId,
  'root_id': obsId,
  'kind': 'OBSERVATION',
  'installation': installations.first['id'],
  'cohort': null,
  'symptoms': 'Aspect inhabituel',
  'behavior': 'Nage inhabituelle',
  'occurred_at': '2026-11-13T10:00:00Z',
  'recorded_at': '2026-11-13T10:01:00Z',
  'actor': 1,
  'actor_name': 'Éleveur test',
  'note': 'Données synthétiques',
  'is_current': true,
  'supersedes': null,
};
Map<String, dynamic> healthTreatment({bool known = false}) => {
  ...healthObservation(),
  'id': '64000000-0000-4000-8000-000000000001',
  'root_id': '64000000-0000-4000-8000-000000000001',
  'kind': 'TREATMENT',
  'product_snapshot': healthCatalog()['products'][0],
  'quantity': '1.250000',
  'unit': 'dose',
  'ongoing': true,
  'reason': 'Acte effectivement réalisé',
  'withdrawal_days': known ? 2 : null,
  'withdrawal_source': known ? 'Source fictive de qualification' : '',
  'withdrawal_until': known ? '2026-11-15T10:00:00Z' : null,
  'precaution': {
    'status': known ? 'ACTIVE' : 'UNKNOWN',
    'message': known ? 'Délai documenté en cours' : unknownWithdrawal,
  },
  'observation': obsId,
  'time_precision': 'DATETIME',
};

class FakeHealth extends FakeAquatic {
  bool interrupt = false, refuse = false;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> read(String path) async {
    paths.add(path);
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('health-products/')) return healthCatalog();
    return super.read(path);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    paths.add(path);
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('health-observations/')) return [healthObservation()];
    if (path.startsWith('health-history/')) {
      return [healthObservation(), healthTreatment()];
    }
    if (path.startsWith('health-state/')) {
      return [healthTreatment(), healthTreatment(known: true)];
    }
    return super.list(path);
  }

  @override
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body,
  ) async {
    paths.add(path);
    writes.add(Map<String, dynamic>.from(body));
    if (interrupt) {
      interrupt = false;
      throw const ApiConnectionException();
    }
    if (refuse) throw const ApiHttpException(400, 'Date ou référence invalide');
    return {'id': 'new'};
  }
}

Future<void> choose(WidgetTester t, String label, String choice) async {
  final f = find.widgetWithText(DropdownButtonFormField<String>, label);
  await t.ensureVisible(f);
  await t.tap(f);
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

Future<void> click(WidgetTester t, String label) async {
  final f = find.text(label);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> open(
  WidgetTester t,
  FakeHealth fake,
  String kind, {
  Map<String, dynamic>? initial,
  bool prefill = false,
}) async {
  await t.pumpWidget(
    testApp(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => HealthEditor(
                service: fake,
                kind: kind,
                catalog: healthCatalog(),
                owner: true,
                installations: installations,
                cohorts: cohorts,
                initial: initial,
                initialInstallation: prefill
                    ? installations.first['id'] as String
                    : null,
                initialCohort: prefill ? cohorts.first['id'] as String : null,
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    ),
  );
  await click(t, 'Ouvrir');
}

Future<void> treatmentFields(WidgetTester t) async {
  await choose(t, 'Bassin concerné', 'Bassin Nord');
  await choose(t, 'Produit utilisé', 'Produit existant · Vaccin · dose');
  await fill(t, 'quantity', '1,25');
  await fill(t, 'reason', 'Acte constaté');
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  final folder = Platform.environment['ELEVAGE_PHASE3A_CAPTURES'];
  if (folder == null) return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final sdk = Platform.environment['FLUTTER_ROOT']!;
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            ).readAsBytes(),
          ),
        ),
      );
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'observation no diagnosis photo or mortality and global basin preserved',
    (t) async {
      final f = FakeHealth();
      await open(t, f, 'OBSERVATION');
      await choose(t, 'Bassin concerné', 'Bassin Nord');
      await fill(t, 'symptoms', 'Aspect constaté');
      await fill(t, 'behavior', 'Comportement constaté');
      await click(t, 'Enregistrer');
      expect(f.paths.last, 'health-observations/');
      expect(f.writes.single['cohort'], isNull);
      expect(f.writes.single.containsKey('diagnosis'), false);
      expect(f.writes.single.containsKey('photo'), false);
      expect(f.writes.single.containsKey('mortality'), false);
      f.api.close();
    },
  );
  testWidgets('empty observation blocked then context prefill is retained', (
    t,
  ) async {
    final f = FakeHealth();
    await open(t, f, 'OBSERVATION', prefill: true);
    await click(t, 'Enregistrer');
    expect(f.writes, isEmpty);
    expect(find.textContaining('Décrivez au moins'), findsOneWidget);
    await fill(t, 'behavior', 'Nage constatée');
    await click(t, 'Enregistrer');
    expect(f.writes.single['installation'], installations.first['id']);
    expect(f.writes.single['cohort'], cohorts.first['id']);
    f.api.close();
  });
  testWidgets(
    'treatment confirms administered reuses product unknown delay and no expense',
    (t) async {
      final f = FakeHealth();
      await open(t, f, 'TREATMENT');
      await treatmentFields(t);
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      await click(t, 'Je confirme que le traitement a été administré');
      await click(t, 'Enregistrer');
      final body = f.writes.single;
      expect(body['supply_product'], vaccine);
      expect(body['quantity'], '1.25');
      expect(body['unit'], 'dose');
      expect(body['administration_status'], 'ADMINISTERED');
      expect(body['withdrawal_days'], isNull);
      expect(body['withdrawal_source'], '');
      expect(body.containsKey('amount'), false);
      expect(body.containsKey('expense'), false);
      f.api.close();
    },
  );
  testWidgets(
    'documented zero delay requires source distinct from unknown and links observation',
    (t) async {
      final f = FakeHealth();
      await open(t, f, 'TREATMENT');
      await treatmentFields(t);
      await choose(t, 'Observation liée', '13/11/2026 · Aspect inhabituel');
      await click(t, 'Délai avant commercialisation connu et documenté');
      await fill(t, 'withdrawal_days', '0');
      await click(t, 'Je confirme que le traitement a été administré');
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      await fill(t, 'withdrawal_source', 'Document de qualification');
      await click(t, 'Enregistrer');
      expect(f.writes.single['withdrawal_days'], 0);
      expect(f.writes.single['withdrawal_source'], 'Document de qualification');
      expect(f.writes.single['observation'], obsId);
      f.api.close();
    },
  );
  testWidgets(
    'nonstock product unit is explicit and no biological dose proposed',
    (t) async {
      final f = FakeHealth();
      await open(t, f, 'TREATMENT');
      await choose(t, 'Bassin concerné', 'Bassin Nord');
      await choose(
        t,
        'Produit utilisé',
        'Produit liquide déclaré · Produit de traitement · mL',
      );
      expect(find.text('Unité : mL'), findsOneWidget);
      await fill(t, 'quantity', '2.000001');
      await fill(t, 'reason', 'Acte saisi');
      await click(t, 'Je confirme que le traitement a été administré');
      await click(t, 'Enregistrer');
      expect(f.writes.single['sanitary_product'], medicine);
      expect(f.writes.single['unit'], 'mL');
      expect(f.writes.single.containsKey('supply_product'), false);
      f.api.close();
    },
  );
  testWidgets('product creation is separate from purchase and treatment', (
    t,
  ) async {
    final f = FakeHealth();
    await open(t, f, 'PRODUCT');
    await fill(t, 'name', 'Produit déclaré');
    await choose(t, 'Type de produit', 'Autre produit sanitaire');
    await choose(t, 'Unité d’administration', 'g');
    await click(t, 'Enregistrer');
    expect(f.paths.last, 'health-products/');
    expect(f.writes.single['unit'], 'g');
    expect(f.writes.single.containsKey('quantity'), false);
    expect(f.writes.single.containsKey('amount'), false);
    f.api.close();
  });
  testWidgets('uncertain response retries same immutable body and UUID', (
    t,
  ) async {
    final f = FakeHealth()..interrupt = true;
    await open(t, f, 'OBSERVATION', prefill: true);
    await fill(t, 'symptoms', 'Aspect constaté');
    await click(t, 'Enregistrer');
    expect(find.text('Réessayer la même opération'), findsOneWidget);
    expect(
      t.widget<TextFormField>(find.byKey(const ValueKey('symptoms'))).enabled,
      false,
    );
    await click(t, 'Réessayer la même opération');
    expect(f.writes.length, 2);
    expect(f.writes.first, f.writes.last);
    f.api.close();
  });
  testWidgets('known rejection can be corrected with new UUID', (t) async {
    final f = FakeHealth()..refuse = true;
    await open(t, f, 'OBSERVATION', prefill: true);
    await fill(t, 'symptoms', 'Aspect constaté');
    await click(t, 'Enregistrer');
    expect(
      t.widget<TextFormField>(find.byKey(const ValueKey('symptoms'))).enabled,
      true,
    );
    f.refuse = false;
    await fill(t, 'symptoms', 'Description corrigée');
    await click(t, 'Enregistrer');
    expect(
      f.writes.first['operation_uuid'],
      isNot(f.writes.last['operation_uuid']),
    );
    f.api.close();
  });
  testWidgets(
    'rectification preserves target and sends full replacement with reason',
    (t) async {
      final f = FakeHealth();
      await open(t, f, 'TREATMENT', initial: healthTreatment());
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      await fill(t, 'correction_reason', 'Corriger la note');
      await click(t, 'Je confirme que le traitement a été administré');
      await click(t, 'Enregistrer');
      expect(f.paths.last, 'health-corrections/');
      expect(f.writes.single['target'], healthTreatment()['id']);
      expect(f.writes.single['treatment']['supply_product'], vaccine);
      expect(f.writes.single['reason'], 'Corriger la note');
      f.api.close();
    },
  );
  testWidgets(
    'date only is explicit and future check never becomes planned treatment',
    (t) async {
      final f = FakeHealth();
      await open(t, f, 'OBSERVATION', prefill: true);
      await fill(t, 'symptoms', 'Aspect constaté');
      await click(t, 'Heure connue');
      await click(t, 'Enregistrer');
      expect(f.writes.single['time_precision'], 'DATE');
      expect(
        f.writes.single['occurred_at'],
        startsWith('${f.writes.single['business_date']}T00:00:00'),
      );
      f.api.close();
    },
  );
  testWidgets('uncertain care cannot be retried under another session', (
    t,
  ) async {
    ApiService.setLocalPresentationIdentity('synthetic-health-author-A');
    addTearDown(ApiService.clearLocalPresentationIdentity);
    final f = FakeHealth()..interrupt = true;
    await open(t, f, 'OBSERVATION', prefill: true);
    await fill(t, 'symptoms', 'Constat de A');
    await click(t, 'Enregistrer');
    ApiService.setLocalPresentationIdentity('synthetic-health-author-B');
    await click(t, 'Réessayer la même opération');
    expect(f.writes.length, 1);
    expect(find.textContaining('Session modifiée'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    f.api.close();
  });
  for (final kind in ['OBSERVATION', 'TREATMENT']) {
    testWidgets('scroll and save at 360 with text twice $kind', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = FakeHealth();
      await t.pumpWidget(
        testApp(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => HealthEditor(
                      service: f,
                      kind: kind,
                      catalog: healthCatalog(),
                      owner: true,
                      installations: installations,
                      cohorts: cohorts,
                      initialInstallation: installations.first['id'] as String,
                    ),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await click(t, 'Ouvrir');
      if (kind == 'OBSERVATION') {
        await fill(t, 'symptoms', 'Description constatée sur petit écran');
      } else {
        await choose(t, 'Produit utilisé', 'Produit existant · Vaccin · dose');
        await fill(t, 'quantity', '1');
        await fill(t, 'reason', 'Acte constaté sur petit écran');
        await click(t, 'Je confirme que le traitement a été administré');
      }
      await click(t, 'Enregistrer');
      expect(f.writes.length, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      f.api.close();
    });
  }
  for (final kind in ['cohort', 'installation']) {
    testWidgets(
      'open sanitary observation from $kind detail preserves context',
      (t) async {
        final f = FakeHealth();
        await t.pumpWidget(
          testApp(
            Scaffold(
              body: AquaticWorkspace(
                service: f,
                capabilities: const {
                  'can_enable': true,
                  'write': ['aquatic.health.observe'],
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final state = t.state<AquaticWorkspaceState>(
          find.byType(AquaticWorkspace),
        );
        state.showPage(kind == 'cohort' ? 'cohorts' : 'installations');
        await t.pumpAndSettle();
        final row = kind == 'cohort' ? cohorts.first : installations.first;
        await click(t, '${row['name']} · ${row['code']}');
        await click(t, 'Signaler un problème');
        expect(find.text('Signaler un problème de santé'), findsOneWidget);
        final basin = t.widget<DropdownButtonFormField<String>>(
          find.widgetWithText(
            DropdownButtonFormField<String>,
            'Bassin concerné',
          ),
        );
        final population = t.widget<DropdownButtonFormField<String>>(
          find.widgetWithText(
            DropdownButtonFormField<String>,
            'Cohorte (facultative)',
          ),
        );
        if (kind == 'cohort') {
          expect(population.initialValue, row['id']);
        } else {
          expect(basin.initialValue, row['id']);
          expect(population.initialValue, isNull);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        f.api.close();
      },
    );
  }
  for (final width in [360.0, 1080.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final mode in [
        'OBSERVATION',
        'TREATMENT',
        'PRODUCT',
        'CORRECTION',
      ]) {
        testWidgets('V2 $mode $width text$scale layout', (t) async {
          t.view.physicalSize = Size(width, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final f = FakeHealth(), key = GlobalKey();
          await t.pumpWidget(
            testApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    body: HealthEditor(
                      service: f,
                      kind: mode == 'CORRECTION' ? 'TREATMENT' : mode,
                      catalog: healthCatalog(),
                      owner: true,
                      installations: installations,
                      cohorts: cohorts,
                      initial: mode == 'CORRECTION' ? healthTreatment() : null,
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          if (scale == 1) await capture(t, key, '$mode-${width.toInt()}');
          await t.pumpWidget(const SizedBox());
          f.api.close();
        });
      }
      testWidgets(
        'health panel $width text$scale filters unknown precautions and read only rights',
        (t) async {
          t.view.physicalSize = Size(width, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final f = FakeHealth(), key = GlobalKey();
          await t.pumpWidget(
            testApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: HealthPanel(
                        service: f,
                        owner: false,
                        rights: const [],
                        installations: installations,
                        cohorts: cohorts,
                        species: const [
                          {'id': '42', 'name': 'Tilapia'},
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text('Signaler un problème'), findsNothing);
          expect(find.text('Enregistrer un traitement'), findsNothing);
          expect(find.text(unknownWithdrawal), findsOneWidget);
          expect(find.text('Ajouter un produit au référentiel'), findsNothing);
          await choose(t, 'Cohorte', 'Novembre');
          expect(
            Uri.parse(
              f.paths.where((p) => p.startsWith('health-history/')).last,
            ).queryParameters['cohort'],
            cohorts.first['id'],
          );
          expect(
            Uri.parse(
              f.paths.where((p) => p.startsWith('health-state/')).last,
            ).queryParameters.containsKey('from'),
            false,
          );
          await click(t, 'Consulter l’historique');
          expect(find.text('Observation sanitaire'), findsOneWidget);
          if (scale == 1) await capture(t, key, 'history-${width.toInt()}');
          expect(t.takeException(), isNull);
          f.offline = true;
          await click(t, 'Actualiser');
          expect(
            find.textContaining('Suivi sanitaire indisponible'),
            findsOneWidget,
          );
          expect(find.text('Observation sanitaire'), findsNothing);
          await t.pumpWidget(const SizedBox());
          f.api.close();
        },
      );
    }
  }
  testWidgets('history from basin detail opens history with basin filter', (
    t,
  ) async {
    final f = FakeHealth();
    await t.pumpWidget(
      testApp(
        Scaffold(
          body: AquaticWorkspace(
            service: f,
            capabilities: const {'can_enable': true, 'write': <String>[]},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    t
        .state<AquaticWorkspaceState>(find.byType(AquaticWorkspace))
        .showPage('installations');
    await t.pumpAndSettle();
    await click(
      t,
      '${installations.first['name']} · ${installations.first['code']}',
    );
    await click(t, 'Historique sanitaire');
    expect(find.text('Observation sanitaire'), findsOneWidget);
    expect(find.text('Signaler un problème de santé'), findsNothing);
    expect(
      Uri.parse(
        f.paths.where((p) => p.startsWith('health-history/')).last,
      ).queryParameters['installation'],
      installations.first['id'],
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    f.api.close();
  });
  testWidgets('workspace health entry stays in aquatic navigation', (t) async {
    final f = FakeHealth();
    await t.pumpWidget(
      testApp(
        Scaffold(
          body: AquaticWorkspace(
            service: f,
            capabilities: const {
              'can_enable': true,
              'write': ['aquatic.health.observe', 'aquatic.health.treat'],
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await click(t, 'Santé');
    expect(find.text('Signaler un problème'), findsOneWidget);
    expect(find.text('Enregistrer un traitement'), findsOneWidget);
    expect(find.text('Consulter l’historique'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    f.api.close();
  });
}
