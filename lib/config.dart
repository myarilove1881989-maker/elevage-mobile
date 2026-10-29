import 'package:flutter/foundation.dart';

/// Reviewed allowlist. Confirm ownership and DB isolation before the first APK.
class EnvironmentConfig {
  const EnvironmentConfig({
    this.environment = 'production',
    this.apiOverride = '',
    this.flavor = '',
    this.labHost = '',
    this.labTransport = '',
  });
  static const productionApi = 'https://backend-elevage.onrender.com/api';
  static const pilotApi = 'https://backend-elevage-pilot.onrender.com/api';
  final String environment, apiOverride, flavor, labHost, labTransport;
  bool get isWifiLab => isLab && labTransport == 'wifi';
  static bool privateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((n) => n == null || n < 0 || n > 255)) return false;
    if (List.generate(4, (i) => numbers[i].toString()).join('.') != host)
      return false;
    return numbers[0] == 10 ||
        (numbers[0] == 172 && numbers[1]! >= 16 && numbers[1]! <= 31) ||
        (numbers[0] == 192 && numbers[1] == 168);
  }

  bool get isLab => environment == 'lab' || flavor == 'lab';
  Uri get laboratoryEndpoint {
    final uri = Uri.tryParse(apiOverride);
    if (environment != 'lab' ||
        flavor != 'lab' ||
        labHost.isEmpty ||
        (labTransport.isNotEmpty && labTransport != 'wifi') ||
        (isWifiLab && !privateIpv4(labHost)) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != labHost ||
        (uri.port != 443 &&
            !((labHost == '127.0.0.1' || isWifiLab) && uri.port == 8443)) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/api' ||
        labHost != labHost.toLowerCase() ||
        !RegExp(r'^[a-z0-9]+(?:[.-][a-z0-9]+)+$').hasMatch(labHost) ||
        labHost == 'onrender.com' ||
        labHost.endsWith('.onrender.com')) {
      throw StateError('Laboratoire : destination HTTPS dédiée requise.');
    }
    return uri;
  }

  bool get isPilot => environment == 'pilot' || flavor == 'pilot';
  String get apiUrl {
    if (!isLab && (labHost.isNotEmpty || labTransport.isNotEmpty)) {
      throw StateError('Transport Wi-Fi exclusivement LAB.');
    }
    if (isLab) return laboratoryEndpoint.toString();
    if (!{'production', 'pilot'}.contains(environment)) {
      throw StateError('Environnement inconnu.');
    }
    if (isPilot) {
      if (environment != 'pilot' ||
          flavor != 'pilot' ||
          apiOverride != pilotApi) {
        throw StateError(
          'Le pilote exige son flavor et son API HTTPS autorisée.',
        );
      }
      return pilotApi;
    }
    if (flavor.isNotEmpty && flavor != 'production') {
      throw StateError('Flavor inconnu.');
    }
    return apiOverride.isEmpty ? productionApi : apiOverride;
  }

  void validate({bool web = false, bool release = kReleaseMode}) {
    if (isLab && (web || release)) {
      throw StateError(
        'Le laboratoire exige Android debug, sans distribution.',
      );
    }
    if (web && isPilot) {
      throw StateError('Ce pilote exige Android.');
    }
    if (release && !isLab && !isPilot && apiUrl != productionApi) {
      throw StateError('La production release exige son API HTTPS exacte.');
    }
    Config.validatedApiUrl(apiUrl, release: release);
  }

  String get tokenKey => isLab
      ? 'lab_token_${Uri.encodeComponent(apiUrl)}'
      : isPilot
      ? 'pilot_token_${Uri.encodeComponent(apiUrl)}'
      : 'token';
  // External browsers cannot enforce the API redirect policy.
  bool get externalLinksAllowed => !isPilot && !isLab;
}

class Config {
  static const current = EnvironmentConfig(
    environment: String.fromEnvironment('APP_ENV', defaultValue: 'production'),
    apiOverride: String.fromEnvironment('API_URL'),
    flavor: String.fromEnvironment('FLUTTER_APP_FLAVOR'),
    labHost: String.fromEnvironment('LAB_API_HOST'),
    labTransport: String.fromEnvironment('LAB_TRANSPORT'),
  );
  static bool get isPilot => current.isPilot;
  static String get apiUrl => current.apiUrl;

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
    if (current.isLab && value != current.apiUrl) {
      throw StateError('Destination hors laboratoire.');
    }
    if (isPilot && value != EnvironmentConfig.pilotApi) {
      throw StateError('Destination hors environnement pilote.');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}
