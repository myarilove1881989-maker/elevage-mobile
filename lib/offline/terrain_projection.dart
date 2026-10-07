import 'dart:convert';
import 'package:drift/drift.dart';
import 'outbox.dart';
import 'terrain_store.dart';

/// Projection is derived from the immutable ledger, so it cannot precede its commit.
mixin TerrainProjection on GeneratedDatabase implements TerrainStore {
  Future<void> createTerrainMappings() async {
    await customStatement('CREATE TABLE terrain_entity_mapping ('
      'entity_type TEXT NOT NULL,local_entity_id TEXT NOT NULL,server_entity_id INTEGER NOT NULL CHECK(server_entity_id>0),'
      'operation_id TEXT NOT NULL REFERENCES outbox(operation_id),PRIMARY KEY(entity_type,local_entity_id))');
  }

  Future<void> projectReceipt(Map<String,dynamic> receipt) async {
    final mappings=receipt['entity_mappings']??const [];
    if(mappings is! List || mappings.length>10) {throw StateError('Correspondances serveur invalides.');}
    if(mappings.isNotEmpty && receipt['business_status']!='CONFIRMED') {throw StateError('Correspondance non confirmée.');}
    final operation=await customSelect('SELECT declaration FROM outbox WHERE operation_id=?',
      variables:[Variable(receipt['client_operation_id'] as String)]).getSingle();
    final declaration=jsonDecode(operation.read<String>('declaration')) as Map;
    final allowed=const {'CLIENT':{'CLIENT'},'ACHAT':{'ACHAT','LOT'},'NAISSANCE':{'NAISSANCE','LOT'}}[declaration['entity_type']]??const <String>{};
    for(final item in mappings) {
      if(item is! Map || item['entity_type'] is! String ||
        !allowed.contains(item['entity_type']) ||
        item['local_entity_id']!=declaration['local_entity_id'] ||
        item['local_entity_id'] is! String || !operationUuidPattern.hasMatch(item['local_entity_id'] as String) ||
        item['server_entity_id'] is! int || (item['server_entity_id'] as int)<1) {throw StateError('Correspondance hors déclaration.');}
      final previous=await customSelect('SELECT server_entity_id FROM terrain_entity_mapping WHERE entity_type=? AND local_entity_id=?',
        variables:[Variable(item['entity_type'] as String),Variable(item['local_entity_id'] as String)]).getSingleOrNull();
      if(previous!=null && previous.read<int>('server_entity_id')!=item['server_entity_id']) {throw StateError('Correspondance serveur contradictoire.');}
      await customStatement('INSERT OR IGNORE INTO terrain_entity_mapping VALUES(?,?,?,?)',
        [item['entity_type'],item['local_entity_id'],item['server_entity_id'],receipt['client_operation_id']]);
    }
  }

  @override
  Future<List<Map<String,dynamic>>> projectedPage(String collection,{int offset=0,int limit=50,int? taskUserId}) async {
    if(!{'clients','tasks'}.contains(collection) || offset<0 || limit<1 || limit>200 ||
      (collection=='tasks' && (taskUserId==null || taskUserId<1))) {throw ArgumentError('Page terrain invalide.');}
    if(collection=='clients') {
      final rows=await customSelect("SELECT payload AS data,'CONFIRMED_CACHE' AS state,NULL AS operation_id,NULL AS local_uuid,received_at FROM confirmed_cache WHERE collection='clients' "
        "UNION ALL SELECT json_set(json_extract(o.declaration,'\$.payload'),'\$.id',COALESCE(m.server_entity_id,json_extract(o.declaration,'\$.local_entity_id'))) AS data,"
        "o.business_status AS state,o.operation_id,json_extract(o.declaration,'\$.local_entity_id') AS local_uuid,o.received_at "
        "FROM outbox o LEFT JOIN terrain_entity_mapping m ON m.entity_type='CLIENT' AND m.local_entity_id=json_extract(o.declaration,'\$.local_entity_id') "
        "WHERE json_extract(o.declaration,'\$.entity_type')='CLIENT' AND json_extract(o.declaration,'\$.operation_type')='CREATE' "
        "AND o.business_status NOT IN ('NOT_APPLIED','SUPERSEDED') AND NOT EXISTS(SELECT 1 FROM confirmed_cache c WHERE c.collection='clients' AND c.entity_id=CAST(m.server_entity_id AS TEXT)) "
        'ORDER BY data LIMIT ? OFFSET ?',variables:[Variable(limit),Variable(offset)]).get();
      return rows.map((row)=>{'data':jsonDecode(row.read<String>('data')),'state':row.read<String>('state'),
        'operation_id':row.readNullable<String>('operation_id'),'local_uuid':row.readNullable<String>('local_uuid'),
        'confirmed_received_at':row.readNullable<int>('received_at')}).toList();
    }
    final rows=await customSelect("SELECT payload,received_at FROM confirmed_cache WHERE collection='tasks' AND "
      "(json_extract(payload,'\$.assigned_to') IS NULL OR json_extract(payload,'\$.assigned_to')=?) ORDER BY entity_id LIMIT ? OFFSET ?",
      variables:[Variable(taskUserId!),Variable(limit),Variable(offset)]).get();
    final result=<Map<String,dynamic>>[];
    for(final row in rows) {
      final data=Map<String,dynamic>.from(jsonDecode(row.read<String>('payload')) as Map);
      var state='CONFIRMED_CACHE';String? dependency;
      final operations=await customSelect("SELECT declaration,business_status,operation_id FROM outbox WHERE author_user_id=? "
        "AND json_extract(declaration,'\$.entity_type')='TASK' AND json_extract(declaration,'\$.payload.task_id')=? "
        "AND business_status NOT IN ('NOT_APPLIED','SUPERSEDED') ORDER BY local_sequence",
        variables:[Variable(taskUserId),Variable(data['id'] as int)]).get();
      for(final operation in operations) {
        final declaration=jsonDecode(operation.read<String>('declaration')) as Map;
        final expected=int.tryParse(declaration['expected_server_version'] as String);
        if(expected==null || (data['version'] as int)>expected) {continue;}
        final payload=declaration['payload'] as Map;
        data['status']=payload['status'];if(payload.containsKey('report')) {data['report']=payload['report'];}
        data['version']=expected+1;state=operation.read<String>('business_status');
        dependency=state=='CONFIRMED'?null:operation.read<String>('operation_id');
      }
      result.add({'data':data,'state':state,'dependency':dependency,'confirmed_received_at':row.read<int>('received_at')});
    }
    return result;
  }
}
