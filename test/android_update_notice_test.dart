import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/android_update.dart';
import 'package:app_elevage/widgets/android_update_notice.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11);
  Map<String, Object> manifest() => {
    'schemaVersion': 1,
    'applicationId': 'com.elevage.app',
    'published': true,
    'versionCode': 118,
    'downloadUrl': AndroidUpdate.downloadUrl.toString(),
    'publishedAt': '2026-11-02T16:34:54Z',
    'sha256': 'a' * 64,
  };
  test(
    'uses integer build ordering and rejects unpublished or foreign releases',
    () {
      expect(AndroidUpdate.parse(manifest(), 117, now)?.code, 118);
      expect(AndroidUpdate.parse(manifest(), 118, now), isNull);
      expect(AndroidUpdate.parse(manifest(), 119, now), isNull);
      expect(
        AndroidUpdate.parse(
          {...manifest(), 'versionCode': 1000},
          999,
          now,
        )?.code,
        1000,
      );
      for (final change in <Map<String, Object>>[
        {'published': false},
        {'versionCode': '118'},
        {'versionCode': 118.5},
        {'applicationId': 'other.app'},
        {'schemaVersion': 2},
        {'downloadUrl': 'https://example.com/app.apk'},
        {'publishedAt': '2027-01-01T00:00:00Z'},
        {'sha256': 'invalid'},
      ]) {
        expect(
          AndroidUpdate.parse({...manifest(), ...change}, 117, now),
          isNull,
        );
      }
    },
  );

  Future<void> show(
    WidgetTester tester, {
    required Future<AndroidUpdate?> Function() check,
    Future<bool> Function()? open,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AndroidUpdateNotice(
              check: check,
              openDownload: open,
              child: const Center(child: Text('Démarrage disponible')),
            ),
          ),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('startup stays visible during slow network and after failure', (
    tester,
  ) async {
    final pending = Completer<AndroidUpdate?>();
    await show(tester, check: () => pending.future);
    expect(find.text('Démarrage disponible'), findsOneWidget);
    expect(find.text('Plus tard'), findsNothing);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Démarrage disponible'), findsOneWidget);
    expect(find.text('Plus tard'), findsNothing);
  }, skip: kIsWeb);
  testWidgets(
    'opens official page and allows postponement on a narrow display',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      await show(
        tester,
        check: () async => const AndroidUpdate(118),
        open: () async {
          opened++;
          return false;
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Une mise à jour d’Élev’Age est disponible'),
        findsOneWidget,
      );
      await tester.tap(find.text('Télécharger la mise à jour'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(
        find.text('Impossible d’ouvrir le navigateur. Réessayez plus tard.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(find.text('Plus tard'), findsNothing);
      expect(find.text('Démarrage disponible'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: kIsWeb,
  );
  testWidgets('equal version and non-Android never show a notice', (
    tester,
  ) async {
    await show(tester, check: () async => null);
    await tester.pumpAndSettle();
    expect(find.text('Plus tard'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    var calls = 0;
    await show(
      tester,
      platform: TargetPlatform.iOS,
      check: () async {
        calls++;
        return const AndroidUpdate(118);
      },
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Plus tard'), findsNothing);
  });
  testWidgets(
    'Web makes no update request even with Android platform override',
    (tester) async {
      var calls = 0;
      await show(
        tester,
        check: () async {
          calls++;
          return const AndroidUpdate(118);
        },
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Plus tard'), findsNothing);
      expect(find.text('Démarrage disponible'), findsOneWidget);
    },
    skip: !kIsWeb,
  );
}
