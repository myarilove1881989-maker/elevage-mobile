import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/android_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('elevage/app_version');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => '117'));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Map<String, Object> release() => {
    'schemaVersion': 1,
    'applicationId': 'com.elevage.app',
    'published': true,
    'versionCode': 118,
    'sha256': 'a' * 64,
    'publishedAt': '2026-01-01T00:00:00Z',
    'downloadUrl': AndroidUpdate.downloadUrl.toString(),
  };
  test(
    'reads installed package build and makes only anonymous official GET',
    () async {
      final service = AndroidUpdateService(
        clientFactory: () => MockClient((request) async {
          expect(request.url, AndroidUpdate.manifestUrl);
          expect(request.method, 'GET');
          expect(request.headers.containsKey('Authorization'), false);
          expect(request.followRedirects, false);
          return http.Response(jsonEncode(release()), 200);
        }),
      );
      expect((await service.check())?.code, 118);
      messenger.setMockMethodCallHandler(channel, (_) async => '118');
      expect(await service.check(), isNull);
      messenger.setMockMethodCallHandler(channel, (_) async => '119');
      expect(await service.check(), isNull);
    },
  );
  test(
    'offline, bad JSON, redirects and oversized responses are silent',
    () async {
      for (final response in [
        http.Response('bad json', 200),
        http.Response('', 302),
        http.Response('', 503),
        http.Response('x' * 16385, 200),
      ]) {
        expect(
          await AndroidUpdateService(
            clientFactory: () => MockClient((_) async => response),
          ).check(),
          isNull,
        );
      }
      expect(
        await AndroidUpdateService(
          clientFactory: () =>
              MockClient((_) async => throw Exception('offline')),
        ).check(),
        isNull,
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect(await AndroidUpdateService().check(), isNull);
    },
  );
}
