import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../config.dart';
import 'lab_server_probe.dart';

/// External review of DNS, TLS and the synthetic database must precede a build.
/// The reviewed JSON and its digest are compiled together, never user supplied.
class LabIsolationApproval {
  const LabIsolationApproval({required this.endpoint, required this.reference,
    required this.laboratoryId, required this.certificateSha256,
    required this.reviewedAt, required this.expiresAt});
  final String endpoint, reference, laboratoryId, certificateSha256;
  final DateTime reviewedAt, expiresAt;

  bool validFor(EnvironmentConfig config, DateTime now) {
    if (!config.isLab) return false;
    final hex = RegExp(r'^[0-9a-f]{64}$');
    return endpoint == config.laboratoryEndpoint.toString() &&
      hex.hasMatch(reference) && hex.hasMatch(certificateSha256) &&
      RegExp(r'^[0-9a-f]{32}$').hasMatch(laboratoryId) &&
      reviewedAt.isUtc && expiresAt.isUtc && !now.isBefore(reviewedAt) &&
      now.isBefore(expiresAt) && expiresAt.isAfter(reviewedAt) &&
      expiresAt.difference(reviewedAt) <= const Duration(hours: 8);
  }

  static Future<LabIsolationApproval> fromReviewedJson(
    String encoded, String expectedDigest) async {
    if (encoded.length > 8192 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedDigest)) {
      throw StateError('Preuve de laboratoire absente ou invalide.');
    }
    final bytes = base64Decode(encoded);
    final digest = await Sha256().hash(bytes);
    if (digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join() != expectedDigest) {
      throw StateError('Preuve de laboratoire altérée.');
    }
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    const fields = {'version', 'endpoint', 'laboratory_id', 'certificate_sha256', 'reviewed_at', 'expires_at'};
    if (json['version'] != 1 || json.length != fields.length || !fields.containsAll(json.keys)) {
      throw StateError('Contrat de preuve inconnu.');
    }
    return LabIsolationApproval(endpoint: json['endpoint'] as String, reference: expectedDigest,
      laboratoryId: json['laboratory_id'] as String, certificateSha256: json['certificate_sha256'] as String,
      reviewedAt: DateTime.parse(json['reviewed_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String));
  }
}

/// PIN state never authorizes networking. Stop/expiry requires an app restart.
class LabNetworkGate extends ChangeNotifier {
  LabNetworkGate({LabIsolationApproval? approval, DateTime Function()? clock,
    Future<bool> Function(EnvironmentConfig, String)? serverProbe})
    : _approval = approval, _clock = clock ?? DateTime.now, _probe = serverProbe ?? probeLabServer;
  static final instance = LabNetworkGate();
  LabIsolationApproval? _approval;
  final DateTime Function() _clock;
  final Future<bool> Function(EnvironmentConfig, String) _probe;
  Timer? _expiry;
  Timer? _admission;
  int _admissionEpoch = 0;
  bool _everAuthorized = false;
  String? _endpoint;
  final Set<VoidCallback> _closers = {};
  final List<String> _journal = [];
  bool get enabled => _endpoint != null && _approval != null &&
    !_clock().isBefore(_approval!.reviewedAt) && _clock().isBefore(_approval!.expiresAt);
  bool isApprovedFor(EnvironmentConfig config) => enabled &&
    _approval!.validFor(config, _clock().toUtc()) && _endpoint == config.laboratoryEndpoint.toString();
  List<String> get destinationJournal => List.unmodifiable(_journal);
  String? get laboratoryId => _approval?.laboratoryId;
  Stream<bool?> serverAvailability(EnvironmentConfig config) async* {
    while (isApprovedFor(config)) {
      yield await _probe(config, _approval!.laboratoryId);
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  void permitVerifiedIsolation(
    EnvironmentConfig config, {
    required String evidenceReference,
  }) {
    final endpoint = config.laboratoryEndpoint.toString();
    if (_approval == null || !_approval!.validFor(config, _clock().toUtc()) ||
        evidenceReference != _approval!.reference || _everAuthorized) {
      throw StateError(
        'Preuve externe explicite requise ; arrêter avant réautorisation.',
      );
    }
    _endpoint = endpoint;
    _everAuthorized = true;
    _expiry = Timer(_approval!.expiresAt.difference(_clock().toUtc()), stop);
    notifyListeners();
  }

  Future<bool> initializeFromBuild(EnvironmentConfig config) async {
    if (!config.isLab) return false;
    const encoded = String.fromEnvironment('LAB_ISOLATION_JSON');
    const digest = String.fromEnvironment('LAB_ISOLATION_SHA256');
    if (encoded.isEmpty || digest.isEmpty || _everAuthorized) return false;
    try {
      _approval = await LabIsolationApproval.fromReviewedJson(encoded, digest);
      if (!_approval!.validFor(config, _clock().toUtc())) throw StateError('Autorisation expirée.');
      final epoch = ++_admissionEpoch;
      Future<bool> admit() async {
        if (epoch != _admissionEpoch || !_approval!.validFor(config, _clock().toUtc())) return false;
        final verified = await _probe(config, _approval!.laboratoryId);
        if (!verified || epoch != _admissionEpoch || !_approval!.validFor(config, _clock().toUtc())) return false;
        _admission?.cancel(); _admission = null;
        permitVerifiedIsolation(config, evidenceReference: digest);
        return true;
      }
      if (!await admit()) {
        if (epoch != _admissionEpoch) return false;
        var busy = false;
        _admission = Timer.periodic(const Duration(seconds: 3), (_) async {
          if (busy || epoch != _admissionEpoch) return;
          if (!_approval!.validFor(config, _clock().toUtc())) { stop(); return; }
          busy = true;
          try { await admit(); } finally { busy = false; }
        });
        return false;
      }
      return true;
    } catch (_) {
      _approval = null;
      stop();
      return false;
    }
  }

  void stop() {
    _everAuthorized = true;
    _admissionEpoch++; _admission?.cancel(); _admission = null;
    _expiry?.cancel(); _expiry = null;
    _endpoint = null;
    for (final close in _closers.toList()) {
      close();
    }
    notifyListeners();
  }

  void attach(VoidCallback close) => _closers.add(close);
  void detach(VoidCallback close) => _closers.remove(close);

  bool permits(EnvironmentConfig config, Uri target) =>
      isApprovedFor(config) &&
      target.scheme == 'https' &&
      target.host == config.labHost &&
      target.port == config.laboratoryEndpoint.port &&
      target.userInfo.isEmpty &&
      !target.hasFragment &&
      (target.path == '/api' || target.path.startsWith('/api/')) &&
      !target.path.contains('%') &&
      !target.path.contains('\\') &&
      !target.pathSegments.any((p) => p == '.' || p == '..');

  void record(Uri target, {required bool allowed}) {
    // Never log paths, query, credentials, payloads or operator identifiers.
    _journal.add(
      '${allowed ? "allow" : "deny"} ${target.scheme}://${target.host}:${target.port}',
    );
    if (_journal.length > 100) _journal.removeAt(0);
  }

  @override
  void dispose() {
    _endpoint = null;
    _admissionEpoch++; _admission?.cancel();
    _expiry?.cancel();
    for (final close in _closers.toList()) { close(); }
    _closers.clear();
    super.dispose();
  }
}
