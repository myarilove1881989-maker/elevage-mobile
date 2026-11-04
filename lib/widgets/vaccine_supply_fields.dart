import 'package:flutter/material.dart';
import '../offline/outbox.dart' show newOperationUuid;

class VaccineSupplyDraft {
  String? product;int? species,lot;bool create=false;
  final id=newOperationUuid();
  final name=TextEditingController(),count=TextEditingController(),doses=TextEditingController(),batch=TextEditingController(),
    expiry=TextEditingController(),received=TextEditingController(text:DateTime.now().toIso8601String().split('T').first);
  Map<String,dynamic> payload() {
    int positive(String value,int max) {if(!RegExp(r'^\d+$').hasMatch(value))throw StateError('Nombre entier requis.');final n=int.parse(value);if(n<1 || n>max)throw StateError('Quantité hors limites.');return n;}
    final expires=DateTime.tryParse(expiry.text.trim()),at=DateTime.tryParse(received.text.trim());
    if(species==null || (create?name.text.trim().isEmpty:product==null) || batch.text.trim().isEmpty || expires==null || at==null || expires.toIso8601String().split('T').first!=expiry.text.trim() || at.toIso8601String().split('T').first!=received.text.trim() ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expiry.text.trim()) || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(received.text.trim())) {throw StateError('Complétez le vaccin, son lot fabricant et les dates.');}
    return {if(create)'new_product':{'id':id,'name':name.text.trim()} else 'product':product,'species':species,'lot':lot,
      'vial_count':positive(count.text,1000),'doses_per_vial':positive(doses.text,1000000),'manufacturer_batch':batch.text.trim(),
      'expires_on':expiry.text.trim(),'received_on':received.text.trim()};
  }
  void dispose() {for(final c in [name,count,doses,batch,expiry,received]) {c.dispose();}}
}
class VaccineSupplyFields extends StatefulWidget {
  const VaccineSupplyFields({super.key,required this.draft,required this.catalog,required this.editable});
  final VaccineSupplyDraft draft;final Map<String,dynamic> catalog;final bool editable;
  @override State<VaccineSupplyFields> createState()=>_VaccineSupplyFieldsState();
}
class _VaccineSupplyFieldsState extends State<VaccineSupplyFields> {
  @override Widget build(BuildContext context) {
    final d=widget.draft;
    Widget text(String key,String label,TextEditingController controller)=>TextField(key:Key(key),controller:controller,enabled:widget.editable,decoration:InputDecoration(labelText:label));
    return Column(spacing:16,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      DropdownButtonFormField<String>(key:const Key('vaccine-product'),initialValue:d.create?'new':d.product,isExpanded:true,
        decoration:const InputDecoration(labelText:'Vaccin du référentiel'),items:[
          for(final p in widget.catalog['products'] as List)if(p['archived']!=true)DropdownMenuItem(value:p['id'] as String,child:Text('${p['name']}',maxLines:1,overflow:TextOverflow.ellipsis)),
          const DropdownMenuItem(value:'new',child:Text('Ajouter un vaccin'))],
        onChanged:widget.editable?(v)=>setState(() {d.create=v=='new';d.product=d.create?null:v;}):null),
      if(d.create)text('vaccine-name','Nom du vaccin',d.name),
      DropdownButtonFormField<int>(key:const Key('vaccine-species'),initialValue:d.species,isExpanded:true,decoration:const InputDecoration(labelText:'Espèce'),
        items:[for(final s in widget.catalog['species'] as List)DropdownMenuItem(value:s['id'] as int,child:Text('${s['nom']}',maxLines:1,overflow:TextOverflow.ellipsis))],
        onChanged:widget.editable?(v)=>setState(() {d.species=v;d.lot=null;}):null),
      DropdownButtonFormField<int>(key:ValueKey('vaccine-lot-${d.species}'),initialValue:d.lot??0,isExpanded:true,
        decoration:const InputDecoration(labelText:'Lot destinataire facultatif'),items:[const DropdownMenuItem(value:0,child:Text('Partagé entre lots de cette espèce',maxLines:1,overflow:TextOverflow.ellipsis)),
          for(final lot in widget.catalog['lots'] as List)if(lot['espece_id']==d.species)DropdownMenuItem(value:lot['id'] as int,child:Text('${lot['nom']}',maxLines:1,overflow:TextOverflow.ellipsis))],
        onChanged:widget.editable?(v)=>setState(()=>d.lot=v==0?null:v):null),
      text('vaccine-count','Nombre de flacons',d.count),text('vaccine-doses','Doses par flacon',d.doses),
      text('vaccine-batch','Lot fabricant',d.batch),text('vaccine-expiry','Péremption (AAAA-MM-JJ)',d.expiry),
      text('vaccine-received','Approvisionnement (AAAA-MM-JJ)',d.received),
      const Text('Chaque flacon recevra son identifiant. Aucune durée après ouverture n’est définie automatiquement.'),
    ]);
  }
}
