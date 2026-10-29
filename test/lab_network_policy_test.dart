import 'dart:async';
import 'dart:io';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:app_elevage/services/lab_network_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const lab = EnvironmentConfig(
  environment: 'lab',
  flavor: 'lab',
  apiOverride: 'https://lab.example.test/api',
  labHost: 'lab.example.test',
);

class ClosableMock extends MockClient {
  ClosableMock(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

final reviewedAt = DateTime.utc(2026, 10, 17, 12);
final evidence = 'a' * 64;
LabIsolationApproval approval({String? endpoint, DateTime? expiry}) => LabIsolationApproval(
  endpoint: endpoint ?? lab.apiUrl, reference: evidence,
  laboratoryId: 'cba00010753e44f899db6f2d5f8fe9fb', certificateSha256: 'b' * 64,
  reviewedAt: reviewedAt, expiresAt: expiry ?? reviewedAt.add(const Duration(hours: 1)));
LabNetworkGate reviewedGate() {
  final gate = LabNetworkGate(approval: approval(), clock: () => reviewedAt);
  addTearDown(gate.dispose);
  return gate;
}

void main() {
  test('dedicated config has separate credentials and no external exports', () {
    expect(lab.apiUrl, 'https://lab.example.test/api');
    expect(lab.tokenKey, startsWith('lab_token_'));
    expect(lab.externalLinksAllowed, isFalse);
    lab.validate(release: false);
    expect(() => lab.validate(release: true), throwsStateError);
    expect(() => lab.validate(web: true, release: false), throwsStateError);
  });
  for (final config in [
    const EnvironmentConfig(environment: 'lab', flavor: 'lab'),
    const EnvironmentConfig(environment: 'lab'),
    const EnvironmentConfig(flavor: 'lab'),
    const EnvironmentConfig(
      environment: 'lab',
      flavor: 'production',
      apiOverride: 'https://lab.example.test/api',
      labHost: 'lab.example.test',
    ),
    for (final url in [
      EnvironmentConfig.productionApi,
      EnvironmentConfig.pilotApi,
      'https://unreviewed.onrender.com/api',
      'http://lab.example.test/api',
      'https://lab.example.test:444/api',
      'https://lab.example.test/api?secret=x',
      'https://lab.example.test/api#fragment',
      'https://user:password@lab.example.test/api',
      'https://other.example.test/api',
      'https://lab.example.test/api/',
      'https://lab.example.test/not-api',
    ])
      EnvironmentConfig(
        environment: 'lab',
        flavor: 'lab',
        apiOverride: url,
        labHost: Uri.parse(url).host.endsWith('.onrender.com')
            ? Uri.parse(url).host
            : 'lab.example.test',
      ),
  ]) {
    test(
      'invalid lab config refuses ${config.apiOverride} ${config.flavor}',
      () {
        expect(() => config.apiUrl, throwsStateError);
      },
    );
  }
  test(
    'default stop denies before inner transport and needs evidence',
    () async {
      final gate = LabNetworkGate();
      var sent = 0;
      final client = GuardedApiClient(
        MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        }),
        configuration: lab,
        labGate: gate,
      );
      await expectLater(
        client.get(Uri.parse('${lab.apiUrl}/lots/')),
        throwsA(isA<NetworkDestinationException>()),
      );
      expect(sent, 0);
      expect(
        () => gate.permitVerifiedIsolation(lab, evidenceReference: ''),
        throwsStateError,
      );
      expect(gate.enabled, isFalse);
      client.close();
    },
  );
  for (final url in [
    EnvironmentConfig.productionApi,
    EnvironmentConfig.pilotApi,
    'https://other.example.test/api',
    'http://lab.example.test/api',
    'https://lab.example.test:444/api',
    'https://lab.example.test/api-evil/',
    'https://lab.example.test/api/%2e%2e/secret',
    'https://user:password@lab.example.test/api',
    'https://lab.example.test/api#fragment',
  ]) {
    test('armed lab rejects destination $url before transport', () async {
      var sent = 0;
      final gate = reviewedGate()
        ..permitVerifiedIsolation(lab, evidenceReference: evidence);
      final client = GuardedApiClient(
        MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        }),
        configuration: lab,
        labGate: gate,
      );
      await expectLater(
        client.get(Uri.parse(url)),
        throwsA(isA<NetworkDestinationException>()),
      );
      expect(sent, 0);
      client.close();
    });
  }
  for (final location in [
    EnvironmentConfig.productionApi,
    '${lab.apiUrl}/other/',
  ]) {
    test('all redirect responses refused $location', () async {
      var sent = 0;
      final gate = reviewedGate()
        ..permitVerifiedIsolation(lab, evidenceReference: evidence);
      final client = GuardedApiClient(
        MockClient((r) async {
          sent++;
          expect(r.followRedirects, isFalse);
          expect(r.maxRedirects, 0);
          return http.Response('', 307, headers: {'location': location});
        }),
        configuration: lab,
        labGate: gate,
      );
      await expectLater(
        client.get(Uri.parse('${lab.apiUrl}/lots/')),
        throwsA(isA<NetworkDestinationException>()),
      );
      expect(sent, 1);
      client.close();
    });
  }
  test(
    'allowed endpoint sends once with no sensitive destination journal',
    () async {
      final gate = reviewedGate()
        ..permitVerifiedIsolation(lab, evidenceReference: evidence);
      final client = GuardedApiClient(
        MockClient((_) async => http.Response('{}', 200)),
        configuration: lab,
        labGate: gate,
      );
      await client.get(
        Uri.parse('${lab.apiUrl}/operator/42/?pin=123456&token=synthetic'),
      );
      expect(gate.destinationJournal, ['allow https://lab.example.test:443']);
      expect(gate.destinationJournal.join(), isNot(contains('123456')));
      client.close();
    },
  );
  test(
    'stop closes every attached transport and late response is rejected',
    () async {
      final response = Completer<http.Response>();
      final gate = reviewedGate()
        ..permitVerifiedIsolation(lab, evidenceReference: evidence);
      final inner = ClosableMock((_) => response.future);
      final client = GuardedApiClient(inner, configuration: lab, labGate: gate);
      final other = ClosableMock((_) async => http.Response('{}', 200));
      final second = GuardedApiClient(other, configuration: lab, labGate: gate);
      final pending = client.get(Uri.parse('${lab.apiUrl}/lots/'));
      final assertion = expectLater(
        pending,
        throwsA(isA<NetworkDestinationException>()),
      );
      await Future<void>.delayed(Duration.zero);
      gate.stop();
      expect(inner.closed, isTrue);
      expect(other.closed, isTrue);
      expect(gate.enabled, isFalse);
      response.complete(http.Response('{}', 200));
      await assertion;
      await expectLater(
        second.get(Uri.parse('${lab.apiUrl}/lots/')),
        throwsA(isA<NetworkDestinationException>()),
      );
      client.close();
      second.close();
    },
  );
  test(
    'stopped lab cannot be enabled by another config or PIN semantics',
    () async {
      final gate = reviewedGate();
      expect(
        () => gate.permitVerifiedIsolation(
          const EnvironmentConfig(),
          evidenceReference: evidence,
        ),
        throwsStateError,
      );
      expect(gate.enabled, isFalse);
      gate.permitVerifiedIsolation(lab, evidenceReference: evidence);
      expect(
        () => gate.permitVerifiedIsolation(lab, evidenceReference: evidence),
        throwsStateError,
      );
      gate.stop();
      expect(gate.enabled, isFalse);
    },
  );
  test(
    'lab flavor has unique id, label, all-domain exclusions and no release signing',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationIdSuffix = ".lab"'));
      expect(gradle, contains('if (labRequested) null else System.getenv(it)'));
      expect(
        File('android/app/src/lab/res/values/strings.xml').readAsStringSync(),
        contains('LABORATOIRE'),
      );
      for (final file in [
        'lab_backup_rules.xml',
        'lab_data_extraction_rules.xml',
      ]) {
        final text = File(
          'android/app/src/lab/res/xml/$file',
        ).readAsStringSync();
        for (final domain in [
          'root',
          'file',
          'database',
          'sharedpref',
          'external',
          'device_root',
          'device_file',
          'device_database',
          'device_sharedpref',
        ]) {
          expect(text, contains('domain="$domain" path="."'));
        }
        if (file.contains('extraction')) {
          expect(text, contains('<cloud-backup>'));
          expect(text, contains('<device-transfer>'));
        }
      }
    },
  );
}
