import 'dart:convert';
import 'package:drift/drift.dart';
import 'offline_grant.dart';
import 'outbox.dart';

mixin OutboxDatabaseMethods on GeneratedDatabase implements OutboxStore {
  int get outboxFarmId;
  DateTime Function() get outboxClock;
  Future<void> applyProjectionReceipt(Map<String,dynamic> receipt) async {}

  Future<void> createOutboxSchema() async {
    await customStatement('CREATE TABLE local_sequence_counter (singleton INTEGER PRIMARY KEY CHECK(singleton=1),next_sequence INTEGER NOT NULL)');
    await customStatement('INSERT INTO local_sequence_counter VALUES(1,1)');
    await customStatement('CREATE TABLE outbox ('
      'operation_id TEXT PRIMARY KEY,local_sequence INTEGER NOT NULL UNIQUE CHECK(local_sequence>0),'
      'farm_id INTEGER NOT NULL CHECK(farm_id=$outboxFarmId),author_user_id INTEGER NOT NULL,'
      'device_id INTEGER NOT NULL,device_generation INTEGER NOT NULL,declaration TEXT NOT NULL CHECK(json_valid(declaration)),'
      "transport_status TEXT NOT NULL CHECK(transport_status IN ('LOCAL_PENDING','IN_FLIGHT','RETRY_WAIT','SERVER_RECEIVED','TRANSPORT_BLOCKED')),"
      "business_status TEXT NOT NULL CHECK(business_status IN ('UNREVIEWED','WAITING_DEPENDENCY','CONFIRMED','NEEDS_RECONCILIATION','NOT_APPLIED','SUPERSEDED')),"
      "attempt_count INTEGER NOT NULL DEFAULT 0,last_error TEXT NOT NULL DEFAULT '',retry_at INTEGER,"
      'created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,received_at INTEGER,applied_at INTEGER,'
      "server_entity_id TEXT NOT NULL DEFAULT '',server_version TEXT NOT NULL DEFAULT '')");
    await customStatement('CREATE INDEX outbox_transport_sequence ON outbox(transport_status,local_sequence)');
    await customStatement('CREATE INDEX outbox_author_sequence ON outbox(author_user_id,local_sequence)');
    await customStatement('CREATE TRIGGER outbox_original_immutable BEFORE UPDATE OF '
      'operation_id,local_sequence,farm_id,author_user_id,device_id,device_generation,declaration,created_at ON outbox '
      "BEGIN SELECT RAISE(ABORT,'Original terrain declaration is immutable'); END");
    await customStatement('CREATE TRIGGER outbox_no_delete BEFORE DELETE ON outbox '
      "BEGIN SELECT RAISE(ABORT,'Terrain history cannot be deleted'); END");
  }

  Future<void> recoverInterruptedOutbox() async {
    final now=outboxClock().toUtc().millisecondsSinceEpoch;
    await customStatement("UPDATE outbox SET transport_status='RETRY_WAIT',last_error='INTERRUPTED_REQUEST',retry_at=?,updated_at=? WHERE transport_status='IN_FLIGHT'",[now,now]);
  }

  void _rejectPayloadSecrets(dynamic value,[int depth=0]) {
    if(depth>16) throw ArgumentError('Déclaration trop profonde.');
    if(value is Map) {
      for(final entry in value.entries) {
        if(RegExp(r'(^|_)(password|pin|jwt|token|private_key|refresh|secret|access|authorization)(_|$)',caseSensitive:false).hasMatch(entry.key.toString())) {
          throw ArgumentError('Secret interdit dans une déclaration terrain.');
        }
        _rejectPayloadSecrets(entry.value,depth+1);
      }
    } else if(value is List) { for(final child in value) { _rejectPayloadSecrets(child,depth+1); } }
  }

  @override
  Future<OutboxEntry> enqueue({required VerifiedOfflineGrant grant,
    required bool Function() isSessionCurrent,required String entityType,required String operationType,
    required Map<String,dynamic> payload,required DateTime businessOccurredAt,String? operationId,
    String? localEntityId,List<String> dependencies=const [],String expectedServerVersion='',
    Future<void> Function()? project}) async {
    final now=outboxClock().toUtc();
    final id=operationId??newOperationUuid();
    final grantId=grant.claims['jti'] as String;
    final entityId=localEntityId??(operationType=='CREATE'?id:null);
    if(grant.farmId!=outboxFarmId || !grant.permits('can_create_terrain_operation',now) ||
      !isSessionCurrent() || !operationUuidPattern.hasMatch(id) || !operationUuidPattern.hasMatch(grantId) ||
      (entityId!=null && !operationUuidPattern.hasMatch(entityId)) ||
      !RegExp(r'^[A-Z][A-Z_]{0,31}$').hasMatch(entityType) ||
      !{'CREATE','UPDATE','CANCEL','REVERSE'}.contains(operationType) || expectedServerVersion.length>100 ||
      dependencies.length>50 || dependencies.toSet().length!=dependencies.length || dependencies.contains(id) ||
      dependencies.any((d)=>!operationUuidPattern.hasMatch(d))) {
      throw StateError('Session ou déclaration terrain invalide.');
    }
    _rejectPayloadSecrets(payload);
    final copied=freezeJson(jsonDecode(jsonEncode(payload)));
    if(utf8.encode(canonicalDeclaration(copied)).length>65536) throw ArgumentError('Déclaration trop volumineuse.');
    final declaration=<String,dynamic>{'client_operation_id':id,'exploitation_id':grant.farmId,
      'author_user_id':grant.userId,'author_membership_id':grant.claims['membership_id'],
      'device_id':grant.deviceId,'device_generation':grant.generation,'offline_authorization_id':grantId,
      'entity_type':entityType,'operation_type':operationType,'local_entity_id':entityId,'payload':copied,
      'dependencies':List<String>.from(dependencies),'expected_server_version':expectedServerVersion,
      'business_occurred_at':businessOccurredAt.toUtc().toIso8601String()};
    return transaction(() async {
      if(!isSessionCurrent() || !grant.permits('can_create_terrain_operation',outboxClock())) throw StateError('Profil verrouillé.');
      final previous=await customSelect('SELECT * FROM outbox WHERE operation_id=?',variables:[Variable(id)]).getSingleOrNull();
      if(previous!=null) {
        final original=Map<String,dynamic>.from(jsonDecode(previous.read<String>('declaration')) as Map);
        original.remove('local_sequence');original.remove('local_recorded_at');
        if(canonicalDeclaration(original)!=canonicalDeclaration(declaration)) throw StateError('UUID déjà utilisé pour une autre déclaration.');
        return _entry(previous);
      }
      final counter=await customSelect('SELECT next_sequence FROM local_sequence_counter WHERE singleton=1').getSingle();
      final sequence=counter.read<int>('next_sequence');
      await customStatement('UPDATE local_sequence_counter SET next_sequence=next_sequence+1 WHERE singleton=1');
      declaration['local_sequence']=sequence;declaration['local_recorded_at']=now.toIso8601String();
      await customStatement('INSERT INTO outbox(operation_id,local_sequence,farm_id,author_user_id,device_id,device_generation,declaration,transport_status,business_status,created_at,updated_at) '
        "VALUES(?,?,?,?,?,?,?,'LOCAL_PENDING','UNREVIEWED',?,?)",[id,sequence,grant.farmId,grant.userId,grant.deviceId,grant.generation,
          canonicalDeclaration(declaration),now.millisecondsSinceEpoch,now.millisecondsSinceEpoch]);
      if(project!=null) await project();
      if(!isSessionCurrent() || !grant.permits('can_create_terrain_operation',outboxClock())) throw StateError('Profil verrouillé pendant la déclaration.');
      return _entry(await customSelect('SELECT * FROM outbox WHERE operation_id=?',variables:[Variable(id)]).getSingle());
    });
  }

  OutboxEntry _entry(QueryRow row) {
    DateTime? date(String key) {final value=row.readNullable<int>(key);return value==null?null:DateTime.fromMillisecondsSinceEpoch(value,isUtc:true);}
    return OutboxEntry(declaration:Map<String,dynamic>.from(jsonDecode(row.read<String>('declaration')) as Map),
      transportStatus:row.read<String>('transport_status'),businessStatus:row.read<String>('business_status'),
      attemptCount:row.read<int>('attempt_count'),lastError:row.read<String>('last_error'),retryAt:date('retry_at'),
      receivedAt:date('received_at'),appliedAt:date('applied_at'),serverEntityId:row.read<String>('server_entity_id'),serverVersion:row.read<String>('server_version'));
  }

  @override
  Future<List<OutboxEntry>> leasePending({int limit=50})=>transaction(() async {
    if(limit<1 || limit>50) throw ArgumentError('Lot de transport invalide.');
    final now=outboxClock().toUtc().millisecondsSinceEpoch;
    final rows=await customSelect("SELECT * FROM outbox WHERE transport_status='LOCAL_PENDING' OR (transport_status='RETRY_WAIT' AND retry_at<=?) ORDER BY local_sequence LIMIT ?",variables:[Variable(now),Variable(limit)]).get();
    final result=<OutboxEntry>[];
    for(final row in rows) {
      final id=row.read<String>('operation_id');
      await customStatement("UPDATE outbox SET transport_status='IN_FLIGHT',attempt_count=attempt_count+1,updated_at=? WHERE operation_id=?",[now,id]);
      result.add(_entry(await customSelect('SELECT * FROM outbox WHERE operation_id=?',variables:[Variable(id)]).getSingle()));
    }
    return result;
  });

  @override
  Future<List<OutboxEntry>> awaitingReceipts({int limit=50}) async {
    if(limit<1 || limit>50) throw ArgumentError('Page invalide.');
    final rows=await customSelect("SELECT * FROM outbox WHERE transport_status='SERVER_RECEIVED' AND business_status NOT IN ('CONFIRMED','NOT_APPLIED','SUPERSEDED') ORDER BY updated_at,local_sequence LIMIT ?",variables:[Variable(limit)]).get();
    return rows.map(_entry).toList();
  }

  @override
  Future<void> acceptReceipts(List<Map<String,dynamic>> receipts)=>transaction(() async {
    if(receipts.length>50) throw ArgumentError('Lot de reçus invalide.');
    for(final receipt in receipts) {
      final id=receipt['client_operation_id'];
      if(id is! String || !operationUuidPattern.hasMatch(id) || receipt['transport_status']!='SERVER_RECEIVED' || !businessStates.contains(receipt['business_status'])) throw StateError('Reçu serveur invalide.');
      final row=await customSelect('SELECT * FROM outbox WHERE operation_id=?',variables:[Variable(id)]).getSingleOrNull();
      if(row==null || row.read<int>('author_user_id')!=receipt['author_user_id']) throw StateError('Reçu hors contexte.');
      if({'CONFIRMED','NOT_APPLIED','SUPERSEDED'}.contains(row.read<String>('business_status')) &&
        {'UNREVIEWED','WAITING_DEPENDENCY'}.contains(receipt['business_status'])) throw StateError('Reçu métier obsolète.');
      final reason=receipt['reason_code']??'';
      if(reason is! String || !RegExp(r'^[A-Z0-9_]{0,50}$').hasMatch(reason)) throw StateError('Code métier invalide.');
      final received=DateTime.parse(receipt['received_at'] as String).toUtc();
      final applied=receipt['applied_at']==null?null:DateTime.parse(receipt['applied_at'] as String).toUtc();
      if(receipt['business_status']=='CONFIRMED' && (applied==null || receipt['server_entity_id']==null || receipt['server_entity_id']=='') ) throw StateError('Confirmation métier incomplète.');
      await customStatement("UPDATE outbox SET transport_status='SERVER_RECEIVED',business_status=?,last_error=?,retry_at=NULL,received_at=?,applied_at=?,server_entity_id=?,server_version=?,updated_at=? WHERE operation_id=?",
        [receipt['business_status'],receipt['reason_code']??'',received.millisecondsSinceEpoch,applied?.millisecondsSinceEpoch,
          receipt['server_entity_id']??'',receipt['server_version']??'',outboxClock().toUtc().millisecondsSinceEpoch,id]);
      await applyProjectionReceipt(receipt);
    }
  });

  @override
  Future<void> transportFailure(List<String> operationIds,{required String code,bool blocked=false})=>transaction(() async {
    if(!RegExp(r'^[A-Z0-9_]{1,50}$').hasMatch(code)) throw ArgumentError('Code de transport invalide.');
    final now=outboxClock().toUtc().millisecondsSinceEpoch;
    for(final id in operationIds) {
      final row=await customSelect('SELECT attempt_count,transport_status FROM outbox WHERE operation_id=?',variables:[Variable(id)]).getSingleOrNull();
      if(row==null || row.read<String>('transport_status')!='IN_FLIGHT') continue;
      final attempt=row.read<int>('attempt_count').clamp(1,8).toInt();
      final retry=now+(1<<attempt)*5000;
      await customStatement('UPDATE outbox SET transport_status=?,last_error=?,retry_at=?,updated_at=? WHERE operation_id=?',
        [blocked?'TRANSPORT_BLOCKED':'RETRY_WAIT',code,blocked?null:retry,now,id]);
    }
  });

  @override
  Future<List<OutboxEntry>> listOutbox({int? authorId,int limit=50,int offset=0}) async {
    if(limit<1 || limit>200 || offset<0 || (authorId!=null && authorId<1)) throw ArgumentError('Page invalide.');
    final rows=await customSelect('SELECT * FROM outbox ${authorId==null?'':'WHERE author_user_id=?'} ORDER BY local_sequence DESC LIMIT ? OFFSET ?',
      variables:[if(authorId!=null)Variable(authorId),Variable(limit),Variable(offset)]).get();
    return rows.map(_entry).toList();
  }
}
