import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/widgets/farm_login_loading.dart';
import 'package:app_elevage/widgets/micro_feedback.dart';
import 'package:app_elevage/widgets/sync_feedback_tracker.dart';
import 'package:app_elevage/widgets/connection_indicator.dart';
import 'package:app_elevage/offline/sync_state.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'auth_connection_test.dart' show AuthApiFake, authApp;

class SlowLoginApi extends AuthApiFake {
  final result = Completer<bool>();
  int calls = 0;
  @override
  Future<bool> login(String username, String password) {
    calls++;
    return result.future;
  }
}

Widget demo(Widget child, {bool reduced = false, double width = 390}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          disableAnimations: reduced,
        ),
        child: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.animationsEnabled = true;
    ApiService.token = null;
    globalToken = null;
  });
  tearDown(() {
    AppSettings.instance.animationsEnabled = true;
  });
  testWidgets(
    'fast loading disappears before 300 ms without creating an animal',
    (t) async {
      await t.pumpWidget(demo(const FarmLoginLoading(active: true)));
      await t.pump(const Duration(milliseconds: 299));
      expect(find.byKey(const Key('farm-login-loading')), findsNothing);
      await t.pumpWidget(demo(const FarmLoginLoading(active: false)));
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(FarmAnimalFrame), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    },
  );
  testWidgets(
    'one local animal per slow loading; removed immediately on completion',
    (t) async {
      var choices = 0;
      FarmAnimal choose() => FarmAnimal.values[(choices++) % 5];
      await t.pumpWidget(
        demo(FarmLoginLoading(active: true, chooseAnimal: choose)),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Connexion à votre exploitation…'), findsOneWidget);
      expect(
        t.widget<FarmAnimalFrame>(find.byType(FarmAnimalFrame)).animal,
        FarmAnimal.hen,
      );
      await t.pump(const Duration(milliseconds: 200));
      expect(choices, 1);
      await t.pumpWidget(
        demo(FarmLoginLoading(active: false, chooseAnimal: choose)),
      );
      expect(find.byType(FarmAnimalFrame), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(
        demo(FarmLoginLoading(active: true, chooseAnimal: choose)),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(
        t.widget<FarmAnimalFrame>(find.byType(FarmAnimalFrame)).animal,
        FarmAnimal.pig,
      );
      await t.pumpWidget(const SizedBox());
      expect(t.binding.transientCallbackCount, 0);
    },
  );
  testWidgets(
    'failed login keeps normal error and duplicate submission guard',
    (t) async {
      final api = SlowLoginApi();
      await t.pumpWidget(authApp(LoginScreen(apiService: api)));
      await t.enterText(find.byType(TextField).at(0), 'synthetic');
      await t.enterText(find.byType(TextField).at(1), 'synthetic');
      await t.tap(find.text('Se connecter'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 310));
      expect(find.byType(FarmAnimalFrame), findsOneWidget);
      expect(
        t.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(api.calls, 1);
      api.result.complete(false);
      await t.pumpAndSettle();
      expect(find.text('Identifiants invalides'), findsOneWidget);
      expect(find.byType(FarmAnimalFrame), findsNothing);
      expect(find.byKey(const Key('micro-confirmation')), findsNothing);
      await t.pumpWidget(const SizedBox());
      api.close();
    },
  );
  testWidgets(
    'reduced or disabled motion keeps a static animal and no walking ticker',
    (t) async {
      await t.pumpWidget(
        demo(const FarmLoginLoading(active: true), reduced: true),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(FarmAnimalFrame), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(const SizedBox());
      AppSettings.instance.animationsEnabled = false;
      await t.pumpWidget(demo(const FarmLoginLoading(active: true)));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  test('motion preference is stored locally without API', () async {
    await AppSettings.instance.setAnimationsEnabled(false);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'settings_micro_animations',
      ),
      false,
    );
    AppSettings.instance.animationsEnabled = true;
    await AppSettings.instance.load();
    expect(AppSettings.instance.animationsEnabled, false);
  });
  testWidgets(
    'confirmed receipt celebrates once, expires, and never intercepts input',
    (t) async {
      final receipt = Object();
      var taps = 0;
      await t.pumpWidget(
        demo(
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () =>
                      MicroFeedback.confirmed(context, operation: receipt),
                  child: const Text('Confirmé'),
                ),
                TextButton(
                  onPressed: () => taps++,
                  child: const Text('Saisie suivante'),
                ),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.text('Confirmé'));
      await t.pump();
      expect(find.byKey(const Key('micro-confirmation')), findsOneWidget);
      await t.tap(find.text('Saisie suivante'));
      expect(taps, 1);
      await t.pump(const Duration(milliseconds: 800));
      await t.pump();
      expect(find.byKey(const Key('micro-confirmation')), findsNothing);
      await t.tap(find.text('Confirmé'));
      await t.pump();
      expect(find.byKey(const Key('micro-confirmation')), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(t.binding.transientCallbackCount, 0);
    },
  );
  testWidgets('static confirmation has no confetti or ticker and expires', (
    t,
  ) async {
    AppSettings.instance.animationsEnabled = false;
    await t.pumpWidget(
      demo(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => MicroFeedback.confirmed(context),
            child: const Text('Confirmé'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Confirmé'));
    await t.pump();
    final frame = t.widget<ConfirmationFrame>(find.byType(ConfirmationFrame));
    expect(frame.progress, 1);
    expect(frame.confetti, false);
    await t.pumpAndSettle();
    expect(t.binding.transientCallbackCount, 0);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });
  test(
    'sync needs a real witnessed cycle, new success and every counter cleared',
    () {
      final tracker = SyncFeedbackTracker();
      final old = DateTime.utc(2026),
          next = old.add(const Duration(seconds: 1));
      bool observe(
        SyncSummary s, {
        bool busy = false,
        bool unavailable = false,
        bool? network = true,
      }) => tracker.observe(
        summary: s,
        busy: busy,
        unavailable: unavailable,
        networkAvailable: network,
      );
      expect(observe(SyncSummary(lastSuccess: old)), false);
      expect(
        observe(SyncSummary(lastSuccess: next)),
        false,
      ); // mere refresh/reconnection
      observe(SyncSummary(pending: 2, lastSuccess: old));
      observe(SyncSummary(pending: 2, lastSuccess: old), busy: true);
      expect(observe(SyncSummary(pending: 1, lastSuccess: next)), false);
      observe(SyncSummary(pending: 1, lastSuccess: next), busy: true);
      expect(
        observe(SyncSummary(lastSuccess: next.add(const Duration(seconds: 1)))),
        true,
      );
      expect(
        observe(SyncSummary(lastSuccess: next.add(const Duration(seconds: 1)))),
        false,
      );
    },
  );
  for (final kind in [
    'pending',
    'awaiting',
    'conflicts',
    'blocked',
    'error',
    'network',
    'same-success',
  ]) {
    test('no global sync success with $kind', () {
      final tracker = SyncFeedbackTracker();
      final before = DateTime.utc(2026);
      tracker.observe(
        summary: SyncSummary(pending: 1, lastSuccess: before),
        busy: false,
        unavailable: false,
      );
      tracker.observe(
        summary: SyncSummary(pending: 1, lastSuccess: before),
        busy: true,
        unavailable: false,
      );
      final after = SyncSummary(
        pending: kind == 'pending' ? 1 : 0,
        awaitingValidation: kind == 'awaiting' ? 1 : 0,
        conflicts: kind == 'conflicts' ? 1 : 0,
        blocked: kind == 'blocked' ? 1 : 0,
        lastSuccess: kind == 'same-success'
            ? before
            : before.add(const Duration(seconds: 1)),
      );
      expect(
        tracker.observe(
          summary: after,
          busy: false,
          unavailable: kind == 'error',
          networkAvailable: kind == 'network' ? false : true,
        ),
        false,
      );
    });
  }
  testWidgets(
    'existing indicator shows sync once, not after remount or a reconnect',
    (t) async {
      final source = Object();
      final before = DateTime.utc(2026),
          after = before.add(const Duration(seconds: 1));
      Widget indicator(SyncSummary s, {bool busy = false}) => demo(
        ConnectionIndicator(
          syncSource: source,
          syncSummary: s,
          syncing: busy,
          networkAvailable: true,
          lastSuccess: after,
        ),
      );
      await t.pumpWidget(
        indicator(SyncSummary(pending: 1, lastSuccess: before)),
      );
      await t.pumpWidget(
        indicator(SyncSummary(pending: 1, lastSuccess: before), busy: true),
      );
      await t.pumpWidget(indicator(SyncSummary(lastSuccess: after)));
      await t.pump();
      expect(find.text('Données synchronisées'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2300));
      await t.pump();
      expect(find.text('Données synchronisées'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(indicator(SyncSummary(lastSuccess: after)));
      await t.pump();
      expect(find.text('Données synchronisées'), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(t.binding.transientCallbackCount, 0);
    },
  );
  testWidgets('new pending work removes the temporary synchronized notice', (
    t,
  ) async {
    final source = Object();
    final before = DateTime.utc(2026),
        after = before.add(const Duration(seconds: 1));
    Widget indicator(SyncSummary s, bool busy) => demo(
      ConnectionIndicator(
        syncSource: source,
        syncSummary: s,
        syncing: busy,
        networkAvailable: true,
      ),
    );
    await t.pumpWidget(
      indicator(SyncSummary(pending: 1, lastSuccess: before), false),
    );
    await t.pumpWidget(
      indicator(SyncSummary(pending: 1, lastSuccess: before), true),
    );
    await t.pumpWidget(indicator(SyncSummary(lastSuccess: after), false));
    await t.pump();
    expect(find.text('Données synchronisées'), findsOneWidget);
    await t.pumpWidget(
      indicator(SyncSummary(pending: 1, lastSuccess: after), false),
    );
    await t.pump();
    expect(find.text('Données synchronisées'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('vector frames stay bounded on 320px phone and large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      demo(const FarmLoginLoading(active: true), reduced: true, width: 320),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(FarmAnimalFrame)), const Size(76, 54));
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'dispose before delay and during motion cancels every controller',
    (t) async {
      await t.pumpWidget(demo(const FarmLoginLoading(active: true)));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(demo(const FarmLoginLoading(active: true)));
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      expect(t.binding.transientCallbackCount, 0);
      expect(t.takeException(), isNull);
    },
  );
}
