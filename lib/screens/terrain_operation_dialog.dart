part of 'offline_tablet_screen.dart';

const _terrainNames={'DEPENSE':'Dépense','ALIMENTATION':'Alimentation','PESEE':'Pesée','COLLECTE_OEUFS':'Collecte d’œufs',
  'MORTALITE':'Mortalité','DON':'Don','VOL':'Vol','ACHAT':'Achat','NAISSANCE':'Naissance'};
class _TerrainField {
  const _TerrainField(this.key,this.label,{this.scale,this.integer=false,this.required=true,this.zero=false,this.maxLength=255});
  final String key,label;final int? scale;final bool integer,required,zero;final int maxLength;
}
const _terrainFields={
  'DEPENSE':[_TerrainField('montant','Montant',scale:2),_TerrainField('note','Note',required:false)],
  'ALIMENTATION':[_TerrainField('aliment','Aliment'),_TerrainField('quantite_kg','Quantité (kg)',scale:3),
    _TerrainField('prix_kg','Prix par kg',scale:2,required:false,zero:true),_TerrainField('note','Note',required:false)],
  'PESEE':[_TerrainField('nombre_animaux_peses','Animaux pesés',integer:true),_TerrainField('poids_total_kg','Poids total (kg)',scale:3),_TerrainField('note','Note',required:false)],
  'COLLECTE_OEUFS':[_TerrainField('nombre_collecte','Œufs collectés',integer:true),_TerrainField('nombre_casses','Cassés',integer:true,zero:true),
    _TerrainField('nombre_declasses','Déclassés',integer:true,zero:true),_TerrainField('nombre_consommes_donnes','Consommés ou donnés',integer:true,zero:true),_TerrainField('note','Note',required:false)],
  'MORTALITE':[_TerrainField('quantite','Quantité',integer:true),_TerrainField('note','Constat / motif',required:false)],
  'DON':[_TerrainField('quantite','Quantité',integer:true),_TerrainField('note','Constat / motif',required:false)],
  'VOL':[_TerrainField('quantite','Quantité',integer:true),_TerrainField('note','Constat / motif',required:false)],
  'ACHAT':[_TerrainField('nom_lot','Nom du nouveau lot',maxLength:100),_TerrainField('quantite','Quantité',integer:true),
    _TerrainField('prix_unitaire','Prix unitaire',scale:2),_TerrainField('fournisseur','Fournisseur',required:false),_TerrainField('note','Note',required:false)],
  'NAISSANCE':[_TerrainField('nom_nouveau_lot','Nom du lot enfant',maxLength:100),_TerrainField('total_naissances','Total des naissances',integer:true),
    _TerrainField('mort_nes','Mort-nés',integer:true,zero:true),_TerrainField('note','Note',required:false)],
};

String? _fixedDecimal(String text,int scale) {
  final value=text.trim().replaceAll(',','.');
  final match=RegExp('^([0-9]{1,8})(?:\\.([0-9]{1,$scale}))?\$').firstMatch(value);
  if(match==null) {return null;}
  return '${BigInt.parse(match[1]!)}.${(match[2]??'').padRight(scale,'0')}';
}
BigInt _scaledInteger(String decimal)=>BigInt.parse(decimal.replaceAll('.',''));
String _money(BigInt cents)=>'${cents~/BigInt.from(100)}.${(cents%BigInt.from(100)).toString().padLeft(2,'0')}';

class _TerrainOperationDialog extends StatefulWidget {
  const _TerrainOperationDialog({required this.lots,required this.species,required this.categories,required this.expenses,required this.searchLots});
  final List<Map<String,dynamic>> lots,species,categories;
  final List<OutboxEntry> expenses;
  final Future<List<Map<String,dynamic>>> Function(String) searchLots;
  @override
  State<_TerrainOperationDialog> createState()=>_TerrainOperationDialogState();
}
class _TerrainOperationDialogState extends State<_TerrainOperationDialog> {
  final form=GlobalKey<FormState>();
  final fields=<String,TextEditingController>{};
  String kind='DEPENSE',production='CHAIR',productionStatus='ELEVAGE';
  Map<String,dynamic>? lot,species,category;
  OutboxEntry? expense;
  DateTime occurred=DateTime.now();
  String? error;
  late List<Map<String,dynamic>> lotChoices=widget.lots;
  final lotSearch=TextEditingController();
  bool searching=false;int searchVersion=0;
  @override
  void initState() {
    super.initState();
    for(final list in _terrainFields.values) {
      for(final spec in list) {
        fields.putIfAbsent(spec.key,()=>TextEditingController(text:spec.integer && spec.zero?'0':'')..addListener(_changed));
      }
    }
  }
  void _changed() {if(mounted) {setState((){});}}
  @override
  void dispose() {for(final controller in fields.values) {controller.dispose();}lotSearch.dispose();super.dispose();}
  bool get removal=>{'MORTALITE','DON','VOL'}.contains(kind);
  bool get shortage=>removal && lot!=null && (int.tryParse(fields['quantite']!.text)??0)>((lot!['data'] as Map)['projected_stock'] as int? ?? 0);
  Map<String,dynamic> reference(Map<String,dynamic> row) {
    final id=(row['data'] as Map)['id'];
    return id is int?{'server_id':id}:{'local_uuid':row['local_uuid']??id};
  }
  bool expenseMatchesLot(OutboxEntry entry) {
    if(lot==null) {return true;}
    final ref=(entry.declaration['payload'] as Map)['lot_ref'];
    if(ref is! Map) {return false;}
    return ref['server_id']==(lot!['data'] as Map)['id'] ||
      (ref['local_uuid']!=null && ref['local_uuid']==lot!['local_uuid']);
  }
  String? validate(_TerrainField spec,String? input) {
    final value=(input??'').trim();
    if(value.isEmpty) {return spec.required?'Indiquez ce champ.':spec.key=='note' && shortage?'Un motif est nécessaire pour ce constat supérieur au stock projeté.':null;}
    if(spec.integer) {
      final number=int.tryParse(value);
      if(!RegExp(r'^[0-9]{1,9}$').hasMatch(value) || number==null || number<(spec.zero?0:1) || number>2147483647) {return 'Nombre entier ${spec.zero?'positif ou nul':'supérieur à zéro'} requis.';}
    }
    if(spec.scale!=null) {
      final number=_fixedDecimal(value,spec.scale!);
      if(number==null || (!spec.zero && _scaledInteger(number)==BigInt.zero)) {return 'Montant positif, avec ${spec.scale} décimales au maximum.';}
    }
    return null;
  }
  Future<void> chooseDate() async {
    final date=await showDatePicker(context:context,initialDate:occurred,firstDate:DateTime(2010),lastDate:DateTime.now());
    if(date==null || !mounted) {return;}
    final time=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(occurred));
    if(time==null || !mounted) {return;}
    setState(()=>occurred=DateTime(date.year,date.month,date.day,time.hour,time.minute));
  }
  Future<void> search() async {
    if(searching) {return;}
    setState(()=>searching=true);
    try {
      final rows=await widget.searchLots(lotSearch.text.trim());
      if(mounted) {setState((){lotChoices=rows;lot=null;searchVersion++;});}
    } catch (_) {if(mounted) {setState(()=>error='Recherche indisponible. Vérifiez que votre profil reste ouvert.');}}
    finally {if(mounted) {setState(()=>searching=false);}}
  }
  void save() {
    if(!form.currentState!.validate()) {return;}
    if(occurred.isAfter(DateTime.now().add(const Duration(minutes:5)))) {setState(()=>error='Vérifiez la date et l’heure de l’opération réalisée.');return;}
    final payload=<String,dynamic>{};final dependencies=<String>[];
    for(final spec in _terrainFields[kind]!) {
      final value=fields[spec.key]!.text.trim();if(value.isEmpty && !spec.required) {continue;}
      payload[spec.key]=spec.integer?int.parse(value):spec.scale==null?value:_fixedDecimal(value,spec.scale!);
    }
    if(kind=='ACHAT') {
      payload['espece']=(species!['data'] as Map)['id'];
      final total=_scaledInteger(payload['prix_unitaire'] as String)*BigInt.from(payload['quantite'] as int);
      if(total>BigInt.from(9999999999)) {setState(()=>error='Le total de cet achat dépasse la limite de montant.');return;}
      payload['prix_total']=_money(total);payload['type_production']=production;payload['statut_production']=productionStatus;
    } else {
      payload['lot_ref']=reference(lot!);
      final dependency=lot!['dependency'];if(dependency is String) {dependencies.add(dependency);}
    }
    if(kind=='DEPENSE' && category!=null) {payload['categorie_id']=(category!['data'] as Map)['id'];}
    if(kind=='ALIMENTATION' && expense!=null) {
      payload['depense_ref']=expense!.businessStatus=='CONFIRMED'?{'server_id':int.parse(expense!.serverEntityId)}:
        {'local_uuid':expense!.declaration['local_entity_id']};
      if(expense!.businessStatus!='CONFIRMED') {dependencies.add(expense!.operationId);}
    }
    if(kind=='NAISSANCE') {
      payload['type_production']=production;
      if((payload['mort_nes'] as int)>(payload['total_naissances'] as int)) {setState(()=>error='Les mort-nés ne peuvent pas dépasser le total.');return;}
    }
    if(kind=='COLLECTE_OEUFS' && (payload['nombre_casses'] as int)+(payload['nombre_declasses'] as int)+(payload['nombre_consommes_donnes'] as int)>(payload['nombre_collecte'] as int)) {
      setState(()=>error='Les œufs cassés, déclassés et consommés/donnés dépassent la collecte.');return;
    }
    Navigator.pop(context,<String,dynamic>{'entity_type':kind,'payload':payload,'dependencies':dependencies.toSet().toList(),'occurred':occurred.toUtc()});
  }
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Opération réalisée sur le terrain'),
    content:SizedBox(width:440,child:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Enregistrement sur la tablette. La confirmation et le stock définitifs appartiennent au serveur.'),
      DropdownButtonFormField<String>(isExpanded:true,initialValue:kind,decoration:const InputDecoration(labelText:'Opération'),
        items:[for(final entry in _terrainNames.entries)DropdownMenuItem(value:entry.key,child:Text(entry.value))],
        onChanged:(value){if(value!=null) {setState((){kind=value;lot=null;expense=null;error=null;});}}),
      if(kind!='ACHAT') ...[
        TextField(controller:lotSearch,maxLength:100,decoration:const InputDecoration(labelText:'Rechercher un lot sur la tablette')),
        TextButton(onPressed:searching?null:search,child:Text(searching?'Recherche…':'Rechercher')),
      ],
      if(kind!='ACHAT') DropdownButtonFormField<Map<String,dynamic>>(isExpanded:true,key:ValueKey('lot-$kind-$searchVersion'),initialValue:lot,
        decoration:InputDecoration(labelText:kind=='NAISSANCE'?'Lot parent / origine':'Lot'),
        items:[for(final row in lotChoices)DropdownMenuItem(value:row,child:Text(((row['data'] as Map)['nom']).toString(),maxLines:1,overflow:TextOverflow.ellipsis))],
        validator:(value)=>value==null?'Choisissez le lot.':null,onChanged:(value)=>setState((){lot=value;expense=null;})),
      if(kind=='ACHAT') DropdownButtonFormField<Map<String,dynamic>>(isExpanded:true,initialValue:species,decoration:const InputDecoration(labelText:'Espèce'),
        items:[for(final row in widget.species)DropdownMenuItem(value:row,child:Text(((row['data'] as Map)['nom']).toString(),maxLines:1,overflow:TextOverflow.ellipsis))],
        validator:(value)=>value==null?'Choisissez l’espèce.':null,onChanged:(value)=>setState(()=>species=value)),
      if(kind=='DEPENSE') DropdownButtonFormField<Map<String,dynamic>>(isExpanded:true,initialValue:category,decoration:const InputDecoration(labelText:'Catégorie (facultative)'),
        items:[const DropdownMenuItem(value:null,child:Text('Sans catégorie')),for(final row in widget.categories)DropdownMenuItem(value:row,child:Text(((row['data'] as Map)['nom']).toString(),maxLines:1,overflow:TextOverflow.ellipsis))],
        onChanged:(value)=>setState(()=>category=value)),
      if(kind=='ALIMENTATION') DropdownButtonFormField<OutboxEntry>(isExpanded:true,key:ValueKey('expense-${lot==null?'none':(lot!['data'] as Map)['id']}'),initialValue:expense,decoration:const InputDecoration(labelText:'Dépense associée (facultative)'),
        items:[const DropdownMenuItem(value:null,child:Text('Sans dépense associée')),for(final entry in widget.expenses.where(expenseMatchesLot))DropdownMenuItem(value:entry,
          child:Text('Dépense ${(entry.declaration['payload'] as Map)['montant']}'))],onChanged:(value)=>setState(()=>expense=value)),
      for(final spec in _terrainFields[kind]!) TextFormField(key:ValueKey('$kind-${spec.key}'),controller:fields[spec.key],maxLength:spec.maxLength,
        keyboardType:spec.integer?TextInputType.number:spec.scale!=null?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,
        decoration:InputDecoration(labelText:spec.label),validator:(value)=>validate(spec,value)),
      if(shortage) const Text('Alerte : ce constat dépasse le stock projeté. Il sera conservé avec votre motif et peut nécessiter un rapprochement.',style:TextStyle(color:Colors.red)),
      if({'ACHAT','NAISSANCE'}.contains(kind)) DropdownButtonFormField<String>(isExpanded:true,initialValue:production,decoration:const InputDecoration(labelText:'Production'),
        items:const [DropdownMenuItem(value:'CHAIR',child:Text('Chair')),DropdownMenuItem(value:'OEUFS',child:Text('Œufs')),DropdownMenuItem(value:'REPRODUCTION',child:Text('Reproduction')),DropdownMenuItem(value:'AUTRE',child:Text('Autre'))],
        onChanged:(value){if(value!=null) {setState(()=>production=value);}}),
      if(kind=='ACHAT') DropdownButtonFormField<String>(isExpanded:true,initialValue:productionStatus,decoration:const InputDecoration(labelText:'État du lot'),
        items:const [DropdownMenuItem(value:'ELEVAGE',child:Text('Élevage')),DropdownMenuItem(value:'PONTE',child:Text('Ponte')),DropdownMenuItem(value:'REFORME',child:Text('Réforme')),DropdownMenuItem(value:'TERMINE',child:Text('Terminé'))],
        onChanged:(value){if(value!=null) {setState(()=>productionStatus=value);}}),
      TextButton(onPressed:chooseDate,child:Text('Date / heure : ${occurred.day}/${occurred.month}/${occurred.year} ${occurred.hour.toString().padLeft(2,'0')}:${occurred.minute.toString().padLeft(2,'0')}')),
      if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
    ])))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
      FilledButton(onPressed:save,child:const Text('Conserver sur la tablette'))]);
}
