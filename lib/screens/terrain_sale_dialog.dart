part of 'offline_tablet_screen.dart';

class _TerrainSaleDialog extends StatefulWidget {
  const _TerrainSaleDialog({required this.lots,required this.clients,required this.searchLots,
    required this.searchClients,required this.clientSales});
  final List<Map<String,dynamic>> lots,clients;
  final Future<List<Map<String,dynamic>>> Function(String) searchLots,searchClients,clientSales;
  @override
  State<_TerrainSaleDialog> createState()=>_TerrainSaleDialogState();
}

class _TerrainSaleDialogState extends State<_TerrainSaleDialog> {
  final form=GlobalKey<FormState>();
  final quantity=TextEditingController(),price=TextEditingController(),amount=TextEditingController(),note=TextEditingController();
  final lotSearch=TextEditingController(),clientSearch=TextEditingController();
  String kind='VENTE_ANIMAUX',pack='UNITE',mode='ESPECES';
  final size=TextEditingController(text:'30');
  final extraEggs=TextEditingController(text:'0');
  Map<String,dynamic>? lot,client,sale;
  late List<Map<String,dynamic>> lots=widget.lots,clients=widget.clients;
  List<Map<String,dynamic>> sales=[];
  bool searching=false;int version=0;
  String? error;
  DateTime occurred=DateTime.now();
  @override
  void initState() {super.initState();quantity.addListener(changed);size.addListener(changed);extraEggs.addListener(changed);}
  void changed() {if(mounted) {setState((){});}}
  int get saleQuantity {
    final count=int.tryParse(quantity.text.trim())??0;
    if(kind=='VENTE_OEUFS' && pack=='COMPOSE') {return count*30+(int.tryParse(extraEggs.text.trim())??0);}
    final multiplier=kind=='VENTE_OEUFS'?{'UNITE':1,'DOUZAINE':12,'PLATEAU':30}[pack]??int.tryParse(size.text.trim())??0:1;
    return count*multiplier;
  }
  bool get shortage=>kind!='ENCAISSEMENT' && lot!=null && saleQuantity>((lot!['data'] as Map)[kind=='VENTE_OEUFS'?'projected_egg_stock':'projected_stock'] as int? ??0);
  @override
  void dispose() {for(final controller in [quantity,price,amount,note,size,extraEggs,lotSearch,clientSearch]) {controller.dispose();}super.dispose();}
  Map<String,dynamic> reference(Map<String,dynamic> row,{bool saleReference=false}) {
    final id=(row['data'] as Map)[saleReference?'reference_id':'id'];
    return id is int?{'server_id':id}:{'local_uuid':row['local_uuid']??id};
  }
  String? integer(String? value)=>RegExp(r'^[0-9]{1,9}$').hasMatch(value??'') && (int.tryParse(value??'')??0)>0?null:'Quantité entière supérieure à zéro requise.';
  String? decimal(String? value) {
    final parsed=_fixedDecimal(value??'',2);
    return parsed!=null && _scaledInteger(parsed)>BigInt.zero?null:'Montant positif, deux décimales au maximum.';
  }
  Future<void> search(bool clientSearchRequested) async {
    if(searching) {return;}
    setState(()=>searching=true);
    try {
      final result=await (clientSearchRequested?widget.searchClients(clientSearch.text.trim()):widget.searchLots(lotSearch.text.trim()));
      if(mounted) {setState(() {version++;if(clientSearchRequested) {clients=result;client=null;sale=null;sales=[];} else {lots=result;lot=null;}});}
    } catch (_) {if(mounted) {setState(()=>error='Recherche indisponible. Rouvrez votre profil si nécessaire.');}}
    finally {if(mounted) {setState(()=>searching=false);}}
  }
  Future<void> chooseClient(Map<String,dynamic>? value) async {
    setState(() {client=value;sale=null;sales=[];error=null;version++;});
    if(value==null) {return;}
    try {
      final result=await widget.clientSales((value['data'] as Map)['id'].toString());
      if(mounted && identical(client,value)) {setState(()=>sales=result);}
    } catch (_) {if(mounted) {setState(()=>error='Ventes du client indisponibles sur cette tablette.');}}
  }
  Future<void> chooseDate() async {
    final day=await showDatePicker(context:context,initialDate:occurred,firstDate:DateTime(2010),lastDate:DateTime.now());
    if(day==null || !mounted) {return;}
    final time=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(occurred));
    if(time!=null && mounted) {setState(()=>occurred=DateTime(day.year,day.month,day.day,time.hour,time.minute));}
  }
  void save() {
    if(!form.currentState!.validate()) {return;}
    if(occurred.isAfter(DateTime.now().add(const Duration(minutes:5)))) {setState(()=>error='Vérifiez la date métier.');return;}
    final payload=<String,dynamic>{'client_ref':reference(client!)};
    final dependencies=<String>{};
    final clientDependency=client!['operation_id'];
    if(clientDependency is String && !{'CONFIRMED','CONFIRMED_CACHE'}.contains(client!['state'])) {dependencies.add(clientDependency);}
    if(kind=='ENCAISSEMENT') {
      payload.addAll({'montant_recu':_fixedDecimal(amount.text,2),'mode':mode,'note':note.text.trim()});
      if(sale!=null) {
        payload['vente_ref']=reference(sale!,saleReference:true);payload['vente_type']=(sale!['data'] as Map)['entity_type'];
        if(sale!['dependency'] is String) {dependencies.add(sale!['dependency'] as String);}
      }
    } else {
      payload['lot_ref']=reference(lot!);
      if(lot!['dependency'] is String) {dependencies.add(lot!['dependency'] as String);}
      final count=int.parse(quantity.text.trim());
      if(saleQuantity<1 || saleQuantity>2147483647) {setState(()=>error='Vérifiez la quantité totale de cette déclaration.');return;}
      final unitPrice=_fixedDecimal(price.text,2)!;
      if(_scaledInteger(unitPrice)*BigInt.from(kind=='VENTE_OEUFS' && pack=='COMPOSE'?1:count)>BigInt.parse('999999999999')) {setState(()=>error='Le montant de la vente dépasse la limite.');return;}
      if(kind=='VENTE_ANIMAUX') {payload.addAll({'quantite':count,'prix_unitaire':unitPrice});}
      else if(pack=='COMPOSE') {payload.addAll({'conditionnement':pack,'nombre_alveoles':count,'oeufs_supplementaires':int.parse(extraEggs.text.trim()),'prix_total':unitPrice});}
      else {payload.addAll({'conditionnement':pack,'nombre_conditionnements':count,'prix_unitaire_conditionnement':unitPrice,
        if(pack=='CARTON')'oeufs_par_conditionnement':int.parse(size.text.trim())});}
      if(note.text.trim().isNotEmpty) {payload['note']=note.text.trim();}
    }
    Navigator.pop(context,<String,dynamic>{'entity_type':kind,'payload':payload,'dependencies':dependencies.toList(),'occurred':occurred.toUtc()});
  }
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Vente ou encaissement terrain'),
    content:SizedBox(width:440,child:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Le serveur confirme le stock, les origines des œufs et l’affectation comptable. Le montant physiquement reçu reste conservé.'),
      DropdownButtonFormField<String>(initialValue:kind,decoration:const InputDecoration(labelText:'Opération'),
        items:const [DropdownMenuItem(value:'VENTE_ANIMAUX',child:Text('Vente animaux')),DropdownMenuItem(value:'VENTE_OEUFS',child:Text('Vente d’œufs')),DropdownMenuItem(value:'ENCAISSEMENT',child:Text('Encaissement reçu'))],
        onChanged:(value) {if(value!=null) {setState(() {kind=value;lot=null;sale=null;error=null;version++;});}}),
      TextField(controller:clientSearch,maxLength:100,decoration:const InputDecoration(labelText:'Rechercher un client sur la tablette')),
      TextButton(onPressed:searching?null:()=>search(true),child:const Text('Rechercher le client')),
      DropdownButtonFormField<Map<String,dynamic>>(key:ValueKey('client-$version'),initialValue:client,
        decoration:const InputDecoration(labelText:'Client'),items:[for(final row in clients)DropdownMenuItem(value:row,child:Text((row['data'] as Map)['nom'].toString()))],
        validator:(value)=>value==null?'Choisissez le client.':null,onChanged:chooseClient),
      if(kind!='ENCAISSEMENT') ...[
        TextField(controller:lotSearch,maxLength:100,decoration:const InputDecoration(labelText:'Rechercher un lot')),
        TextButton(onPressed:searching?null:()=>search(false),child:const Text('Rechercher le lot')),
        DropdownButtonFormField<Map<String,dynamic>>(key:ValueKey('sale-lot-$version'),initialValue:lot,
          decoration:const InputDecoration(labelText:'Lot'),items:[for(final row in lots.where((row)=>kind!='VENTE_OEUFS' || (row['data'] as Map)['type_production']=='OEUFS'))DropdownMenuItem(value:row,child:Text((row['data'] as Map)['nom'].toString()))],
          validator:(value)=>value==null?'Choisissez le lot.':null,onChanged:(value)=>setState(()=>lot=value)),
        if(kind=='VENTE_OEUFS') DropdownButtonFormField<String>(initialValue:pack,decoration:const InputDecoration(labelText:'Conditionnement'),
          items:const [DropdownMenuItem(value:'UNITE',child:Text('Unité')),DropdownMenuItem(value:'DOUZAINE',child:Text('Douzaine')),DropdownMenuItem(value:'PLATEAU',child:Text('Plateau de 30')),DropdownMenuItem(value:'CARTON',child:Text('Carton')),DropdownMenuItem(value:'COMPOSE',child:Text('Alvéoles et œufs supplémentaires'))],
          onChanged:(value) {if(value!=null) {setState(()=>pack=value);}}),
        if(kind=='VENTE_OEUFS' && pack=='CARTON') TextFormField(controller:size,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Œufs par carton'),validator:integer),
        TextFormField(key:const ValueKey('sale-quantity'),controller:quantity,keyboardType:TextInputType.number,
          decoration:InputDecoration(labelText:kind=='VENTE_OEUFS'?pack=='COMPOSE'?'Alvéoles de 30':'Nombre de conditionnements':'Animaux vendus'),
          validator:(value)=>kind=='VENTE_OEUFS' && pack=='COMPOSE'?RegExp(r'^[0-9]{1,9}$').hasMatch(value??'')?null:'Nombre d’alvéoles positif ou nul requis.':integer(value)),
        if(kind=='VENTE_OEUFS' && pack=='COMPOSE') TextFormField(controller:extraEggs,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Œufs supplémentaires (0 à 29)'),
          validator:(value)=>RegExp(r'^[0-9]{1,2}$').hasMatch(value??'') && (int.tryParse(value??'')??30)<=29?null:'Indiquez de 0 à 29 œufs.'),
        TextFormField(key:const ValueKey('sale-price'),controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:InputDecoration(labelText:kind=='VENTE_OEUFS' && pack=='COMPOSE'?'Prix total de la vente':'Prix unitaire du conditionnement / animal'),validator:decimal),
        if(lot!=null) Text('Dernier stock confirmé : ${(lot!['data'] as Map)[kind=='VENTE_OEUFS'?'stock_oeufs':'stock']} • stock projeté : ${(lot!['data'] as Map)[kind=='VENTE_OEUFS'?'projected_egg_stock':'projected_stock']}'),
        if(shortage) const Text('Alerte : cette vente dépasse le stock projeté. Indiquez le motif ; le serveur devra rapprocher ce constat.',style:TextStyle(color:Colors.red,fontWeight:FontWeight.bold)),
        TextFormField(key:const ValueKey('sale-note'),controller:note,maxLength:10000,decoration:const InputDecoration(labelText:'Motif / constat'),
          validator:(value)=>shortage && (value??'').trim().isEmpty?'Indiquez le motif de la survente.':null),
        const Text('Vente enregistrée sur la tablette — confirmation serveur en attente. Une survente restera à rapprocher.'),
      ] else ...[
        DropdownButtonFormField<Map<String,dynamic>>(key:ValueKey('cash-sale-$version'),initialValue:sale,decoration:const InputDecoration(labelText:'Vente visée (facultative)'),
          items:[const DropdownMenuItem(value:null,child:Text('Encaissement sans vente visée')),for(final row in sales)DropdownMenuItem(value:row,child:Text((row['data'] as Map)['nom'].toString()))],onChanged:(value)=>setState(()=>sale=value)),
        TextFormField(key:const ValueKey('cash-amount'),controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Montant physiquement reçu'),validator:decimal),
        DropdownButtonFormField<String>(initialValue:mode,decoration:const InputDecoration(labelText:'Mode de réception'),
          items:const [DropdownMenuItem(value:'ESPECES',child:Text('Espèces')),DropdownMenuItem(value:'MOBILE_MONEY',child:Text('Mobile money')),DropdownMenuItem(value:'VIREMENT',child:Text('Virement')),DropdownMenuItem(value:'CHEQUE',child:Text('Chèque'))],
          onChanged:(value) {if(value!=null) {setState(()=>mode=value);}}),
        TextFormField(controller:note,maxLength:10000,decoration:const InputDecoration(labelText:'Constat / note')),
      ],
      TextButton(onPressed:chooseDate,child:Text('Date métier : ${occurred.day}/${occurred.month}/${occurred.year} ${occurred.hour}:${occurred.minute.toString().padLeft(2,'0')}')),
      if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
    ])))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
      FilledButton(onPressed:save,child:const Text('Conserver sur la tablette'))]);
}
