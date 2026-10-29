import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/operation_history.dart';
import '../services/history_presentation.dart';
import '../widgets/operation_history_list.dart';
import '../widgets/operation_status.dart';
import '../theme/terre_et_or_theme.dart';

class OwnerOperationHistoryScreen extends StatefulWidget {
  const OwnerOperationHistoryScreen({super.key,required this.api});
  final ApiService api;
  @override
  State<OwnerOperationHistoryScreen> createState()=>_OwnerOperationHistoryScreenState();
}
class _OwnerOperationHistoryScreenState extends State<OwnerOperationHistoryScreen> {
  final author=TextEditingController(),lot=TextEditingController();
  List<Map<String,dynamic>> rows=[];
  final names=HistoryNames();
  String kind='',status='',operation='';
  DateTime? start,end;
  bool busy=false,failed=false,hasNext=false;
  int page=1;
  String? displayedToken;
  @override
  void initState() {super.initState();load();}
  @override
  void dispose() {author.dispose();lot.dispose();super.dispose();}
  Future<void> load({bool next=false}) async {
    if(busy) return;
    final token=ApiService.sessionIdentity;
    setState(()=>busy=true);
    for(final path in ['/lots/','/clients/','/categories-depense/']) {
      try {final data=await widget.api.get(path); if(!mounted || token!=ApiService.sessionIdentity) return;
        names.add(path=='/lots/'?'lots':path=='/clients/'?'clients':'categories',data);
      } catch (_) {}
    }
    final params={'view':'operations','page':'${next?page+1:1}',
      if(author.text.trim().isNotEmpty) 'author':author.text.trim(),
      if(lot.text.trim().isNotEmpty) 'lot':lot.text.trim(),
      if(kind.isNotEmpty) 'kind':kind,
      if(start!=null) 'start':start!.toUtc().toIso8601String(),
      if(end!=null) 'end':DateTime(end!.year,end!.month,end!.day+1).toUtc().toIso8601String(),
      if(operation.isNotEmpty) 'operation':operation};
    try {
      final data=await widget.api.get('/history/?${Uri(queryParameters:params).query}');
      if(!mounted || token!=(ApiService.sessionIdentity)) return;
      final received=(data['results'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
      setState(() {rows=[if(next && displayedToken==token) ...rows,...received];
        hasNext=data['next']!=null;page=next?page+1:1;failed=false;displayedToken=token;});
    } catch (_) {if(mounted) setState(()=>failed=true);}
    finally {if(mounted) setState(()=>busy=false);}
  }
  Future<void> date(bool first) async {
    final value=await showDatePicker(context:context,initialDate:DateTime.now(),
      firstDate:DateTime(2000),lastDate:DateTime.now());
    if(value!=null && mounted) setState(() {if(first) {start=value;} else {end=value;}});
  }
  String state(Map<String,dynamic> row)=>row['business_status']=='SUPERSEDED'
    ?'Annulée — original conservé':row['business_status']=='NEEDS_RECONCILIATION'
      ?(row['applied_at']==null?'Non appliquée — résolution métier nécessaire':'Partiellement appliquée — anomalie à résoudre')
      :operationStatus(transport:'SERVER_RECEIVED',business:row['business_status'] as String);
  String reason(dynamic code)=>const {
    'SALE_HAS_ACTIVE_ALLOCATIONS':'La vente comporte un paiement affecté. Aucune compensation automatique.',
    'BUSINESS_EFFECT_ALREADY_REVERSED':'Cette opération a déjà été annulée.',
    'OFFLINE_PERMISSION_DENIED':'La permission nécessaire manque dans l’autorisation applicable.',
    'AUTHOR_RIGHTS_CHANGED':'Une invalidation de droits bloque cette opération.',
    'STOCK_INSUFFICIENT':'Le stock disponible ne permet pas cette opération.',
    'EXPENSE_HAS_ACTIVE_FEED_DECLARATION':'La dépense est liée à une distribution d’aliment.',
    'EXPENSE_HAS_ACTIVE_FEED':'La dépense est liée à une distribution d’aliment.',
    'DEPENDENCY_NOT_APPLIED':'Une opération liée n’a pas été confirmée.',
  }[code]??(code==null || code==''?'':'Anomalie documentée : $code');
  Widget detail(Map<String,dynamic> row) {
    final id=row['actor_user_id'];
    if(row['author_name'] is String) names.authors[id.toString()]=row['author_name'];
    names.add('lots',row['lots']);
    final item=OperationHistoryItem(identity:row['operation_id'],author:row['author_name']??'Éleveur non renseigné',
      authorId:id,entityType:row['entity_type'],type:historyTypeLabel(row['entity_type']),
      status:state(row),businessState:row['business_status'],businessDate:row['business_occurred_at']??'',
      recordedDate:row['local_recorded_at']??'',details:'',reason:(row['payload'] as Map?)?['reason'],data:Map<String,dynamic>.from(row['payload']??{}));
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[OperationHistoryList(items:[item],names:names),
      if(row['original_operation_id']!=null) TextButton(onPressed:busy?null:() {
        operation=row['original_operation_id'];load();},child:const Text('Voir l’opération initiale')),
      for(final cancellation in row['cancellations'] as List? ?? []) TextButton(onPressed:busy?null:() {
        operation=cancellation['operation_id'];load();},child:const Text('Voir l’annulation')),
    ]);
  }
  @override
  Widget build(BuildContext context)=>Theme(data:terreEtOrTheme(context),child:Builder(builder:(context)=>Scaffold(appBar:AppBar(title:const Text('Activité complète reçue')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const TerreEtOrHeader(icon:Icons.history,title:'Historique de l’exploitation',subtitle:'Consultez et filtrez les opérations de votre équipe'),
      const Text('Les opérations encore sur une tablette apparaîtront après transmission. Aucune validation du propriétaire n’est nécessaire.'),
      ExpansionTile(title:const Text('Filtres'),children:[
      TextField(controller:author,enabled:!busy,decoration:const InputDecoration(labelText:'Éleveur — nom')),
      TextField(controller:lot,enabled:!busy,decoration:const InputDecoration(labelText:'Lot — nom')),
      DropdownButtonFormField<String>(initialValue:kind,decoration:const InputDecoration(labelText:'Type d’opération'),
        items:[const DropdownMenuItem(value:'',child:Text('Tous')),for(final code in ['VENTE_ANIMAUX','VENTE_OEUFS','DEPENSE','ACHAT','NAISSANCE','MORTALITE','DON','VOL','CLIENT','COLLECTE_OEUFS','ENCAISSEMENT','ALIMENTATION','PESEE','TASK'])
          DropdownMenuItem(value:code,child:Text(historyTypeLabel(code)))],onChanged:busy?null:(v)=>setState(()=>kind=v!)),
      DropdownButtonFormField<String>(initialValue:status,decoration:const InputDecoration(labelText:'Statut'),
        items:[const DropdownMenuItem(value:'',child:Text('Tous')),for(final code in ['En attente','Synchronisée','Échec'])
          DropdownMenuItem(value:code,child:Text(code))],
        onChanged:busy?null:(v)=>setState(()=>status=v!)),
      TextButton(onPressed:busy?null:()=>date(true),child:Text('Du : ${start?.toString().split(' ').first??'sans limite'}')),
      TextButton(onPressed:busy?null:()=>date(false),child:Text('Au : ${end?.toString().split(' ').first??'sans limite'}')),
      FilledButton(onPressed:busy?null:()=>load(),child:const Text('Appliquer les filtres')),
      TextButton(onPressed:busy?null:() {author.clear();lot.clear();start=null;end=null;operation='';kind='';status='';load();},child:const Text('Effacer les filtres')),
      ]),
      if(busy) const LinearProgressIndicator(),
      if(failed) const Text('Lecture indisponible. Ce registre est réservé au propriétaire. Vérifiez les filtres et la connexion.'),
      if(displayedToken==(ApiService.sessionIdentity)) ...[
        for(final row in rows) if(status.isEmpty || status==(
          {'CONFIRMED','SUPERSEDED'}.contains(row['business_status'])?'Synchronisée':
          {'NOT_APPLIED','NEEDS_RECONCILIATION'}.contains(row['business_status'])?'Échec':'En attente')) detail(row),
        if(rows.isEmpty) const Text('Aucune opération reçue pour ces filtres.')],
      if(hasNext) TextButton(onPressed:busy?null:()=>load(next:true),child:const Text('Charger la suite')),
    ]))));
}
