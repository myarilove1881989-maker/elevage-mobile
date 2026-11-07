import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/theme/design_system_v2.dart';
import 'package:app_elevage/widgets/farm_login_loading.dart';
import 'package:app_elevage/widgets/micro_feedback.dart';
import 'package:app_elevage/widgets/connection_indicator.dart';
import 'package:app_elevage/offline/sync_state.dart';

const capture = bool.fromEnvironment('AUDIT_CAPTURE');
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    if (!kIsWeb) {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('visual review three native animations $width', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Widget card(String title, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
      final sync = Object();
      final now = DateTime.utc(2026, 11, 7);
      Widget page({bool busy = true}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: designSystemV2(ThemeData(fontFamily: 'Roboto')),
        home: Scaffold(
          appBar: AppBar(title: const Text('Élev’Age · Aperçu local')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'MICRO-ANIMATIONS V1',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Données fictives · aucune opération réelle',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 12),
                    card(
                      '1 · Connexion lente',
                      const FarmLoginLoading(
                        active: true,
                        chooseAnimal: pickCow,
                      ),
                    ),
                    card(
                      'Les cinq animaux · éléments vectoriels locaux',
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        children: [
                          for (final animal in FarmAnimal.values)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FarmAnimalFrame(animal: animal, phase: .3),
                                Text(
                                  [
                                    'Poule',
                                    'Cochon',
                                    'Vache',
                                    'Chèvre',
                                    'Mouton',
                                  ][animal.index],
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    card(
                      '2 · Opération confirmée · 700 ms',
                      const ConfirmationFrame(progress: .55, confetti: true),
                    ),
                    card(
                      '3 · Synchronisation terminée',
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ConnectionIndicator(
                            syncSource: sync,
                            syncSummary: SyncSummary(
                              pending: busy ? 1 : 0,
                              lastSuccess: busy ? null : now,
                            ),
                            syncing: busy,
                            networkAvailable: true,
                            lastSuccess: now,
                            clock: () => now,
                          ),
                          const Flexible(child: Text('Données synchronisées')),
                        ],
                      ),
                    ),
                    const Text(
                      'La reconnexion seule, un refus ou une attente hors ligne ne déclenchent aucune confirmation.',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpWidget(page());
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpWidget(page(busy: false));
      await t.pump();
      await t.pump(const Duration(milliseconds: 380));
      expect(t.takeException(), isNull);
      if (capture && !kIsWeb) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            Uri.file(
              'D:/ElevAge-Dev/mobile/.local/micro-animations-v1/captures/overview-${width.toInt()}.png',
            ),
          ),
        );
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      expect(t.binding.transientCallbackCount, 0);
    });
  }
  testWidgets('frame work benchmark synthetic host, not device FPS', (t) async {
    Future<double> measure(Widget Function(int) frame) async {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 120; i++) {
        await t.pumpWidget(MaterialApp(home: Center(child: frame(i))));
      }
      watch.stop();
      await t.pumpWidget(const SizedBox());
      return watch.elapsedMicroseconds / 120 / 1000;
    }

    final baseline = await measure(
      (_) => const SizedBox(width: 76, height: 54),
    );
    final animated = await measure(
      (i) => FarmAnimalFrame(animal: FarmAnimal.cow, phase: i / 120),
    );
    debugPrint(
      'MICRO_BENCH host widget pump average ms: baseline=$baseline vector=$animated; includes harness/layout, not release GPU or device startup',
    );
  });
}

FarmAnimal pickCow() => FarmAnimal.cow;
