import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/permission_contract.dart';
import '../services/physical_stock_summary.dart';
import '../offline/health_task_state.dart';
import '../screens/health_agenda_screen.dart';

class PhysicalStockCards extends StatefulWidget {
  const PhysicalStockCards({super.key,required this.api,this.species,this.lot,this.revision=0});
  final ApiService api;final int? species,lot;final int revision;
  @override State<PhysicalStockCards> createState()=>_PhysicalStockCardsState();
}
class _PhysicalStockCardsState extends State<PhysicalStockCards> {
  Map<String,dynamic>? feed,vaccine;List tasks=[];PermissionContract? rights;String? error,identity;
  int? expiryDays,upcomingDays;bool agendaUnavailable=false;bool loading=true;int generation=0;Timer? clock;String? observedIdentity;
  String get scope=>'stock-alerts:${rights!.farmId}:${rights!.userId}';
  @override void initState(){super.initState();ApiService.businessChanges.addListener(changed);widget.api.sessionChanges?.addListener(sessionChanged);load();clock=Timer.periodic(const Duration(minutes:1),(_){if(mounted)setState((){});});}
  void changed(){load();}
  void sessionChanged(){if(observedIdentity!=ApiService.sessionIdentity)load();}

  @override void didUpdateWidget(covariant PhysicalStockCards old){super.didUpdateWidget(old);if(old.api!=widget.api){old.api.sessionChanges?.removeListener(sessionChanged);widget.api.sessionChanges?.addListener(sessionChanged);}
    if(old.api!=widget.api || old.revision!=widget.revision)load();}
  @override void dispose(){clock?.cancel();ApiService.businessChanges.removeListener(changed);widget.api.sessionChanges?.removeListener(sessionChanged);super.dispose();}
  Future<void> load() async {
    final ticket=++generation,captured=ApiService.sessionIdentity;observedIdentity=captured;
    if(mounted)setState((){loading=true;error=null;feed=null;vaccine=null;tasks=[];rights=null;});
    try {
      final caps=await widget.api.get('/me/capabilities/');
      final policy=PermissionContract.decode(Map<String,dynamic>.from(caps['permission_contract'] as Map),userId:caps['user'] as int,
        farmId:caps['exploitation'] as int,role:caps['role'] as String,rightsVersion:caps['membership']['version'] as int,allowHttpV2:true);
      if(!policy.allows('stocks.read'))throw StateError('Consultation des stocks non autorisée.');
      final data=await Future.wait([widget.api.get('/feed-supplies/?presentation=1'),widget.api.get('/vaccine-supplies/')]);
      List agenda=[];var failedAgenda=false;if(policy.allows('agenda.read')) {try{agenda=await widget.api.get('/tasks/') as List;}catch(_){failedAgenda=true;}}
      final prefs=await SharedPreferences.getInstance();
      if(!mounted || ticket!=generation || captured!=ApiService.sessionIdentity)return;
      for(final snapshot in data) {if(snapshot['exploitation']!=null && snapshot['exploitation']!=policy.farmId)throw StateError('Stock hors exploitation.');}
      setState((){identity=captured;rights=policy;feed=Map<String,dynamic>.from(data[0] as Map);vaccine=Map<String,dynamic>.from(data[1] as Map);tasks=agenda;agendaUnavailable=failedAgenda;
        expiryDays=prefs.getInt('stock-alerts:${policy.farmId}:${policy.userId}:expiry');upcomingDays=prefs.getInt('stock-alerts:${policy.farmId}:${policy.userId}:upcoming');loading=false;});
    }catch(_){if(mounted && ticket==generation)setState((){loading=false;error='Stocks indisponibles ou accès non autorisé. Actualisez votre connexion.';});}
  }
  bool get current=>identity==ApiService.sessionIdentity && rights!=null;
  int? get species {if(widget.species!=null)return widget.species;for(final lot in feed?['lots'] as List? ?? const []){if(lot['id']==widget.lot)return lot['espece_id'] as int?;}return null;}
  Map<String,dynamic> get fs=>feedSummary(feed!,species:species,lot:widget.lot);
  Map<String,dynamic> get vs=>vaccineSummary(vaccine!,DateTime.now().toUtc(),species:species,lot:widget.lot,warningDays:expiryDays);
  String state(Map data) {
    final pending=(data['pending_operations'] as List? ?? const []).length,review=(data['review_operations'] as List? ?? const []).length;
    final at=DateTime.tryParse('${data['as_of']}');
    return 'Confirmé au ${at?.toLocal().toString()??'horodatage indisponible — données anciennes'} · $pending en attente · $review à vérifier';
  }
  Widget card(bool isFeed) {
    final sum=isFeed?fs:vs,data=isFeed?feed!:vaccine!;
    final alerts=<String>[];
    if(isFeed){for(final p in sum['details']){if(p['archived']==true)continue;if(p['empty']==true){alerts.add('Rupture : ${p['name']}');}else if(p['low']==true){alerts.add('Stock faible : ${p['name']}');}}}
    else {if(sum['expired']>0)alerts.add('${sum['expired']} doses périmées');if(sum['soon']>0)alerts.add('${sum['soon']} flacons proches de péremption');for(final p in sum['details']){if(p['low']==true && p['archived']!=true)alerts.add('Stock faible : ${p['name']}');}}
    return Card(child:InkWell(onTap:()=>details(isFeed),borderRadius:BorderRadius.circular(12),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Icon(isFeed?Icons.grass:Icons.vaccines,color:Colors.green),const SizedBox(width:8),Expanded(child:Text(isFeed?"Stock d’aliments":"Stock de vaccins",style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)))]),
      const SizedBox(height:12),Text(isFeed?'${sum['confirmed']} kg confirmés':'${sum['usable']} doses utilisables · ${sum['vials']} flacons disponibles',style:const TextStyle(fontSize:18)),
      Text(isFeed?'Estimé : ${sum['estimated']} kg':'Estimé : ${sum['estimated']} doses utilisables'),
      if(!isFeed && data['local_estimate']==true)const Text('Estimation sur flacons confirmés ; réceptions en attente non incluses.',style:TextStyle(fontSize:12)),
      if(!isFeed)Text('${sum['expired']} périmées · ${sum['unusable']} inutilisables · ${sum['physical']} physiquement présentes'),
      Text(state(data),style:Theme.of(context).textTheme.bodySmall),
      if((isFeed?num.parse('${sum['estimated']}')<0:(sum['estimated'] as int)<0))const Text('Estimation négative : stock à réconcilier avant utilisation.',style:TextStyle(color:Colors.deepOrange)),
      if(alerts.isNotEmpty)Text('${alerts.take(2).join(' · ')}${alerts.length>2?' · +${alerts.length-2} alertes':''}',style:const TextStyle(color:Colors.deepOrange)),
      const Text('Détails, seuils et historique',style:TextStyle(color:Colors.green)),
    ]))));
  }
  Future<void> details(bool isFeed) async {
    final captured=identity,data=isFeed?feed!:vaccine!,sum=isFeed?fs:vs;
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(context)=>_StockScope(allowed:()=>current,changes:widget.api.sessionChanges,child:SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.8,child:ListView(padding:const EdgeInsets.all(16),children:[
      Text(isFeed?"Stock d’aliments":"Stock de vaccins",style:Theme.of(context).textTheme.titleLarge),Text(state(data)),
      if(widget.lot!=null)const Text('Inclut le stock partagé de cette espèce et le stock réservé au lot. Ne pas additionner les vues de lots.'),
      if(widget.species!=null || widget.lot!=null)const Text('Seuils comparés au total du produit, sans filtre.'),
      for(final p in sum['details'])Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${p['name']}${p['archived']==true?' (archivé)':''}',style:const TextStyle(fontWeight:FontWeight.bold)),
        Text(isFeed?'Confirmé : ${p['confirmed']} kg · estimé : ${p['estimated']} kg\nPartagé : ${p['shared']} kg · réservé : ${p['reserved']} kg':
          '${p['usable']} doses utilisables · estimé : ${p['estimated']}\n${p['vials']} flacons disponibles · ${p['expired']} doses périmées · ${p['unusable']} inutilisables'),
        Text('Seuil : ${p['alert_threshold']??'non renseigné'} ${isFeed?'kg':'doses'}'),
        Wrap(children:[TextButton(onPressed:()=>history(p),child:const Text('Historique')),
          if(rights?.role=='OWNER')TextButton(onPressed:() async {if(captured!=ApiService.sessionIdentity)return;await threshold(p,isFeed);},child:const Text('Configurer le seuil'))]),
      ]))),
      if((data['review_operations'] as List? ?? []).isNotEmpty)const Text('Des opérations nécessitent une réconciliation. Consultez l’historique des opérations ; elles restent conservées.'),
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Fermer')),
    ]))))) ;
  }
  Future<void> threshold(Map product,bool isFeed) async {
    final captured=identity,controller=TextEditingController(text:'${product['alert_threshold']??'0'}');String? failure;
    final route=DialogRoute<bool>(context:context,builder:(context)=>_StockScope(allowed:()=>current,changes:widget.api.sessionChanges,child:StatefulBuilder(builder:(context,setDialog)=>AlertDialog(title:const Text('Seuil de stock faible'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(isFeed?'Seuil en kilogrammes, au niveau de l’exploitation.':'Seuil en doses entières, au niveau de l’exploitation.'),
      TextField(controller:controller,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Seuil (0 désactive le stock faible)')),
      if(failure!=null)Text(failure!),const Text('Configuration avec connexion requise.'),]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),TextButton(onPressed:() async {
        if(captured!=ApiService.sessionIdentity)return;
        final value=controller.text.trim();if(!RegExp(isFeed?r'^\d{1,11}(?:\.\d{1,3})?$':r'^\d{1,11}$').hasMatch(value)){setDialog(()=>failure='Quantité invalide.');return;}
        try{await widget.api.patch('/supply-products/${product['id']}/threshold/',{'alert_threshold':value,'expected_threshold':'${product['alert_threshold']??'0'}'});if(context.mounted && captured==ApiService.sessionIdentity)Navigator.pop(context,true);}
        catch(_){if(context.mounted)setDialog(()=>failure='Modification non confirmée. Actualisez avant de réessayer.');}
      },child:const Text('Enregistrer'))]))));
    final saved=await Navigator.of(context).push(route);await route.completed;controller.dispose();
    if(saved==true && mounted && captured==ApiService.sessionIdentity){Navigator.pop(context);await load();}
  }
  Future<void> history(Map product) async {
    final captured=identity;final rows=<dynamic>[];int? before;bool loading=true;String? failure;
    Future<void> page(StateSetter update) async {
      try{final result=await widget.api.get('/supply-products/${product['id']}/history/${before==null?'':'?before=$before'}');
        if(!mounted || captured!=ApiService.sessionIdentity)return;update((){rows.addAll(result['results'] as List);before=result['next_before'] as int?;loading=false;});}
      catch(_){if(mounted && captured==ApiService.sessionIdentity)update((){failure='Historique indisponible. Une connexion est requise pour les pages non mises en cache.';loading=false;});}
    }
    var started=false;await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(context)=>StatefulBuilder(builder:(context,update){
      if(!started){started=true;scheduleMicrotask(()=>page((fn){if(context.mounted)update(fn);}));}
      return _StockScope(allowed:()=>current,changes:widget.api.sessionChanges,child:SafeArea(child:SizedBox(height:MediaQuery.sizeOf(context).height*.75,child:ListView(padding:const EdgeInsets.all(16),children:[Text('Historique · ${product['name']}'),
        const Text('Mouvements signés : entrées, sorties, pertes, transferts et corrections. Historique confirmé ; les attentes restent dans l’historique des opérations.'),
        for(final row in rows)ListTile(title:Text('${movementLabel(row['kind'])} · ${row['quantity']}'),subtitle:Text('${row['at']} · opérateur ${row['operator']}\n${row['reason']} · lot ${row['lot']??'partagé'}${row['vial']==null?'':' · flacon ${row['vial']}'}')),
        if(loading)const Center(child:CircularProgressIndicator()),if(failure!=null)Text(failure!),
        if(!loading && before!=null)TextButton(onPressed:(){update(()=>loading=true);page((fn){if(context.mounted)update(fn);});},child:const Text('Voir plus')),
      ]))));}));
  }
  Future<void> settings() async {
    final captured=identity;final expiry=TextEditingController(text:expiryDays?.toString()??''),upcoming=TextEditingController(text:upcomingDays?.toString()??'');
    final route=DialogRoute<bool>(context:context,builder:(context)=>_StockScope(allowed:()=>current,changes:widget.api.sessionChanges,child:AlertDialog(title:const Text('Alertes visuelles'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Choisissez vos horizons en jours. Vide : alerte anticipée désactivée. Aucun protocole vaccinal n’est proposé.'),
      TextField(controller:expiry,decoration:const InputDecoration(labelText:'Péremption dans … jours')),TextField(controller:upcoming,decoration:const InputDecoration(labelText:'Vaccination dans … jours'))]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),TextButton(onPressed:() async {
        int? parse(String s)=>s.trim().isEmpty?null:int.tryParse(s.trim());final e=parse(expiry.text),u=parse(upcoming.text);
        if((expiry.text.trim().isNotEmpty && (e==null || e<0 || e>365)) || (upcoming.text.trim().isNotEmpty && (u==null || u<0 || u>365)))return;
        if(captured!=ApiService.sessionIdentity)return;final key=scope;final prefs=await SharedPreferences.getInstance();
        if(captured!=ApiService.sessionIdentity)return;
        for(final pair in {'expiry':e,'upcoming':u}.entries){if(pair.value==null){await prefs.remove('$key:${pair.key}');}else{await prefs.setInt('$key:${pair.key}',pair.value!);}}
        if(context.mounted && captured==ApiService.sessionIdentity)Navigator.pop(context,true);
      },child:const Text('Enregistrer'))])));
    final saved=await Navigator.of(context).push(route);await route.completed;expiry.dispose();upcoming.dispose();if(saved==true && mounted)await load();
  }
  @override Widget build(BuildContext context) {
    if(loading)return const Padding(padding:EdgeInsets.all(16),child:Text('Chargement des stocks physiques…'));
    if(error!=null || !current)return ListTile(title:Text(error??'Profil changé. Actualisez les stocks.'),trailing:IconButton(onPressed:load,icon:const Icon(Icons.refresh)));
    if(widget.lot!=null && species==null)return const ListTile(title:Text('Espèce du lot indisponible : actualisez les références avant de consulter le stock partagé.'));
    final now=DateTime.now().toUtc();var overdue=0,upcoming=0;
    for(final task in tasks){final h=task['health'];if(h is! Map || h['fulfilled']==true || task['status']=='CANCELLED' || (widget.species!=null && h['species']!=widget.species) || (widget.lot!=null && h['lot']!=widget.lot))continue;
      if(healthTaskOverdue(task,now)){overdue++;}else if(upcomingDays!=null){final day=DateTime.tryParse('${task['date']}');if(day!=null && !day.isAfter(parisDay(now).add(Duration(days:upcomingDays!))))upcoming++;}}
    return Column(children:[LayoutBuilder(builder:(context,c)=>c.maxWidth>=650?Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:card(true)),Expanded(child:card(false))]):Column(children:[card(true),card(false)])),
      if(agendaUnavailable)const Text('Agenda indisponible : les alertes vaccinales n’ont pas pu être actualisées.'),
      Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[if(overdue>0 || upcoming>0)TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>HealthAgendaScreen(api:widget.api,lotId:widget.lot))),child:Text('$upcoming vaccinations à venir · $overdue en retard')),
        TextButton(onPressed:settings,child:const Text('Configurer les alertes visuelles')),IconButton(onPressed:load,tooltip:'Actualiser les stocks',icon:const Icon(Icons.refresh))])]);
  }
}

class _StockScope extends StatefulWidget {
  const _StockScope({required this.allowed,required this.child,this.changes});
  final bool Function() allowed;final Widget child;final Listenable? changes;
  @override State<_StockScope> createState()=>_StockScopeState();
}
class _StockScopeState extends State<_StockScope> {
  Timer? timer;bool valid=true;
  void check(){final next=widget.allowed();if(mounted && next!=valid)setState(()=>valid=next);}
  @override void initState(){super.initState();valid=widget.allowed();widget.changes?.addListener(check);timer=Timer.periodic(const Duration(seconds:1),(_)=>check());}
  @override void dispose(){timer?.cancel();widget.changes?.removeListener(check);super.dispose();}
  @override Widget build(BuildContext context)=>valid?widget.child:const SafeArea(child:Padding(padding:EdgeInsets.all(24),child:Text('Profil ou droits modifiés. Fermez cette vue puis actualisez.')));
}

String movementLabel(Object? kind)=>const {'ENTRY':'Entrée','DISTRIBUTION':'Distribution','TRANSFER':'Transfert','LOSS':'Perte','CORRECTION':'Correction','ADMINISTRATION':'Administration','REVERSAL':'Annulation'}[kind]??'Mouvement';
