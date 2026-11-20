import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/pisciculture/aquatic_service.dart';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'package:app_elevage/pisciculture/aquatic_forms.dart';
import 'package:app_elevage/pisciculture/activity_selector.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'package:app_elevage/widgets/connection_indicator.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/farm_session.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/offline/sync_state.dart';
import 'production_tracking_test.dart' show testApp;

const rights = [
  'aquatic.read',
  'aquatic.installations.manage',
  'aquatic.cohorts.manage',
  'aquatic.transfers.create',
];
final installations = [
  {
    'id': '10000000-0000-4000-8000-000000000001',
    'name': 'Bassin Nord',
    'code': 'NORD',
    'type': 'BASSIN',
    'status': 'ACTIVE',
    'capacity': null,
    'capacity_unit': '',
    'location': 'Nord',
    'version': 1,
  },
  {
    'id': '10000000-0000-4000-8000-000000000002',
    'name': 'Bassin Sud',
    'code': 'SUD',
    'type': 'BASSIN',
    'status': 'ACTIVE',
    'capacity': null,
    'capacity_unit': '',
    'location': 'Sud',
    'version': 1,
  },
];
final species = [
  {'id': 'profile', 'species': 42, 'name': 'Tilapia'},
];
final cohorts = [
  {
    'id': '30000000-0000-4000-8000-000000000001',
    'name': 'Novembre',
    'code': 'NOV',
    'status': 'OPEN',
    'species': 42,
    'stage': null,
    'origin': {'type': 'PURCHASE'},
    'started_at': '2026-11-12T09:00:00Z',
    'gross_count': 1000,
    'version': 1,
    'positions': [
      {
        'id': 'p1',
        'installation': installations[0]['id'],
        'gross_count': 600,
        'available_count': 600,
        'version': 1,
      },
      {
        'id': 'p2',
        'installation': installations[1]['id'],
        'gross_count': 400,
        'available_count': 400,
        'version': 1,
      },
    ],
  },
];

class FakeAquatic extends AquaticService {
  FakeAquatic() : super(ApiService());
  bool offline = false;
  final writes = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> list(String path) async {
    if (offline) throw const ApiConnectionException();
    if (path.startsWith('installations')) return installations;
    if (path.startsWith('cohorts')) return cohorts;
    if (path.startsWith('species')) return species;
    return [];
  }

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (offline) throw const ApiConnectionException();
    return {
      'metrics': {
        'live_count': {'value': 1000},
        'active_installations': {'value': 2},
        'active_cohorts': {'value': 1},
      },
      'by_species': [
        {'cohort__species__nom': 'Tilapia', 'count': 1000},
      ],
      'by_installation': [
        {'installation__name': 'Bassin Nord', 'count': 600},
        {'installation__name': 'Bassin Sud', 'count': 400},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body,
  ) async {
    writes.add(body);
    if (offline) throw const ApiConnectionException();
    return {'status': 'APPLIED'};
  }
}

class InterruptedAquatic extends FakeAquatic {
  @override
  Future<Map<String, dynamic>> send(
    String path,
    Map<String, dynamic> body,
  ) async {
    writes.add(Map<String, dynamic>.from(body));
    if (writes.length == 1) throw const ApiConnectionException();
    return {'status': 'APPLIED'};
  }
}

class DelayedAquatic extends FakeAquatic {
  final first = Completer<Map<String, dynamic>>();
  int reads = 0;
  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (reads++ == 0) return first.future;
    final result = await super.read(path);
    (result['metrics'] as Map)['live_count'] = {'value': 2000};
    return result;
  }
}

FarmSession owner() {
  final codes = PermissionContract.catalogue
      .where((c) => c != 'agenda.progress')
      .toList();
  return FarmSession(
    userId: 1,
    farmId: 1,
    role: 'OWNER',
    origin: SessionOrigin.personalHttp,
    network: NetworkState.available,
    sync: const SyncSummary(),
    permissions: PermissionContract.decode(
      {
        'version': 2,
        'rights_version': 1,
        'user': 1,
        'exploitation': 1,
        'role': 'OWNER',
        'permissions': codes,
      },
      userId: 1,
      farmId: 1,
      role: 'OWNER',
      rightsVersion: 1,
      allowHttpV2: true,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  for (final width in [1440.0, 1280.0, 1080.0, 768.0, 360.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('aquatic shell width $width scale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = FakeAquatic(), capture = GlobalKey();
        await tester.pumpWidget(
          testApp(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1100),
                textScaler: TextScaler.linear(scale),
              ),
              child: RepaintBoundary(
                key: capture,
                child: Scaffold(
                  drawer: const Drawer(),
                  appBar: FarmTopBar(
                    session: owner(),
                    actions: {for (final d in FarmDestination.values) d: () {}},
                    connection: const ConnectionIndicator(lastSuccess: null),
                    onRefresh: () {},
                    onLogout: () {},
                  ),
                  body: Column(
                    children: [
                      ActivitySelector(aquatic: true, onSelect: (_) {}),
                      Expanded(
                        child: AquaticWorkspace(
                          service: fake,
                          capabilities: {'write': rights},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final left = tester.getRect(
              find.byKey(const ValueKey('activity-terrestrial')),
            ),
            right = tester.getRect(
              find.byKey(const ValueKey('activity-aquatic')),
            );
        expect(left.width, right.width);
        expect(left.width + right.width, width);
        if (width >= 1080 && scale == 1) {
          for (final d in [
            FarmDestination.purchases,
            FarmDestination.expenses,
            FarmDestination.movements,
            FarmDestination.billing,
          ])
            expect(
              find.byKey(ValueKey('navigation-${d.name}-horizontal')),
              findsOneWidget,
            );
          expect(
            find.byKey(const Key('topProductionTrackingButton')),
            findsOneWidget,
          );
        }
        expect(find.text('1000'), findsOneWidget);
        expect(find.textContaining('Tableau de bord',findRichText:true), findsWidgets);
        expect(find.byKey(const ValueKey('activity-aquatic')), findsOneWidget); // Utilities now open from the common navigation.
        expect(find.textContaining('Non disponible (phases suivantes)'), findsNothing);
        expect(tester.takeException(), isNull);
        final folder = Platform.environment['ELEVAGE_AQUATIC_PROOF_DIR'];
        if (folder != null && scale == 1)
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$folder/aquatic-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        await tester.pumpWidget(const SizedBox());
        fake.api.close();
      });
    }
  }
  testWidgets('cohort form and transfer form preserve units and fields', (
    tester,
  ) async {
    final fake = FakeAquatic();
    await tester.pumpWidget(
      testApp(
        AquaticForm(
          service: fake,
          kind: 'transfer',
          installations: installations,
          cohorts: cohorts,
          species: species,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nombre à transférer'), findsOneWidget);
    expect(find.textContaining('réserve de pertes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    fake.api.close();
  });
  testWidgets('offline workspace never claims a save', (tester) async {
    final fake = FakeAquatic()..offline = true;
    final key=GlobalKey<AquaticWorkspaceState>();
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: AquaticWorkspace(
            key:key,
            service: fake,
            capabilities: {'write': rights},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Connexion indisponible'), findsOneWidget);
    expect(fake.writes, isEmpty);
    await key.currentState!.form('cohort');
    await tester.pumpAndSettle();
    expect(find.text('Actualisez les données avec une connexion avant cette opération.'),findsOneWidget);
    expect(fake.writes,isEmpty);
    await tester.pumpWidget(const SizedBox());
    fake.api.close();
  });
  testWidgets(
    'interrupted transfer resumes identical command UUID and payload',
    (tester) async {
      final fake = InterruptedAquatic();
      await tester.pumpWidget(
        testApp(
          AquaticForm(
            service: fake,
            kind: 'transfer',
            installations: installations,
            cohorts: cohorts,
            species: species,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('aquatic-count')),
        '150',
      );
      await tester.enterText(
        find.byKey(const ValueKey('aquatic-reason')),
        'Répartition',
      );
      await tester.ensureVisible(find.text('Confirmer'));
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Réponse interrompue'), findsOneWidget);
      await tester.ensureVisible(find.text('Reprendre la même opération'));
      await tester.tap(find.text('Reprendre la même opération'));
      await tester.pumpAndSettle();
      expect(fake.writes, hasLength(2));
      expect(fake.writes[0], fake.writes[1]);
      await tester.pumpWidget(const SizedBox());
      fake.api.close();
    },
  );
  testWidgets('older response cannot overwrite newer aquatic filter result', (
    tester,
  ) async {
    final fake = DelayedAquatic(), key = GlobalKey<AquaticWorkspaceState>();
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: AquaticWorkspace(
            key: key,
            service: fake,
            capabilities: {'write': rights},
          ),
        ),
      ),
    );
    await tester.pump();
    await key.currentState!.reload();
    await tester.pumpAndSettle();
    expect(find.text('2000'), findsOneWidget);
    fake.first.complete({
      'metrics': {
        'live_count': {'value': 1000},
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('2000'), findsOneWidget);
    expect(find.text('1000'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    fake.api.close();
  });
  testWidgets('switching to terrestrial ignores late aquatic response', (
    tester,
  ) async {
    final fake = DelayedAquatic();
    bool aquatic = true;
    await tester.pumpWidget(
      testApp(
        StatefulBuilder(
          builder: (context, change) => Scaffold(
            body: Column(
              children: [
                ActivitySelector(
                  aquatic: aquatic,
                  onSelect: (value) => change(() => aquatic = value),
                ),
                Expanded(
                  child: aquatic
                      ? AquaticWorkspace(
                          service: fake,
                          capabilities: {'write': rights},
                        )
                      : const Text('Stock terrestre : 80'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('activity-terrestrial')));
    await tester.pump();
    fake.first.complete({
      'metrics': {
        'live_count': {'value': 1000},
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('Stock terrestre : 80'), findsOneWidget);
    expect(find.byType(AquaticWorkspace), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    fake.api.close();
  });
  testWidgets('activity selector is usable with Tab and Enter', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      testApp(
        Scaffold(body: ActivitySelector(aquatic: true, onSelect: changes.add)),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(changes, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [1440.0, 360.0]) {
    for (final kind in ['installation', 'cohort', 'transfer', 'onboarding']) {
      testWidgets('$kind form at $width with real V2 widgets', (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = FakeAquatic(), capture = GlobalKey();
        await tester.pumpWidget(
          testApp(
            RepaintBoundary(
              key: capture,
              child: AquaticForm(
                service: fake,
                kind: kind,
                installations: installations,
                cohorts: cohorts,
                species: species,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final folder = Platform.environment['ELEVAGE_AQUATIC_PROOF_DIR'];
        if (folder != null)
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
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
        await tester.pumpWidget(const SizedBox());
        fake.api.close();
      });
    }
  }
}
