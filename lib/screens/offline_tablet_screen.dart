import 'package:flutter/material.dart';
import '../config.dart';
import '../offline/device_identity.dart';
import '../offline/foundation_api.dart';
import '../offline/local_operator_session.dart';
import '../offline/tablet_controller.dart';
import '../offline/outbox_transport.dart';
import '../offline/outbox.dart';
part 'terrain_personal_dialogs.dart';
part 'terrain_operation_dialog.dart';
part 'terrain_sale_dialog.dart';

class OfflineTabletScreen extends StatefulWidget {
  const OfflineTabletScreen({super.key,this.controller});
  final TabletController? controller;
  @override
  State<OfflineTabletScreen> createState()=>_OfflineTabletScreenState();
}

class _OfflineTabletScreenState extends State<OfflineTabletScreen> with WidgetsBindingObserver {
  late final TabletController tablet;
  final username=TextEditingController(),password=TextEditingController();
  bool busy=false;
  String? message;
  String collection='lots';
  int offset=0;
  List<Map<String,dynamic>> rows=[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const secrets=AndroidOperatorSecretStore();
    tablet=widget.controller ?? TabletController(api:FoundationApi(baseUrl:Config.validatedApiUrl(Config.apiUrl),
      deviceIdentity:AndroidDeviceIdentity(),secrets:secrets),secrets:secrets);
    _run(tablet.initialize);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    tablet.setForeground(state==AppLifecycleState.resumed);
    if(state!=AppLifecycleState.resumed) { tablet.lock(); if(mounted) setState(()=>rows=[]); }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tablet.lock();tablet.api.close();tablet.dispose();
    username.dispose();password.dispose();super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if(busy) return;
    setState(() {busy=true;message=null;});
    try { await action(); }
    catch(error) {
      if(mounted) {
        setState(()=>message=error is StateError?error.message.toString():
          error is FoundationApiException || error is DeviceTransportException?error.toString():'Connexion ou stockage sécurisé indisponible.');
      }
    } finally { if(mounted) setState(()=>busy=false); }
  }

  Future<String?> _pinDialog({String title='PIN personnel'}) async {
    return showDialog<String>(context:context,builder:(_)=>_PersonalPinDialog(title:title));
  }

  Future<void> _read() async {rows=await tablet.readPage(collection,offset:offset);}

  Future<void> _createClient() async {
    final author=tablet.operators?.session;
    final payload=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>const _TerrainClientDialog());
    if(payload==null || !mounted) {return;}
    await _run(() async {
      if(author==null || !identical(author,tablet.operators?.session)) {throw StateError('Le profil a été verrouillé. Rouvrez votre PIN.');}
      await tablet.declare(entityType:'CLIENT',operationType:'CREATE',payload:payload,businessOccurredAt:DateTime.now().toUtc());
      collection='clients';offset=0;await _read();
      if(mounted) {setState(()=>message='Client enregistré sur la tablette — confirmation serveur en attente.');}
    });
  }

  Future<void> _reportTask(Map<String,dynamic> row) async {
    final author=tablet.operators?.session;
    final task=Map<String,dynamic>.from(row['data'] as Map);
    if(task['status']=='CANCELLED') {return;}
    final report=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>_TerrainTaskDialog(task:task));
    if(report==null || !mounted) {return;}
    await _run(() async {
      if(author==null || !identical(author,tablet.operators?.session)) {throw StateError('Le profil a été verrouillé. Rouvrez votre PIN.');}
      await tablet.declare(entityType:'TASK',operationType:'UPDATE',payload:{'task_id':task['id'],...report},
        expectedServerVersion:task['version'].toString(),dependencies:row['dependency']==null?[]:[row['dependency'] as String],
        businessOccurredAt:DateTime.now().toUtc());
      await _read();
      if(mounted) {setState(()=>message='Compte rendu conservé sur la tablette — confirmation serveur en attente.');}
    });
  }

  Future<void> _terrainOperation() async {
    final author=tablet.operators?.session;
    final lots=<Map<String,dynamic>>[],species=<Map<String,dynamic>>[],categories=<Map<String,dynamic>>[];
    var loaded=false;
    await _run(() async {
      for(final pair in [('lots',lots),('species',species),('expense_categories',categories)]) {
        var page=0;
        while(page<200) {
          final rows=await tablet.readPage(pair.$1,offset:page);pair.$2.addAll(rows);
          if(rows.length<50) {break;}page+=50;
        }
      }
      loaded=true;
    });
    if(!loaded || !mounted || author==null || !identical(author,tablet.operators?.session)) {return;}
    final declaration=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>_TerrainOperationDialog(lots:lots,species:species,categories:categories,
      searchLots:(search)=>tablet.readPage('lots',search:search),
      expenses:tablet.outboxRows.where((entry)=>entry.declaration['entity_type']=='DEPENSE' && !{'NEEDS_RECONCILIATION','NOT_APPLIED','SUPERSEDED'}.contains(entry.businessStatus)).toList()));
    if(declaration==null || !mounted) {return;}
    await _run(() async {
      if(!identical(author,tablet.operators?.session)) {throw StateError('Le profil a été verrouillé. Rouvrez votre PIN.');}
      await tablet.declare(entityType:declaration['entity_type'] as String,operationType:'CREATE',payload:Map<String,dynamic>.from(declaration['payload'] as Map),
        dependencies:List<String>.from(declaration['dependencies'] as List),businessOccurredAt:declaration['occurred'] as DateTime);
      await _read();
      if(mounted) {setState(()=>message='Opération conservée sur la tablette — confirmation serveur en attente.');}
    });
  }

  Future<void> _terrainSale() async {
    final author=tablet.operators?.session;
    final lots=<Map<String,dynamic>>[],clients=<Map<String,dynamic>>[];
    var loaded=false;
    await _run(() async {
      lots.addAll(await tablet.readPage('lots'));clients.addAll(await tablet.readPage('clients'));loaded=true;
    });
    if(!loaded || !mounted || author==null || !identical(author,tablet.operators?.session)) {return;}
    final declaration=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>_TerrainSaleDialog(
      lots:lots,clients:clients,searchLots:(search)=>tablet.readPage('lots',search:search),
      searchClients:(search)=>tablet.readPage('clients',search:search),clientSales:(client)=>tablet.readPage('sales',search:client)));
    if(declaration==null || !mounted) {return;}
    await _run(() async {
      if(!identical(author,tablet.operators?.session)) {throw StateError('Le profil a été verrouillé. Rouvrez votre PIN.');}
      await tablet.declare(entityType:declaration['entity_type'] as String,operationType:'CREATE',
        payload:Map<String,dynamic>.from(declaration['payload'] as Map),dependencies:List<String>.from(declaration['dependencies'] as List),
        businessOccurredAt:declaration['occurred'] as DateTime);
      collection=declaration['entity_type']=='ENCAISSEMENT'?'cash':'sales';offset=0;await _read();
      if(mounted) {setState(()=>message=collection=='sales'?'Vente enregistrée sur la tablette — confirmation serveur en attente.':
        'Montant reçu conservé sur la tablette — affectation serveur en attente.');}
    });
  }

  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:tablet,builder:(context,_) {
    final session=tablet.operators?.session;
    return Scaffold(appBar:AppBar(title:const Text('Tablette de l’exploitation'),actions:[
      if(session!=null) IconButton(tooltip:'Verrouiller / changer d’opérateur',icon:const Icon(Icons.lock_outline),
        onPressed:busy?null:()=>setState(() {tablet.lock();rows=[];})),
    ]),body:ListView(padding:const EdgeInsets.all(16),children:[
      if(busy) const LinearProgressIndicator(),
      if(message!=null) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(message!,style:const TextStyle(color:Colors.red))),
      Text(tablet.farmId==null?'Cette tablette doit être préparée par le propriétaire.':
        'Exploitation ${tablet.farmId} • données conservées sur cette tablette'),
      const SizedBox(height:16),
      if(tablet.farmId!=null) ...[
        Text(tablet.sync?.busy==true?'Synchronisation en cours…':
          tablet.sync?.networkAvailable==true?'Réseau disponible':tablet.sync?.networkAvailable==false?'Hors ligne':'État du réseau en cours de vérification'),
        Text(tablet.sync?.summary.lastSuccess==null?'Aucune synchronisation réussie enregistrée':
          'Dernière synchronisation : ${tablet.sync!.summary.lastSuccess!.toLocal()}'),
        Text('${tablet.sync?.summary.pending??0} déclarations en attente • ${tablet.sync?.summary.conflicts??0} conflits à rapprocher'),
        if((tablet.sync?.summary.blocked??0)>0) const Text('Transmission bloquée : intervention du propriétaire nécessaire.'),
        if(tablet.sync?.error!=null) Text(tablet.sync!.error!),
        OutlinedButton(onPressed:busy || tablet.sync?.busy==true?null:()=>_run(() async {
          await tablet.syncOutbox();
          if(tablet.operators?.session!=null) await _read();
        }),
          child:const Text('Synchroniser maintenant')),
      ],
      if(session==null) ...[
        for(final profile in tablet.profiles) ListTile(leading:const Icon(Icons.person_outline),
          title:Text(profile['display_name'] as String),subtitle:const Text('Ouvrir avec mon PIN'),
          enabled:!busy,onTap:() async {
            final pin=await _pinDialog();
            if(pin==null || !mounted) return;
            await _run(() async {
              await tablet.unlockProfile(profile['user_id'] as int,profile['display_name'] as String,pin);
              offset=0;await _read();
            });
          }),
        const Divider(),
        const Text('Préparation avec une connexion Internet'),
        TextField(controller:username,autocorrect:false,decoration:const InputDecoration(labelText:'Compte personnel')),
        TextField(controller:password,obscureText:true,enableSuggestions:false,autocorrect:false,
          decoration:const InputDecoration(labelText:'Mot de passe')),
        FilledButton(onPressed:busy?null:()=>_run(() async {
          try {await tablet.signIn(username.text.trim(),password.text);} finally {password.clear();}
        }),child:const Text('Me connecter')),
        if(tablet.api.personal?.role=='OWNER') ...[
          OutlinedButton(onPressed:busy?null:()=>_run(tablet.preparePrimaryTablet),child:const Text('Préparer cette tablette principale')),
          const Text('L’activation hors ligne de l’exploitation doit être décidée par le propriétaire. '
            'La préparation de tablette ne l’active pas automatiquement.'),
          OutlinedButton(onPressed:busy || tablet.cache==null?null:()=>_run(tablet.refreshCache),child:const Text('Actualiser les données confirmées')),
        ],
        if(tablet.api.personal?.role=='OPERATEUR') OutlinedButton(onPressed:busy?null:() async {
          final pin=await _pinDialog(title:'Préparer ou renouveler mon profil');
          if(pin==null || !mounted) return;
          await _run(()=>tablet.prepareOperator(pin));
        },child:const Text('Préparer mon accès par PIN')),
      ] else ...[
        Text('Profil ouvert : ${tablet.selectedName}',style:Theme.of(context).textTheme.titleMedium),
        FilledButton.icon(onPressed:busy?null:_createClient,icon:const Icon(Icons.person_add_outlined),label:const Text('Enregistrer un client')),
        FilledButton.icon(onPressed:busy?null:_terrainOperation,icon:const Icon(Icons.add_circle_outline),label:const Text('Enregistrer une opération terrain')),
        FilledButton.icon(onPressed:busy?null:_terrainSale,icon:const Icon(Icons.point_of_sale),label:const Text('Enregistrer une vente ou un encaissement')),
        for(final entry in tablet.outboxRows) ListTile(
          title:Text('Déclaration ${entry.sequence}'),
          subtitle:Text(entry.businessStatus=='CONFIRMED'?'Confirmée par le serveur':
            entry.businessStatus=='NEEDS_RECONCILIATION'?'Reçue • à rapprocher':
            entry.businessStatus=='NOT_APPLIED'?'Reçue • non appliquée':
            entry.businessStatus=='SUPERSEDED'?'Reçue • remplacée avec historique':
            entry.transportStatus=='SERVER_RECEIVED'?'Reçue • confirmation métier en attente':
            entry.transportStatus=='TRANSPORT_BLOCKED'?'Conservée • transmission bloquée':
            'Conservée sur cette tablette • transmission en attente')),
        TextButton(onPressed:busy?null:() async {
          final oldPin=await _pinDialog(title:'Mon PIN actuel');
          if(oldPin==null || !mounted) return;
          final newPin=await _pinDialog(title:'Mon nouveau PIN');
          if(newPin==null || !mounted) return;
          await _run(() async {
            if(!await tablet.operators!.changePin(session.grant,oldPin,newPin)) {
              throw StateError('PIN incorrect ou temporairement bloqué.');
            }
            tablet.lock();rows=[];
          });
        },child:const Text('Changer mon PIN')),
        const Text('Les données confirmées et les déclarations de cette tablette restent distinctes.'),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(key:ValueKey(collection),initialValue:collection,decoration:const InputDecoration(labelText:'Consulter'),
          items:const [DropdownMenuItem(value:'lots',child:Text('Lots')),DropdownMenuItem(value:'clients',child:Text('Clients')),
            DropdownMenuItem(value:'species',child:Text('Espèces')),DropdownMenuItem(value:'tasks',child:Text('Agenda')),
            DropdownMenuItem(value:'sales',child:Text('Ventes')),DropdownMenuItem(value:'cash',child:Text('Encaissements reçus'))],
          onChanged:busy?null:(value) { if(value==null) return;collection=value;offset=0;_run(_read); }),
        for(final row in rows) ListTile(onTap:collection=='tasks' && !busy?()=>_reportTask(row):null,
          title:Text(((row['data'] as Map)['nom']??(row['data'] as Map)['title']??'Donnée').toString()),
          subtitle:collection=='lots'?Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Stock confirmé : ${(row['data'] as Map)['stock']}'),
            Text('Mouvements locaux : ${(row['data'] as Map)['local_delta']??0} • stock projeté : ${(row['data'] as Map)['projected_stock']??(row['data'] as Map)['stock']}'),
            if((row['data'] as Map)['type_production']=='OEUFS') Text('Œufs confirmés : ${(row['data'] as Map)['stock_oeufs']??0} • œufs projetés : ${(row['data'] as Map)['projected_egg_stock']??0}'),
            if(row['state']=='NEEDS_RECONCILIATION') const Text('Rapprochement nécessaire',style:TextStyle(color:Colors.red)),
          ]):collection=='cash'?Text('Reçu : ${(row['data'] as Map)['montant_recu']} • affecté : ${(row['data'] as Map)['montant_affecte']??'en attente'} • à rapprocher : ${(row['data'] as Map)['montant_a_rapprocher']??'en attente'}'):
          collection=='sales'?Text('Montant : ${(row['data'] as Map)['montant_total']} • ${row['state']=='CONFIRMED' || row['state']=='CONFIRMED_CACHE'?'confirmée par le serveur':row['state']=='NEEDS_RECONCILIATION'?'à rapprocher':'document provisoire — confirmation en attente'}'):Text(
            row['state']=='NEEDS_RECONCILIATION'?'Déclaration à rapprocher':
            row['state']!=null && !{'CONFIRMED','CONFIRMED_CACHE'}.contains(row['state'])?'Conservé sur la tablette • confirmation en attente':
            collection=='tasks'?'${(row['data'] as Map)['date']} • ${_taskStatus((row['data'] as Map)['status'])}':'Confirmé par le serveur')),
        if(rows.isEmpty) const Padding(padding:EdgeInsets.all(16),child:Text('Aucune donnée confirmée sur cette page.')),
        Row(children:[TextButton(onPressed:busy || offset==0?null:()=>_run(() async {offset-=50;await _read();}),child:const Text('Précédent')),
          TextButton(onPressed:busy || rows.length<50?null:()=>_run(() async {offset+=50;await _read();}),child:const Text('Suivant'))]),
        OutlinedButton(onPressed:busy?null:()=>_run(() async {await tablet.refreshCache();offset=0;await _read();}),child:const Text('Actualiser avec Internet')),
      ],
    ]));
  });
}

class _PersonalPinDialog extends StatefulWidget {
  const _PersonalPinDialog({required this.title});
  final String title;
  @override
  State<_PersonalPinDialog> createState()=>_PersonalPinDialogState();
}

class _PersonalPinDialogState extends State<_PersonalPinDialog> {
  final pin=TextEditingController();
  @override
  void dispose() {pin.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>AlertDialog(
    title:Text(widget.title),content:TextField(controller:pin,obscureText:true,
      keyboardType:TextInputType.number,maxLength:12,autofocus:true,
      decoration:const InputDecoration(labelText:'6 à 12 chiffres')),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
      FilledButton(onPressed:()=>Navigator.pop(context,pin.text),child:const Text('Valider'))]);
}
