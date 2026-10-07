import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Only a verified server signature can create this local authorization.
class VerifiedOfflineGrant {
  VerifiedOfflineGrant._(this.claims, this.token);
  final Map<String, dynamic> claims;
  final String token;
  int get userId => int.parse(claims['sub'] as String);
  int get farmId => claims['exploitation_id'] as int;
  int get deviceId => claims['device_id'] as int;
  int get rightsVersion => claims['rights_version'] as int;
  int get generation => claims['write_generation'] as int;
  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch((claims['exp'] as int) * 1000, isUtc: true);

  bool permits(String capability, DateTime now) => now.toUtc().isBefore(expiresAt) &&
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
      final nowSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
      if ((payload['iat'] as int) > nowSeconds || (payload['exp'] as int) <= nowSeconds ||
          (payload['iat'] as int) >= (payload['exp'] as int)) {
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
      payload['capabilities'] = Map<String, dynamic>.unmodifiable(payload['capabilities'] as Map<String, dynamic>);
      return VerifiedOfflineGrant._(Map<String, dynamic>.unmodifiable(payload), token);
    } catch (_) {
      throw StateError('Autorisation hors ligne invalide ou expirée.');
    }
  }
}
