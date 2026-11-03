import 'outbox.dart';
import 'tablet_controller.dart';
import 'feed_stock_projection.dart';

bool supportsFeedStock(TabletController tablet)=>tablet.operators?.session?.grant.hasFineContract==true &&
  (tablet.operators!.session!.grant.claims['capabilities'] as Map)['feed_stock_contract']==1;

Future<Map<String,dynamic>> localFeedCatalog(TabletController tablet) async {
  final session=tablet.operators?.session,cache=tablet.cache;
  if(session==null || cache==null || cache is! OutboxStore || !supportsFeedStock(tablet))throw StateError('Renouvelez l’accès hors ligne pour utiliser les stocks.');
  final pages=await cache.cachedPage('feed_stock',limit:1);
  if(pages.isEmpty)throw StateError('Chargez une première fois le stock avec Internet.');
  final originals=<OutboxEntry>[];
  for(var offset=0;;offset+=200) {
    final batch=await (cache as OutboxStore).listOutbox(offset:offset,limit:200);originals.addAll(batch);
    if(batch.length<200)break;
  }
  final projected=projectFeedStock(Map<String,dynamic>.from(pages.single['data'] as Map),originals,session.grant.farmId);
  final species=<dynamic>[],lots=<dynamic>[];
  for(final collection in ['species','lots']) {
    for(var offset=0;;offset+=200) {
      final batch=await cache.cachedPage(collection,offset:offset,limit:200);
      for(final row in batch) {
        final data=Map<String,dynamic>.from(row['data'] as Map);
        if(collection=='species')species.add(data);
        else if(data['date_fin']==null && data['statut_production']!='TERMINE')lots.add({...data,'espece_id':data['espece']});
      }
      if(batch.length<200)break;
    }
  }
  if(!identical(session,tablet.operators?.session) || !identical(cache,tablet.cache))throw StateError('Profil verrouillé pendant la lecture.');
  return {...projected,'species':species,'lots':lots};
}

Future<List<Map<String,dynamic>>> localFeedHistory(TabletController tablet,Uri uri,Object? baseline) async {
  final session=tablet.operators?.session,cache=tablet.cache;
  if(session==null || cache==null || cache is! OutboxStore)throw StateError('Profil personnel ouvert requis.');
  final result=<Map<String,dynamic>>[if(baseline is List)for(final row in baseline)Map<String,dynamic>.from(row as Map)];
  final cancelled=<Object?>{};
  int version(Map row)=>int.tryParse((row['physical_stock']?['distribution_version']??'').toString().split(':').last)??0;
  for(var offset=0;;offset+=200) {
    final batch=await cache.cachedPage('feed_distributions',offset:offset,limit:200);
    for(final row in batch) {
      final item=Map<String,dynamic>.from(row['data'] as Map);
      if(item['exploitation']!=session.grant.farmId)throw StateError('Historique hors exploitation.');
      if(item['voided']==true){cancelled.add(item['id']);result.removeWhere((r)=>r['id']==item['id']);continue;}
      final index=result.indexWhere((r)=>r['id']==item['id']);
      if(index<0)result.add(item);else if(version(item)>=version(result[index]))result[index]=item;
    }
    if(batch.length<200)break;
  }
  final entries=<OutboxEntry>[];
  for(var offset=0;;offset+=200) {
    final batch=await (cache as OutboxStore).listOutbox(offset:offset,limit:200);entries.addAll(batch);
    if(batch.length<200)break;
  }
  entries.sort((a,b)=>a.sequence.compareTo(b.sequence));
  for(final row in entries) {
    final d=row.declaration,p=d['payload'] as Map;
    if(d['entity_type']!='ALIMENTATION' || p['stock_version']!=1 || d['operation_type']!='CREATE' ||
        {'NOT_APPLIED','SUPERSEDED'}.contains(row.businessStatus))continue;
    final lot=(p['lot_ref'] as Map)['server_id'];
    if(uri.queryParameters['lot']!=null && '$lot'!=uri.queryParameters['lot'])continue;
    final server=int.tryParse(row.serverEntityId);
    if(cancelled.contains(server))continue;
    if(result.any((r)=>(server!=null && r['id']==server) || r['_local_uuid']==d['local_entity_id']))continue;
    result.add({'id':server??d['local_entity_id'],'_local_uuid':d['local_entity_id'],'lot':lot,
      'aliment':'Aliment du référentiel','quantite_kg':p['quantite_kg'],'distribution_at':d['business_occurred_at'],
      'date':(d['business_occurred_at'] as String).split('T').first,'note':p['note']??'',
      'local_only':row.businessStatus!='CONFIRMED','_review_required':row.businessStatus=='NEEDS_RECONCILIATION',
      'physical_stock':{'product':p['product'],'source_lot':p['source_lot']},'local_state':row.businessStatus});
  }
  if(!identical(session,tablet.operators?.session))throw StateError('Profil verrouillé pendant la lecture.');
  return result.where((row)=>uri.queryParameters['lot']==null || '${row['lot']}'==uri.queryParameters['lot']).toList();
}
