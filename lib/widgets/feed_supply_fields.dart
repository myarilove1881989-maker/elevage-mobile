import 'package:flutter/material.dart';
import '../offline/outbox.dart' show newOperationUuid;

/// In-memory connected draft only. Never persists/enqueues an offline operation.
class FeedSupplyDraft {
  String? product;
  bool newProduct = false, sacks = false;
  final newProductId = newOperationUuid();
  final name = TextEditingController(), quantity = TextEditingController(), sackWeight = TextEditingController();
  int? species, lot;
  DateTime receivedOn = DateTime.now();
  void dispose() {name.dispose();quantity.dispose();sackWeight.dispose();}
  Map<String,dynamic> payload() {
    final number = quantity.text.trim().replaceAll(',', '.');
    final weight = sackWeight.text.trim().replaceAll(',', '.');
    bool valid(String value) => RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(value) && (num.tryParse(value) ?? 0)>0;
    if (species == null || (!newProduct && product == null) || (newProduct && name.text.trim().isEmpty) ||
        !valid(number) || (sacks && (!RegExp(r'^\d+$').hasMatch(number) || !valid(weight)))) {
      throw const FormatException('Renseignez l’aliment, l’espèce et une quantité positive ; le poids du sac est obligatoire.');
    }
    return {
      if (newProduct) 'new_product':{'id':newProductId,'name':name.text.trim()} else 'product':product,
      'species':species,'lot':lot,
      if (sacks) ...{'bags':number,'kg_per_bag':weight} else 'kg':number,
      'received_on':'${receivedOn.year.toString().padLeft(4,'0')}-${receivedOn.month.toString().padLeft(2,'0')}-${receivedOn.day.toString().padLeft(2,'0')}',
    };
  }
}

class FeedSupplyFields extends StatefulWidget {
  const FeedSupplyFields({super.key,required this.draft,required this.catalog,required this.editable});
  final FeedSupplyDraft draft;
  final Map<String,dynamic> catalog;
  final bool editable;
  @override
  State<FeedSupplyFields> createState()=>_FeedSupplyFieldsState();
}

class _FeedSupplyFieldsState extends State<FeedSupplyFields> {
  @override
  Widget build(BuildContext context) {
    final d=widget.draft;
    final lots=(widget.catalog['lots'] as List).where((row)=>row['espece_id']==d.species);
    String label(String collection, Object? id) {
      for(final row in widget.catalog[collection] as List) {if(row['id']==id)return row['nom'] as String;}
      return 'Référence archivée';
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const SizedBox(height:16),
      const Text('Approvisionnement d’aliment',style:TextStyle(fontWeight:FontWeight.bold)),
      const Text('Quantités physiques uniquement. Le lot comptable et le montant ci-dessus restent indépendants.'),
      SwitchListTile(key:const Key('feed-new'),title:const Text('Ajouter un nouvel aliment'),value:d.newProduct,
        onChanged:widget.editable?(v)=>setState(()=>d.newProduct=v):null),
      if(d.newProduct) TextField(key:const Key('feed-name'),controller:d.name,enabled:widget.editable,maxLength:120,
        decoration:const InputDecoration(labelText:'Nom du nouvel aliment'))
      else DropdownButtonFormField<String>(key:const Key('feed-product'),initialValue:d.product,isExpanded:true,
        decoration:const InputDecoration(labelText:'Aliment'),items:[for(final row in widget.catalog['products'] as List)
          DropdownMenuItem(value:row['id'] as String,child:Text(row['name'] as String))],
        onChanged:widget.editable?(v)=>setState(()=>d.product=v):null),
      DropdownButtonFormField<int>(key:const Key('feed-species'),initialValue:d.species,isExpanded:true,
        decoration:const InputDecoration(labelText:'Espèce destinataire'),items:[for(final row in widget.catalog['species'] as List)
          DropdownMenuItem(value:row['id'] as int,child:Text(row['nom'] as String))],
        onChanged:widget.editable?(v)=>setState((){d.species=v;d.lot=null;}):null),
      DropdownButtonFormField<int>(key:ValueKey('feed-lot-${d.species}'),initialValue:d.lot??0,isExpanded:true,
        decoration:const InputDecoration(labelText:'Lot physique destinataire'),items:[
          const DropdownMenuItem(value:0,child:Text('Stock partagé de cette espèce')),
          for(final row in lots) DropdownMenuItem(value:row['id'] as int,child:Text(row['nom'] as String))],
        onChanged:widget.editable?(v)=>setState(()=>d.lot=v==0?null:v):null),
      DropdownButtonFormField<bool>(key:const Key('feed-unit'),initialValue:d.sacks,
        decoration:const InputDecoration(labelText:'Unité de saisie'),items:const[
          DropdownMenuItem(value:false,child:Text('Kilogrammes')),DropdownMenuItem(value:true,child:Text('Sacs'))],
        onChanged:widget.editable?(v)=>setState(()=>d.sacks=v??false):null),
      TextField(key:const Key('feed-quantity'),controller:d.quantity,enabled:widget.editable,
        keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:d.sacks?'Nombre de sacs':'Quantité achetée (kg)')),
      if(d.sacks) TextField(key:const Key('feed-sack-weight'),controller:d.sackWeight,enabled:widget.editable,
        keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:const InputDecoration(labelText:'Poids d’un sac (kg)')),
      TextButton(key:const Key('feed-received-date'),onPressed:widget.editable?()async{
        final date=await showDatePicker(context:context,initialDate:d.receivedOn,
          firstDate:DateTime(2000),lastDate:DateTime.now());
        if(mounted && date!=null)setState(()=>d.receivedOn=date);
      }:null,child:Text('Date d’approvisionnement : ${d.receivedOn.day}/${d.receivedOn.month}/${d.receivedOn.year}')),
      if(!d.newProduct && d.product!=null) ...[
        const Text('Stocks confirmés par position (kg) :'),
        for(final row in widget.catalog['products'] as List) if(row['id']==d.product)
          for(final position in row['positions'] as List)
            Text('${position['kg']} kg - ${label('species',position['species_id'])}, ${position['lot_id']==null?'partagé':label('lots',position['lot_id'])}'),
      ],
    ]);
  }
}
