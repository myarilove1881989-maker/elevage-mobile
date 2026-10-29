import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config.dart';
import 'lab_network_gate.dart';
import 'environment_http_client.dart';

class NetworkDestinationException implements Exception {
  const NetworkDestinationException();
  @override
  String toString() =>
      'Connexion refusée : destination hors pilote ou redirection.';
}

/// All three transports pass here before the inner client can send any bytes.
class GuardedApiClient extends http.BaseClient {
  GuardedApiClient(
    http.Client? inner, {
    EnvironmentConfig? configuration,
    LabNetworkGate? labGate,
    bool enforceProductionForTesting = false,
  }) : _inner = inner ?? environmentHttpClient(configuration ?? Config.current),
       _configuration = configuration ?? Config.current,
       _restrictProduction = kReleaseMode || enforceProductionForTesting,
       _labGate = labGate ?? LabNetworkGate.instance {
    if (_guardedProduction) _configuration.validate(release: true);
    if (_configuration.isLab) _labGate.attach(_inner.close);
  }
  final bool _restrictProduction;
  bool get _guardedProduction => _restrictProduction &&
      !_configuration.isLab && !_configuration.isPilot;
  final LabNetworkGate _labGate;
  final http.Client _inner;
  final EnvironmentConfig _configuration;

  void validateBaseUrl(String value) {
    if (_guardedProduction && value != EnvironmentConfig.productionApi) {
      throw const NetworkDestinationException();
    }
    if (_configuration.isLab && value != _configuration.apiUrl) {
      throw const NetworkDestinationException();
    }
    if (_configuration.isPilot && value != _configuration.apiUrl) {
      throw const NetworkDestinationException();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_configuration.isLab) {
      final allowed = _labGate.permits(_configuration, request.url);
      _labGate.record(request.url, allowed: allowed);
      if (!allowed) throw const NetworkDestinationException();
      request.followRedirects = false;
      request.maxRedirects = 0;
      final response = await _inner.send(request);
      if (!_labGate.permits(_configuration, request.url) ||
          (response.statusCode >= 300 && response.statusCode < 400) ||
          ((_configuration.labHost == '127.0.0.1' || _configuration.isWifiLab) &&
            response.headers['x-elevage-lab'] != _labGate.laboratoryId)) {
        await response.stream.listen((_) {}).cancel();
        throw const NetworkDestinationException();
      }
      return response;
    }
    if (!_configuration.isPilot && !_guardedProduction) return _inner.send(request);
    final allowed = Uri.parse(_configuration.apiUrl);
    final target = request.url;
    if (target.scheme != allowed.scheme ||
        target.host != allowed.host ||
        target.port != allowed.port ||
        target.userInfo.isNotEmpty ||
        target.hasFragment ||
        !(target.path == allowed.path ||
            target.path.startsWith('${allowed.path}/')) ||
        target.path.contains('%') ||
        target.path.contains('\\') ||
        target.pathSegments.any((part) => part == '.' || part == '..')) {
      throw const NetworkDestinationException();
    }
    request.followRedirects = false;
    request.maxRedirects = 0;
    final response = await _inner.send(request);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.listen((_) {}).cancel();
      throw const NetworkDestinationException();
    }
    return response;
  }

  @override
  void close() {
    if (_configuration.isLab) _labGate.detach(_inner.close);
    _inner.close();
  }
}
