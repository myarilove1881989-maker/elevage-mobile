import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/device_identity.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/local_operator_session.dart';

class MemorySecrets implements OperatorSecretStore {
  final values = <String,String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async { values[key] = value; }
}

class RecordingIdentity implements DeviceIdentity {
  Uint8List? message;
  @override
  Future<Map<String,dynamic>> publicIdentity() async => {};
  @override
  Future<String> sign(Uint8List message) async { this.message = message; return 'signature'; }
}

void main() {
  final now = DateTime.utc(2026,10,7,4);
  late SimpleKeyPair key;
  late String pem;
  Future<String> tokenFor(int user, {int farm = 1}) async {
    final header = base64Url.encode(utf8.encode(jsonEncode({'alg':'EdDSA','kid':'test'}))).replaceAll('=', '');
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'iss':'elevage-offline', 'aud':'elevage-device','typ':'offline-authorization',
      'jti':'test-$user', 'sub':'$user', 'membership_id':user, 'exploitation_id':farm,
      'device_id':7, 'write_generation':2,'rights_version':3,
      'iat':now.millisecondsSinceEpoch ~/ 1000,
      'exp':now.add(const Duration(days:3)).millisecondsSinceEpoch ~/ 1000,
      'capabilities':{'can_create_sale':true},
    }))).replaceAll('=', '');
    final signature = await Ed25519().sign(utf8.encode('$header.$payload'), keyPair:key);
    return '$header.$payload.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
  }
  Future<VerifiedOfflineGrant> grantFor(int user) async => VerifiedOfflineGrant.verify(
      token:await tokenFor(user),publicKeyPem:pem,trustedKeyId:'test',farmId:1,userId:user,
      deviceId:7,generation:2,rightsVersion:3,now:now);

  setUp(() async {
    key = await Ed25519().newKeyPair();
    final public = await key.extractPublicKey();
    pem = '-----BEGIN PUBLIC KEY-----\n${base64.encode([
      0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00,...public.bytes,
    ])}\n-----END PUBLIC KEY-----';
  });

  test('signature covers exact transmitted body and query without final newline', () async {
    final identity = RecordingIdentity();
    final headers = await deviceProofHeaders(identity:identity,challengeId:'challenge',deviceId:7,
      userId:1,purpose:'WRITE',method:'POST',pathAndQuery:'/api/test/?x=1',
      body:Uint8List.fromList(utf8.encode('{}')));
    expect(headers['X-Elevage-Device'],'7');
    expect(utf8.decode(identity.message!),
      'ELEVAGE-DEVICE-V1\nchallenge\n7\n1\nWRITE\nPOST\n/api/test/?x=1\n'
      '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a');
  });

  test('grant rejects cross tenant, expired and wrong authority', () async {
    final token = await tokenFor(1);
    Future<VerifiedOfflineGrant> verify(int farm, String keyId, DateTime time) =>
      VerifiedOfflineGrant.verify(token:token,publicKeyPem:pem,trustedKeyId:keyId,
        farmId:farm,userId:1,deviceId:7,generation:2,rightsVersion:3,now:time);
    await expectLater(verify(2,'test',now),throwsStateError);
    await expectLater(verify(1,'unknown',now),throwsStateError);
    await expectLater(verify(1,'test',now.add(const Duration(days:4))),throwsStateError);
    final grant = await verify(1,'test',now);
    expect(() => grant.claims['sub']='2',throwsUnsupportedError);
    expect(() => (grant.claims['capabilities'] as Map)['can_create_sale']=false,throwsUnsupportedError);
  });

  test('Jean and Paul retain separate PINs across restart and switching locks', () async {
    final secrets = MemorySecrets();
    final jean = await grantFor(1), paul = await grantFor(2);
    var sessions = LocalOperatorSessions(store:secrets,namespace:'test',farmId:1,deviceId:7,generation:2,clock:()=>now);
    await sessions.enroll(jean,'123456');
    await sessions.enroll(paul,'654321');
    expect(secrets.values.values.any((v)=>v.contains('123456') || v.contains('654321')),isFalse);
    expect(await sessions.unlock(jean,'123456'),isTrue);
    expect(sessions.session!.userId,1);
    expect(await sessions.unlock(paul,'123456'),isFalse);
    expect(sessions.session,isNull);
    sessions = LocalOperatorSessions(store:secrets,namespace:'test',farmId:1,deviceId:7,generation:2,clock:()=>now);
    expect(sessions.session,isNull);
    expect(await sessions.unlock(paul,'654321'),isTrue);
    expect(sessions.session!.userId,2);
    expect(await sessions.changePin(paul,'654321','234567'),isTrue);
    expect(sessions.session,isNull);
    expect(await sessions.unlock(paul,'654321'),isFalse);
    expect(await sessions.unlock(paul,'234567'),isTrue);
  });

  test('lockout survives restart and blocks clock rollback', () async {
    final secrets = MemorySecrets();
    final jean = await grantFor(1);
    var time = now;
    var sessions = LocalOperatorSessions(store:secrets,namespace:'test',farmId:1,deviceId:7,generation:2,clock:()=>time);
    await sessions.enroll(jean,'123456');
    for (var i=0;i<5;i++) { expect(await sessions.unlock(jean,'000000'),isFalse); }
    sessions = LocalOperatorSessions(store:secrets,namespace:'test',farmId:1,deviceId:7,generation:2,clock:()=>time);
    expect(await sessions.unlock(jean,'123456'),isFalse);
    time = now.add(const Duration(seconds:31));
    expect(await sessions.unlock(jean,'123456'),isTrue);
    time = now.add(const Duration(seconds:1));
    expect(await sessions.unlock(jean,'123456'),isFalse);
    expect(sessions.session,isNull);
  });

  test('valid signed grant cannot open another device or farm local session',() async {
    final grant=await grantFor(1);
    for(final context in [(2,7,2),(1,8,2),(1,7,3)]) {
      final sessions=LocalOperatorSessions(store:MemorySecrets(),namespace:'test',
        farmId:context.$1,deviceId:context.$2,generation:context.$3,clock:()=>now);
      await expectLater(sessions.enroll(grant,'123456'),throwsStateError);
      expect(sessions.session,isNull);
    }
  });
}
