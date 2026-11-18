import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/offline_grant.dart';
import 'permission_contract_test.dart' show contract;
void main(){
final now=DateTime.utc(2026,10,11);
  Future<VerifiedOfflineGrant> grant({Map<String,dynamic>? rights,int user=1,Map<String,dynamic> markers=const {}}) async {
    final key=await Ed25519().newKeyPair();
    final public=await key.extractPublicKey();
    final pem='-----BEGIN PUBLIC KEY-----\n${base64.encode([0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00,...public.bytes])}\n-----END PUBLIC KEY-----';
    String part(Map<String,dynamic> value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
    final header=part({'alg':'EdDSA','kid':'synthetic'});
    final capabilities=<String,dynamic>{'can_create_terrain_operation':true,...markers};
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


  test('signed vaccination requires explicit protocol marker and explicit permission',()async{
    final raw=contract(rights:['finance.read','vaccinations.create']);
    final old=await grant(rights:raw);
    expect(old.permitsOperation('VACCINATION','CREATE',now),isFalse);
    final ready=await grant(rights:raw,markers:{'vaccine_stock_contract':1});
    expect(ready.permitsOperation('VACCINATION','CREATE',now),isTrue);
    expect(ready.permitsOperation('VACCINATION','UPDATE',now),isFalse);
    expect(ready.permitsOperation('VACCINATION','CREATE',ready.expiresAt),isFalse);
    final noRight=await grant(rights:contract(rights:['finance.read']),markers:{'vaccine_stock_contract':1});
    expect(noRight.permitsOperation('VACCINATION','CREATE',now),isFalse);
  });
  test('unknown or wrongly typed signed stock versions never enable vaccination',()async{
    for(final version in [true,1.0,'1',2,null]) {
      final signed=await grant(rights:contract(rights:['finance.read','vaccinations.create']),markers:{'vaccine_stock_contract':version});
      expect(signed.permitsOperation('VACCINATION','CREATE',now),isFalse);
    }
  });
  test('feed corrections require version but legacy creation remains compatible',()async{
    final raw=contract(rights:['finance.read','feed.create','feed.update','feed.delete']);
    final old=await grant(rights:raw);
    expect(old.permitsOperation('ALIMENTATION','CREATE',now),isTrue);
    expect(old.permitsOperation('ALIMENTATION','UPDATE',now),isFalse);
    final ready=await grant(rights:raw,markers:{'feed_stock_contract':1});
    expect(ready.permitsOperation('ALIMENTATION','UPDATE',now),isTrue);
    expect(ready.permitsOperation('ALIMENTATION','REVERSE',now),isTrue);
    expect(ready.permitsOperation('VACCINATION','CREATE',now),isFalse);
  });
  test('protocol marker cannot be added to an immutable verified grant',()async{
    final signed=await grant(rights:contract());
    expect(()=> (signed.claims['capabilities'] as Map)['vaccine_stock_contract']=1,throwsUnsupportedError);
  });
}
