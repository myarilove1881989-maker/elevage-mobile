import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const pilot = EnvironmentConfig(
  environment: 'pilot',
  flavor: 'pilot',
  apiOverride: EnvironmentConfig.pilotApi,
);

void main() {
  test('production defaults and custom development endpoint are preserved', () {
    expect(const EnvironmentConfig().apiUrl, EnvironmentConfig.productionApi);
    expect(
      const EnvironmentConfig(flavor: 'production').apiUrl,
      EnvironmentConfig.productionApi,
    );
    expect(
      const EnvironmentConfig(apiOverride: 'http://localhost:8000/api').apiUrl,
      'http://localhost:8000/api',
    );
    expect(const EnvironmentConfig().tokenKey, 'token');
    expect(const EnvironmentConfig().externalLinksAllowed, isTrue);
  });

  test(
    'pilot requires explicit environment, flavor and reviewed exact URL',
    () {
      expect(pilot.apiUrl, EnvironmentConfig.pilotApi);
      expect(pilot.tokenKey, isNot('token'));
      expect(pilot.externalLinksAllowed, isFalse);
      expect(() => pilot.validate(web: true), throwsStateError);
      for (final configuration in [
        const EnvironmentConfig(environment: 'pilto'),
        const EnvironmentConfig(flavor: 'unknown'),
        const EnvironmentConfig(environment: 'pilot'),
        const EnvironmentConfig(flavor: 'pilot'),
        const EnvironmentConfig(
          environment: 'pilot',
          flavor: 'production',
          apiOverride: EnvironmentConfig.pilotApi,
        ),
        const EnvironmentConfig(
          environment: 'pilot',
          apiOverride: EnvironmentConfig.pilotApi,
        ),
        const EnvironmentConfig(
          flavor: 'pilot',
          apiOverride: EnvironmentConfig.pilotApi,
        ),
        for (final url in [
          EnvironmentConfig.productionApi,
          'https://backend-elevage-lczf.onrender.com/api',
          '${EnvironmentConfig.pilotApi}/',
          ' ${EnvironmentConfig.pilotApi}',
          'https://unknown.onrender.com/api',
          'http://backend-elevage-pilot.onrender.com/api',
          'https://backend-elevage-pilot.onrender.com:444/api',
          '${EnvironmentConfig.pilotApi}?next=production',
          '${EnvironmentConfig.pilotApi}#fragment',
        ])
          EnvironmentConfig(
            environment: 'pilot',
            flavor: 'pilot',
            apiOverride: url,
          ),
      ]) {
        expect(() => configuration.apiUrl, throwsStateError);
      }
    },
  );

  test('disallowed URLs never reach transport, even with credentials', () async {
    var sent = 0;
    final client = GuardedApiClient(
      MockClient((_) async {
        sent++;
        return http.Response('{}', 200);
      }),
      configuration: pilot,
    );
    for (final value in [
      '${EnvironmentConfig.productionApi}/token/',
      'https://backend-elevage-lczf.onrender.com/api/token/',
      'https://elevage-mobile.onrender.com/api/token/',
      'https://backend-elevage-pilot.onrender.com.attacker.invalid/api/token/',
      'https://backend-elevage-pilot.onrender.com./api/token/',
      'http://backend-elevage-pilot.onrender.com/api/token/',
      'https://backend-elevage-pilot.onrender.com:444/api/token/',
      'https://user:secret@backend-elevage-pilot.onrender.com/api/token/',
      'https://backend-elevage-pilot.onrender.com/token/',
      'https://backend-elevage-pilot.onrender.com/api-other/token/',
      '${EnvironmentConfig.pilotApi}/token/#fragment',
      '${EnvironmentConfig.pilotApi}/%2e%2e/token/',
      '${EnvironmentConfig.pilotApi}/%2fadmin/',
      '${EnvironmentConfig.pilotApi}/%5cadmin/',
      '${EnvironmentConfig.pilotApi}/%252e%252e/token/',
    ]) {
      final request = http.Request('POST', Uri.parse(value))
        ..headers['Authorization'] = 'Bearer synthetic-token'
        ..body = 'synthetic-password';
      await expectLater(
        client.send(request),
        throwsA(isA<NetworkDestinationException>()),
      );
    }
    expect(sent, 0);
    client.close();
  });

  test(
    'pilot allows API queries and paths while disabling redirect following',
    () async {
      var sent = 0;
      final client = GuardedApiClient(
        MockClient((request) async {
          sent++;
          expect(request.followRedirects, isFalse);
          expect(request.maxRedirects, 0);
          return http.Response('{}', 200);
        }),
        configuration: pilot,
      );
      for (final path in [
        '/token/',
        '/devices/',
        '/offline/submissions/',
        '/lots/?limit=10&offset=0',
      ]) {
        expect(
          (await client.get(
            Uri.parse('${EnvironmentConfig.pilotApi}$path'),
          )).statusCode,
          200,
        );
      }
      expect(sent, 4);
      client.close();
    },
  );

  for (final status in [301, 302, 303, 307, 308]) {
    test(
      'pilot rejects $status redirect, including same-origin and relative',
      () async {
        for (final location in [
          EnvironmentConfig.productionApi,
          'https://backend-elevage-lczf.onrender.com/api/token/',
          '${EnvironmentConfig.pilotApi}/token/',
          '/api/token/',
          '//backend-elevage.onrender.com/api/token/',
        ]) {
          var sent = 0;
          final client = GuardedApiClient(
            MockClient((request) async {
              sent++;
              expect(request.followRedirects, isFalse);
              return http.Response(
                'synthetic response',
                status,
                headers: {'location': location},
              );
            }),
            configuration: pilot,
          );
          await expectLater(
            client.post(
              Uri.parse('${EnvironmentConfig.pilotApi}/token/'),
              body: 'synthetic-password',
            ),
            throwsA(isA<NetworkDestinationException>()),
          );
          expect(sent, 1);
          client.close();
        }
      },
    );
  }

  test(
    'production client preserves redirect behavior and custom destinations',
    () async {
      final client = GuardedApiClient(
        MockClient((request) async {
          expect(request.followRedirects, isTrue);
          return http.Response('', 302);
        }),
        configuration: const EnvironmentConfig(),
      );
      expect(
        (await client.get(
          Uri.parse('http://localhost:8000/api/token/'),
        )).statusCode,
        302,
      );
      client.close();
    },
  );
}
