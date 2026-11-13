import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/breeding_panel.dart';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'package:app_elevage/services/api_service.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic, installations, cohorts;
import 'production_tracking_test.dart' show testApp;

const groupId = '71000000-0000-4000-8000-000000000001';
const repId = '72000000-0000-4000-8000-000000000001';
const hatchId = '73000000-0000-4000-8000-000000000001';
const estimateId = '73000000-0000-4000-8000-000000000002';
final breedingGroups = <Map<String, dynamic>>[
  {
    'id': groupId,
    'name': 'Géniteurs Nord',
    'species': 42,
    'species_name': 'Tilapia',
    'installation': installations.first['id'],
    'installation_name': 'Bassin Nord',
    'cohort': cohorts.first['id'],
    'males': null,
    'females': null,
    'status': 'ACTIVE',
    'version': 1,
    'note': '',
    'occurred_at': '2026-11-12T10:00:00Z',
    'recorded_at': '2026-11-12T10:01:00Z',
  },
];
final reproductions = <Map<String, dynamic>>[
  {
    'id': repId,
    'group': groupId,
    'group_name': 'Géniteurs Nord',
    'species': 42,
    'species_name': 'Tilapia',
    'installation': installations.first['id'],
    'installation_name': 'Bassin Nord',
    'occurred_at': '2026-11-13T08:00:00Z',
    'recorded_at': '2026-11-13T08:01:00Z',
    'status': 'OPEN',
    'version': 1,
    'technique': '',
    'note': '',
  },
];
Map<String, dynamic> hatchFact({bool estimated = false}) => {
  'id': estimated ? estimateId : hatchId,
  'kind': 'HATCH',
  'reproduction': repId,
  'group': groupId,
  'group_name': 'Géniteurs Nord',
  'species': 42,
  'installation': installations.first['id'],
  'installation_name': 'Bassin Nord',
  'occurred_at': '2026-11-13T09:00:00Z',
  'recorded_at': '2026-11-13T09:01:00Z',
  'quantity': estimated ? 500 : 100,
  'quality': estimated ? 'ESTIMATED' : 'COUNTED',
  'canceled': false,
  'actor': 1,
  'actor_name': 'Éleveur test',
  'note': 'Données fictives de qualification',
  'reason': '',
  'availability': {
    'confirmed_total': estimated ? null : 100,
    'placed_total': estimated ? 0 : 40,
    'available_confirmed': estimated ? null : 60,
    'voided': false,
  },
};
List<Map<String, dynamic>> breedingFacts() => [
  hatchFact(),
  hatchFact(estimated: true),
  {
    ...hatchFact(),
    'id': '74000000-0000-4000-8000-000000000001',
    'kind': 'SPAWN',
    'quantity': null,
    'quality': 'UNKNOWN',
    'availability': null,
  },
];

class FakeBreeding extends FakeAquatic {
  bool interrupt = false, refuse = false;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> read(String path) async {
    paths.add(path);
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('reproductions/$repId/')) {
      return {
        ...reproductions.first,
        'facts': breedingFacts(),
        'hatches': <dynamic>[],
      };
    }
    if (path.startsWith('brood-groups/$groupId/')) return breedingGroups.first;
    return super.read(path);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    paths.add(path);
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('brood-groups/')) return breedingGroups;
    if (path.startsWith('reproductions/')) return reproductions;
    if (path.startsWith('breeding-facts/')) return breedingFacts();
    if (path.startsWith('breeding-revisions/')) {
      return [
        {
          'id': 1,
          'actor': 1,
          'occurred_at': '2026-11-13T10:00:00Z',
          'reason': 'Motif conservé',
          'before': {'name': 'Ancien nom'},
          'after': {'name': 'Géniteurs Nord'},
        },
      ];
    }
    if (path.startsWith('stages/')) {
      return [
        {
          'id': '75000000-0000-4000-8000-000000000001',
          'species': 42,
          'name': 'Stade déclaré',
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
    paths.add(path);
    writes.add(Map<String, dynamic>.from(body));
    if (interrupt) {
      interrupt = false;
      throw const ApiConnectionException();
    }
    if (refuse) {
      throw const ApiHttpException(409, 'HATCH_CONFIRMED_QUANTITY_EXCEEDED');
    }
    return {'id': 'created'};
  }
}

const breedingSpecies = <Map<String, dynamic>>[
  {'id': '42', 'name': 'Tilapia'},
];
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

Widget editor(
  FakeBreeding f,
  String kind, {
  Map<String, dynamic>? initial,
  bool prefill = false,
}) => BreedingEditor(
  service: f,
  kind: kind,
  groups: breedingGroups,
  reproductions: reproductions,
  facts: breedingFacts(),
  stages: const [],
  installations: installations,
  cohorts: cohorts,
  species: breedingSpecies,
  initial: initial,
  initialInstallation: prefill ? installations.first['id'] as String : null,
  initialCohort: prefill ? cohorts.first['id'] as String : null,
  initialReproduction: ['SPAWN', 'INCUBATION', 'HATCH'].contains(kind)
      ? repId
      : null,
);
Future<void> open(
  WidgetTester t,
  FakeBreeding f,
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
              builder: (_) =>
                  editor(f, kind, initial: initial, prefill: prefill),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    ),
  );
  await click(t, 'Ouvrir');
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  final folder = Platform.environment['ELEVAGE_PHASE3B_CAPTURES'];
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
    final root = Platform.environment['FLUTTER_ROOT']!;
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
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
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'group with known cohort keeps sex unknown and adds no initial_count',
    (t) async {
      final f = FakeBreeding();
      await open(t, f, 'GROUP', prefill: true);
      await fill(t, 'name', 'Groupe déclaré');
      await click(t, 'Enregistrer');
      final b = f.writes.single;
      expect(f.paths.last, 'brood-groups/');
      expect(b['cohort'], cohorts.first['id']);
      expect(b['males'], isNull);
      expect(b['females'], isNull);
      expect(b.containsKey('initial_count'), false);
      f.api.close();
    },
  );
  testWidgets('explicit zero sex count stays zero and unknown remains null', (
    t,
  ) async {
    final f = FakeBreeding();
    await open(t, f, 'GROUP', prefill: true);
    await fill(t, 'name', 'Groupe déclaré');
    await click(t, 'Mâles et femelles (facultatif)');
    await fill(t, 'males', '0');
    await click(t, 'Enregistrer');
    expect(f.writes.single['males'], 0);
    expect(f.writes.single['females'], isNull);
    f.api.close();
  });
  testWidgets('simple reproduction imposes no spawn technique or egg count', (
    t,
  ) async {
    final f = FakeBreeding();
    await open(t, f, 'REPRODUCTION');
    await choose(t, 'Groupe de géniteurs', 'Géniteurs Nord');
    await click(t, 'Enregistrer');
    expect(f.paths.last, 'reproductions/');
    expect(f.writes.single['group'], groupId);
    expect(f.writes.single['technique'], '');
    expect(f.writes.single.containsKey('quantity'), false);
    f.api.close();
  });
  for (final kind in ['SPAWN', 'INCUBATION', 'HATCH']) {
    testWidgets('$kind quantity unknown has no live entry', (t) async {
      final f = FakeBreeding();
      await open(t, f, kind);
      await click(t, 'Enregistrer');
      final b = f.writes.single;
      expect(f.paths.last, 'breeding-facts/');
      expect(b['kind'], kind);
      expect(b['quality'], 'UNKNOWN');
      expect(b['quantity'], isNull);
      expect(b['parent'], isNull);
      expect(b.containsKey('initial_count'), false);
      f.api.close();
    });
  }
  testWidgets('spawn estimate is explicit and never inferred as fry', (
    t,
  ) async {
    final f = FakeBreeding();
    await open(t, f, 'SPAWN');
    await choose(t, 'Qualité de la quantité', 'Estimé');
    await fill(t, 'quantity', '1000');
    await click(t, 'Enregistrer');
    expect(f.writes.single['quality'], 'ESTIMATED');
    expect(f.writes.single['quantity'], 1000);
    expect(f.writes.single.containsKey('cohort'), false);
    f.api.close();
  });
  testWidgets(
    'placement uses a confirmed source and an explicit actual count',
    (t) async {
      final f = FakeBreeding();
      await open(t, f, 'PLACEMENT', initial: hatchFact());
      await fill(t, 'quantity', '20');
      await fill(t, 'reason', 'Mise en élevage comptée');
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      await click(
        t,
        'Je confirme l’effectif réellement compté et mis en élevage',
      );
      await click(t, 'Enregistrer');
      final b = f.writes.single;
      expect(f.paths.last, 'fry-placements/');
      expect(b['hatch'], hatchId);
      expect(b['quantity'], 20);
      expect(b['actually_counted'], true);
      expect(b.containsKey('confirm_total'), false);
      expect(b.containsKey('initial_count'), false);
      f.api.close();
    },
  );
  testWidgets(
    'estimated hatch needs newly typed confirmed total and justification',
    (t) async {
      final f = FakeBreeding();
      await open(t, f, 'PLACEMENT', initial: hatchFact(estimated: true));
      await fill(t, 'quantity', '20');
      await fill(t, 'reason', 'Effectif réellement mis en élevage');
      await click(
        t,
        'Je confirme l’effectif réellement compté et mis en élevage',
      );
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      await fill(t, 'confirm_total', '30');
      await fill(t, 'confirmation_reason', 'Comptage réel du lot');
      await click(t, 'Enregistrer');
      final b = f.writes.single;
      expect(b['confirm_total'], 30);
      expect(b['quantity'], 20);
      expect(b['confirm_total'], isNot(500));
      f.api.close();
    },
  );
  testWidgets(
    'standalone count declares total including previously allocated fry',
    (t) async {
      final f = FakeBreeding();
      await open(t, f, 'COUNT', initial: hatchFact());
      await fill(t, 'quantity', '100');
      await fill(t, 'reason', 'Comptage total constaté');
      await click(t, 'Je confirme un comptage réel, pas une estimation');
      await click(t, 'Enregistrer');
      expect(f.paths.last, 'hatch-counts/');
      expect(f.writes.single['quantity'], 100);
      expect(f.writes.single.containsKey('id'), false);
      f.api.close();
    },
  );
  testWidgets(
    'uncertain placement retry retains UUID cohort identity and source',
    (t) async {
      final f = FakeBreeding()..interrupt = true;
      await open(t, f, 'PLACEMENT', initial: hatchFact());
      await fill(t, 'quantity', '20');
      await fill(t, 'reason', 'Entrée comptée');
      await click(
        t,
        'Je confirme l’effectif réellement compté et mis en élevage',
      );
      await click(t, 'Enregistrer');
      expect(
        t.widget<TextFormField>(find.byKey(const ValueKey('quantity'))).enabled,
        false,
      );
      await click(t, 'Réessayer la même opération');
      expect(f.writes.length, 2);
      expect(f.writes.first, f.writes.last);
      f.api.close();
    },
  );
  testWidgets('known overuse refusal allows correction with another UUID', (
    t,
  ) async {
    final f = FakeBreeding()..refuse = true;
    await open(t, f, 'PLACEMENT', initial: hatchFact());
    await fill(t, 'quantity', '70');
    await fill(t, 'reason', 'Entrée comptée');
    await click(
      t,
      'Je confirme l’effectif réellement compté et mis en élevage',
    );
    await click(t, 'Enregistrer');
    expect(
      find.textContaining('effectif confirmé disponible est insuffisant'),
      findsOneWidget,
    );
    f.refuse = false;
    await fill(t, 'quantity', '20');
    await click(t, 'Enregistrer');
    expect(f.writes.last['quantity'], 20);
    expect(
      f.writes.last['operation_uuid'],
      isNot(f.writes.first['operation_uuid']),
    );
    f.api.close();
  });
  testWidgets('session change cannot reattribute pending fry introduction', (
    t,
  ) async {
    ApiService.setLocalPresentationIdentity('synthetic-breeding-A');
    addTearDown(ApiService.clearLocalPresentationIdentity);
    final f = FakeBreeding()..interrupt = true;
    await open(t, f, 'GROUP', prefill: true);
    await fill(t, 'name', 'Groupe A');
    await click(t, 'Enregistrer');
    ApiService.setLocalPresentationIdentity('synthetic-breeding-B');
    await click(t, 'Réessayer la même opération');
    expect(f.writes.length, 1);
    expect(find.textContaining('Session modifiée'), findsOneWidget);
    f.api.close();
  });
  testWidgets('metadata update sends only changed fields and keeps a reason', (
    t,
  ) async {
    final f = FakeBreeding();
    await open(t, f, 'GROUP_EDIT', initial: breedingGroups.first);
    await choose(t, 'Statut', 'Inactif');
    await fill(t, 'reason', 'Pause du groupe');
    await click(t, 'Enregistrer');
    expect(f.paths.last, 'brood-group-revisions/');
    expect(f.writes.single['expected_version'], 1);
    expect(f.writes.single['status'], 'INACTIVE');
    expect(f.writes.single.containsKey('installation'), false);
    expect(f.writes.single.containsKey('males'), false);
    f.api.close();
  });
  testWidgets('void keeps original reference and explicit justification', (
    t,
  ) async {
    final f = FakeBreeding();
    await open(t, f, 'VOID', initial: hatchFact());
    await fill(t, 'reason', 'Constat erroné, original conservé');
    await click(t, 'Enregistrer');
    expect(f.paths.last, 'breeding-voids/');
    expect(f.writes.single['target'], hatchId);
    expect(f.writes.single.containsKey('quantity'), false);
    f.api.close();
  });
  for (final kind in ['GROUP', 'PLACEMENT']) {
    testWidgets('actual save 360 text twice $kind', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = FakeBreeding();
      await t.pumpWidget(
        testApp(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => editor(
                      f,
                      kind,
                      initial: kind == 'PLACEMENT'
                          ? hatchFact(estimated: true)
                          : null,
                      prefill: kind == 'GROUP',
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
      if (kind == 'GROUP') {
        await fill(t, 'name', 'Groupe constaté');
      } else {
        await fill(t, 'quantity', '10');
        await fill(t, 'confirm_total', '20');
        await fill(t, 'confirmation_reason', 'Comptage effectif');
        await fill(t, 'reason', 'Mise en élevage réelle');
        await click(
          t,
          'Je confirme l’effectif réellement compté et mis en élevage',
        );
      }
      await click(t, 'Enregistrer');
      expect(f.writes.length, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      f.api.close();
    });
  }
  testWidgets(
    'invalid optional sex count remains validated after folding details',
    (t) async {
      final f = FakeBreeding();
      await open(t, f, 'GROUP', prefill: true);
      await fill(t, 'name', 'Groupe');
      await click(t, 'Mâles et femelles (facultatif)');
      await fill(t, 'males', '2.5');
      await click(t, 'Mâles et femelles (facultatif)');
      await click(t, 'Enregistrer');
      expect(f.writes, isEmpty);
      expect(find.text('Réessayer la même opération'), findsNothing);
      await t.pumpWidget(const SizedBox());
      f.api.close();
    },
  );
  for (final width in [360.0, 1080.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final kind in [
        'GROUP',
        'REPRODUCTION',
        'SPAWN',
        'INCUBATION',
        'HATCH',
        'PLACEMENT',
      ]) {
        testWidgets('V2 $kind width$width text$scale', (t) async {
          t.view.physicalSize = Size(width, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final f = FakeBreeding(), key = GlobalKey();
          await t.pumpWidget(
            testApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    body: editor(
                      f,
                      kind,
                      initial: kind == 'PLACEMENT'
                          ? hatchFact(estimated: true)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          if (scale == 1) await capture(t, key, '$kind-${width.toInt()}');
          await t.pumpWidget(const SizedBox());
          f.api.close();
        });
      }
      testWidgets(
        'panel width$width text$scale no false totals filters and stale clearing',
        (t) async {
          t.view.physicalSize = Size(width, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final f = FakeBreeding(), key = GlobalKey();
          await t.pumpWidget(
            testApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: BreedingPanel(
                        service: f,
                        owner: false,
                        rights: const [],
                        installations: installations,
                        cohorts: cohorts,
                        species: breedingSpecies,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('Nouvelle reproduction'), findsNothing);
          expect(find.text('Mettre les alevins en élevage'), findsNothing);
          await click(t, 'Historique');
          expect(
            find.textContaining('disponible confirmé : inconnu'),
            findsOneWidget,
          );
          await choose(t, 'Espèce', 'Tilapia');
          expect(
            Uri.parse(
              f.paths.where((p) => p.startsWith('breeding-facts/?')).last,
            ).queryParameters['species'],
            '42',
          );
          if (scale == 1) await capture(t, key, 'history-${width.toInt()}');
          expect(t.takeException(), isNull);
          f.offline = true;
          await click(t, 'Actualiser');
          expect(
            find.textContaining('Reproduction indisponible'),
            findsOneWidget,
          );
          expect(find.text('Ponte'), findsNothing);
          await t.pumpWidget(const SizedBox());
          f.api.close();
        },
      );
    }
  }
  testWidgets(
    'optional stages are in reproduction detail and group audit is accessible',
    (t) async {
      final f = FakeBreeding();
      await t.pumpWidget(
        testApp(
          Scaffold(
            body: SingleChildScrollView(
              child: BreedingPanel(
                service: f,
                owner: true,
                rights: const [],
                installations: installations,
                cohorts: cohorts,
                species: breedingSpecies,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await click(t, 'Voir les étapes et les alevins');
      expect(find.text('Enregistrer une ponte'), findsOneWidget);
      expect(find.text('Enregistrer une incubation'), findsOneWidget);
      expect(find.textContaining('Taux de fécondation'), findsOneWidget);
      await click(t, 'Fermer');
      await click(t, 'Mes géniteurs');
      await click(t, 'Historique du groupe');
      expect(find.text('Motif : Motif conservé'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      f.api.close();
    },
  );
  for (final kind in ['cohort', 'installation']) {
    testWidgets('prefill group from $kind detail without creating fish', (
      t,
    ) async {
      final f = FakeBreeding();
      await t.pumpWidget(
        testApp(
          Scaffold(
            body: AquaticWorkspace(
              service: f,
              capabilities: const {
                'can_enable': true,
                'write': ['aquatic.breeders.manage'],
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      t
          .state<AquaticWorkspaceState>(find.byType(AquaticWorkspace))
          .showPage(kind == 'cohort' ? 'cohorts' : 'installations');
      await t.pumpAndSettle();
      final row = kind == 'cohort' ? cohorts.first : installations.first;
      await click(t, '${row['name']} · ${row['code']}');
      await click(t, 'Groupe de géniteurs');
      expect(find.text('Créer un groupe de géniteurs'), findsOneWidget);
      if (kind == 'cohort') {
        final field = t.widget<DropdownButtonFormField<String>>(
          find.widgetWithText(
            DropdownButtonFormField<String>,
            'Cohorte d’origine',
          ),
        );
        expect(field.initialValue, row['id']);
      } else {
        final field = t.widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: find.byType(BreedingEditor),
            matching: find.widgetWithText(
              DropdownButtonFormField<String>,
              'Installation',
            ),
          ),
        );
        expect(field.initialValue, row['id']);
      }
      expect(f.writes, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      f.api.close();
    });
  }
}
