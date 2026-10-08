import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'device_identity.dart';
import 'local_operator_session.dart';
import 'offline_grant.dart';

class FoundationApiException implements Exception {
  const FoundationApiException(this.status);
  final int status;
  @override
  String toString() => status == 401 ? 'Connexion personnelle requise.' :
      status == 403 ? 'Cette action n’est pas autorisée.' :
      status == 503 ? 'La préparation hors ligne est indisponible sur le serveur.' :
      'Le serveur n’a pas accepté cette demande ($status).';
}

class OnlineOperatorIdentity {
  OnlineOperatorIdentity({required this.userId, required this.farmId,
    required this.role, required this.capabilities, required this.access,
    required this.refresh});
  final int userId, farmId;
  final String role;
  final Map<String,dynamic> capabilities;
  String access, refresh;
}

/// Dedicated personal credentials. Never uses ApiService's global session.
class FoundationApi {
  FoundationApi({required this.baseUrl, required this.deviceIdentity,
    required this.secrets, http.Client? client,DateTime Function()? clock})
      : client=client ?? http.Client(),clock=clock??DateTime.now {
    final uri=Uri.parse(baseUrl);
    if (uri.scheme!='https' || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('La préparation exige HTTPS.');
    }
  }
  final String baseUrl;
  final DeviceIdentity deviceIdentity;
  final OperatorSecretStore secrets;
  final http.Client client;
  final DateTime Function() clock;
  OnlineOperatorIdentity? personal;
  Future<void>? _refreshing;
  void close() => client.close();

  Future<Map<String,dynamic>> _send(String method,String path,{Map<String,dynamic>? data,
    Map<String,String>? proof,String? access}) async {
    if (!path.startsWith('/') || path.contains('..') || path.contains('\n')) throw ArgumentError('Chemin invalide.');
    final request=http.Request(method,Uri.parse('$baseUrl$path'));
    request.headers.addAll({'Content-Type':'application/json',if(access!=null)'Authorization':'Bearer $access',...?(proof)});
    if (data!=null) request.body=jsonEncode(data);
    final response=await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds:30)))
        .timeout(const Duration(seconds:30));
    if (response.statusCode<200 || response.statusCode>=300) throw FoundationApiException(response.statusCode);
    if (response.body.isEmpty) return {};
    final decoded=jsonDecode(response.body);
    return decoded is Map<String,dynamic> ? decoded : {'results':decoded};
  }

  Future<OnlineOperatorIdentity> logIn(String username,String password,{int? expectedFarm}) async {
    personal=null;
    final tokens=await _send('POST','/token/',data:{'username':username,'password':password});
    final capabilities=await _send('GET','/me/capabilities/',access:tokens['access'] as String);
    final farm=capabilities['exploitation'] as int;
    if (expectedFarm!=null && expectedFarm!=farm) throw StateError('Ce compte appartient à une autre exploitation.');
    final identity=OnlineOperatorIdentity(userId:capabilities['user'] as int,farmId:farm,
      role:capabilities['role'] as String,capabilities:Map.unmodifiable(capabilities),
      access:tokens['access'] as String,refresh:tokens['refresh'] as String);
    await _saveCredentials(identity);
    personal=identity;
    return identity;
  }

  String _credentialKey(OnlineOperatorIdentity identity) =>
      'personal_credentials_${Uri.encodeComponent(baseUrl)}_${identity.farmId}_${identity.userId}';
  Future<void> _saveCredentials(OnlineOperatorIdentity identity) => secrets.write(_credentialKey(identity),
      jsonEncode({'access':identity.access,'refresh':identity.refresh}));

  Future<Map<String,dynamic>> request(String method,String path,{Map<String,dynamic>? data,
    Map<String,String>? proof}) async {
    final identity=personal;
    if (identity==null) throw const FoundationApiException(401);
    try { return await _send(method,path,data:data,proof:proof,access:identity.access); }
    on FoundationApiException catch(error) {
      if(error.status!=401) rethrow;
      _refreshing ??= _refresh(identity);
      try { await _refreshing; } finally { _refreshing=null; }
      if (!identical(personal,identity)) throw const FoundationApiException(401);
      return _send(method,path,data:data,proof:proof,access:identity.access);
    }
  }

  Future<void> _refresh(OnlineOperatorIdentity identity) async {
    try {
      final tokens=await _send('POST','/token/refresh/',data:{'refresh':identity.refresh});
      if (!identical(personal,identity)) throw const FoundationApiException(401);
      identity.access=tokens['access'] as String;
      if(tokens['refresh'] is String) identity.refresh=tokens['refresh'] as String;
      await _saveCredentials(identity);
    } catch (_) {
      if(identical(personal,identity)) personal=null;
      rethrow;
    }
  }

  Future<Map<String,dynamic>> registerInstallation(String name) async {
    if(personal?.role!='OWNER') throw const FoundationApiException(403);
    final identity=await deviceIdentity.publicIdentity();
    return request('POST','/devices/',data:{'installation_uuid':identity['installation_uuid'],
      'public_key':identity['public_key'],'platform':'ANDROID','display_name':name});
  }

  Future<Map<String,dynamic>> signedRequest(String path,{required int deviceId,
    required String purpose,Map<String,dynamic> data=const {}}) async {
    final identity=personal;
    if(identity==null) throw const FoundationApiException(401);
    final challenge=await request('POST','/devices/challenge/',
      data:{'device_id':deviceId,'purpose':purpose});
    if(!identical(identity,personal)) throw const FoundationApiException(401);
    if(challenge['device_id']!=deviceId || challenge['user_id']!=identity.userId ||
        challenge['purpose']!=purpose || challenge['signature_contract']!='ELEVAGE-DEVICE-V1') {
      throw StateError('Challenge de tablette invalide.');
    }
    final headers=await deviceProofHeaders(identity:deviceIdentity,
      challengeId:challenge['id'] as String,deviceId:deviceId,userId:identity.userId,
      purpose:purpose,method:'POST',pathAndQuery:'${Uri.parse(baseUrl).path}$path',
      body:Uint8List.fromList(utf8.encode(jsonEncode(data))));
    if(!identical(identity,personal)) throw const FoundationApiException(401);
    return request('POST',path,data:data,proof:headers);
  }

  Future<VerifiedOfflineGrant> provisionGrant() async {
    final identity=personal;
    if(identity==null || identity.role!='OPERATEUR') throw const FoundationApiException(403);
    final capabilities=await request('GET','/me/capabilities/');
    if(capabilities['offline_policy_enabled']!=true) throw StateError('La préparation de cette exploitation doit être activée par son propriétaire.');
    final device=capabilities['primary_device'] as Map<String,dynamic>?;
    if(device==null) throw StateError('Tablette principale requise.');
    final local=await deviceIdentity.publicIdentity();
    if(device['installation_uuid']!=local['installation_uuid']) throw StateError('Cette tablette n’est pas la tablette principale.');
    final response=await signedRequest('/offline-authorizations/',deviceId:device['id'] as int,purpose:'GRANT');
    final member=capabilities['membership'] as Map<String,dynamic>;
    final grant=await VerifiedOfflineGrant.verify(token:response['authorization'] as String,
      publicKeyPem:response['public_key'] as String,trustedKeyId:response['key_id'] as String,
      farmId:identity.farmId,userId:identity.userId,deviceId:device['id'] as int,
      generation:capabilities['write_generation'] as int,rightsVersion:member['version'] as int,
      now:clock().toUtc());
    final grantRecord=jsonEncode({'token':grant.token,'public_key':response['public_key'],'key_id':response['key_id'],
      'device_id':grant.deviceId,'generation':grant.generation,'rights_version':grant.rightsVersion});
    final namespace=Uri.encodeComponent(baseUrl);
    await secrets.write('offline_grant_history_${namespace}_${grant.claims['jti']}',grantRecord);
    await secrets.write('offline_grant_${namespace}_${grant.farmId}_${grant.userId}',grantRecord);
    return grant;
  }

  Future<VerifiedOfflineGrant> loadLocalGrant({required int farmId,required int userId}) async {
    final encoded=await secrets.read('offline_grant_${Uri.encodeComponent(baseUrl)}_${farmId}_$userId');
    if(encoded==null) throw StateError('Une connexion personnelle est requise pour préparer ce profil.');
    final record=jsonDecode(encoded) as Map<String,dynamic>;
    return VerifiedOfflineGrant.verify(token:record['token'] as String,
      publicKeyPem:record['public_key'] as String,trustedKeyId:record['key_id'] as String,
      farmId:farmId,userId:userId,deviceId:record['device_id'] as int,
      generation:record['generation'] as int,rightsVersion:record['rights_version'] as int,
      now:clock().toUtc());
  }
}
