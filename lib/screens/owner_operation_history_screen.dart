import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/operation_history.dart';
import '../widgets/operation_status.dart';
import '../offline/outbox.dart';
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
    final params={'view':'operations','page':'${next?page+1:1}',
      if(author.text.trim().isNotEmpty) 'author':author.text.trim(),
      if(lot.text.trim().isNotEmpty) 'lot':lot.text.trim(),
      if(kind.isNotEmpty) 'kind':kind, if(status.isNotEmpty) 'status':status,
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
  Widget detail(Map<String,dynamic> row)=>ExpansionTile(
    title:Text('${row['operation_type']=='REVERSE'?'Annulation : ':''}${historyTypeLabel(row['entity_type'] as String)} — ${state(row)}'),
    subtitle:Text('${row['author_name']} • ${row['business_occurred_at']}'),
    childrenPadding:const EdgeInsets.all(12),children:[
      Text('Saisie déclarée : ${row['local_recorded_at']}'),
      Text('Réception serveur : ${row['received_at']}'),
      if(row['late_sync']==true) const Text('Synchronisation tardive : plus de cinq minutes après la saisie déclarée.'),
      if(row['received_with_old_permissions']==true) const Text('Reçue sous une ancienne autorisation après un retrait métier.'),
      if(row['ordinary_business_tolerance']==true) const Text('Acceptée avec les anciennes permissions après un retrait métier.'),
      const Text('La date de saisie provient de la tablette.'),
      Text('Employé : ${row['author_name']} (${row['actor_user_id']})'),
      for(final lot in row['lots'] as List? ?? const []) Text('Lot : ${lot['nom']} (${lot['id']})'),
      Text('Permission utilisée : ${row['permission']}'),
      SelectableText('Autorisation : ${row['authorization_id']} • version ${row['rights_version']}'),
      Text('Motif : ${(row['payload'] as Map)['reason']??row['reason_text']??''} ${reason(row['reason_code'])}'),
      Text(historyDetails(row['payload'] as Map)),
      for(final entry in (row['payload'] as Map).entries) Text('${const {
        'lot_ref':'Lot','client_ref':'Client','quantite':'Quantité','prix_unitaire':'Prix unitaire',
        'montant':'Montant','montant_recu':'Montant reçu','reason':'Motif d’annulation',
        'original_operation_id':'Opération initiale','note':'Note','categorie_id':'Catégorie',
        'nombre_oeufs':'Œufs','prix_total':'Prix total','nom_lot':'Nom du lot',
      }[entry.key]??entry.key} : ${entry.value}'),
      SelectableText('Identifiant : ${row['operation_id']}'),
      if(row['original_operation_id']!=null) TextButton(onPressed:busy?null:() {
        operation=row['original_operation_id'] as String;load();
      },child:const Text('Ouvrir l’opération initiale')),
      for(final cancellation in row['cancellations'] as List) TextButton(onPressed:busy?null:() {
        operation=cancellation['operation_id'] as String;load();
      },child:Text('Ouvrir l’annulation — ${cancellation['reason']}')),
    ]);
  @override
  Widget build(BuildContext context)=>Theme(data:terreEtOrTheme(context),child:Builder(builder:(context)=>Scaffold(appBar:AppBar(title:const Text('Activité complète reçue')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const TerreEtOrHeader(icon:Icons.history,title:'Historique de l’exploitation',subtitle:'Consultez et filtrez les opérations de votre équipe'),
      const Text('Les opérations encore sur une tablette apparaîtront après transmission. Aucune validation du propriétaire n’est nécessaire.'),
      TextField(controller:author,enabled:!busy,decoration:const InputDecoration(labelText:'Employé — nom ou identifiant')),
      TextField(controller:lot,enabled:!busy,decoration:const InputDecoration(labelText:'Lot — nom ou identifiant')),
      DropdownButtonFormField<String>(initialValue:kind,decoration:const InputDecoration(labelText:'Type d’opération'),
        items:[const DropdownMenuItem(value:'',child:Text('Tous')),for(final code in ['VENTE_ANIMAUX','VENTE_OEUFS','DEPENSE','ACHAT','NAISSANCE','MORTALITE','DON','VOL','CLIENT','COLLECTE_OEUFS','ENCAISSEMENT','ALIMENTATION','PESEE','TASK'])
          DropdownMenuItem(value:code,child:Text(historyTypeLabel(code)))],onChanged:busy?null:(v)=>setState(()=>kind=v!)),
      DropdownButtonFormField<String>(initialValue:status,decoration:const InputDecoration(labelText:'Statut'),
        items:[const DropdownMenuItem(value:'',child:Text('Tous')),for(final code in businessStates)
          DropdownMenuItem(value:code,child:Text(code=='SUPERSEDED'?'Annulée':operationStatus(transport:'SERVER_RECEIVED',business:code)))],
        onChanged:busy?null:(v)=>setState(()=>status=v!)),
      TextButton(onPressed:busy?null:()=>date(true),child:Text('Du : ${start?.toString().split(' ').first??'sans limite'}')),
      TextButton(onPressed:busy?null:()=>date(false),child:Text('Au : ${end?.toString().split(' ').first??'sans limite'}')),
      FilledButton(onPressed:busy?null:()=>load(),child:const Text('Appliquer les filtres')),
      TextButton(onPressed:busy?null:() {author.clear();lot.clear();start=null;end=null;operation='';load();},child:const Text('Effacer les dates, l’employé, le lot et le lien')),
      if(busy) const LinearProgressIndicator(),
      if(failed) const Text('Lecture indisponible. Ce registre est réservé au propriétaire. Vérifiez les filtres et la connexion.'),
      if(displayedToken==(ApiService.sessionIdentity)) ...[
        for(final row in rows) Card(child:detail(row)),
        if(rows.isEmpty) const Text('Aucune opération reçue pour ces filtres.')],
      if(hasNext) TextButton(onPressed:busy?null:()=>load(next:true),child:const Text('Charger la suite')),
    ]))));
}
