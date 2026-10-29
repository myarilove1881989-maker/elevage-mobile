import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../config.dart';

http.Client environmentHttpClient(EnvironmentConfig config) {
  if (!config.isLab || (!config.isWifiLab && config.laboratoryEndpoint.host != '127.0.0.1')) return http.Client();
  const ca = String.fromEnvironment('LAB_CA_PEM');
  if (ca.isEmpty) throw StateError('Certificat public du laboratoire absent.');
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(base64Decode(ca));
  final client = HttpClient(context: context);
  client.findProxy = (_) => 'DIRECT';
  return IOClient(client);
}
