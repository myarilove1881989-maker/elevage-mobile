import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/device_identity.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/local_operator_session.dart';

class TestSecretStore implements OperatorSecretStore {
  final values=<String,String>{};
  @override
  Future<String?> read(String key) async=>values[key];
  @override
  Future<void> write(String key,String value) async {values[key]=value;}
}
class TestIdentity implements DeviceIdentity {
  Uint8List? signed;
  @override
  Future<Map<String,dynamic>> publicIdentity() async=>{
    'installation_uuid':'test-installation','public_key':'test-public-only',
    'algorithm':'P256-SHA256-DER','private_key_exportable':false,
  };
  @override
  Future<String> sign(Uint8List message) async {signed=message;return 'test-proof';}
}

void main() {
  test('cross-farm login never persists credentials or changes personal session',() async {
    final secrets=TestSecretStore();
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
      client:MockClient((request) async=>http.Response(jsonEncode(request.url.path.endsWith('/token/')?
        {'access':'test-access','refresh':'test-refresh'}:
        {'user':1,'exploitation':2,'role':'OPERATEUR'}),200)));
    await expectLater(api.logIn('operator','synthetic-password',expectedFarm:1),throwsStateError);
    expect(secrets.values,isEmpty);
    expect(api.personal,isNull);
    api.close();
  });

  test('challenge proof uses server contract and exact HTTP path/body',() async {
    final identity=TestIdentity();
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:identity,secrets:TestSecretStore(),
      client:MockClient((request) async {
        if(request.url.path.endsWith('/token/')) return http.Response('{"access":"a","refresh":"r"}',200);
        if(request.url.path.endsWith('/capabilities/')) return http.Response('{"user":1,"exploitation":2,"role":"OWNER"}',200);
        if(request.url.path.endsWith('/challenge/')) return http.Response(jsonEncode({
          'id':'challenge','device_id':7,'user_id':1,'purpose':'ACTIVATE','signature_contract':'ELEVAGE-DEVICE-V1'}),201);
        expect(request.headers['X-Elevage-Signature'],'test-proof');
        expect(request.body,'{}');
        return http.Response('{"status":"ACTIVE"}',200);
      }));
    await api.logIn('owner','synthetic-password');
    await api.signedRequest('/devices/7/activate/',deviceId:7,purpose:'ACTIVATE');
    expect(utf8.decode(identity.signed!),contains('\nPOST\n/api/devices/7/activate/\n'));
    api.close();
  });

  test('expired access refreshes only the same personal identity',() async {
    var refreshCount=0;
    final secrets=TestSecretStore();
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
      client:MockClient((request) async {
        if(request.url.path.endsWith('/token/')) return http.Response('{"access":"old","refresh":"personal-refresh"}',200);
        if(request.url.path.endsWith('/capabilities/')) return http.Response('{"user":1,"exploitation":2,"role":"OPERATEUR"}',200);
        if(request.url.path.endsWith('/refresh/')) {
          expect(jsonDecode(request.body)['refresh'],'personal-refresh');refreshCount++;
          return http.Response('{"access":"new"}',200);
        }
        return request.headers['Authorization']=='Bearer new'?http.Response('{"results":[]}',200):http.Response('{}',401);
      }));
    await api.logIn('operator','synthetic-password');
    await api.request('GET','/cache-page/?collection=clients');
    expect(refreshCount,1);
    expect(api.personal!.access,'new');
    expect(secrets.values.values.single,contains('personal-refresh'));
    expect(secrets.values.values.single,isNot(contains('synthetic-password')));
    api.close();
  });
}
