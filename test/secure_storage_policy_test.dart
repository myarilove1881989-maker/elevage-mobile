import 'package:app_elevage/services/secure_storage_policy.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('policy preserves aliases/ciphers/migration options while refusing reset', () {
    final expected = const AndroidOptions().toMap()..['resetOnError']='false';
    expect(protectedSecureStorage.aOptions.toMap(), expected);
  });

  for (final failure in ['read','write']) {
    test('secure token $failure error preserves legacy value and does not delete secrets', () async {
      SharedPreferences.setMockInitialValues({'token':'synthetic-legacy'});
      debugDefaultTargetPlatformOverride=TargetPlatform.android;
      const channel=MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
      final calls=<String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel,(call) async {
          calls.add(call.method);
          expect(((call.arguments as Map)['options'] as Map)['resetOnError'],'false');
          throw PlatformException(code:'synthetic-key-unavailable');
        });
      try {
        final store=TokenService();
        if(failure=='read') {
          await expectLater(store.getToken(),throwsA(isA<PlatformException>()));
        } else {
          await expectLater(store.saveToken('synthetic-new'),throwsA(isA<PlatformException>()));
        }
        expect(calls,[failure]);
        expect((await SharedPreferences.getInstance()).getString('token'),'synthetic-legacy');
      } finally {
        debugDefaultTargetPlatformOverride=null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel,null);
      }
    });
  }
}
