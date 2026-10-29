import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:app_elevage/services/lab_network_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

EnvironmentConfig wifi(
  String host, {
  int port = 8443,
  String scheme = 'https',
}) => EnvironmentConfig(
  environment: 'lab',
  flavor: 'lab',
  labHost: host,
  labTransport: 'wifi',
  apiOverride: '$scheme://$host:$port/api',
);
void main() {
  for (final host in [
    '192.168.1.100',
    '10.1.2.3',
    '172.16.0.2',
    '172.31.255.254',
  ]) {
    test(
      'private Wi-Fi destination accepted only with explicit transport: $host',
      () {
        final config = wifi(host);
        expect(config.apiUrl, 'https://$host:8443/api');
        expect(
          () => EnvironmentConfig(
            environment: 'lab',
            flavor: 'lab',
            labHost: host,
            apiOverride: 'https://$host:8443/api',
          ).apiUrl,
          throwsStateError,
        );
      },
    );
  }
  for (final host in [
    '127.0.0.1',
    '8.8.8.8',
    '169.254.1.2',
    '172.32.0.1',
    'lab.example.test',
    '192.168.001.2',
    '192.168.1.999',
  ]) {
    test(
      'Wi-Fi refuses non-private or malformed host $host',
      () => expect(() => wifi(host).apiUrl, throwsStateError),
    );
  }
  test('HTTP and unexpected ports remain forbidden', () {
    expect(
      () => wifi('192.168.1.100', scheme: 'http').apiUrl,
      throwsStateError,
    );
    expect(() => wifi('192.168.1.100', port: 8444).apiUrl, throwsStateError);
  });
  for (final variant in ['production', 'pilot']) {
    test(
      '$variant cannot use Wi-Fi exception',
      () => expect(
        () => EnvironmentConfig(
          environment: variant,
          flavor: variant,
          labTransport: 'wifi',
        ).apiUrl,
        throwsStateError,
      ),
    );
  }
  test(
    'closed candidate does not even probe without compiled isolation evidence',
    () async {
      var probes = 0;
      final gate = LabNetworkGate(
        serverProbe: (_, _) async {
          probes++;
          return true;
        },
      );
      expect(await gate.initializeFromBuild(wifi('192.168.1.100')), isFalse);
      expect(gate.enabled, isFalse);
      expect(probes, 0);
      gate.dispose();
    },
  );
  test('no proof means zero outgoing application requests', () async {
    var sends = 0;
    final gate = LabNetworkGate();
    final config = wifi('192.168.1.100');
    final client = GuardedApiClient(
      MockClient((_) async {
        sends++;
        return http.Response('{}', 200);
      }),
      configuration: config,
      labGate: gate,
    );
    await expectLater(
      client.get(Uri.parse('${config.apiUrl}/token/')),
      throwsA(isA<NetworkDestinationException>()),
    );
    expect(sends, 0);
    expect(gate.enabled, isFalse);
    client.close();
    gate.dispose();
  });
  test(
    'approved Wi-Fi refuses other host/port, wrong laboratory and redirects',
    () async {
      final config = wifi('192.168.1.100');
      final time = DateTime.utc(2026, 10, 17, 12);
      final a = LabIsolationApproval(
        endpoint: config.apiUrl,
        reference: 'a' * 64,
        laboratoryId: 'b' * 32,
        certificateSha256: 'c' * 64,
        reviewedAt: time,
        expiresAt: time.add(const Duration(hours: 1)),
      );
      final gate = LabNetworkGate(approval: a, clock: () => time);
      gate.permitVerifiedIsolation(config, evidenceReference: 'a' * 64);
      var sends = 0;
      var redirect = false;
      var correct = false;
      final client = GuardedApiClient(
        MockClient((r) async {
          sends++;
          expect(r.followRedirects, isFalse);
          return http.Response(
            '{}',
            redirect ? 302 : 200,
            headers: {'x-elevage-lab': correct ? 'b' * 32 : 'd' * 32},
          );
        }),
        configuration: config,
        labGate: gate,
      );
      for (final url in [
        'https://192.168.1.101:8443/api/x',
        'https://192.168.1.100:8444/api/x',
        EnvironmentConfig.pilotApi,
        EnvironmentConfig.productionApi,
      ]) {
        await expectLater(
          client.get(Uri.parse(url)),
          throwsA(isA<NetworkDestinationException>()),
        );
      }
      expect(sends, 0);
      await expectLater(
        client.get(Uri.parse('${config.apiUrl}/x')),
        throwsA(isA<NetworkDestinationException>()),
      );
      correct = true;
      redirect = true;
      await expectLater(
        client.get(Uri.parse('${config.apiUrl}/x')),
        throwsA(isA<NetworkDestinationException>()),
      );
      redirect = false;
      expect(
        (await client.get(Uri.parse('${config.apiUrl}/x'))).statusCode,
        200,
      );
      gate.stop();
      await expectLater(
        client.get(Uri.parse('${config.apiUrl}/x')),
        throwsA(isA<NetworkDestinationException>()),
      );
      client.close();
      gate.dispose();
    },
  );
}
