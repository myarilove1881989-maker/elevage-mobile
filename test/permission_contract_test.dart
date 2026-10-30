import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'package:app_elevage/offline/prepared_operation_policy.dart';

Map<String,dynamic> contract({int user = 1, String role = 'OPERATEUR', List<String>? rights}) => {
  'version':1,'user':user,'exploitation':7,'role':role,'rights_version':3,
  'permissions':rights??['finance.read','purchases.create','mortality.create'],
};
PermissionContract decode(Map<String,dynamic> data,{int user=1,String role='OPERATEUR'}) =>
  PermissionContract.decode(data,userId:user,farmId:7,role:role,rightsVersion:3);

void main() {
  final now = DateTime.utc(2026,10,11);
  test('HTTP fine contract is validated before storing personal credentials', () async {
    final secrets=TestSecretStore();
    final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
      client:MockClient((request) async=>http.Response(jsonEncode(request.url.path.endsWith('/token/')?
        {'access':'synthetic-access','refresh':'synthetic-refresh'}:
        {'user':1,'exploitation':7,'role':'OPERATEUR','membership':{'version':3},
         'permission_contract':contract()}),200)));
    final identity=await api.logIn('synthetic','synthetic-password',expectedFarm:7);
    expect(identity.userId,1);
    expect(secrets.values.length,1);
    expect(secrets.values.values.single,isNot(contains('synthetic-password')));
    api.close();
  });
  test('invalid HTTP extension never persists credentials or installs a personal session', () async {
    for(final extension in [contract()..['user']=2,contract()..['version']=2,
      contract(rights:['finance.read','invented.create']),null]) {
      final secrets=TestSecretStore();
      final api=FoundationApi(baseUrl:'https://test.invalid/api',deviceIdentity:TestIdentity(),secrets:secrets,
        client:MockClient((request) async=>http.Response(jsonEncode(request.url.path.endsWith('/token/')?
          {'access':'synthetic-access','refresh':'synthetic-refresh'}:
          {'user':1,'exploitation':7,'role':'OPERATEUR','membership':{'version':3},
           'permission_contract':extension}),200)));
      await expectLater(api.logIn('synthetic','synthetic-password'),throwsStateError);
      expect(api.personal,isNull);
      expect(secrets.values,isEmpty);
      api.close();
    }
  });
  Future<VerifiedOfflineGrant> grant({Map<String,dynamic>? rights,int user=1}) async {
    final key=await Ed25519().newKeyPair();
    final public=await key.extractPublicKey();
    final pem='-----BEGIN PUBLIC KEY-----\n${base64.encode([0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00,...public.bytes])}\n-----END PUBLIC KEY-----';
    String part(Map<String,dynamic> value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
    final header=part({'alg':'EdDSA','kid':'synthetic'});
    final capabilities=<String,dynamic>{'can_create_terrain_operation':true};
    if(rights!=null) {
      // The former HTTP-only preparation fixture now uses the fully bound signed v2 contract.
      capabilities['permission_contract']={...rights,'version':2,'grant_id':'synthetic-grant',
        'grant_version':1,'membership_id':user,'device_id':4,'write_generation':1,
        'iat':now.millisecondsSinceEpoch~/1000,
        'exp':now.add(const Duration(hours:24)).millisecondsSinceEpoch~/1000};
    }
    final payload=part({'iss':'elevage-offline','aud':'elevage-device','typ':'offline-authorization',
      'jti':'synthetic-grant','sub':'$user','membership_id':user,'exploitation_id':7,'device_id':4,
      'write_generation':1,'rights_version':3,'iat':now.millisecondsSinceEpoch~/1000,
      'exp':now.add(Duration(hours:rights==null?168:24)).millisecondsSinceEpoch~/1000,
      'capabilities':capabilities,
    });
    final signature=await Ed25519().sign(utf8.encode('$header.$payload'),keyPair:key);
    final token='$header.$payload.${base64Url.encode(signature.bytes).replaceAll('=','')}';
    return VerifiedOfflineGrant.verify(token:token,publicKeyPem:pem,trustedKeyId:'synthetic',
      farmId:7,userId:user,deviceId:4,generation:1,rightsVersion:3,now:now);
  }

  test('Jean purchases and mortality cannot sell, Paul sales cannot purchase', () {
    final jean=decode(contract());
    final paul=decode(contract(user:2,rights:['finance.read','animal_sales.create','births.create']),user:2);
    expect(jean.allows('purchases.create'),isTrue);
    expect(jean.allows('animal_sales.create'),isFalse);
    expect(paul.allows('animal_sales.create'),isTrue);
    expect(paul.allows('purchases.create'),isFalse);
    expect(jean.allows('finance.read'),isTrue);
    expect(paul.allows('finance.read'),isTrue);
  });
  test('OWNER can plan but never receives business writes', () {
    final owner=decode(contract(role:'OWNER',rights:['finance.read','users.manage','agenda.plan']),role:'OWNER');
    expect(owner.allows('agenda.plan'),isTrue);
    expect(owner.allows('purchases.create'),isFalse);
    expect(()=>decode(contract(role:'OWNER'),role:'OWNER'),throwsStateError);
    expect(()=>decode(contract(role:'OWNER',rights:['finance.read','agenda.progress']),role:'OWNER'),throwsStateError);
  });
  test('unknown codes, versions and cross-profile identity fail closed', () {
    for(final data in [contract()..['version']=2,contract()..['user']=2,
      contract()..['exploitation']=8,contract()..['rights_version']=2,
      contract(rights:['finance.read','unknown.create']),
      contract(rights:['finance.read','finance.read']),contract(rights:['purchases.create'])]) {
      expect(()=>decode(data),throwsStateError);
    }
    expect(()=>decode(contract(rights:['finance.read','users.manage'])),throwsStateError);
  });
  test('known revocation denies operations without altering contract', () {
    final rights=decode(contract());
    expect(rights.allows('purchases.create',revoked:true),isFalse);
    expect(rights.permissions,contains('purchases.create'));
    expect(()=>rights.permissions.clear(),throwsUnsupportedError);
  });
  test('old signed grant remains valid and is identified for explicit transition', () async {
    final old=await grant();
    final before=old.token;
    expect(old.permits('can_create_terrain_operation',now),isTrue);
    expect(preparedOperationDecision(old,'ACHAT','CREATE',now),PreparedOperationDecision.legacyTransitionRequired);
    expect(old.token,before);
    expect(old.permits('can_create_terrain_operation',now),isTrue);
  });
  test('prepared exact operation, expiration and known revocation', () async {
    final signed=await grant(rights:contract());
    expect(preparedOperationDecision(signed,'ACHAT','CREATE',now),PreparedOperationDecision.allowed);
    expect(preparedOperationDecision(signed,'VENTE_ANIMAUX','CREATE',now),PreparedOperationDecision.denied);
    expect(preparedOperationDecision(signed,'ACHAT','CREATE',signed.expiresAt),PreparedOperationDecision.denied);
    expect(preparedOperationDecision(signed,'ACHAT','CREATE',now,revoked:true),PreparedOperationDecision.denied);
    expect(preparedOperationDecision(signed,'ACHAT','DELETE',now),PreparedOperationDecision.denied);
  });
  test('prepared grant does not borrow another profile permissions or stale rights', () async {
    // Refusal now happens during cryptographic grant verification, before any profile can use it.
    await expectLater(grant(rights:contract(user:2)),throwsStateError);
    await expectLater(grant(rights:contract()..['rights_version']=2),throwsStateError);
  });
  test('only reviewed update commands are authorized', () {
    expect(PermissionContract.operationAction('TRANSFERT','CREATE'),isNull);
    expect(PermissionContract.operationAction('COLLECTE_OEUFS','UPDATE'),'egg_collections.update');
    expect(PermissionContract.operationAction('TASK','UPDATE'),'agenda.progress');
  });
}
