import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('release transport refuses every other destination before exposing credentials', () async {
    var sends = 0;
    final client = GuardedApiClient(MockClient((_) async {
      sends++;
      return http.Response('{}', 200);
    }), configuration: const EnvironmentConfig(flavor: 'production'),
      enforceProductionForTesting: true);
    for (final url in [
      '${EnvironmentConfig.pilotApi}/token/',
      'https://backend-elevage-lczf.onrender.com/api/token/',
      'https://backend-elevage.onrender.com.attacker.invalid/api/token/',
      'https://backend-elevage.onrender.com:444/api/token/',
      'http://backend-elevage.onrender.com/api/token/',
      'https://backend-elevage.onrender.com/admin/',
      'https://user:synthetic@backend-elevage.onrender.com/api/token/',
      '${EnvironmentConfig.productionApi}/%2fadmin/',
      '${EnvironmentConfig.productionApi}/token/#fragment',
    ]) {
      final request = http.Request('POST', Uri.parse(url))
        ..headers['Authorization'] = 'Bearer synthetic-only'
        ..body = 'synthetic-only';
      await expectLater(client.send(request), throwsA(isA<NetworkDestinationException>()));
    }
    expect(sends, 0);
    client.close();
  });

  test('production release refuses an unauthorized constructor base URL', () {
    final client = GuardedApiClient(MockClient((_) async => http.Response('', 200)),
      enforceProductionForTesting: true);
    expect(() => client.validateBaseUrl(EnvironmentConfig.pilotApi),
      throwsA(isA<NetworkDestinationException>()));
    client.validateBaseUrl(EnvironmentConfig.productionApi);
    client.close();
  });

  for (final code in [301,302,303,307,308]) {
    test('release transport refuses $code without following even a relative redirect', () async {
      var sends=0;
      final client=GuardedApiClient(MockClient((request) async {
        sends++;
        expect(request.followRedirects,isFalse);
        expect(request.maxRedirects,0);
        return http.Response('',code,headers:{'location':'/api/token/'});
      }),enforceProductionForTesting:true);
      await expectLater(client.get(Uri.parse('${EnvironmentConfig.productionApi}/token/')),
        throwsA(isA<NetworkDestinationException>()));
      expect(sends,1);
      client.close();
    });
  }

  test('release permits canonical API paths and pagination query',() async {
    var sends=0;
    final client=GuardedApiClient(MockClient((_) async {sends++;return http.Response('{}',200);}),
      enforceProductionForTesting:true);
    for(final path in ['/token/','/offline/submissions/','/lots/?limit=10&offset=0']) {
      expect((await client.get(Uri.parse('${EnvironmentConfig.productionApi}$path'))).statusCode,200);
    }
    expect(sends,3);client.close();
  });
}
