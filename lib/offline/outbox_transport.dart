import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'device_identity.dart';
import 'outbox.dart';

class DeviceTransportException implements Exception {
  const DeviceTransportException(this.status,{this.reasonCode=''});
  final int status;
  final String reasonCode;
  @override
  String toString()=>status==403?'Cette tablette ne peut plus transmettre normalement.':
    'Transmission indisponible. Les déclarations restent conservées.';
}

class DeviceOutboxApi {
  DeviceOutboxApi({required this.baseUrl,required this.identity,required this.deviceId,
    required this.farmId,required this.generation,http.Client? client}) :client=client??http.Client() {
    final uri=Uri.parse(baseUrl);
    if(uri.scheme!='https' || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
      deviceId<1 || farmId<1 || generation<1) throw ArgumentError('Transport appareil HTTPS requis.');
  }
  final String baseUrl;
  final DeviceIdentity identity;
  final int deviceId,farmId,generation;
  final http.Client client;
  void close()=>client.close();

  Future<Map<String,dynamic>> _post(String path,Uint8List body,{Map<String,String> proof=const {}}) async {
    final request=http.Request('POST',Uri.parse('$baseUrl$path'));
    request.headers.addAll({'Content-Type':'application/json',...proof});
    request.bodyBytes=body;
    final response=await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds:30)))
      .timeout(const Duration(seconds:30));
    if(response.statusCode<200 || response.statusCode>=300) {
      var reason='';
      if(response.bodyBytes.length<=4096) {
        try {
          final error=jsonDecode(response.body);
          final detail=error is Map?error['detail']:null;
          if({'DEVICE_CHALLENGE_EXPIRED_OR_USED','ACTIVE_PRIMARY_DEVICE_REQUIRED',
              'DEVICE_TRANSPORT_PROOF_INVALID','DECLARATION_DEVICE_CONTEXT_MISMATCH',
              'ORIGINAL_AUTHORIZATION_CONTEXT_INVALID'}.contains(detail)) reason=detail as String;
        } catch (_) { /* Only bounded, known server codes are retained. */ }
      }
      throw DeviceTransportException(response.statusCode,reasonCode:reason);
    }
    if(response.bodyBytes.length>262144) throw StateError('Réponse de transport trop volumineuse.');
    final decoded=jsonDecode(response.body);
    if(decoded is! Map<String,dynamic>) throw StateError('Réponse de transport invalide.');
    return decoded;
  }

  Future<List<Map<String,dynamic>>> _signed(String purpose,Map<String,dynamic> data) async {
    final public=await identity.publicIdentity();
    final challenge=await _post('/offline/transport-challenge/',Uint8List.fromList(utf8.encode(jsonEncode({
      'device_id':deviceId,'installation_uuid':public['installation_uuid'],'purpose':purpose}))));
    final path=purpose=='RECEIVE'?'/offline/submissions/':'/offline/submissions/status/';
    final fullPath=Uri.parse('$baseUrl$path').path;
    if(challenge['device_id']!=deviceId || challenge['exploitation_id']!=farmId ||
      challenge['device_generation']!=generation || challenge['purpose']!=purpose ||
      challenge['method']!='POST' || challenge['path']!=fullPath ||
      challenge['signature_contract']!='ELEVAGE-DEVICE-TRANSPORT-V1' ||
      challenge['id'] is! String || !operationUuidPattern.hasMatch(challenge['id'] as String)) {
      throw StateError('Défi de transport hors contexte.');
    }
    final body=Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final digest=await Sha256().hash(body);
    final hex=digest.bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    final message='ELEVAGE-DEVICE-TRANSPORT-V1\n${challenge['id']}\n$deviceId\n$farmId\n'
      '$generation\n$purpose\nPOST\n$fullPath\n$hex';
    final response=await _post(path,body,proof:{'X-Elevage-Device':'$deviceId',
      'X-Elevage-Challenge':challenge['id'] as String,
      'X-Elevage-Signature':await identity.sign(Uint8List.fromList(utf8.encode(message)))});
    final receipts=response['receipts'];
    if(receipts is! List || receipts.length>50) throw StateError('Reçus de transport invalides.');
    return receipts.map((r)=>Map<String,dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String,dynamic>>> receive(List<OutboxEntry> entries) {
    if(entries.isEmpty || entries.length>50 || entries.any((entry)=>
      entry.declaration['exploitation_id']!=farmId || entry.declaration['device_id']!=deviceId ||
      entry.declaration['device_generation']!=generation)) throw StateError('Déclarations hors contexte appareil.');
    return _signed('RECEIVE',{'operations':entries.map((entry)=>entry.declaration).toList()});
  }

  Future<List<Map<String,dynamic>>> status(List<String> ids) {
    if(ids.isEmpty || ids.length>50 || ids.any((id)=>!operationUuidPattern.hasMatch(id))) throw ArgumentError('Identifiants de reçus invalides.');
    return _signed('STATUS',{'operation_ids':ids});
  }
}

/// A single flight prevents manual/network triggers from overlapping requests.
class OutboxTransport {
  OutboxTransport({required this.store,required this.api});
  final OutboxStore store;
  final DeviceOutboxApi api;
  Future<void>? _running;
  Future<void> syncOnce() {
    if(_running!=null) return _running!;
    final task=_sync().whenComplete(()=>_running=null);
    _running=task;return task;
  }

  void _validateIds(List<Map<String,dynamic>> receipts,List<String> requested,{required bool complete}) {
    final ids=receipts.map((r)=>r['client_operation_id']).toList();
    if(ids.toSet().length!=ids.length || ids.any((id)=>!requested.contains(id)) ||
      (complete && ids.length!=requested.length)) throw StateError('Reçus ne correspondant pas aux déclarations.');
  }

  Future<void> _sync() async {
    final waiting=await store.awaitingReceipts();
    if(waiting.isNotEmpty) {
      final ids=waiting.map((e)=>e.operationId).toList();
      final receipts=await api.status(ids);
      _validateIds(receipts,ids,complete:false);
      await store.acceptReceipts(receipts);
    }
    final entries=await store.leasePending();
    if(entries.isEmpty) return;
    final ids=entries.map((e)=>e.operationId).toList();
    try {
      final receipts=await api.receive(entries);
      _validateIds(receipts,ids,complete:true);
      await store.acceptReceipts(receipts);
    } on DeviceTransportException catch(error) {
      final expired=error.reasonCode=='DEVICE_CHALLENGE_EXPIRED_OR_USED';
      await store.transportFailure(ids,code:expired?'CHALLENGE_EXPIRED':'HTTP_${error.status}',
        blocked:!expired && {400,401,403,409}.contains(error.status));
      rethrow;
    } catch (_) {
      await store.transportFailure(ids,code:'NETWORK_OR_RECEIPT_FAILURE');
      throw const DeviceTransportException(0);
    }
  }
}
