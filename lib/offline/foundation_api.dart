import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../services/guarded_api_client.dart';
import 'device_identity.dart';
import 'local_operator_session.dart';
import 'offline_grant.dart';
import '../services/permission_contract.dart';
import '../services/initial_password.dart';

class FoundationApiException implements Exception {
  const FoundationApiException(this.status, {this.operation});
  final String? operation;
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
      : client=GuardedApiClient(client),clock=clock??DateTime.now {
    this.client.validateBaseUrl(baseUrl);
    final uri=Uri.parse(baseUrl);
    if (uri.scheme!='https' || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('La préparation exige HTTPS.');
    }
  }
  final String baseUrl;
  final DeviceIdentity deviceIdentity;
  final OperatorSecretStore secrets;
  final GuardedApiClient client;
  final DateTime Function() clock;
  OnlineOperatorIdentity? personal;
  Future<void>? _refreshing;
  int _personalEpoch=0;
  final Set<String> _restrictedProfiles={};
  String _revalidationKey(int farm,int user) =>
      'offline_revalidation_${Uri.encodeComponent(baseUrl)}_${farm}_$user';
  /// Denial-only durable marker. It cannot authorize or extend a grant.
  Future<void> requirePersonalRevalidation(int farm,int user) async {
    final key=_revalidationKey(farm,user);
    _restrictedProfiles.add(key);
    await secrets.write(key,'blocked');
  }
  /// Read-only observation; never replaces signed offline authorization.
  int get personalEpoch => _personalEpoch;
  void invalidatePendingPersonalWork() { _personalEpoch++; }
  void _ensureCurrent(int epoch, OnlineOperatorIdentity? identity) {
    if (epoch!=_personalEpoch || !identical(personal,identity)) {
      throw StateError('La session personnelle a changé. Recommencer explicitement.');
    }
  }
  void close() { invalidatePendingPersonalWork(); client.close(); }

  Future<Map<String,dynamic>> _send(String method,String path,{Map<String,dynamic>? data,
    Map<String,String>? proof,String? access}) async {
    if (!path.startsWith('/') || path.contains('..') || path.contains('\n')) throw ArgumentError('Chemin invalide.');
    final request=http.Request(method,Uri.parse('$baseUrl$path'));
    request.headers.addAll({'Content-Type':'application/json',if(access!=null)'Authorization':'Bearer $access',...?(proof)});
    if (data!=null) request.body=jsonEncode(data);
    final response=await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds:30)))
        .timeout(const Duration(seconds:30));
    if (response.statusCode<200 || response.statusCode>=300) throw FoundationApiException(response.statusCode,operation:_operation(path));
    if (response.body.isEmpty) return {};
    final decoded=jsonDecode(response.body);
    return decoded is Map<String,dynamic> ? decoded : {'results':decoded};
  }

  String _operation(String path) {
    if(path=='/token/') return 'Connexion personnelle';
    if(path=='/password/change-initial/') return 'Changement du mot de passe initial';
    if(path=='/me/capabilities/') return 'Vérification du rôle';
    if(path=='/offline-policy/enable/') return 'Activation hors ligne';
    if(path=='/offline-authorizations/') return 'Préparation du profil PIN';
    if(path=='/devices/') return 'Enregistrement de la tablette';
    if(path=='/devices/challenge/') return 'Vérification de la tablette';
    return 'Préparation de la tablette';
  }

  Future<void> changeInitialPassword(String token,String password) async {
    final epoch=_personalEpoch;
    final identity=personal;
    await _send('POST','/password/change-initial/',data:{'change_token':token,'new_password':password});
    _ensureCurrent(epoch,identity);
  }

  Future<OnlineOperatorIdentity> logIn(String username,String password,{int? expectedFarm}) async {
    final epoch=++_personalEpoch;
    personal=null;
    final tokens=await _send('POST','/token/',data:{'username':username,'password':password});
    _ensureCurrent(epoch,null);
    if (tokens['password_change_required']==true) {
      throw InitialPasswordRequired(tokens['change_token'] as String);
    }
    final capabilities=await _send('GET','/me/capabilities/',access:tokens['access'] as String);
    _ensureCurrent(epoch,null);
    final farm=capabilities['exploitation'] as int;
    // HTTP extension only. Old servers/grants retain their existing contract.
    if (capabilities.containsKey('permission_contract')) {
      final contract = capabilities['permission_contract'];
      if (contract is! Map<String,dynamic>) throw StateError('Contrat de permissions invalide.');
      PermissionContract.decode(contract,userId:capabilities['user'] as int,farmId:farm,
        role:capabilities['role'] as String,
        rightsVersion:(capabilities['membership'] as Map)['version'] as int);
    }
    if (expectedFarm!=null && expectedFarm!=farm) throw StateError('Ce compte appartient à une autre exploitation.');
    final identity=OnlineOperatorIdentity(userId:capabilities['user'] as int,farmId:farm,
      role:capabilities['role'] as String,capabilities:Map.unmodifiable(capabilities),
      access:tokens['access'] as String,refresh:tokens['refresh'] as String);
    await _saveCredentials(identity);
    _ensureCurrent(epoch,null);
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
    final epoch=_personalEpoch;
    try {
      final response=await _send(method,path,data:data,proof:proof,access:identity.access);
      _ensureCurrent(epoch,identity);
      return response;
    }
    on FoundationApiException catch(error) {
      _ensureCurrent(epoch,identity);
      if(error.status!=401) rethrow;
      _refreshing ??= _refresh(identity);
      try { await _refreshing; } finally { _refreshing=null; }
      if (!identical(personal,identity)) throw const FoundationApiException(401);
      _ensureCurrent(epoch,identity);
      final response=await _send(method,path,data:data,proof:proof,access:identity.access);
      _ensureCurrent(epoch,identity);
      return response;
    }
  }

  Future<void> _refresh(OnlineOperatorIdentity identity) async {
    final epoch=_personalEpoch;
    try {
      final tokens=await _send('POST','/token/refresh/',data:{'refresh':identity.refresh});
      _ensureCurrent(epoch,identity);
      identity.access=tokens['access'] as String;
      if(tokens['refresh'] is String) identity.refresh=tokens['refresh'] as String;
      await _saveCredentials(identity);
      _ensureCurrent(epoch,identity);
    } catch (_) {
      if(epoch==_personalEpoch && identical(personal,identity)) personal=null;
      rethrow;
    }
  }

  /// An unlocked personal-code profile may restore only its own encrypted
  /// credentials. A fresh server refresh and matching credential epoch are
  /// mandatory before any HTTP use. This never signs or fabricates a grant.
  Future<void> restoreAfterPersonalCode(VerifiedOfflineGrant grant) async {
    if(personal!=null || !grant.hasFineContract || grant.credentialVersion==null || !grant.validAt(clock())) {
      throw const FoundationApiException(401);
    }
    final epoch=_personalEpoch;
    final key='personal_credentials_${Uri.encodeComponent(baseUrl)}_${grant.farmId}_${grant.userId}';
    final encoded=await secrets.read(key);
    _ensureCurrent(epoch,null);
    if(encoded==null) throw const FoundationApiException(401);
    final saved=jsonDecode(encoded) as Map;
    final tokens=await _send('POST','/token/refresh/',data:{'refresh':saved['refresh']});
    _ensureCurrent(epoch,null);
    final caps=await _send('GET','/me/capabilities/',access:tokens['access'] as String);
    _ensureCurrent(epoch,null);
    if(caps['user']!=grant.userId || caps['exploitation']!=grant.farmId || caps['role']!='OPERATEUR' ||
       caps['credential_version']!=grant.credentialVersion || caps['membership']['version']!=grant.rightsVersion) {
      throw const FoundationApiException(403);
    }
    final identity=OnlineOperatorIdentity(userId:grant.userId,farmId:grant.farmId,role:'OPERATEUR',
      capabilities:Map.unmodifiable(caps),access:tokens['access'] as String,
      refresh:(tokens['refresh']??saved['refresh']) as String);
    await _saveCredentials(identity);_ensureCurrent(epoch,null);personal=identity;
  }

  Future<Map<String,dynamic>> registerInstallation(String name) async {
    final owner=personal, epoch=_personalEpoch;
    if(owner?.role!='OWNER') throw const FoundationApiException(403);
    final identity=await deviceIdentity.publicIdentity();
    _ensureCurrent(epoch,owner);
    return request('POST','/devices/',data:{'installation_uuid':identity['installation_uuid'],
      'public_key':identity['public_key'],'platform':'ANDROID','display_name':name});
  }

  Future<Map<String,dynamic>> signedRequest(String path,{required int deviceId,
    required String purpose,Map<String,dynamic> data=const {}}) async {
    final identity=personal;
    if(identity==null) throw const FoundationApiException(401);
    final epoch=_personalEpoch;
    final challenge=await request('POST','/devices/challenge/',
      data:{'device_id':deviceId,'purpose':purpose});
    if(!identical(identity,personal)) throw const FoundationApiException(401);
    _ensureCurrent(epoch,identity);
    if(challenge['device_id']!=deviceId || challenge['user_id']!=identity.userId ||
        challenge['purpose']!=purpose || challenge['signature_contract']!='ELEVAGE-DEVICE-V1') {
      throw StateError('Challenge de tablette invalide.');
    }
    final headers=await deviceProofHeaders(identity:deviceIdentity,
      challengeId:challenge['id'] as String,deviceId:deviceId,userId:identity.userId,
      purpose:purpose,method:'POST',pathAndQuery:'${Uri.parse(baseUrl).path}$path',
      body:Uint8List.fromList(utf8.encode(jsonEncode(data))));
    if(!identical(identity,personal)) throw const FoundationApiException(401);
    _ensureCurrent(epoch,identity);
    return request('POST',path,data:data,proof:headers);
  }

  /// Authenticated server observation, never an offline authorization by itself.
  Future<Map<String,dynamic>> personalCapabilities() async {
    final identity=personal, epoch=_personalEpoch;
    if(identity==null) throw const FoundationApiException(401);
    final value=await request('GET','/me/capabilities/');
    _ensureCurrent(epoch,identity);
    if(value['user']!=identity.userId || value['exploitation']!=identity.farmId ||
        value['role']!=identity.role) {
      throw const FoundationApiException(403);
    }
    return value;
  }

  Future<VerifiedOfflineGrant> provisionGrant({bool requireFine=false,
    FutureOr<void> Function(Map<String,dynamic>)? onCapabilities,
    FutureOr<void> Function(VerifiedOfflineGrant)? onVerifiedGrant}) async {
    final identity=personal;
    if(identity==null || identity.role!='OPERATEUR') throw const FoundationApiException(403);
    final epoch=_personalEpoch;
    final capabilities=await personalCapabilities();
    _ensureCurrent(epoch,identity);
    await onCapabilities?.call(capabilities);
    _ensureCurrent(epoch,identity);
    if(capabilities['offline_policy_enabled']!=true) throw StateError('La préparation de cette exploitation doit être activée par son propriétaire.');
    final device=capabilities['primary_device'] as Map<String,dynamic>?;
    if(device==null) throw StateError('Tablette principale requise.');
    final local=await deviceIdentity.publicIdentity();
    _ensureCurrent(epoch,identity);
    if(device['installation_uuid']!=local['installation_uuid']) throw StateError('Cette tablette n’est pas la tablette principale.');
    final extension=capabilities['offline_permission_contract'];
    if(extension != null && (extension is! Map || extension['issuance_enabled'] is! bool ||
        extension['supported_versions'] is! List ||
        (extension['issuance_enabled']==true && !(extension['supported_versions'] as List).contains(2)))) {
      throw StateError('Extension de permissions hors ligne incompatible.');
    }
    final fine=extension is Map && extension['issuance_enabled']==true &&
      extension['supported_versions'] is List && (extension['supported_versions'] as List).contains(2);
    if(requireFine && !fine) throw const FoundationApiException(503);
    final fineMarker='offline_fine_required_${Uri.encodeComponent(baseUrl)}_${identity.farmId}_${identity.userId}';
    if(!fine) {
      final converted=await secrets.read(fineMarker);
      _ensureCurrent(epoch,identity);
      if(converted!=null) {
        throw StateError('Ce profil exige un renouvellement V2 explicite.');
      }
      final previous=await secrets.read('offline_grant_${Uri.encodeComponent(baseUrl)}_${identity.farmId}_${identity.userId}');
      _ensureCurrent(epoch,identity);
      if(previous!=null) {
        // Classification only to refuse a downgrade. It cannot authorize anything.
        // The original token/history remains intact, even if it is now expired.
        try {
          final token=(jsonDecode(previous) as Map)['token'] as String;
          final claims=jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
          if((claims['capabilities'] as Map).containsKey('permission_contract')) {
            throw StateError('Renouvellement du contrat fin requis ; retour V1 interdit.');
          }
        } catch (_) {
          throw StateError('Ce profil exige un renouvellement sûr du contrat signé.');
        }
      }
    }
    final response=await signedRequest('/offline-authorizations/',deviceId:device['id'] as int,purpose:'GRANT',
      data:fine ? {'permission_contract_version':2} : const {});
    _ensureCurrent(epoch,identity);
    final member=capabilities['membership'] as Map<String,dynamic>;
    final grant=await VerifiedOfflineGrant.verify(token:response['authorization'] as String,
      publicKeyPem:response['public_key'] as String,trustedKeyId:response['key_id'] as String,
      farmId:identity.farmId,userId:identity.userId,deviceId:device['id'] as int,
      generation:capabilities['write_generation'] as int,rightsVersion:member['version'] as int,
      now:clock().toUtc());
    _ensureCurrent(epoch,identity);
    if(fine && !grant.hasFineContract) throw StateError('Le serveur a omis le contrat fin demandé.');
    await onVerifiedGrant?.call(grant);
    _ensureCurrent(epoch,identity);
    final grantRecord=jsonEncode({'token':grant.token,'public_key':response['public_key'],'key_id':response['key_id'],
      'device_id':grant.deviceId,'generation':grant.generation,'rights_version':grant.rightsVersion});
    final namespace=Uri.encodeComponent(baseUrl);
    if(grant.hasFineContract) {
      // Denial-only marker survives interruption before history/current pointer.
      // It cannot authorize a write or replace signature verification.
      await secrets.write(fineMarker,'2');
      _ensureCurrent(epoch,identity);
    }
    await secrets.write('offline_grant_history_${namespace}_${grant.claims['jti']}',grantRecord);
    _ensureCurrent(epoch,identity);
    await secrets.write('offline_grant_${namespace}_${grant.farmId}_${grant.userId}',grantRecord);
    _ensureCurrent(epoch,identity);
    final revalidation=_revalidationKey(grant.farmId,grant.userId);
    final blocked=await secrets.read(revalidation);
    _ensureCurrent(epoch,identity);
    if(blocked!=null || _restrictedProfiles.contains(revalidation)) {
      await secrets.write(revalidation,grant.claims['jti'] as String);
      _ensureCurrent(epoch,identity);
      _restrictedProfiles.remove(revalidation);
    }
    return grant;
  }

  Future<VerifiedOfflineGrant> loadLocalGrant({required int farmId,required int userId}) async {
    final key=_revalidationKey(farmId,userId);
    if(_restrictedProfiles.contains(key)) throw StateError('Validation personnelle en ligne requise.');
    final revalidation=await secrets.read(key);
    final encoded=await secrets.read('offline_grant_${Uri.encodeComponent(baseUrl)}_${farmId}_$userId');
    if(encoded==null) throw StateError('Une connexion personnelle est requise pour préparer ce profil.');
    final record=jsonDecode(encoded) as Map<String,dynamic>;
    final grant=await VerifiedOfflineGrant.verify(token:record['token'] as String,
      publicKeyPem:record['public_key'] as String,trustedKeyId:record['key_id'] as String,
      farmId:farmId,userId:userId,deviceId:record['device_id'] as int,
      generation:record['generation'] as int,rightsVersion:record['rights_version'] as int,
      now:clock().toUtc());
    if(revalidation!=null && revalidation!=grant.claims['jti']) {
      throw StateError('Validation personnelle en ligne requise.');
    }
    return grant;
  }
}
