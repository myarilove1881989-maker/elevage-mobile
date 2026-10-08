import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Bounded test-only checks. Never records tokens, key bytes or author credentials.
class GrantDiagnosticClient extends http.BaseClient {
  GrantDiagnosticClient(this.delegate,{required this.expected});
  final http.Client delegate;
  final Map<String,dynamic> Function() expected;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response=await delegate.send(request);
    if(!request.url.path.endsWith('/offline-authorizations/') || response.statusCode!=201) return response;
    final bytes=await response.stream.toBytes();
    final data=jsonDecode(utf8.decode(bytes)) as Map;
    final parts=(data['authorization'] as String).split('.');
    final payload=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
    final header=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0])))) as Map;
    final pem=data['public_key'] as String;
    final der=base64.decode(pem.replaceAll('-----BEGIN PUBLIC KEY-----','').replaceAll('-----END PUBLIC KEY-----','').replaceAll(RegExp(r'\s'),''));
    final valid=der.length==44 && await Ed25519().verify(utf8.encode('${parts[0]}.${parts[1]}'),
      signature:Signature(base64Url.decode(base64Url.normalize(parts[2])),publicKey:SimplePublicKey(der.sublist(12),type:KeyPairType.ed25519)));
    final now=DateTime.now().toUtc().millisecondsSinceEpoch~/1000;
    final matches=expected().entries.every((entry)=>payload[entry.key]==entry.value);
    debugPrint('REAL_GRANT_DIAGNOSTIC signature=$valid alg=${header['alg']=='EdDSA'} kid=${header['kid']==data['key_id']} '
      'context_matches=$matches contract_matches=${payload['iss']=='elevage-offline' && payload['aud']=='elevage-device' && payload['typ']=='offline-authorization'} '
      'issued_delta_seconds=${now-(payload['iat'] as int)} expires_remaining_seconds=${(payload['exp'] as int)-now} '
      'subject_string=${payload['sub'] is String} membership_integer=${payload['membership_id'] is int} '
      'capabilities_map=${payload['capabilities'] is Map<String,dynamic>}');
    return http.StreamedResponse(Stream.value(bytes),response.statusCode,headers:response.headers,
      reasonPhrase:response.reasonPhrase,request:response.request);
  }
  @override
  void close()=>delegate.close();
}
