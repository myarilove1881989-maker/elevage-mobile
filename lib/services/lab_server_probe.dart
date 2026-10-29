import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'environment_http_client.dart';

/// The only pre-admission request: fixed endpoint, no credentials or redirects.
Future<bool> probeLabServer(EnvironmentConfig config, String laboratoryId) async {
  http.Client? client;
  try {
    client = environmentHttpClient(config);
    final request = http.Request('GET', Uri.parse('${config.laboratoryEndpoint}/lab/isolation/'))
      ..followRedirects = false ..maxRedirects = 0;
    final response = await client.send(request).timeout(const Duration(seconds: 3));
    if (response.statusCode != 200 || response.headers['x-elevage-lab'] != laboratoryId) return false;
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 3))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024) return false;
    }
    final json = jsonDecode(utf8.decode(bytes));
    return json is Map && json['laboratory_id'] == laboratoryId && json['synthetic_only'] == true;
  } catch (_) { return false; }
  finally { client?.close(); }
}
