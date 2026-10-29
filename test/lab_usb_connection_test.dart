import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app_elevage/config.dart';
import 'package:app_elevage/services/environment_http_client.dart';
import 'package:app_elevage/services/guarded_api_client.dart';
import 'package:app_elevage/services/lab_network_gate.dart';
import 'package:app_elevage/services/lab_server_probe.dart';

void main() {
  final enabled = Config.current.isLab && Config.current.labHost == '127.0.0.1';
  test('real HTTPS uses the dedicated CA and authenticates synthetic accounts only', () async {
    final gate = LabNetworkGate();
    expect(await gate.initializeFromBuild(Config.current), isTrue);
    final client = GuardedApiClient(null, labGate: gate);
    try {
      final credentials = jsonDecode(await File(Platform.environment['LAB_TEST_CREDENTIALS']!).readAsString()) as Map;
      for (final pair in [['owner','recette-owner'],['paul','recette-paul'],['jean','recette-jean']]) {
        final request = http.Request('POST', Uri.parse('${Config.apiUrl}/token/'))
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({'username':pair[1],'password':credentials[pair[0]]});
        final login = await http.Response.fromStream(await client.send(request));
        expect(login.statusCode,200);
        final token = (jsonDecode(login.body) as Map)['access'];
        final response = await client.get(Uri.parse('${Config.apiUrl}/me/capabilities/'),
          headers: {'authorization':'Bearer $token'});
        expect(response.statusCode,200);
        final state = jsonDecode(response.body) as Map;
        if (pair[0] != 'owner') {
          final codes = ((state['permission_contract'] as Map)['permissions'] as List);
          expect(codes, contains('animal_sales.create'));
          expect(codes.contains('animal_sales.cancel'), pair[0]=='paul');
        }
      }
      expect(await probeLabServer(Config.current, '0'*32), isFalse);
      await expectLater(client.get(Uri.parse('https://127.0.0.1:8444/api/lab/isolation/')),
        throwsA(isA<NetworkDestinationException>()));
      await expectLater(client.get(Uri.parse(EnvironmentConfig.pilotApi)),
        throwsA(isA<NetworkDestinationException>()));
      gate.stop();
      await expectLater(client.get(Uri.parse('${Config.apiUrl}/lab/isolation/')),
        throwsA(isA<NetworkDestinationException>()));
    } finally { client.close();gate.dispose(); }
  }, skip: !enabled);

  test('unapproved roots and wrong IP/DNS name are refused by real TLS', () async {
    final plain = http.Client();
    final trusted = environmentHttpClient(Config.current);
    try {
      final tlsFailure = anyOf(isA<HandshakeException>(), isA<http.ClientException>());
      await expectLater(plain.get(Uri.parse('${Config.apiUrl}/lab/isolation/')), throwsA(tlsFailure));
      await expectLater(trusted.get(Uri.parse('https://localhost:8443/api/lab/isolation/')), throwsA(tlsFailure));
    } finally { plain.close();trusted.close(); }
  }, skip: !enabled);

}
