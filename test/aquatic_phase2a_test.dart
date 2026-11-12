import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/observation_panel.dart';
import 'package:app_elevage/services/api_service.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic, installations, cohorts;
import 'production_tracking_test.dart' show testApp;

class ObservationFake extends FakeAquatic {
  bool interrupt = false;
  List<Map<String, dynamic>> history = [];
  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('weights') ||
        path.startsWith('water-readings') ||
        path.startsWith('observation-rules')) {
      return history;
    }
    return super.list(path);
  }

  @override
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body,
  ) async {
    writes.add(Map.from(body));
    if (interrupt) {
      interrupt = false;
      throw const ApiConnectionException();
    }
    return {'id': 'synthetic'};
  }
}

final fakeWeight = <String, dynamic>{
  'id': 'synthetic-weight',
  'cohort': cohorts.first['id'],
  'installation': null,
  'occurred_at': '2026-11-12T10:00:00Z',
  'note': 'Données fictives de qualification',
  'result': {
    'mean_g': {'decimal': '250'},
    'biomass_kg': {'decimal': '250'},
    'count_reference': {
      'gross_count': 1000,
      'quality': 'EXACT',
      'at': '2026-11-12T09:00:00Z',
    },
  },
  'freshness': {'age_seconds': 86400, 'status': 'UNCONFIGURED', 'policy': null},
};
Future<void> editor(
  WidgetTester tester,
  ObservationFake fake,
  String kind,
) async {
  await tester.pumpWidget(
    testApp(
      Scaffold(
        body: ObservationEditor(
          service: fake,
          kind: kind,
          installations: installations,
          cohorts: cohorts,
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
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Enregistrer'));
  await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
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
  test('Decimal strings preserve input and reject non finite values', () {
    expect(observationDecimal('12,5'), '12.5');
    for (final v in ['NaN', 'Infinity', '1e5', 'abc', '']) {
      expect(validObservationDecimal(v), false);
    }
    expect(validObservationDecimal('0'), true);
    expect(validObservationDecimal('0', positive: true), false);
    expect(validObservationDecimal('0.000001', positive: true), true);
  });
  testWidgets(
    'Water empty rejected; zero transmitted and missing readings omitted',
    (tester) async {
      final fake = ObservationFake();
      await editor(tester, fake, 'WATER');
      await save(tester);
      expect(fake.writes, isEmpty);
      expect(
        find.text('Renseignez au moins une mesure d’eau.'),
        findsOneWidget,
      );
      await fill(tester, 'Température (°C)', '0');
      await save(tester);
      expect(fake.writes.single['temperature_c'], '0');
      expect(fake.writes.single.containsKey('ph'), false);
      expect(fake.writes.single.containsKey('oxygen_mg_l'), false);
      fake.api.close();
    },
  );
  testWidgets('Sample sends strings and explicit reference date', (
    tester,
  ) async {
    final fake = ObservationFake();
    await editor(tester, fake, 'WEIGHT');
    await fill(tester, 'Nombre de poissons échantillonnés (n)', '50');
    await fill(tester, 'Masse de l’échantillon (kg)', '12,5');
    await save(tester);
    expect(fake.writes.single['sample_count'], 50);
    expect(fake.writes.single['mass_kg'], '12.5');
    expect(fake.writes.single.containsKey('direct_mean_g'), false);
    expect(fake.writes.single['cohort'], cohorts.first['id']);
    expect(fake.writes.single['count_reference_at'], isNotNull);
    fake.api.close();
  });
  testWidgets('Direct weight excludes sample pair', (tester) async {
    final fake = ObservationFake();
    await editor(tester, fake, 'WEIGHT');
    await tester.tap(find.text('Échantillon : n et masse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poids moyen direct').last);
    await tester.pumpAndSettle();
    await fill(tester, 'Poids moyen direct (g)', '250');
    await save(tester);
    expect(fake.writes.single['direct_mean_g'], '250');
    expect(fake.writes.single.containsKey('sample_count'), false);
    fake.api.close();
  });
  testWidgets('Uncertain reply reuses identical UUID and payload', (
    tester,
  ) async {
    final fake = ObservationFake()..interrupt = true;
    await editor(tester, fake, 'WATER');
    await fill(tester, 'pH (sans unité)', '7');
    await save(tester);
    expect(find.text('Réessayer la même opération'), findsOneWidget);
    await tester.ensureVisible(find.text('Réessayer la même opération'));
    await tester.tap(find.text('Réessayer la même opération'));
    await tester.pumpAndSettle();
    expect(fake.writes.length, 2);
    expect(fake.writes[0], fake.writes[1]);
    fake.api.close();
  });
  testWidgets('Read-only has no write action; offline clears history', (
    tester,
  ) async {
    final fake = ObservationFake()..history = [fakeWeight];
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: ObservationPanel(
              service: fake,
              kind: 'WEIGHT',
              rights: const [],
              installations: installations,
              cohorts: cohorts,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.text('Poids moyen : 250 g'), findsOneWidget);
    fake.offline = true;
    await tester.tap(find.text('Actualiser'));
    await tester.pumpAndSettle();
    expect(find.text('Poids moyen : 250 g'), findsNothing);
    expect(find.textContaining('Historique indisponible'), findsOneWidget);
    fake.api.close();
  });

  testWidgets('Graph isolates the selected cohort and capture', (tester) async {
    tester.view.physicalSize = const Size(1080, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = ObservationFake()
      ..history = [
        {
          ...fakeWeight,
          'id': 'earlier-weight',
          'occurred_at': '2026-11-11T10:00:00Z',
          'result': {
            ...fakeWeight['result'] as Map,
            'mean_g': {'decimal': '200'},
            'biomass_kg': {'decimal': '200'},
            'count_reference': {
              ...fakeWeight['result']['count_reference'] as Map,
              'at': '2026-11-11T09:00:00Z',
            },
          },
        },
        fakeWeight,
        {
          ...fakeWeight,
          'id': 'basin-observation',
          'cohort': null,
          'installation': installations.first['id'],
          'result': {
            ...fakeWeight['result'] as Map,
            'mean_g': {'decimal': '800'},
          },
        },
      ];
    final key = GlobalKey();
    await tester.pumpWidget(
      testApp(
        RepaintBoundary(
          key: key,
          child: Scaffold(
            body: SingleChildScrollView(
              child: ObservationPanel(
                service: fake,
                kind: 'WEIGHT',
                rights: const [],
                installations: installations,
                cohorts: cohorts,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novembre').last);
    await tester.pumpAndSettle();
    expect(find.text('Poids moyen : 250 g'), findsOneWidget);
    expect(find.text('Poids moyen : 800 g'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WeightEvolutionPainter,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final folder = Platform.environment['ELEVAGE_PHASE2A_CAPTURES'];
    if (folder != null) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$folder/weight-history-1080.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    fake.api.close();
  });
  for (final width in [360.0, 1080.0]) {
    for (final kind in ['WEIGHT', 'WATER', 'RULE']) {
      testWidgets('V2 $kind editor $width fits and capture', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = ObservationFake(), key = GlobalKey();
        await tester.pumpWidget(
          testApp(
            RepaintBoundary(
              key: key,
              child: Scaffold(
                body: ObservationEditor(
                  service: fake,
                  kind: kind,
                  installations: installations,
                  cohorts: cohorts,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final folder = Platform.environment['ELEVAGE_PHASE2A_CAPTURES'];
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
              '$folder/$kind-editor-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        fake.api.close();
      });
    }
  }
}
