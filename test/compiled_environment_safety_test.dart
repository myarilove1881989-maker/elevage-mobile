import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:app_elevage/services/lab_network_gate.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('isolated compiled environment',() {
  test('compiled isolated environment has correct endpoint and separate token namespace', () {
    final config=Config.current;
    expect(config.isLab || config.isPilot,isTrue);
    expect(config.apiUrl,config.isPilot?EnvironmentConfig.pilotApi:'https://192.168.1.100:8443/api');
    expect(config.tokenKey,isNot('token'));
    expect(config.externalLinksAllowed,isFalse);
    config.validate(release:!config.isLab);
    if(config.isLab) expect(()=>config.validate(release:true),throwsStateError);
  });
  test('compiled isolated token lifecycle never reads or deletes production credentials',() async {
    SharedPreferences.setMockInitialValues({'token':'synthetic-legacy-production'});
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    const channel=MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final encrypted=<String,String>{'token':'synthetic-production'};
    final accessed=<String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel,(call) async {
        final args=call.arguments as Map;
        final key=args['key'] as String;
        accessed.add(key);
        expect((args['options'] as Map)['resetOnError'],'false');
        if(call.method=='read') return encrypted[key];
        if(call.method=='write') encrypted[key]=args['value'] as String;
        if(call.method=='delete') encrypted.remove(key);
        return null;
      });
    try {
      final store=TokenService();
      expect(await store.getToken(),isNull);
      await store.saveToken('synthetic-isolated');
      expect(await store.getToken(),'synthetic-isolated');
      await store.clearToken();
      expect(encrypted,{'token':'synthetic-production'});
      expect(accessed,everyElement(Config.current.tokenKey));
      expect((await SharedPreferences.getInstance()).getString('token'),'synthetic-legacy-production');
    } finally {
      debugDefaultTargetPlatformOverride=null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    }
  });
  test('compiled isolated client never sends credentials to production',() async {
    var sends=0;
    final gate=LabNetworkGate();
    final client=GuardedApiClient(MockClient((_) async {sends++;return http.Response('',200);}),labGate:gate);
    try {
      await expectLater(client.post(Uri.parse('${EnvironmentConfig.productionApi}/token/'),
        headers:{'Authorization':'Bearer synthetic-only'},body:'synthetic-only'),
        throwsA(isA<NetworkDestinationException>()));
      expect(sends,0);
    } finally {client.close();gate.dispose();}
  });
  },skip:!(Config.current.isLab || Config.current.isPilot));
}
