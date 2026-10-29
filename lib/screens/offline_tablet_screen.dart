import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../config.dart';
import '../services/initial_password.dart';
import 'initial_password_screen.dart';
import 'dashboard_screen.dart';
import '../services/api_service.dart';
import '../services/lab_network_gate.dart';
import 'add_depense_screen.dart';
import '../offline/device_identity.dart';
import '../offline/foundation_api.dart';
import '../offline/local_operator_session.dart';
import '../offline/tablet_controller.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/operation_status.dart';
import '../offline/outbox.dart';
import '../services/farm_session.dart';
import '../services/operation_history.dart';
import '../widgets/farm_navigation.dart';
import '../widgets/operation_history_list.dart';
part 'terrain_personal_dialogs.dart';
part 'terrain_operation_dialog.dart';
part 'terrain_sale_dialog.dart';

class OfflineTabletScreen extends StatefulWidget {
  const OfflineTabletScreen({super.key,this.controller,this.configure=false,this.onOpenOnline});
  final bool configure;
  final Future<void> Function(String access,String username)? onOpenOnline;
  final TabletController? controller;
  @override
  State<OfflineTabletScreen> createState()=>_OfflineTabletScreenState();
}

class _OfflineTabletScreenState extends State<OfflineTabletScreen> with WidgetsBindingObserver {
  late final TabletController tablet;
  final username=TextEditingController(),password=TextEditingController();
  bool busy=false;
  bool manualSyncBusy=false;
  String? message;
  bool messageIsError=false;
  final summaryKey=GlobalKey();
  String collection='lots';
  int offset=0;
  List<Map<String,dynamic>> rows=[];
  bool showHistory=false;
  bool pageMayHaveMore=false;
  bool visibleReadRunning=false,visibleReadPending=false;
  bool _hadOpenProfile=false;
  void _pointerActivity(PointerEvent event) {
    if(event is PointerDownEvent || event is PointerMoveEvent || event is PointerSignalEvent) tablet.userActivity();
  }
  bool _keyActivity(KeyEvent event) {tablet.userActivity();return false;}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const secrets=AndroidOperatorSecretStore();
    tablet=widget.controller ?? TabletController(api:FoundationApi(baseUrl:Config.validatedApiUrl(Config.apiUrl),
      deviceIdentity:AndroidDeviceIdentity(),secrets:secrets),secrets:secrets);
    _hadOpenProfile=tablet.operators?.session!=null;
    tablet.addListener(_tabletChanged);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerActivity);
    HardwareKeyboard.instance.addHandler(_keyActivity);
    _run(tablet.initialize);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    tablet.setForeground(state==AppLifecycleState.resumed);
    if(state==AppLifecycleState.detached) { tablet.lock(); if(mounted) setState(()=>rows=[]); }
  }
  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerActivity);
    HardwareKeyboard.instance.removeHandler(_keyActivity);
    WidgetsBinding.instance.removeObserver(this);
    tablet.removeListener(_tabletChanged);
    tablet.lock();tablet.api.close();tablet.dispose();
    username.dispose();password.dispose();super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if(busy) return;
    setState(() {busy=true;message=null;messageIsError=false;});
    try { await action(); }
    on InitialPasswordRequired catch(requiredChange) {
      password.clear();
      if(mounted) {
        final changed=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>InitialPasswordScreen(
          onChange:tablet.api.changeInitialPassword,changeToken:requiredChange.changeToken)));
        if(mounted) setState(() {messageIsError=changed!=true;message=changed==true
          ?'Mot de passe modifié. Reconnectez votre compte personnel avec le nouveau mot de passe avant de préparer le PIN.'
          :'Le changement du mot de passe initial est nécessaire. Reconnectez votre compte personnel.';});
      }
    }
    catch(error) {
      if(mounted) {
        setState(() {messageIsError=true;message=tabletErrorMessage(error);});
      }
    } finally { if(mounted) setState(()=>busy=false); }
  }

  Future<void> _openOnlineSpace() async {
    final personal=tablet.api.personal;
    if(personal==null || personal.role!='OPERATEUR' || tablet.offlinePolicyEnabled) {
      throw StateError('Reconnectez votre compte personnel.');
    }
    if(widget.onOpenOnline!=null) {
      await widget.onOpenOnline!(personal.access,username.text.trim());
      return;
    }
    final api=ApiService();
    try {
      await api.usePersonalOnlineSession(personal.access,username.text.trim());
    } catch (_) {
      api.close();
      rethrow;
    }
    if(!mounted) {api.close();return;}
    Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>DashboardScreen(apiService:api)));
  }

  Future<void> _cancelOperation(OutboxEntry entry) async {
    final author=tablet.operators?.session;
    final reason=await showDialog<String>(context:context,builder:(_)=>const _RecoveryReasonDialog(cancellation:true));
    if(reason==null || !mounted || !identical(author,tablet.operators?.session)) return;
    await _run(() async {
      final payload=entry.declaration['payload'] as Map;
      await tablet.declare(entityType:entry.declaration['entity_type'] as String,operationType:'REVERSE',
        payload:{'original_operation_id':entry.operationId,'reason':reason,
          if(payload['lot_ref']!=null) 'lot_ref':payload['lot_ref']},
        dependencies:[entry.operationId],businessOccurredAt:tablet.clock().toUtc());
      if(mounted) setState(()=>message='Annulation enregistrée. Ses effets attendent la confirmation du serveur.');
    });
  }

  Future<String?> _pinDialog({String title='PIN personnel'}) async {
    return showDialog<String>(context:context,builder:(_)=>_PersonalPinDialog(title:title));
  }

  List<Map<String,dynamic>> _activeRows(String page,List<Map<String,dynamic>> values) =>
    page=='tasks'?values.where((row)=>(row['data'] as Map)['status']!='CANCELLED').toList():values;

  Future<void> _read() async {
    final values=await tablet.readPage(collection,offset:offset);
    pageMayHaveMore=values.length==50;rows=_activeRows(collection,values);
  }

  // Receipts update the local cache independently of this page's manual sync button.
  // Refresh only local data and never publish a late read into another PIN profile.
  void _tabletChanged() {
    final opened=tablet.operators?.session!=null;
    if(_hadOpenProfile && !opened && mounted) {
      final route=ModalRoute.of(context);
      Navigator.of(context).popUntil((candidate)=>candidate==route || candidate.isFirst);
      setState(() {rows=[];showHistory=false;message=null;});
    }
    _hadOpenProfile=opened;
    if(!mounted || busy || showHistory || tablet.operators?.session==null) return;
    visibleReadPending=true;
    if(!visibleReadRunning) unawaited(_refreshVisibleRows());
  }

  Future<void> _refreshVisibleRows() async {
    visibleReadRunning=true;
    try {
      while(visibleReadPending && mounted) {
        visibleReadPending=false;
        final author=tablet.operators?.session,page=collection,pageOffset=offset;
        if(author==null || busy || showHistory) continue;
        try {
          final values=await tablet.readPage(page,offset:pageOffset);
          if(mounted && !busy && !showHistory && page==collection && pageOffset==offset &&
              identical(author,tablet.operators?.session)) {
            setState(() {rows=_activeRows(page,values);pageMayHaveMore=values.length==50;});
          }
        } catch (_) { /* A locked/replaced profile cannot publish this read. */ }
      }
    } finally {visibleReadRunning=false;}
  }

  Future<void> _syncNow() async {
    if(busy || manualSyncBusy || tablet.knownDeviceRevoked || tablet.sync?.busy==true) return;
    setState(()=>manualSyncBusy=true);
    final author=tablet.operators?.session;
    try {
      // The existing coordinator owns the flight; do not lock all UI actions.
      await tablet.syncOutbox();
      if(!mounted || busy || author==null || !identical(author,tablet.operators?.session)) return;
      final pageCollection=collection,pageOffset=offset;
      final values=await tablet.readPage(pageCollection,offset:pageOffset);
      final nextRows=_activeRows(pageCollection,values);
      if(mounted && !busy && collection==pageCollection && offset==pageOffset &&
          identical(author,tablet.operators?.session)) {
        setState(() {rows=nextRows;pageMayHaveMore=values.length==50;});
      }
    } catch(error) {
      if(mounted && !busy) setState(() {messageIsError=true;message=tabletErrorMessage(error);});
    } finally {
      if(mounted) setState(()=>manualSyncBusy=false);
    }
  }

  Future<void> _recover() async {
    final reason=await showDialog<String>(context:context,builder:(_)=>const _RecoveryReasonDialog());
    if(reason==null || !mounted) return;
    await _run(() async {
      final count=await tablet.recoverPending(reason);
      if(mounted) setState(()=>message='$count déclarations récupérées. Les décisions métier restent distinctes.');
    });
  }

  Future<void> _createClient() async {
    final author=tablet.operators?.session;
    final payload=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>const _TerrainClientDialog());
    if(payload==null || !mounted) {return;}
    await _run(() async {
      if(author==null || !identical(author,tablet.operators?.session)) {throw StateError('Le profil a été verrouillé. Rouvrez votre PIN.');}
      await tablet.declare(entityType:'CLIENT',operationType:'CREATE',payload:payload,businessOccurredAt:DateTime.now().toUtc());
      collection='clients';offset=0;await _read();
      if(mounted) {setState(()=>message='Enregistré sur cet appareil');}
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
      if(mounted) {setState(()=>message='Enregistré sur cet appareil');}
    });
  }

  void _selectPage(String value) {
    if(busy) return;
    Navigator.pop(context);
    collection=value;offset=0;showHistory=false;rows=[];pageMayHaveMore=false;_run(_read);
  }

  void _openOperation(String kind) {
    if(busy) return;
    Navigator.pop(context);
    _terrainOperation(initialKind:kind);
  }

  Future<void> _terrainOperation({String initialKind='ALIMENTATION'}) async {
    if(initialKind=='DEPENSE') {
      if(busy) return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>AddDepenseScreen(tablet:tablet)));
      if(mounted && tablet.operators?.session!=null) await _run(_read);
      return;
    }
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
    final declaration=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>_TerrainOperationDialog(initialKind:initialKind,lots:lots,species:species,categories:categories,
      searchLots:(search)=>tablet.readPage('lots',search:search),
      expenses:tablet.outboxRows.where((entry)=>entry.declaration['entity_type']=='DEPENSE' && !{'NEEDS_RECONCILIATION','NOT_APPLIED','SUPERSEDED'}.contains(entry.businessStatus)).toList()));
    if(declaration==null || !mounted) {return;}
    if(declaration['entity_type']=='DEPENSE') {
      await _terrainOperation(initialKind:'DEPENSE');return;
    }
    await _run(() async {
      if(!identical(author,tablet.operators?.session)) {throw StateError('Le profil a été verrouillé. Rouvrez votre PIN.');}
      await tablet.declare(entityType:declaration['entity_type'] as String,operationType:'CREATE',payload:Map<String,dynamic>.from(declaration['payload'] as Map),
        dependencies:List<String>.from(declaration['dependencies'] as List),businessOccurredAt:declaration['occurred'] as DateTime);
      await _read();
      if(mounted) {setState(()=>message='Enregistré sur cet appareil');}
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
    Future<Map<String,dynamic>> readLot(Map<String,dynamic> selected) async {
        if(!identical(author,tablet.operators?.session)) throw StateError('Profil changé.');
        final id=(selected['data'] as Map)['id'];
        for(var page=0;;page+=50) {
          final rows=await tablet.readPage('lots',offset:page);
          if(!identical(author,tablet.operators?.session)) throw StateError('Profil changé.');
          final matches=rows.where((row)=>(row['data'] as Map)['id']==id).toList();
          if(matches.length==1) return matches.single;
          if(matches.length>1 || rows.isEmpty) throw StateError('Référence absente ou ambiguë.');
        }
    }
    final declaration=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>_TerrainSaleDialog(
      lots:lots,clients:clients,searchLots:(search)=>tablet.readPage('lots',search:search),
      searchClients:(search)=>tablet.readPage('clients',search:search),clientSales:(client)=>tablet.readPage('sales',search:client),
      refreshLot:readLot));
    if(declaration==null || !mounted) {return;}
    await _run(() async {
      if(!identical(author,tablet.operators?.session)) {throw StateError('Le profil a été verrouillé. Rouvrez votre PIN.');}
      await tablet.declare(entityType:declaration['entity_type'] as String,operationType:'CREATE',
        payload:Map<String,dynamic>.from(declaration['payload'] as Map),dependencies:List<String>.from(declaration['dependencies'] as List),
        businessOccurredAt:declaration['occurred'] as DateTime,
        // enqueue runs this guard in the same transaction, after inserting
        // this original. Remove its own delta when comparing with the stock
        // reviewed in the dialog; any intervening change rolls back the write.
        project:declaration['validated_lot']==null?null:() async {
          final reviewed=declaration['validated_lot'] as Map<String,dynamic>;
          final current=await readLot(reviewed);
          final before=reviewed['data'] as Map,after=current['data'] as Map;
          final key=declaration['entity_type']=='VENTE_OEUFS'?'projected_egg_stock':'projected_stock';
          final quantity=declaration['stock_quantity'] as int;
          if(['stock','stock_oeufs','projected_stock','projected_egg_stock'].any((field)=>
              after[field]!=(before[field] as int)-(field==key?quantity:0)) ||
              reviewed['dependency']!=current['dependency'] || reviewed['state']!=current['state']) {
            throw StateError('Le stock a changé pendant la validation. Rouvrez la vente et vérifiez le stock actualisé.');
          }
        });
      collection=declaration['entity_type']=='ENCAISSEMENT'?'cash':'sales';offset=0;await _read();
      if(mounted) {setState(()=>message='Enregistré sur cet appareil');}
    });
  }

  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:tablet,builder:(context,_) {
    final session=tablet.operators?.session;
    return Scaffold(
      bottomNavigationBar: Config.current.isLab ? SafeArea(child: ListenableBuilder(
        listenable: LabNetworkGate.instance,
        builder: (context, _) => MaterialBanner(
          content: Text(LabNetworkGate.instance.enabled
            ? 'LABORATOIRE — données synthétiques — réseau autorisé sous preuve externe'
            : 'LABORATOIRE — réseau arrêté — synchronisation automatique désactivée'),
          actions: [TextButton(onPressed: LabNetworkGate.instance.stop,
            child: const Text('Arrêter le réseau'))],
        ),
      )) : null,drawer: session==null?null:Drawer(child:SafeArea(child:ListView(children:[
      FarmNavigation(session:FarmSession.fromTablet(tablet),actions:{
        FarmDestination.dashboard:()=>_selectPage('lots'),
        FarmDestination.lots:()=>_selectPage('lots'),
        FarmDestination.purchases:()=>_openOperation('ACHAT'),
        FarmDestination.sales:() {Navigator.pop(context);_terrainSale();},
        FarmDestination.expenses:()=>_openOperation('DEPENSE'),
        FarmDestination.movements:()=>_openOperation('MORTALITE'),
        FarmDestination.history:() {if(busy) return;Navigator.pop(context);setState(()=>showHistory=true);},
        FarmDestination.agenda:()=>_selectPage('tasks'),
        FarmDestination.production:()=>_openOperation('COLLECTE_OEUFS'),
      }),
    ]))),appBar:AppBar(title:Text(widget.configure?'Configurer ma tablette':'Parcours utilisateur'),actions:[
      ConnectionIndicator(networkAvailable:tablet.sync?.networkAvailable,
        lastSuccess:tablet.sync?.networkAvailable==true?tablet.sync?.summary.lastSuccess:null,
        syncing:manualSyncBusy || tablet.sync?.busy==true,syncUnavailable:tablet.sync?.error!=null,
        pending:tablet.sync?.summary.pending,conflicts:tablet.sync?.summary.conflicts,
        onSummary:()=>Scrollable.ensureVisible(summaryKey.currentContext!,duration:const Duration(milliseconds:200))),
      if(session!=null) IconButton(tooltip:'Verrouiller / changer d’opérateur',icon:const Icon(Icons.lock_outline),
        onPressed:busy?null:()=>setState(() {tablet.lock();rows=[];})),
    ]),body:ListView(padding:const EdgeInsets.all(16),children:[
      if(busy) const LinearProgressIndicator(),
      if(message!=null) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(message!,style:TextStyle(color:messageIsError?Colors.red:Colors.blueGrey))),
      Text(tablet.farmId==null?'Cette tablette doit être préparée par le propriétaire.':
        'Exploitation ${tablet.farmId} • données conservées sur cette tablette'),
      const SizedBox(height:16),
      if(tablet.farmId!=null) ...[
        Text(key:summaryKey,'État de cette tablette • tous profils'),
        Text(tablet.sync?.summary.lastSuccess==null?'Aucune synchronisation réussie enregistrée':
          'Dernière synchronisation : ${tablet.sync!.summary.lastSuccess!.toLocal()}'),
        if(tablet.sync!=null) ...[
          Text(tablet.sync!.busy?'Synchronisation en cours':'Synchronisation en attente du réseau ou du prochain essai'),
          Text('${tablet.sync!.summary.pending} déclarations à transmettre • ${tablet.sync!.summary.conflicts} opérations à vérifier'),
          Text('${tablet.sync!.summary.awaitingValidation} reçues • confirmation en attente'),
        ] else const Text('Compteurs de synchronisation indisponibles'),
        if(tablet.authorizationStatus!=null) Text(tablet.authorizationStatus!),
        if(tablet.knownDeviceRevoked) const Text('Cette tablette est révoquée. Les déclarations conservées nécessitent une récupération explicite par le propriétaire.'),
        if((tablet.sync?.summary.blocked??0)>0) const Text('Transmission bloquée : intervention du propriétaire nécessaire.'),
        if(tablet.sync?.error!=null) const Text('Synchronisation indisponible : vos données sont conservées'),
        OutlinedButton(onPressed:busy || manualSyncBusy || tablet.knownDeviceRevoked || tablet.sync?.busy==true?null:_syncNow,
          child:const Text('Synchroniser maintenant')),
      ],
      if(session==null) ...[
        Text(tablet.sessionTransitionLabel),
        for(final profile in tablet.profiles) ListTile(leading:const Icon(Icons.person_outline),
          title:Text(profile['display_name'] as String),subtitle:const Text('Ouvrir avec mon PIN'),
          enabled:!busy && !tablet.knownDeviceRevoked,onTap:() async {
            final pin=await _pinDialog();
            if(pin==null || !mounted) return;
            await _run(() async {
              await tablet.unlockProfile(profile['user_id'] as int,profile['display_name'] as String,pin);
              offset=0;await _read();
            });
          }),
        const Divider(),
        const Text('Préparation avec une connexion Internet'),
        if(widget.configure || tablet.api.personal?.role=='OWNER') ...[
          const Text('Configurer ma tablette',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          Text('${tablet.api.personal?.role=='OWNER'?'✓':'1.'} Connexion personnelle du propriétaire'),
          Text('${tablet.deviceId!=null && !tablet.knownDeviceRevoked?'✓':'2.'} Préparer la tablette principale'),
          Text('${tablet.offlinePolicyEnabled?'✓':'3.'} Activer le parcours hors ligne après confirmation'),
          Text('${tablet.lastCompleteCacheRefresh!=null?'✓':'4.'} Charger les données nécessaires'),
          Text(tablet.api.personal?.role=='OWNER' && tablet.deviceId!=null && !tablet.knownDeviceRevoked &&
            tablet.offlinePolicyEnabled && tablet.lastCompleteCacheRefresh!=null
            ? 'Préparation propriétaire terminée. Chaque opérateur doit encore préparer son PIN et obtenir ses droits.'
            : '5. Préparation à terminer : seules les étapes confirmées sont cochées.'),
          const SizedBox(height:12),
        ],
        TextField(controller:username,autocorrect:false,decoration:const InputDecoration(labelText:'Compte personnel')),
        TextField(controller:password,obscureText:true,enableSuggestions:false,autocorrect:false,
          decoration:const InputDecoration(labelText:'Mot de passe')),
        FilledButton(onPressed:busy?null:()=>_run(() async {
          try {
            await tablet.signIn(username.text.trim(),password.text);
            if(mounted) setState(() {
              message=tablet.api.personal?.role=='OPERATEUR' && !tablet.offlinePolicyEnabled
                ?'Connexion réussie. Appuyez sur « Ouvrir mon espace en ligne » pour commencer.'
                :'Connexion réussie. Terminez la préparation de votre tablette et de votre PIN.';
            });
          } finally {password.clear();}
        }),child:const Text('Me connecter')),
        if(tablet.api.personal?.role=='OPERATEUR' && !tablet.offlinePolicyEnabled)
          FilledButton(onPressed:busy?null:()=>_run(_openOnlineSpace),
            child:const Text('Ouvrir mon espace en ligne')),
        if(tablet.api.personal?.role=='OWNER') ...[
          if(tablet.knownDeviceRevoked) OutlinedButton(onPressed:busy?null:_recover,
            child:const Text('Récupérer les déclarations conservées')),
          OutlinedButton(onPressed:busy?null:()=>_run(tablet.preparePrimaryTablet),child:const Text('Préparer cette tablette principale')),
          const Text('L’activation hors ligne de l’exploitation doit être décidée par le propriétaire. '
            'La préparation de tablette ne l’active pas automatiquement.'),
          if(tablet.farmId!=null && !tablet.knownDeviceRevoked) OutlinedButton(
            onPressed:busy || tablet.offlinePolicyEnabled?null:() async {
              final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
                title:const Text('Activer le parcours hors ligne ?'),
                content:const Text('Cette décision concerne votre exploitation. Une tablette principale active et au moins un opérateur actif sont requis. Les droits individuels restent applicables.'),
                actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Annuler')),
                  FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Activer'))]));
              if(confirmed!=true || !mounted) return;
              await _run(() async {await tablet.enableOfflinePolicy();if(mounted) setState(() {message='Activation hors ligne confirmée par le serveur.';});});
            },child:Text(tablet.offlinePolicyEnabled?'Hors ligne activé':'Activer le parcours hors ligne')),
          OutlinedButton(onPressed:busy || tablet.cache==null?null:()=>_run(tablet.refreshCache),child:const Text('Actualiser les données confirmées')),
        ],
        if(tablet.api.personal?.role=='OPERATEUR' && tablet.offlinePolicyEnabled) OutlinedButton(onPressed:busy?null:() async {
          final pin=await _pinDialog(title:'Préparer ou renouveler mon profil');
          if(pin==null || !mounted) return;
          await _run(()=>tablet.prepareOperator(pin));
        },child:const Text('Préparer mon accès par PIN')),
      ] else ...[
        Text(tablet.sessionTransitionLabel),
        Text('Profil ouvert : ${tablet.selectedName}',style:Theme.of(context).textTheme.titleMedium),
        FilledButton.icon(onPressed:busy?null:_createClient,icon:const Icon(Icons.person_add_outlined),label:const Text('Enregistrer un client')),
        FilledButton.icon(onPressed:busy?null:_terrainOperation,icon:const Icon(Icons.add_circle_outline),label:const Text('Enregistrer une opération terrain')),
        FilledButton.icon(onPressed:busy?null:_terrainSale,icon:const Icon(Icons.point_of_sale),label:const Text('Enregistrer une vente ou un encaissement')),
        if(showHistory) OperationHistoryList(items:tablet.outboxRows.map(OperationHistoryItem.local).toList()),
        for(final entry in tablet.outboxRows) ListTile(
          title:Text('${entry.declaration['operation_type']=='REVERSE'?'Annulation — ':''}${historyTypeLabel(entry.declaration['entity_type'] as String)} • ${entry.sequence}'),
          subtitle:Text('${entry.declaration['local_recorded_at']}\n${historyDetails(entry.declaration['payload'] as Map)}\n${OperationHistoryItem.local(entry).status}${entry.lastError.isEmpty?'':' • ${historyReasonLabel(entry.lastError)}'}'),
          trailing:!busy && entry.declaration['operation_type']=='CREATE' &&
            {'UNREVIEWED','WAITING_DEPENDENCY','CONFIRMED'}.contains(entry.businessStatus) &&
            session.grant.permitsOperation(entry.declaration['entity_type'] as String,'REVERSE',tablet.clock())
            ?TextButton(onPressed:()=>_cancelOperation(entry),child:const Text('Annuler')):null),
        if(tablet.outboxRows.length==50) TextButton(onPressed:busy?null:()=>_run(()=>tablet.showOutboxPage(tablet.outboxOffset+50)),child:const Text('Opérations plus anciennes')),
        if(tablet.outboxOffset>0) TextButton(onPressed:busy?null:()=>_run(()=>tablet.showOutboxPage(tablet.outboxOffset-50)),child:const Text('Opérations plus récentes')),
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
            if(row['stock_checkpoint_pending']==true) const Text('Confirmations partielles : dernière base serveur cohérente conservée ; mouvements non encore intégrés au stock.'),
            Text('Mouvements locaux : ${(row['data'] as Map)['local_delta']??0} • stock projeté : ${(row['data'] as Map)['projected_stock']??(row['data'] as Map)['stock']}'),
            if((row['data'] as Map)['type_production']=='OEUFS') Text('Œufs confirmés : ${(row['data'] as Map)['stock_oeufs']??'indisponible'} • œufs projetés : ${(row['data'] as Map)['projected_egg_stock']??'indisponible'}'),
            if(row['state']=='NEEDS_RECONCILIATION') const Text('Rapprochement nécessaire',style:TextStyle(color:Colors.red)),
          ]):collection=='cash'?Text('Reçu : ${(row['data'] as Map)['montant_recu']} • affecté : ${(row['data'] as Map)['montant_affecte']??'en attente'} • à rapprocher : ${(row['data'] as Map)['montant_a_rapprocher']??'en attente'}'):
          collection=='sales'?Text('Montant : ${(row['data'] as Map)['montant_total']} • ${row['state']=='CONFIRMED' || row['state']=='CONFIRMED_CACHE'?'confirmée par le serveur':row['state']=='NEEDS_RECONCILIATION'?'à rapprocher':'document provisoire — confirmation en attente'}'):Text(
            row['state']=='NEEDS_RECONCILIATION'?'Déclaration à rapprocher':
            row['state']!=null && !{'CONFIRMED','CONFIRMED_CACHE'}.contains(row['state'])?'Conservé sur la tablette • confirmation en attente':
            collection=='tasks'?'${(row['data'] as Map)['date']} • ${_taskStatus((row['data'] as Map)['status'])}':'Confirmé par le serveur')),
        if(rows.isEmpty) const Padding(padding:EdgeInsets.all(16),child:Text('Aucune donnée disponible sur cette page locale.')),
        Row(children:[TextButton(onPressed:busy || offset==0?null:()=>_run(() async {offset-=50;await _read();}),child:const Text('Précédent')),
          TextButton(onPressed:busy || !pageMayHaveMore?null:()=>_run(() async {offset+=50;await _read();}),child:const Text('Suivant'))]),
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
