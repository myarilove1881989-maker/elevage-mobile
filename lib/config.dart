import 'package:flutter/foundation.dart';

class Config {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://backend-elevage.onrender.com/api',
  );

  static String validatedApiUrl(String value, {bool release = kReleaseMode}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('Adresse API invalide.');
    }
    if (release &&
        (uri.scheme != 'https' ||
            uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2' ||
            uri.host == '::1')) {
      throw StateError('Le build release exige une API HTTPS publique.');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}
