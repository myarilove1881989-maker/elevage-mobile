import 'package:flutter/material.dart';
import '../offline/feed_stock_projection.dart';

class FeedDistributionDraft {
  String? product;int? sourceLot;
  Map<String,dynamic> payload(Map<String,dynamic> catalog,int lot,String quantity,String note) {
    final target=(catalog['lots'] as List).where((row)=>row['id']==lot).toList();
    if(target.length!=1)throw StateError('Lot absent ou clôturé : actualisez.');
    if(sourceLot!=null && sourceLot!=lot) {throw StateError('Stock réservé à un autre lot.');}
    final species=target.single['espece_id'];
    final products=(catalog['products'] as List).where((row)=>row['id']==product && row['archived']!=true).toList();
    if(products.length!=1)throw StateError('Choisissez un aliment du référentiel.');
    final positions=(products.single['positions'] as List).where((row)=>row['species_id']==species && row['lot_id']==sourceLot).toList();
    final available=positions.isEmpty?BigInt.zero:feedMilli(positions.single['estimated_kg']??positions.single['kg'],signed:true);
    final amount=feedMilli(quantity.trim().replaceAll(',','.'));
    if(amount<=BigInt.zero || amount>available)throw StateError('Quantité supérieure au stock disponible estimé.');
    final parents=[for(final p in catalog['pending_purchases'] as List? ?? const [])
      if(p['product']==product && p['species']==species && p['lot']==sourceLot)p['operation_id'] as String];
    return {'stock_version':1,'lot':lot,'species':species,'product':product,'source_lot':sourceLot,
      'quantite_kg':feedKg(amount),'note':note,
      if(parents.isNotEmpty) ...{'supply_parent_uuid':parents.first,'_feed_dependencies':parents}};
  }
}

class FeedDistributionFields extends StatefulWidget {
  const FeedDistributionFields({super.key,required this.draft,required this.catalog,required this.lotId,required this.editable});
  final FeedDistributionDraft draft;final Map<String,dynamic> catalog;final int lotId;final bool editable;
  @override State<FeedDistributionFields> createState()=>_FeedDistributionFieldsState();
}
class _FeedDistributionFieldsState extends State<FeedDistributionFields> {
  @override Widget build(BuildContext context) {
    final d=widget.draft,c=widget.catalog;
    final targets=(c['lots'] as List).where((row)=>row['id']==widget.lotId).toList();
    final species=targets.isEmpty?null:targets.single['espece_id'];
    final names=(c['species'] as List).where((row)=>row['id']==species).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Espèce : ${names.isEmpty?'indisponible':names.single['nom']} - lot destinataire sélectionné'),
      DropdownButtonFormField<String>(key:const Key('distribution-stock-product'),initialValue:d.product,isExpanded:true,
        decoration:const InputDecoration(labelText:'Aliment du référentiel'),
        items:[for(final p in c['products'] as List)if(p['archived']!=true)
          DropdownMenuItem(value:p['id'] as String,child:Text(p['name'] as String))],
        onChanged:widget.editable?(v)=>setState(()=>d.product=v):null),
      DropdownButtonFormField<int>(key:const Key('distribution-stock-source'),initialValue:d.sourceLot??0,
        decoration:const InputDecoration(labelText:'Stock à utiliser'),items:[
          const DropdownMenuItem(value:0,child:Text('Stock partagé de cette espèce')),
          DropdownMenuItem(value:widget.lotId,child:const Text('Stock réservé à ce lot'))],
        onChanged:widget.editable?(v)=>setState(()=>d.sourceLot=v==0?null:v):null),
      for(final p in c['products'] as List)if(p['id']==d.product)
        for(final position in p['positions'] as List)if(position['species_id']==species && position['lot_id']==d.sourceLot)
          Text('Confirmé : ${position['kg']} kg\nOpérations locales non incluses : ${position['pending_kg']??'0.000'} kg\nDisponible estimé : ${position['estimated_kg']??position['kg']} kg',key:const Key('distribution-stock-values')),
      if(c['local_estimate']==true) const Text('Estimation sur cet appareil. Le serveur validera les conflits et les droits à la synchronisation.'),
      if((c['review_operations'] as List? ?? const []).isNotEmpty) const Text('Des opérations restent à examiner dans l’historique ; elles sont conservées.'),
    ]);
  }
}
