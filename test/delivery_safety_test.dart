import 'dart:io';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release production refuses another HTTPS endpoint', () {
    for (final url in [
      EnvironmentConfig.pilotApi,
      'https://backend-elevage-lczf.onrender.com/api',
      'https://unapproved.invalid/api',
      'https://192.168.1.100/api',
      '${EnvironmentConfig.productionApi}/',
    ]) {
      expect(
        () => EnvironmentConfig(flavor: 'production', apiOverride: url)
            .validate(release: true),
        throwsStateError,
        reason: url,
      );
    }
    const EnvironmentConfig(flavor: 'production').validate(release: true);
    const EnvironmentConfig(flavor: 'production',
      apiOverride: EnvironmentConfig.productionApi).validate(release: true);
    const EnvironmentConfig(apiOverride: 'http://localhost:8000/api')
        .validate(release: false);
  });

  test('main cloud and device transfer exclude private files as well as preferences', () {
    final xml = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    for (final mode in ['cloud-backup', 'device-transfer']) {
      final section = RegExp('<$mode[^>]*>([\\s\\S]*?)</$mode>')
          .firstMatch(xml)!.group(1)!;
      for (final domain in ['root', 'file', 'database', 'sharedpref',
        'external', 'device_root', 'device_file', 'device_database',
        'device_sharedpref']) {
        expect(section, contains('domain="$domain" path="."'),
          reason: '$mode/$domain');
      }
    }
  });

  test('operator secret read propagates failure without requesting destructive reset', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final calls = <String>[];
    Map? options;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        options = (call.arguments as Map)['options'] as Map;
        throw PlatformException(code: 'synthetic-key-unavailable');
      });
    try {
      await expectLater(const AndroidOperatorSecretStore().read('synthetic-key'),
        throwsA(isA<PlatformException>()));
      expect(calls, ['read']);
      expect(options!['resetOnError'], 'false');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    }
  });
}
