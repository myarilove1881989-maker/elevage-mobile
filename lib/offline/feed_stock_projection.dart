import 'outbox.dart';

BigInt feedMilli(Object? value,{bool signed=false}) {
  final text=value.toString();
  final match=RegExp(signed?r'^(-?)(\d{1,11})(?:\.(\d{1,3}))?$':r'^()(\d{1,11})(?:\.(\d{1,3}))?$').firstMatch(text);
  if(match==null)throw StateError('Quantité d’aliment invalide.');
  final number=BigInt.parse(match[2]!)*BigInt.from(1000)+BigInt.parse((match[3]??'').padRight(3,'0'));
  return match[1]=='-'?-number:number;
}
String feedKg(BigInt milli) {
  final absolute=milli.abs();return '${milli.isNegative?'-':''}${absolute~/BigInt.from(1000)}.${(absolute%BigInt.from(1000)).toString().padLeft(3,'0')}';
}

void validateFeedSnapshot(Map<String,dynamic> snapshot,int farm) {
  if(snapshot['schema']!=1 || snapshot['id']!=1 || snapshot['exploitation']!=farm ||
      snapshot['confirmed_business_revision'] is! int || (snapshot['confirmed_business_revision'] as int)<0 ||
      snapshot['products'] is! List || (snapshot['products'] as List).length>1000 || snapshot['coverage'] is! Map) {
    throw StateError('Instantané de stock hors exploitation ou invalide.');
  }
  final ids=<String>{};
  for(final product in snapshot['products'] as List) {
    if(product is! Map || product['id'] is! String || !operationUuidPattern.hasMatch(product['id'] as String) ||
        !ids.add(product['id'] as String) || product['name'] is! String || product['archived'] is! bool || product['positions'] is! List) {
      throw StateError('Référentiel de stock invalide.');
    }
    final positions=<String>{};
    for(final position in product['positions'] as List) {
      if(position is! Map || position['species_id'] is! int || (position['species_id'] as int)<1 ||
          (position['lot_id']!=null && (position['lot_id'] is! int || (position['lot_id'] as int)<1)) ||
          !positions.add('${position['species_id']}:${position['lot_id']}') || feedMilli(position['kg']).isNegative) {
        throw StateError('Position de stock invalide.');
      }
    }
  }
  for(final entry in (snapshot['coverage'] as Map).entries) {
    if(int.tryParse(entry.key.toString())==null || entry.value is! List)throw StateError('Couverture de stock invalide.');
    var end=0;
    for(final interval in entry.value as List) {
      if(interval is! List || interval.length!=2 || interval[0] is! int || interval[1] is! int ||
          interval[0]<=end || interval[1]<interval[0])throw StateError('Couverture de stock invalide.');
      end=interval[1] as int;
    }
  }
}

/// Pure derivation over the existing immutable outbox. No additional queue.
Map<String,dynamic> projectFeedStock(Map<String,dynamic> snapshot,List<OutboxEntry> originals,int farm) {
  validateFeedSnapshot(snapshot,farm);
  final products=<String,Map<String,dynamic>>{};
  final positions=<String,Map<String,dynamic>>{};
  for(final raw in snapshot['products'] as List) {
    final product=Map<String,dynamic>.from(raw as Map)..['positions']=<Map<String,dynamic>>[];
    products[product['id'] as String]=product;
    for(final rawPosition in raw['positions'] as List) {
      final position=Map<String,dynamic>.from(rawPosition as Map);
      position['pending_kg']='0.000';position['estimated_kg']=position['kg'];
      positions['${product['id']}:${position['species_id']}:${position['lot_id']}']=position;
      (product['positions'] as List).add(position);
    }
  }
  final pending=<String>[],review=<String>[],purchases=<Map<String,dynamic>>[];
  final originalById={for(final row in originals)row.operationId:row};
  final ordered=[...originals]..sort((a,b)=>a.sequence.compareTo(b.sequence));
  for(final row in ordered) {
    final d=row.declaration,p=d['payload'] as Map;
    if(d['exploitation_id']!=farm)throw StateError('Déclaration d’une autre exploitation.');
    if(p['stock_version']!=1 || !{'DEPENSE','ALIMENTATION'}.contains(d['entity_type']))continue;
    if(row.businessStatus=='NEEDS_RECONCILIATION') {review.add(row.operationId);continue;}
    if({'NOT_APPLIED','SUPERSEDED'}.contains(row.businessStatus))continue;
    if(row.businessStatus!='CONFIRMED')pending.add(row.operationId);
    final ranges=(snapshot['coverage'] as Map)['${d['device_id']}'] as List? ?? const [];
    if(ranges.any((range)=>row.sequence>=range[0] && row.sequence<=range[1]))continue;
    // Corrections are version-bound server decisions; never guess their delta.
    if(d['operation_type']!='CREATE') {review.add(row.operationId);continue;}
    String? productId;int? species;Object? lot;BigInt delta;
    if(d['entity_type']=='DEPENSE') {
      final supply=p['feed_supply'] as Map;
      productId=(supply['product']??supply['new_product']?['id']) as String?;
      species=supply['species'] as int?;lot=supply['lot']??supply['lot_ref']?['server_id'];
      delta=supply.containsKey('kg')?feedMilli(supply['kg']):feedMilli(supply['bags'])*feedMilli(supply['kg_per_bag'])~/BigInt.from(1000);
      if(productId!=null && !products.containsKey(productId))products[productId]={'id':productId,
        'name':supply['new_product']?['name']??'Aliment local','archived':false,'local_pending':true,'positions':<Map<String,dynamic>>[]};
      if(row.businessStatus!='CONFIRMED')purchases.add({'operation_id':row.operationId,'product':productId,'species':species,'lot':lot});
    } else {
      productId=p['product'] as String?;species=p['species'] as int?;lot=p['source_lot'];
      delta=-feedMilli(p['quantite_kg']);
      final parent=p['supply_parent_uuid'];
      if(parent is String && originalById[parent]!=null && {'NEEDS_RECONCILIATION','NOT_APPLIED','SUPERSEDED'}.contains(originalById[parent]!.businessStatus)) {
        review.add(row.operationId);continue;
      }
    }
    if(productId==null || species==null || !products.containsKey(productId))throw StateError('Stock local sans référence certaine.');
    final key='$productId:$species:$lot';
    if(!positions.containsKey(key)) {
      final position=<String,dynamic>{'species_id':species,'lot_id':lot,'kg':'0.000','pending_kg':'0.000','estimated_kg':'0.000'};
      positions[key]=position;(products[productId]!['positions'] as List).add(position);
    }
    final position=positions[key]!;
    final change=feedMilli(position['pending_kg'],signed:true)+delta;
    position['pending_kg']=feedKg(change);
    position['estimated_kg']=feedKg(feedMilli(position['kg'])+change);
  }
  return {...snapshot,'stock_contract':1,'confirmed':true,'local_estimate':true,'products':products.values.toList(),
    'pending_operations':pending,'review_operations':review,'pending_purchases':purchases};
}
