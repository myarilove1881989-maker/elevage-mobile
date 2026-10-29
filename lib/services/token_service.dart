import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'secure_storage_policy.dart';

abstract interface class TokenStore {
  Future<void> saveToken(String token);
  Future<String?> getToken();
  Future<void> clearToken();
}

/// Android utilise un stockage chiffré protégé par Android Keystore.
/// Le Web conserve son stockage SharedPreferences existant.
class TokenService implements TokenStore {
  TokenService({bool? useSecureStorage, FlutterSecureStorage? secureStorage})
    : _secure =
          useSecureStorage ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
      _storage = secureStorage ?? protectedSecureStorage;

  final bool _secure;
  final FlutterSecureStorage _storage;
  String get _key => Config.current.tokenKey;

  @override
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (_secure) {
      await _storage.write(key: _key, value: token);
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, token);
    }
    if (!(Config.isPilot || Config.current.isLab)) {
      await prefs.remove('auth_token');
    }
  }

  @override
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_secure) return prefs.getString(_key);
    final saved = await _storage.read(key: _key);
    if (saved != null && saved.isNotEmpty) {
      await prefs.remove(_key);
      if (!(Config.isPilot || Config.current.isLab)) {
        await prefs.remove('auth_token');
      }
      return saved;
    }
    if (Config.isPilot || Config.current.isLab) return null;
    final legacy = prefs.getString(_key) ?? prefs.getString('auth_token');
    if (legacy == null || legacy.isEmpty) return null;
    // Ne supprimer l'ancien jeton qu'après l'écriture chiffrée réussie.
    await saveToken(legacy);
    return legacy;
  }

  @override
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    if (!(Config.isPilot || Config.current.isLab)) {
      await prefs.remove('auth_token');
    }
    if (_secure) await _storage.delete(key: _key);
  }
}
