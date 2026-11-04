import 'dart:convert';
import 'package:drift/drift.dart';
import 'outbox.dart';
import 'feed_stock_projection.dart';

/// A confirmed cache row in the existing encrypted database, never another ledger.
mixin FeedCacheSql on GeneratedDatabase {
  Future<void> storeFeedSnapshot(Map<String,dynamic> snapshot,int farm) async {
    validateFeedSnapshot(snapshot,farm);
    final previous=await customSelect("SELECT payload FROM confirmed_cache WHERE collection='feed_stock' AND entity_id='1'").getSingleOrNull();
    if(previous!=null) {
      final old=jsonDecode(previous.read<String>('payload')) as Map;
      if(old['confirmed_business_revision']>snapshot['confirmed_business_revision'])return;
      Map stable(Map row)=>{...row}..remove('as_of')..['products']=[for(final p in row['products'] as List)({...p as Map}..remove('alert_threshold'))];
      if(old['confirmed_business_revision']==snapshot['confirmed_business_revision'] && canonicalDeclaration(stable(old))!=canonicalDeclaration(stable(snapshot))) {
        throw StateError('Instantanés de stock contradictoires.');
      }
      if(old['confirmed_business_revision']==snapshot['confirmed_business_revision']) {
        if(!snapshot.containsKey('as_of') && old.containsKey('as_of'))snapshot['as_of']=old['as_of'];
        final prior={for(final p in old['products'] as List)p['id']:p};
        for(final p in snapshot['products'] as List){if(!p.containsKey('alert_threshold') && prior[p['id']]?.containsKey('alert_threshold')==true)p['alert_threshold']=prior[p['id']]['alert_threshold'];}
      }
    }
    await customStatement("INSERT OR REPLACE INTO confirmed_cache VALUES('feed_stock','1',?,?)",[jsonEncode(snapshot),DateTime.now().toUtc().millisecondsSinceEpoch]);
  }
  Future<void> feedReceipt(Map<String,dynamic> receipt,int farm) async {
    final data=receipt['feed_stock_snapshot'];if(data==null)return;
    if(data is! Map<String,dynamic>)throw StateError('Instantané d’aliment invalide.');
    final original=await customSelect('SELECT declaration FROM outbox WHERE operation_id=?',variables:[Variable(receipt['client_operation_id'] as String)]).getSingle();
    final d=jsonDecode(original.read<String>('declaration')) as Map;
    if((d['payload'] as Map)['stock_version']!=1 || !{'DEPENSE','ALIMENTATION'}.contains(d['entity_type']))throw StateError('Instantané sans déclaration correspondante.');
    await storeFeedSnapshot(data,farm);
    final item=receipt['feed_distribution_snapshot'];
    if(item!=null) {
      if(d['entity_type']!='ALIMENTATION' || item is! Map || item['exploitation']!=farm ||
          item['id'] is! int || '${item['id']}'!=receipt['server_entity_id'] || item['physical_stock'] is! Map || item['voided'] is! bool) {
        throw StateError('Historique de distribution hors contexte.');
      }
      final id='${item['id']}';
      final previous=await customSelect("SELECT payload FROM confirmed_cache WHERE collection='feed_distributions' AND entity_id=?",variables:[Variable(id)]).getSingleOrNull();
      final old=previous==null?null:jsonDecode(previous.read<String>('payload')) as Map;
      if(old==null || (old['confirmed_business_revision'] as int)<=data['confirmed_business_revision']) {
        await customStatement("INSERT OR REPLACE INTO confirmed_cache VALUES('feed_distributions',?,?,?)",[id,
          jsonEncode({...item,'confirmed_business_revision':data['confirmed_business_revision']}),DateTime.now().toUtc().millisecondsSinceEpoch]);
      }
    }
  }
}
