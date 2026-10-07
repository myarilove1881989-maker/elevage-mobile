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

  Future<void> createTerrainCash()=>customStatement('CREATE TABLE terrain_cash_recognition ('
    'operation_id TEXT PRIMARY KEY REFERENCES outbox(operation_id),payload TEXT NOT NULL CHECK(json_valid(payload)),server_version TEXT NOT NULL)');

  Future<void> projectReceipt(Map<String,dynamic> receipt) async {
    final mappings=receipt['entity_mappings']??const [];
    if(mappings is! List || mappings.length>10) {throw StateError('Correspondances serveur invalides.');}
    final reversed=receipt['business_status']=='SUPERSEDED' && receipt['decision_action']=='REVERSE' &&
      receipt['decision_version'] is int && (receipt['decision_version'] as int)>0;
    if(mappings.isNotEmpty && receipt['business_status']!='CONFIRMED' && !reversed &&
      !(receipt['business_status']=='NEEDS_RECONCILIATION' && receipt['cash_recognition']!=null)) {
      throw StateError('Correspondance non confirmée.');
    }
    final operation=await customSelect('SELECT declaration FROM outbox WHERE operation_id=?',
      variables:[Variable(receipt['client_operation_id'] as String)]).getSingle();
    final declaration=jsonDecode(operation.read<String>('declaration')) as Map;
    final kind=declaration['entity_type'] as String;
    final allowed=kind=='ACHAT' || kind=='NAISSANCE'?{kind,'LOT'}:{kind};
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
    if(reversed && {'VENTE_ANIMAUX','VENTE_OEUFS'}.contains(kind)) {
      await customStatement("DELETE FROM confirmed_cache WHERE collection='sales' AND "
        "json_extract(payload,'\$.entity_type')=? AND json_extract(payload,'\$.reference_id')=?",
        [kind,int.tryParse((receipt['server_entity_id']??'').toString())]);
    }
    await _projectStockReceipt(receipt,declaration);
    await _projectCashReceipt(receipt,declaration);
  }

  Future<void> _projectCashReceipt(Map<String,dynamic> receipt,Map declaration) async {
    final cash=receipt['cash_recognition'];
    if(cash==null) {
      if(declaration['entity_type']=='ENCAISSEMENT' && receipt['business_status']=='CONFIRMED') {throw StateError('Reconnaissance d’encaissement manquante.');}
      return;
    }
    const allowed={'montant_recu','montant_affecte','montant_a_rapprocher','payment_id','mode'};
    if(declaration['entity_type']!='ENCAISSEMENT' || cash is! Map || cash.length!=allowed.length ||
      cash.keys.any((key)=>!allowed.contains(key)) || !{'CONFIRMED','NEEDS_RECONCILIATION'}.contains(receipt['business_status']) ||
      cash['payment_id'] is! int || (cash['payment_id'] as int)<1 || cash['mode']!=(declaration['payload'] as Map)['mode']) {
      throw StateError('Reconnaissance d’encaissement invalide.');
    }
    final original=moneyCents((declaration['payload'] as Map)['montant_recu']);
    final received=moneyCents(cash['montant_recu']);
    final assigned=moneyCents(cash['montant_affecte']);final remaining=moneyCents(cash['montant_a_rapprocher']);
    if(original==null || original<=BigInt.zero || original!=received || assigned==null || remaining==null ||
      assigned+remaining!=received || (remaining>BigInt.zero && receipt['business_status']=='CONFIRMED')) {
      throw StateError('Le montant reçu ne correspond pas à son rapprochement.');
    }
    final previous=await customSelect('SELECT payload,server_version FROM terrain_cash_recognition WHERE operation_id=?',
      variables:[Variable(receipt['client_operation_id'] as String)]).getSingleOrNull();
    if(previous!=null) {
      final prior=jsonDecode(previous.read<String>('payload')) as Map;
      if(prior['payment_id']!=cash['payment_id']) {throw StateError('Un encaissement ne peut pas créer un deuxième paiement.');}
      if(previous.read<String>('server_version')==(receipt['server_version']??'') && allowed.any((key)=>prior[key]!=cash[key])) {
        throw StateError('Rapprochement contradictoire pour une même révision.');
      }
    }
    await customStatement('INSERT OR REPLACE INTO terrain_cash_recognition VALUES(?,?,?)',
      [receipt['client_operation_id'],jsonEncode(cash),receipt['server_version']??'']);
  }

  Future<void> _projectStockReceipt(Map<String,dynamic> receipt,Map declaration) async {
    const stockKinds={'ACHAT','NAISSANCE','MORTALITE','DON','VOL','COLLECTE_OEUFS','VENTE_ANIMAUX','VENTE_OEUFS'};
    final snapshots=receipt['stock_snapshots']??const [];
    if(snapshots is! List || snapshots.length>1 ||
      (snapshots.isNotEmpty && (!stockKinds.contains(declaration['entity_type']) ||
        (receipt['business_status']!='CONFIRMED' && !(receipt['business_status']=='SUPERSEDED' && receipt['decision_action']=='REVERSE')))) ||
      (stockKinds.contains(declaration['entity_type']) && receipt['business_status']=='CONFIRMED' && snapshots.length!=1)) {
      throw StateError('Stock confirmé hors déclaration.');
    }
    if(snapshots.isEmpty) {return;}
    int? lotId;
    if({'ACHAT','NAISSANCE'}.contains(declaration['entity_type'])) {
      final mapping=await customSelect("SELECT server_entity_id FROM terrain_entity_mapping WHERE entity_type='LOT' AND local_entity_id=?",
        variables:[Variable(declaration['local_entity_id'] as String)]).getSingleOrNull();
      lotId=mapping?.read<int>('server_entity_id');
    } else {
      final ref=(declaration['payload'] as Map)['lot_ref'];
      if(ref is Map && ref['server_id'] is int) {lotId=ref['server_id'] as int;}
      else if(ref is Map && ref['local_uuid'] is String) {
        final mapping=await customSelect("SELECT server_entity_id FROM terrain_entity_mapping WHERE entity_type='LOT' AND local_entity_id=?",
          variables:[Variable(ref['local_uuid'] as String)]).getSingleOrNull();
        lotId=mapping?.read<int>('server_entity_id');
      }
    }
    const allowed={'id','nom','espece','espece_nom','exploitation','date_debut','date_fin','prix_vente_prevu',
      'type_production','statut_production','date_naissance','age_arrivee_semaines','date_debut_ponte',
      'date_creation','created_by','stock','stock_oeufs','confirmed_business_revision'};
    final snapshot=snapshots.single;
    if(snapshot is! Map || snapshot.keys.any((key)=>!allowed.contains(key)) || lotId==null ||
      snapshot['id']!=lotId || snapshot['exploitation']!=declaration['exploitation_id'] ||
      snapshot['stock'] is! int || (snapshot['stock'] as int)<0 ||
      snapshot['stock_oeufs'] is! int || (snapshot['stock_oeufs'] as int)<0 ||
      snapshot['confirmed_business_revision'] is! int || (snapshot['confirmed_business_revision'] as int)<0) {
      throw StateError('Stock serveur invalide ou hors exploitation.');
    }
    final existing=await customSelect("SELECT payload FROM confirmed_cache WHERE collection='lots' AND entity_id=?",
      variables:[Variable('$lotId')]).getSingleOrNull();
    if(existing!=null) {
      final previous=jsonDecode(existing.read<String>('payload')) as Map;
      final revision=previous['confirmed_business_revision']??0;
      if(revision is! int) {throw StateError('Révision de stock invalide.');}
      if(revision>snapshot['confirmed_business_revision']) {return;}
      if(revision==snapshot['confirmed_business_revision'] &&
        (previous['stock']!=snapshot['stock'] || (previous['stock_oeufs']??0)!=snapshot['stock_oeufs'])) {
        throw StateError('Stock contradictoire pour une même révision.');
      }
    }
    await customStatement("INSERT OR REPLACE INTO confirmed_cache VALUES('lots',?,?,?)",
      ['$lotId',jsonEncode(snapshot),DateTime.now().toUtc().millisecondsSinceEpoch]);
  }

  @override
  Future<List<Map<String,dynamic>>> projectedPage(String collection,{int offset=0,int limit=50,int? taskUserId,String search=''}) async {
    if(!{'clients','tasks','lots','sales','cash'}.contains(collection) || offset<0 || limit<1 || limit>200 || search.length>100 ||
      (collection=='tasks' && (taskUserId==null || taskUserId<1))) {throw ArgumentError('Page terrain invalide.');}
    if(collection=='lots') {return _projectedLots(offset,limit,search);}
    if(collection=='sales') {return _projectedSales(offset,limit,search);}
    if(collection=='cash') {
      final rows=await customSelect("SELECT o.declaration,o.business_status,c.payload FROM outbox o LEFT JOIN terrain_cash_recognition c ON c.operation_id=o.operation_id "
        "WHERE json_extract(o.declaration,'\$.entity_type')='ENCAISSEMENT' ORDER BY o.local_sequence DESC LIMIT ? OFFSET ?",
        variables:[Variable(limit),Variable(offset)]).get();
      return rows.map((row) {
        final declaration=jsonDecode(row.read<String>('declaration')) as Map;
        final data=Map<String,dynamic>.from(declaration['payload'] as Map)..['nom']='Encaissement terrain';
        final recognized=row.readNullable<String>('payload');
        if(recognized!=null) {data.addAll(Map<String,dynamic>.from(jsonDecode(recognized) as Map));}
        return <String,dynamic>{'data':data,'state':row.read<String>('business_status')};
      }).toList();
    }
    if(collection=='clients') {
      final pattern='%${search.replaceAll('\\','\\\\').replaceAll('%','\\%').replaceAll('_','\\_')}%';
      final rows=await customSelect("SELECT * FROM (SELECT payload AS data,'CONFIRMED_CACHE' AS state,NULL AS operation_id,NULL AS local_uuid,received_at FROM confirmed_cache WHERE collection='clients' "
        "UNION ALL SELECT json_set(json_extract(o.declaration,'\$.payload'),'\$.id',COALESCE(m.server_entity_id,json_extract(o.declaration,'\$.local_entity_id'))) AS data,"
        "o.business_status AS state,o.operation_id,json_extract(o.declaration,'\$.local_entity_id') AS local_uuid,o.received_at "
        "FROM outbox o LEFT JOIN terrain_entity_mapping m ON m.entity_type='CLIENT' AND m.local_entity_id=json_extract(o.declaration,'\$.local_entity_id') "
        "WHERE json_extract(o.declaration,'\$.entity_type')='CLIENT' AND json_extract(o.declaration,'\$.operation_type')='CREATE' "
        "AND o.business_status NOT IN ('NOT_APPLIED','SUPERSEDED') AND NOT EXISTS(SELECT 1 FROM confirmed_cache c WHERE c.collection='clients' AND c.entity_id=CAST(m.server_entity_id AS TEXT)) "
        ") WHERE json_extract(data,'\$.nom') LIKE ? ESCAPE '\\' ORDER BY data LIMIT ? OFFSET ?",variables:[Variable(pattern),Variable(limit),Variable(offset)]).get();
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

  Future<List<Map<String,dynamic>>> _projectedSales(int offset,int limit,String clientSearch) async {
    final rows=await customSelect("SELECT * FROM (SELECT payload AS data,'CONFIRMED_CACHE' AS state,NULL AS operation_id,NULL AS local_uuid FROM confirmed_cache c WHERE collection='sales' "
      "AND NOT EXISTS(SELECT 1 FROM terrain_entity_mapping m JOIN outbox o ON o.operation_id=m.operation_id "
      "WHERE o.business_status='SUPERSEDED' AND m.entity_type=json_extract(c.payload,'\$.entity_type') AND m.server_entity_id=json_extract(c.payload,'\$.reference_id')) "
      "UNION ALL SELECT json_set(json_extract(o.declaration,'\$.payload'),'\$.id',COALESCE(m.server_entity_id,json_extract(o.declaration,'\$.local_entity_id')),"
      "'\$.reference_id',COALESCE(m.server_entity_id,json_extract(o.declaration,'\$.local_entity_id')),'\$.entity_type',json_extract(o.declaration,'\$.entity_type'),"
      "'\$.client_id',COALESCE(json_extract(o.declaration,'\$.payload.client_ref.server_id'),cm.server_entity_id,json_extract(o.declaration,'\$.payload.client_ref.local_uuid'))) AS data,"
      "o.business_status AS state,o.operation_id,json_extract(o.declaration,'\$.local_entity_id') AS local_uuid FROM outbox o "
      "LEFT JOIN terrain_entity_mapping m ON m.entity_type=json_extract(o.declaration,'\$.entity_type') AND m.local_entity_id=json_extract(o.declaration,'\$.local_entity_id') "
      "LEFT JOIN terrain_entity_mapping cm ON cm.entity_type='CLIENT' AND cm.local_entity_id=json_extract(o.declaration,'\$.payload.client_ref.local_uuid') "
      "WHERE json_extract(o.declaration,'\$.entity_type') IN ('VENTE_ANIMAUX','VENTE_OEUFS') AND json_extract(o.declaration,'\$.operation_type')='CREATE' "
      "AND o.business_status NOT IN ('NOT_APPLIED','SUPERSEDED') AND NOT EXISTS(SELECT 1 FROM confirmed_cache c WHERE c.collection='sales' "
      "AND json_extract(c.payload,'\$.entity_type')=m.entity_type AND json_extract(c.payload,'\$.reference_id')=m.server_entity_id)) "
      "WHERE (?='' OR CAST(json_extract(data,'\$.client_id') AS TEXT)=?) ORDER BY data LIMIT ? OFFSET ?",
      variables:[Variable(clientSearch),Variable(clientSearch),Variable(limit),Variable(offset)]).get();
    return rows.map((row) {
      final data=Map<String,dynamic>.from(jsonDecode(row.read<String>('data')) as Map);
      final kind=data['entity_type'];
      data['nom']='${kind=='VENTE_OEUFS'?'Vente d’œufs':'Vente animaux'} ${data['reference_id']}';
      if(data['montant_total']==null) {
        final count=kind=='VENTE_OEUFS'?data['conditionnement']=='COMPOSE'?1:data['nombre_conditionnements']:data['quantite'];
        final price=moneyCents(kind=='VENTE_OEUFS'?data['conditionnement']=='COMPOSE'?data['prix_total']:data['prix_unitaire_conditionnement']:data['prix_unitaire']);
        if(count is int && price!=null) {
          final total=price*BigInt.from(count);
          data['montant_total']='${total~/BigInt.from(100)}.${(total%BigInt.from(100)).toString().padLeft(2,'0')}';
        }
      }
      return <String,dynamic>{'data':data,'state':row.read<String>('state'),'local_uuid':row.readNullable<String>('local_uuid'),
        'dependency':{'CONFIRMED','CONFIRMED_CACHE'}.contains(row.read<String>('state'))?null:row.readNullable<String>('operation_id')};
    }).toList();
  }

  Future<List<Map<String,dynamic>>> _projectedLots(int offset,int limit,String search) async {
    final pattern='%${search.replaceAll('\\','\\\\').replaceAll('%','\\%').replaceAll('_','\\_')}%';
    final rows=await customSelect("SELECT payload AS data,NULL AS declaration,NULL AS operation_id,'CONFIRMED_CACHE' AS state,received_at,'0:'||printf('%020d',CAST(entity_id AS INTEGER)) AS sort_key FROM confirmed_cache WHERE collection='lots' AND json_extract(payload,'\$.nom') LIKE ? ESCAPE '\\' "
      "UNION ALL SELECT NULL AS data,declaration,operation_id,business_status AS state,received_at,'1:'||operation_id AS sort_key FROM outbox "
      "WHERE json_extract(declaration,'\$.entity_type') IN ('ACHAT','NAISSANCE') AND json_extract(declaration,'\$.operation_type')='CREATE' "
      "AND (json_extract(declaration,'\$.entity_type')='ACHAT' OR json_extract(declaration,'\$.payload.total_naissances')>json_extract(declaration,'\$.payload.mort_nes')) "
      "AND COALESCE(json_extract(declaration,'\$.payload.nom_lot'),json_extract(declaration,'\$.payload.nom_nouveau_lot')) LIKE ? ESCAPE '\\' "
      "AND business_status NOT IN ('CONFIRMED','NOT_APPLIED','SUPERSEDED') ORDER BY sort_key LIMIT ? OFFSET ?",
      variables:[Variable(pattern),Variable(pattern),Variable(limit),Variable(offset)]).get();
    final result=<Map<String,dynamic>>[];
    for(final row in rows) {
      final encoded=row.readNullable<String>('data');
      Map<String,dynamic> data;String? localId;String? dependency;
      var incoming=0;
      if(encoded!=null) {
        data=Map<String,dynamic>.from(jsonDecode(encoded) as Map);
        final mapping=await customSelect("SELECT local_entity_id FROM terrain_entity_mapping WHERE entity_type='LOT' AND server_entity_id=?",
          variables:[Variable(data['id'] as int)]).getSingleOrNull();
        localId=mapping?.read<String>('local_entity_id');
      }
      else {
        final declaration=jsonDecode(row.read<String>('declaration')) as Map;
        final payload=declaration['payload'] as Map;
        localId=declaration['local_entity_id'] as String;
        incoming=declaration['entity_type']=='ACHAT'?_quantity(payload['quantite']):
          _quantity(payload['total_naissances'])-_quantity(payload['mort_nes']);
        data={'id':localId,'nom':payload['nom_lot']??payload['nom_nouveau_lot']??'Lot provisoire',
          'type_production':payload['type_production']??'CHAIR','stock':0,'stock_oeufs':0,
          'espece':payload['espece'],'confirmed_business_revision':0};
        dependency=row.read<String>('operation_id');
      }
      var delta=incoming;var eggDelta=0;var reconcile=row.read<String>('state')=='NEEDS_RECONCILIATION';
      final operations=await customSelect("SELECT declaration,business_status FROM outbox WHERE business_status NOT IN ('CONFIRMED','NOT_APPLIED','SUPERSEDED') "
        "AND (json_extract(declaration,'\$.payload.lot_ref.server_id')=? OR json_extract(declaration,'\$.payload.lot_ref.local_uuid')=?) ORDER BY local_sequence",
        variables:[Variable(encoded==null?-1:data['id'] as int),Variable(localId??'')]).get();
      for(final operation in operations) {
        final declaration=jsonDecode(operation.read<String>('declaration')) as Map;
        final payload=declaration['payload'] as Map;
        if({'MORTALITE','DON','VOL','VENTE_ANIMAUX'}.contains(declaration['entity_type'])) {delta-=_quantity(payload['quantite']);}
        if(declaration['entity_type']=='VENTE_OEUFS') {eggDelta-=eggQuantity(payload);}
        if(declaration['entity_type']=='COLLECTE_OEUFS') {
          final collected=payload['nombre_collecte']??(_quantity(payload['nombre_alveoles'])*30+_quantity(payload['oeufs_restants']));
          eggDelta+=_quantity(collected)-_quantity(payload['nombre_casses'])-_quantity(payload['nombre_declasses'])-_quantity(payload['nombre_consommes_donnes']);
        }
        reconcile=reconcile || operation.read<String>('business_status')=='NEEDS_RECONCILIATION';
      }
      data['local_delta']=delta;data['projected_stock']=(data['stock'] as int)+delta;
      data['local_egg_delta']=eggDelta;data['projected_egg_stock']=((data['stock_oeufs']??0) as int)+eggDelta;
      result.add({'data':data,'state':reconcile?'NEEDS_RECONCILIATION':row.read<String>('state'),
        'local_uuid':localId,'dependency':dependency,'confirmed_received_at':row.readNullable<int>('received_at')});
    }
    return result;
  }

  int _quantity(dynamic value)=>value is int?value:int.tryParse(value?.toString()??'')??0;
}

BigInt? moneyCents(dynamic value) {
  if(value is! String || !RegExp(r'^[0-9]{1,10}\.[0-9]{2}$').hasMatch(value)) {return null;}
  return BigInt.parse(value.replaceAll('.',''));
}

int eggQuantity(Map payload) {
  final kind=payload['conditionnement'];
  if(kind=='COMPOSE') {return ((payload['nombre_alveoles']??0) as int)*30+((payload['oeufs_supplementaires']??0) as int);}
  final size={'UNITE':1,'DOUZAINE':12,'PLATEAU':30}[kind]??payload['oeufs_par_conditionnement']??0;
  return ((payload['nombre_conditionnements']??0) as int)*(size as int);
}
