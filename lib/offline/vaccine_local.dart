import 'dart:convert';
import 'package:drift/drift.dart';
import 'outbox.dart';
import 'tablet_controller.dart';

bool supportsVaccines(TabletController tablet)=>tablet.operators?.session?.grant.hasFineContract==true &&
  (tablet.operators!.session!.grant.claims['capabilities'] as Map)['vaccine_stock_contract']==1;

void validateVaccineSnapshot(Map data,int farm) {
  if(data['id']!=1 || data['schema']!=1 || data['exploitation']!=farm || data['vaccine_contract']!=1 ||
      data['confirmed_business_revision'] is! int || data['vials'] is! List || (data['vials'] as List).length>10000 ||
      data['products'] is! List || data['coverage'] is! Map || DateTime.tryParse('${data['as_of']}')==null) {
    throw StateError('Stock vaccinal hors exploitation ou invalide.');
  }
  final ids=<String>{};
  for(final vial in data['vials'] as List) {
    if(vial is! Map || !operationUuidPattern.hasMatch('${vial['id']}') || !ids.add('${vial['id']}') ||
        vial['physical'] is! int || vial['physical']<0 || DateTime.tryParse('${vial['usable_until']}')==null) {
      throw StateError('Flacon invalide.');
    }
  }
}

mixin VaccineCacheSql on GeneratedDatabase {
  Future<void> storeVaccineSnapshot(Map<String,dynamic> data,int farm) async {
    validateVaccineSnapshot(data,farm);
    final previous=await customSelect("SELECT payload FROM confirmed_cache WHERE collection='vaccine_stock' AND entity_id='1'").getSingleOrNull();
    if(previous!=null) {
      final old=jsonDecode(previous.read<String>('payload')) as Map;
      if(old['confirmed_business_revision']>data['confirmed_business_revision'] ||
          (old['confirmed_business_revision']==data['confirmed_business_revision'] && DateTime.parse(old['as_of'] as String).isAfter(DateTime.parse(data['as_of'] as String))))return;
    }
    await customStatement("INSERT OR REPLACE INTO confirmed_cache VALUES('vaccine_stock','1',?,?)",[jsonEncode(data),DateTime.now().toUtc().millisecondsSinceEpoch]);
  }
  Future<void> vaccineReceipt(Map<String,dynamic> receipt,int farm) async {
    final data=receipt['vaccine_stock_snapshot'];if(data==null)return;
    final row=await customSelect('SELECT declaration FROM outbox WHERE operation_id=?',variables:[Variable(receipt['client_operation_id'] as String)]).getSingle();
    final original=jsonDecode(row.read<String>('declaration')) as Map;
    if(original['exploitation_id']!=farm || original['payload']['vaccine_version']!=1 || !{'DEPENSE','VACCINATION'}.contains(original['entity_type']))throw StateError('Reçu vaccinal hors contexte.');
    await storeVaccineSnapshot(Map<String,dynamic>.from(data as Map),farm);
    final item=receipt['vaccination_snapshot'];
    if(item!=null) {
      if(item is! Map || item['exploitation']!=farm || '${item['id']}'!=receipt['server_entity_id'] || item['voided'] is! bool)throw StateError('Historique vaccinal invalide.');
      final id='${item['id']}';
      final previous=await customSelect("SELECT payload FROM confirmed_cache WHERE collection='vaccinations' AND entity_id=?",variables:[Variable(id)]).getSingleOrNull();
      final old=previous==null?null:jsonDecode(previous.read<String>('payload')) as Map;
      int version(Map row)=>int.parse((row['version'] as String).split(':').last);
      if(old==null || version(item)>=version(old))await customStatement("INSERT OR REPLACE INTO confirmed_cache VALUES('vaccinations',?,?,?)",[id,jsonEncode(item),DateTime.now().toUtc().millisecondsSinceEpoch]);
    }
  }
}

Map<String,dynamic> projectVaccines(Map<String,dynamic> data,List<OutboxEntry> originals,int farm,DateTime now) {
  validateVaccineSnapshot(data,farm);
  final vials=[for(final vial in data['vials'] as List)Map<String,dynamic>.from(vial as Map)];
  final pending=<String>[],conflicts=<String>[];
  for(final vial in vials) {vial['confirmed_physical']=vial['physical'];vial['confirmed_usable_until']=vial['usable_until'];vial['confirmed_opened_at']=vial['opened_at'];vial['pending_doses']=0;}
  final ordered=[...originals]..sort((a,b)=>a.sequence.compareTo(b.sequence));
  for(final entry in ordered) {
    final d=entry.declaration,p=d['payload'] as Map;
    if(d['exploitation_id']!=farm)throw StateError('Déclaration hors exploitation.');
    if(p['vaccine_version']!=1)continue;
    if(entry.businessStatus=='NEEDS_RECONCILIATION') {conflicts.add(entry.operationId);continue;}
    if({'NOT_APPLIED','SUPERSEDED'}.contains(entry.businessStatus))continue;
    if(entry.businessStatus!='CONFIRMED')pending.add(entry.operationId);
    final coverage=(data['coverage'] as Map)['${d['device_id']}'] as List? ?? const [];
    if(coverage.any((r)=>entry.sequence>=r[0] && entry.sequence<=r[1]))continue;
    if(d['entity_type']!='VACCINATION' || d['operation_type']!='CREATE')continue;
    for(final allocation in p['allocations'] as List) {
      final matches=vials.where((v)=>v['id']==allocation['vial']).toList();
      if(matches.length!=1)throw StateError('Flacon local non confirmé.');
      final vial=matches.single;
      final amount=(allocation['doses'] as int)+(allocation['lost'] as int? ?? 0);
      vial['pending_doses']=(vial['pending_doses'] as int)+amount;
      if((allocation['doses'] as int)>0 && vial['opened_at']==null) {
        vial['opened_at']=allocation['opened_at']??d['business_occurred_at'];
        final seconds=allocation['usable_seconds'];
        if(seconds!=null) {
          final until=DateTime.parse(vial['opened_at'] as String).add(Duration(seconds:seconds as int));
          if(until.isBefore(DateTime.parse(vial['usable_until'] as String)))vial['usable_until']=until.toIso8601String();
        }
      }
    }
  }
  for(final vial in vials) {
    vial['estimated_physical']=(vial['physical'] as int)-(vial['pending_doses'] as int);
    vial['estimated_usable']=now.isBefore(DateTime.parse(vial['usable_until'] as String))?vial['estimated_physical']:0;
  }
  return {...data,'vials':vials,'local_estimate':true,'pending_operations':pending,'review_operations':conflicts};
}

Future<List<OutboxEntry>> vaccineOriginals(TabletController tablet) async {
  final store=tablet.cache! as OutboxStore,result=<OutboxEntry>[];
  for(var offset=0;;offset+=200) {final page=await store.listOutbox(offset:offset,limit:200);result.addAll(page);if(page.length<200)break;}
  return result;
}
Future<Map<String,dynamic>> localVaccineCatalog(TabletController tablet) async {
  final session=tablet.operators?.session,cache=tablet.cache;
  if(session==null || cache==null || !supportsVaccines(tablet))throw StateError('Renouvelez votre accès hors ligne pour les vaccins.');
  final rows=await cache.cachedPage('vaccine_stock',limit:1);
  if(rows.isEmpty)throw StateError('Chargez les flacons une première fois avec Internet.');
  final result=projectVaccines(Map<String,dynamic>.from(rows.single['data'] as Map),await vaccineOriginals(tablet),session.grant.farmId,tablet.clock().toUtc());
  if(!identical(session,tablet.operators?.session) || !identical(cache,tablet.cache))throw StateError('Profil changé.');
  return result;
}
Future<List<Map<String,dynamic>>> localVaccinationHistory(TabletController tablet,String? lot,Object? baseline) async {
  final session=tablet.operators?.session,cache=tablet.cache;
  if(session==null || cache==null)throw StateError('Profil personnel requis.');
  final rows=<String,Map<String,dynamic>>{if(baseline is List)for(final row in baseline)'${row['id']}':Map<String,dynamic>.from(row as Map)};
  for(var offset=0;;offset+=200) {
    final page=await cache.cachedPage('vaccinations',offset:offset,limit:200);
    for(final row in page) {
      final item=Map<String,dynamic>.from(row['data'] as Map);
      if(item['exploitation']!=session.grant.farmId)throw StateError('Historique hors exploitation.');
      final old=rows['${item['id']}'];
      if(old==null || int.parse('${item['version']}'.split(':').last)>=int.parse('${old['version']}'.split(':').last))rows['${item['id']}']=item;
    }
    if(page.length<200)break;
  }
  for(final entry in await vaccineOriginals(tablet)) {
    final d=entry.declaration,p=d['payload'] as Map;
    if(d['entity_type']!='VACCINATION' || d['operation_type']!='CREATE' || {'NOT_APPLIED','SUPERSEDED'}.contains(entry.businessStatus))continue;
    final id=entry.serverEntityId.isEmpty?entry.operationId:entry.serverEntityId;
    rows.putIfAbsent(id,()=>{'id':id,'lot':p['lot_ref']['server_id'],'vaccine':'Vaccin du référentiel','animals':p['animals'],
      'vaccinated_at':d['business_occurred_at'],'allocations':p['allocations'],'operator':d['author_user_id'],
      'local_only':entry.businessStatus!='CONFIRMED','state':entry.businessStatus,'voided':false});
  }
  if(!identical(session,tablet.operators?.session))throw StateError('Profil changé.');
  return rows.values.where((r)=>lot==null || '${r['lot']}'==lot).toList();
}
