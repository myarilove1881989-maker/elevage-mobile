import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      _storage = secureStorage ?? const FlutterSecureStorage();

  final bool _secure;
  final FlutterSecureStorage _storage;
  static const _key = 'token';

  @override
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (_secure) {
      await _storage.write(key: _key, value: token);
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, token);
    }
    await prefs.remove('auth_token');
  }

  @override
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_secure) return prefs.getString(_key);
    final saved = await _storage.read(key: _key);
    if (saved != null && saved.isNotEmpty) {
      await prefs.remove(_key);
      await prefs.remove('auth_token');
      return saved;
    }
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
    await prefs.remove('auth_token');
    if (_secure) await _storage.delete(key: _key);
  }
}
