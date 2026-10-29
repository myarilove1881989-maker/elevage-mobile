import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../services/permission_contract.dart';
import 'package:cryptography/cryptography.dart';

/// Only a verified server signature can create this local authorization.
class VerifiedOfflineGrant {
  VerifiedOfflineGrant._(this.claims, this.token);
  final Map<String, dynamic> claims;
  final String token;
  // Reviewed exception for Android LAB debug only; all other variants stay strict.
  static int get _iatToleranceMilliseconds =>
      !kIsWeb && !kReleaseMode && defaultTargetPlatform == TargetPlatform.android &&
      Config.current.environment == 'lab' && Config.current.flavor == 'lab' ? 5000 : 0;
  int get userId => int.parse(claims['sub'] as String);
  int get farmId => claims['exploitation_id'] as int;
  int get deviceId => claims['device_id'] as int;
  int get rightsVersion => claims['rights_version'] as int;
  int? get credentialVersion => claims['credential_version'] is int && (claims['credential_version'] as int)>0
    ? claims['credential_version'] as int : null;
  int get generation => claims['write_generation'] as int;
  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000, isUtc: true);

  bool get hasFineContract => (claims['capabilities'] as Map).containsKey('permission_contract');

  /// These codes are covered by the existing EdDSA signature, not HTTP visibility.
  PermissionContract? get finePermissions {
    if (!hasFineContract) return null;
    final raw = (claims['capabilities'] as Map)['permission_contract'];
    if (raw is! Map<String,dynamic> ||
        ['version','grant_version','user','membership_id','exploitation','device_id',
          'write_generation','rights_version','iat','exp'].any((key) => raw[key] is! int) || raw['version'] != 2 || raw['grant_version'] != 1 ||
        raw['grant_id'] != claims['jti'] || raw['membership_id'] != claims['membership_id'] ||
        raw['device_id'] != deviceId || raw['write_generation'] != generation ||
        raw['iat'] != claims['iat'] || raw['exp'] != claims['exp'] || raw['role'] != 'OPERATEUR' ||
        (raw['exp'] as int) - (raw['iat'] as int) > 7 * 86400) {
      throw StateError('Contrat signé hors contexte ou incompatible.');
    }
    return PermissionContract.decode({...raw,'version':1},userId:userId,farmId:farmId,
      role:'OPERATEUR',rightsVersion:rightsVersion);
  }

  bool permitsOperation(String kind, String operation, DateTime now) {
    if (!permits('can_create_terrain_operation',now)) return false;
    // V1 originals remain transportable; new writes need signed individual rights.
    if (!hasFineContract) return false;
    try {
      final action = PermissionContract.operationAction(kind,operation);
      return action != null && finePermissions!.allows(action);
    } catch (_) { return false; }
  }

  static bool _validDates(int issuedAt, int expiresAt, DateTime now) {
    final milliseconds = now.toUtc().millisecondsSinceEpoch;
    return issuedAt < expiresAt &&
        issuedAt * 1000 <= milliseconds + _iatToleranceMilliseconds &&
        milliseconds < expiresAt * 1000;
  }

  bool validAt(DateTime now) => _validDates(claims['iat'] as int, claims['exp'] as int, now);

  bool permits(String capability, DateTime now) =>
      validAt(now) &&
      (claims['capabilities'] as Map<String, dynamic>)[capability] == true;

  /// publicKey is provisioned through authenticated HTTPS, never taken from JWT.
  static Future<VerifiedOfflineGrant> verify({required String token, required String publicKeyPem,
    required String trustedKeyId, required int farmId, required int userId,
    required int deviceId, required int generation, required int rightsVersion,
    required DateTime now}) async {
    if (token.length > 16384) throw StateError('Autorisation invalide.');
    try {
      final parts = token.split('.');
      if (parts.length != 3) throw const FormatException();
      final header = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0])))) as Map<String, dynamic>;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      if (header['alg'] != 'EdDSA' || header['kid'] != trustedKeyId ||
          payload['iss'] != 'elevage-offline' || payload['aud'] != 'elevage-device' ||
          payload['typ'] != 'offline-authorization' || payload['sub'] != '$userId' ||
          payload['exploitation_id'] != farmId || payload['device_id'] != deviceId ||
          payload['write_generation'] != generation || payload['rights_version'] != rightsVersion ||
          payload['capabilities'] is! Map<String, dynamic> || payload['membership_id'] is! int ||
          payload['jti'] is! String || payload['iat'] is! int || payload['exp'] is! int) {
        throw const FormatException();
      }
      if (!_validDates(payload['iat'] as int, payload['exp'] as int, now)) {
        throw const FormatException();
      }
      final der = base64.decode(publicKeyPem.replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '').replaceAll(RegExp(r'\s'), ''));
      const prefix = [0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00];
      if (der.length != 44) throw const FormatException();
      for (var i = 0; i < prefix.length; i++) {
        if (der[i] != prefix[i]) throw const FormatException();
      }
      final signature = Signature(base64Url.decode(base64Url.normalize(parts[2])),
          publicKey: SimplePublicKey(der.sublist(12), type: KeyPairType.ed25519));
      if (!await Ed25519().verify(utf8.encode('${parts[0]}.${parts[1]}'), signature: signature)) {
        throw const FormatException();
      }
      dynamic immutable(dynamic value) {
        if (value is Map<String,dynamic>) { return Map<String,dynamic>.unmodifiable(
          value.map((key,child) => MapEntry(key,immutable(child)))); }
        if (value is List) { return List<dynamic>.unmodifiable(value.map(immutable)); }
        return value;
      }
      if(payload.containsKey('credential_version') && (payload['credential_version'] is! int || (payload['credential_version'] as int)<1)) throw const FormatException();
      final verified = VerifiedOfflineGrant._(immutable(payload) as Map<String,dynamic>, token);
      verified.finePermissions; // A present unknown/invalid contract never becomes V1.
      return verified;
    } catch (_) {
      throw StateError('Autorisation hors ligne invalide ou expirée.');
    }
  }
}
