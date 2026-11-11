import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Public release metadata only. Never reads credentials or offline databases.
class AndroidUpdate {
  const AndroidUpdate(this.code);
  final int code;
  static final downloadUrl = Uri.parse(
    'https://elevage-mobile.onrender.com/telecharger',
  );
  static final manifestUrl = Uri.parse(
    'https://elevage-mobile.onrender.com/android-version.json',
  );

  static AndroidUpdate? parse(Object? value, int installed, DateTime now) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['applicationId'] != 'com.elevage.app' ||
        value['published'] != true ||
        value['downloadUrl'] != downloadUrl.toString()) {
      return null;
    }
    final code = value['versionCode'];
    final date = value['publishedAt'];
    final sha = value['sha256'];
    if (installed < 1 ||
        code is! int ||
        code <= installed ||
        code > 2100000000 ||
        date is! String ||
        !date.endsWith('Z') ||
        sha is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) {
      return null;
    }
    final publishedAt = DateTime.tryParse(date);
    if (publishedAt == null || publishedAt.isAfter(now.toUtc())) return null;
    return AndroidUpdate(code);
  }
}

class AndroidUpdateService {
  AndroidUpdateService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  static const _channel = MethodChannel('elevage/app_version');
  Future<AndroidUpdate?> check() async {
    final client = _clientFactory();
    try {
      // One deadline covers native lookup, headers AND response streaming.
      return await _check(client).timeout(const Duration(seconds: 5));
    } catch (_) {
      {
        return null;
      }
    } finally {
      client.close();
    }
  }

  Future<AndroidUpdate?> _check(http.Client client) async {
    final installed = await _channel.invokeMethod<String>('versionCode');
    final code = int.tryParse(installed ?? '');
    if (code == null || code < 1) return null;
    final request = http.Request('GET', AndroidUpdate.manifestUrl)
      ..followRedirects = false;
    request.headers['Cache-Control'] = 'no-cache';
    final response = await client.send(request);
    if (response.statusCode != 200 || (response.contentLength ?? 0) > 16384) {
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > 16384) return null;
    }
    return AndroidUpdate.parse(
      jsonDecode(utf8.decode(bytes)),
      code,
      DateTime.now(),
    );
  }
}
