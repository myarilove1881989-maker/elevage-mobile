import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class DeviceIdentity {
  Future<Map<String, dynamic>> publicIdentity();
  Future<String> sign(Uint8List message);
}

class AndroidDeviceIdentity implements DeviceIdentity {
  static const _channel = MethodChannel('elevage/device_identity');
  void _requireAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Identité de tablette disponible sur Android.');
    }
  }

  @override
  Future<Map<String, dynamic>> publicIdentity() async {
    _requireAndroid();
    final identity = await _channel.invokeMapMethod<String, dynamic>('identity');
    if (identity == null || identity['private_key_exportable'] != false ||
        identity['algorithm'] != 'P256-SHA256-DER') {
      throw StateError('Identité de tablette non sécurisée.');
    }
    return identity;
  }

  @override
  Future<String> sign(Uint8List message) async {
    _requireAndroid();
    final signature = await _channel.invokeMethod<String>('sign', {'message': message});
    if (signature == null) throw StateError('Signature indisponible.');
    return signature;
  }
}

/// Exact server contract: hash the bytes actually sent, including GET empty body.
Future<Map<String, String>> deviceProofHeaders({
  required DeviceIdentity identity,
  required String challengeId,
  required int deviceId,
  required int userId,
  required String purpose,
  required String method,
  required String pathAndQuery,
  required Uint8List body,
}) async {
  if (!{'WRITE', 'ACTIVATE', 'REPLACE', 'GRANT'}.contains(purpose) ||
      deviceId < 1 || userId < 1 || !pathAndQuery.startsWith('/')) {
    throw ArgumentError('Contexte de signature invalide.');
  }
  for (final field in [challengeId, purpose, method, pathAndQuery]) {
    if (field.contains('\n') || field.contains('\r')) {
      throw ArgumentError('Contexte de signature invalide.');
    }
  }
  final digest = await Sha256().hash(body);
  final hex = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final message = 'ELEVAGE-DEVICE-V1\n$challengeId\n$deviceId\n$userId\n'
      '$purpose\n$method\n$pathAndQuery\n$hex';
  return {
    'X-Elevage-Device': '$deviceId',
    'X-Elevage-Challenge': challengeId,
    'X-Elevage-Signature': await identity.sign(Uint8List.fromList(utf8.encode(message))),
  };
}
