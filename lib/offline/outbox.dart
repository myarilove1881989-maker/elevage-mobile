import 'dart:convert';
import 'dart:math';
import 'offline_grant.dart';

const transportStates={'LOCAL_PENDING','IN_FLIGHT','RETRY_WAIT','SERVER_RECEIVED','TRANSPORT_BLOCKED'};
const businessStates={'UNREVIEWED','WAITING_DEPENDENCY','CONFIRMED','NEEDS_RECONCILIATION','NOT_APPLIED','SUPERSEDED'};
final operationUuidPattern=RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

String newOperationUuid() {
  final random=Random.secure();final bytes=List.generate(16,(_)=>random.nextInt(256));
  bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
  final hex=bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

dynamic freezeJson(dynamic value) {
  if(value is Map) return Map<String,dynamic>.unmodifiable(value.map((key,child)=>MapEntry(key.toString(),freezeJson(child))));
  if(value is List) return List<dynamic>.unmodifiable(value.map(freezeJson));
  return value;
}

String canonicalDeclaration(dynamic value) {
  dynamic sorted(dynamic item) {
    if(item is Map) {
      final keys=item.keys.cast<String>().toList()..sort();
      return {for(final key in keys)key:sorted(item[key])};
    }
    if(item is List) return item.map(sorted).toList();
    return item;
  }
  return jsonEncode(sorted(value));
}

class OutboxEntry {
  OutboxEntry({required Map<String,dynamic> declaration,required this.transportStatus,
    required this.businessStatus,required this.attemptCount,required this.lastError,
    this.retryAt,this.receivedAt,this.appliedAt,this.serverEntityId='',this.serverVersion=''})
    :declaration=freezeJson(declaration) as Map<String,dynamic>;
  final Map<String,dynamic> declaration;
  final String transportStatus,businessStatus,lastError,serverEntityId,serverVersion;
  final int attemptCount;
  final DateTime? retryAt,receivedAt,appliedAt;
  String get operationId=>declaration['client_operation_id'] as String;
  int get authorId=>declaration['author_user_id'] as int;
  int get sequence=>declaration['local_sequence'] as int;
}

abstract interface class OutboxStore {
  Future<OutboxEntry> enqueue({required VerifiedOfflineGrant grant,
    required bool Function() isSessionCurrent,required String entityType,
    required String operationType,required Map<String,dynamic> payload,
    required DateTime businessOccurredAt,String? operationId,String? localEntityId,
    List<String> dependencies=const [],String expectedServerVersion='',
    Future<void> Function()? project});
  Future<List<OutboxEntry>> leasePending({int limit=50});
  Future<List<OutboxEntry>> awaitingReceipts({int limit=50});
  Future<void> acceptReceipts(List<Map<String,dynamic>> receipts);
  Future<void> transportFailure(List<String> operationIds,{required String code,bool blocked=false});
  Future<List<OutboxEntry>> listOutbox({int? authorId,int limit=50,int offset=0});
}
