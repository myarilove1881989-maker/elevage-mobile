import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/lab_network_gate.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/sync_coordinator.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;

const lab = EnvironmentConfig(environment: 'lab', flavor: 'lab',
  apiOverride: 'https://lab.example.test/api', labHost: 'lab.example.test');
final now = DateTime.utc(2026, 10, 17, 12);
final reference = 'a' * 64;
LabIsolationApproval approval({String? endpoint, DateTime? reviewed, DateTime? expiry}) =>
  LabIsolationApproval(endpoint: endpoint ?? lab.apiUrl, reference: reference,
    laboratoryId: 'cba00010753e44f899db6f2d5f8fe9fb', certificateSha256: 'b' * 64,
    reviewedAt: reviewed ?? now, expiresAt: expiry ?? now.add(const Duration(hours: 1)));

class TrackingSync extends Fake implements SyncCoordinator {
  bool running = false;
  @override
  void setForeground(bool value) { running = value; }
  @override
  void removeListener(void Function() listener) {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a nonempty label alone never authorizes networking', () async {
    final gate = LabNetworkGate();
    expect(() => gate.permitVerifiedIsolation(lab, evidenceReference: reference), throwsStateError);
    expect(await gate.initializeFromBuild(lab), isFalse);
    expect(gate.enabled, isFalse);
    gate.dispose();
  });

  test('reviewed JSON is digest-bound and malformed contracts fail closed', () async {
    final payload = utf8.encode(jsonEncode({'version': 1, 'endpoint': lab.apiUrl,
      'laboratory_id': 'cba00010753e44f899db6f2d5f8fe9fb', 'certificate_sha256': 'b' * 64,
      'reviewed_at': now.toIso8601String(), 'expires_at': now.add(const Duration(hours: 1)).toIso8601String()}));
    final digest = (await Sha256().hash(payload)).bytes.map((b) => b.toRadixString(16).padLeft(2,'0')).join();
    final parsed = await LabIsolationApproval.fromReviewedJson(base64Encode(payload), digest);
    expect(parsed.validFor(lab, now), isTrue);
    expect(parsed.validFor(const EnvironmentConfig(), now), isFalse);
    await expectLater(LabIsolationApproval.fromReviewedJson(base64Encode(payload), '0' * 64), throwsStateError);
    await expectLater(LabIsolationApproval.fromReviewedJson('!', digest), throwsFormatException);
    await expectLater(LabIsolationApproval.fromReviewedJson('', ''), throwsStateError);
  });

  test('expired future oversized lifetime wrong endpoint and reference stay closed', () {
    for (final value in [approval(expiry: now), approval(reviewed: now.add(const Duration(minutes: 1))),
      approval(expiry: now.add(const Duration(hours: 9))), approval(endpoint: 'https://other.example.test/api')]) {
      final gate = LabNetworkGate(approval: value, clock: () => now);
      expect(() => gate.permitVerifiedIsolation(lab, evidenceReference: reference), throwsStateError);
      expect(gate.enabled, isFalse); gate.dispose();
    }
    final gate = LabNetworkGate(approval: approval(), clock: () => now);
    expect(() => gate.permitVerifiedIsolation(lab, evidenceReference: 'wrong'), throwsStateError);
    expect(gate.enabled, isFalse); gate.dispose();
  });

  testWidgets('lab automatic sync follows approval and expiry; PIN cannot reopen it', (tester) async {
    var clock = now;
    final gate = LabNetworkGate(approval: approval(), clock: () => clock);
    final secrets = TestSecretStore();
    final api = FoundationApi(baseUrl: lab.apiUrl, deviceIdentity: TestIdentity(), secrets: secrets);
    final controller = TabletController(api: api, secrets: secrets, configuration: lab, labGate: gate);
    final sync = TrackingSync(); controller.sync = sync;
    expect(controller.automaticSyncEnabled, isFalse);
    gate.permitVerifiedIsolation(lab, evidenceReference: reference);
    expect(controller.automaticSyncEnabled, isTrue); expect(sync.running, isTrue);
    controller.lock(); expect(gate.enabled, isTrue);
    clock = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(hours: 1));
    expect(controller.automaticSyncEnabled, isFalse); expect(sync.running, isFalse);
    expect(() => gate.permitVerifiedIsolation(lab, evidenceReference: reference), throwsStateError);
    controller.dispose(); api.close(); gate.dispose();
  });

  test('a lab approval does not alter production sync options', () {
    final gate = LabNetworkGate(approval: approval(), clock: () => now);
    gate.permitVerifiedIsolation(lab, evidenceReference: reference);
    final secrets = TestSecretStore();
    final api = FoundationApi(baseUrl: EnvironmentConfig.productionApi, deviceIdentity: TestIdentity(), secrets: secrets);
    final controller = TabletController(api: api, secrets: secrets, automaticSyncEnabled: false,
      configuration: const EnvironmentConfig(), labGate: gate);
    expect(controller.automaticSyncEnabled, isFalse);
    expect(gate.isApprovedFor(const EnvironmentConfig()), isFalse);
    controller.dispose(); api.close(); gate.dispose();
  });
}
