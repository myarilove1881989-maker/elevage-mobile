import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'offline_grant.dart';

abstract interface class OperatorSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class AndroidOperatorSecretStore implements OperatorSecretStore {
  const AndroidOperatorSecretStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) {
    _requireAndroid();
    return _storage.read(key: key);
  }
  @override
  Future<void> write(String key, String value) {
    _requireAndroid();
    return _storage.write(key: key, value: value);
  }
  void _requireAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Les secrets hors ligne exigent Android Keystore.');
    }
  }
}

class LocalOperatorSession {
  const LocalOperatorSession({required this.grant, required this.openedAt});
  final VerifiedOfflineGrant grant;
  final DateTime openedAt;
  int get userId => grant.userId;
}

/// Shared business DB; personal secrets and local lock never replace an HTTP JWT.
class LocalOperatorSessions {
  LocalOperatorSessions({required this.store, required this.namespace,
    required this.farmId, required this.deviceId, required this.generation,
    DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final OperatorSecretStore store;
  final String namespace;
  final int farmId,deviceId,generation;
  final DateTime Function() clock;
  LocalOperatorSession? _session;
  LocalOperatorSession? get session {
    final now=clock().toUtc();
    if(_session!=null && (now.isBefore(_session!.openedAt) || !now.isBefore(_session!.grant.expiresAt))) {
      lock();
    }
    return _session;
  }
  int _lockEpoch=0;
  bool _busy = false;
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);

  String _key(VerifiedOfflineGrant grant) =>
      'operator_pin_${namespace}_${grant.farmId}_${grant.deviceId}_${grant.userId}';

  void lock() { _session = null; _lockEpoch++; }

  Future<void> enroll(VerifiedOfflineGrant grant, String pin) async {
    if (_busy) throw StateError('Une opération de sécurité est déjà en cours.');
    _busy = true;
    lock();
    try {
      _validateGrant(grant);
      _validatePin(pin);
      if (await store.read(_key(grant)) != null) {
        throw StateError('Un PIN existe déjà : utiliser le changement de PIN.');
      }
      await _savePin(grant, pin);
    } finally { _busy = false; }
  }

  Future<void> _savePin(VerifiedOfflineGrant grant, String pin) async {
    final random = Random.secure();
    final salt = List.generate(32, (_) => random.nextInt(256));
    final verifier = await _derive(pin, salt);
    await store.write(_key(grant), jsonEncode({
      'salt': base64.encode(salt), 'verifier': base64.encode(verifier),
      'failures': 0, 'blocked_until': 0,
      'clock_floor': clock().toUtc().millisecondsSinceEpoch,
    }));
  }

  Future<bool> unlock(VerifiedOfflineGrant grant, String pin) async {
    if (_busy) throw StateError('Une opération de sécurité est déjà en cours.');
    _busy = true;
    lock();
    try { return await _unlock(grant, pin); }
    finally { _busy = false; }
  }

  Future<bool> _unlock(VerifiedOfflineGrant grant, String pin) async {
    final epoch=_lockEpoch;
    _validateGrant(grant);
    _validatePin(pin);
    final encoded = await store.read(_key(grant));
    if (encoded == null) return false;
    final record = jsonDecode(encoded) as Map<String, dynamic>;
    final now = clock().toUtc().millisecondsSinceEpoch;
    if (now < (record['clock_floor'] as int) || now < (record['blocked_until'] as int)) return false;
    final actual = await _derive(pin, base64.decode(record['salt'] as String));
    final expected = base64.decode(record['verifier'] as String);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < min(actual.length, expected.length); i++) {
      difference |= actual[i] ^ expected[i];
    }
    record['clock_floor'] = now;
    if (difference != 0) {
      final failures = (record['failures'] as int) + 1;
      record['failures'] = failures;
      if (failures >= 5) record['blocked_until'] = now + min(3600000, 30000 * (1 << min(failures - 5, 7)));
      await store.write(_key(grant), jsonEncode(record));
      return false;
    }
    record['failures'] = 0;
    record['blocked_until'] = 0;
    await store.write(_key(grant), jsonEncode(record));
    _validateGrant(grant);
    if(epoch!=_lockEpoch || clock().toUtc().millisecondsSinceEpoch<now) return false;
    _session = LocalOperatorSession(grant: grant, openedAt: clock().toUtc());
    return true;
  }

  Future<bool> changePin(VerifiedOfflineGrant grant, String oldPin, String newPin) async {
    if (_busy) throw StateError('Une opération de sécurité est déjà en cours.');
    _busy = true;
    lock();
    try {
      _validatePin(newPin);
      if (!await _unlock(grant, oldPin)) return false;
      lock();
      await _savePin(grant, newPin);
      return true;
    } finally { lock(); _busy = false; }
  }

  Future<List<int>> _derive(String pin, List<int> salt) async =>
      (await _kdf.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt)).extractBytes();

  void _validateGrant(VerifiedOfflineGrant grant) {
    if(grant.farmId!=farmId || grant.deviceId!=deviceId || grant.generation!=generation) {
      throw StateError('Ce profil ne correspond pas à cette tablette et exploitation.');
    }
    if (!clock().toUtc().isBefore(grant.expiresAt) ||
        clock().toUtc().millisecondsSinceEpoch < (grant.claims['iat'] as int) * 1000) {
      throw StateError('Autorisation expirée : connexion requise.');
    }
  }
  void _validatePin(String pin) {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) throw ArgumentError('Le PIN doit contenir 6 à 12 chiffres.');
  }
}
