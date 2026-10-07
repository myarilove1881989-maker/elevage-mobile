import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/supervision_service.dart';

const _states={
  'NEEDS_RECONCILIATION':'À rapprocher','UNREVIEWED':'Reçu, validation en cours',
  'WAITING_DEPENDENCY':'En attente d’une opération liée','CONFIRMED':'Confirmé',
  'NOT_APPLIED':'Non appliqué','SUPERSEDED':'Remplacé par une correction','ALL':'Tous les états',
};
const _actions={
  'APPLY_ORIGINAL':'Confirmer la déclaration originale','CANCEL':'Annuler sans supprimer',
  'CORRECTION':'Corriger et appliquer','CASH_ALLOCATION':'Affecter le reliquat reçu',
  'REVERSE':'Contrepasser l’opération','CREATE':'Création','UPDATE':'Modification',
  'TERRAIN_RECEIVED':'Déclaration reçue','TERRAIN_APPLIED':'Déclaration appliquée',
};
const _entities={'CLIENT':'Client','TASK':'Compte rendu de tâche','VENTE_ANIMAUX':'Vente animaux',
  'VENTE_OEUFS':'Vente d’œufs','ENCAISSEMENT':'Encaissement','ACHAT':'Achat','NAISSANCE':'Naissance',
  'MORTALITE':'Mortalité','DON':'Don','VOL':'Vol','COLLECTE_OEUFS':'Collecte d’œufs',
  'DEPENSE':'Dépense','ALIMENTATION':'Alimentation','PESEE':'Pesée'};
const _fields={'nom':'Nom','telephone':'Téléphone','pays':'Pays','ville':'Ville','quantite':'Quantité',
  'prix_unitaire':'Prix unitaire','montant':'Montant','prix_total':'Prix total','note':'Constat',
  'nombre_conditionnements':'Conditionnements','prix_unitaire_conditionnement':'Prix par conditionnement',
  'nombre_alveoles':'Alvéoles','oeufs_supplementaires':'Œufs supplémentaires',
  'report':'Compte rendu','status':'État de la tâche','business_status':'État métier',
  'montant_recu':'Montant physiquement reçu','montant_affecte':'Montant affecté',
  'montant_a_rapprocher':'Reste à rapprocher','stock':'Stock confirmé','quantite_signee':'Variation de stock'};
String _date(dynamic value) {
  final date=DateTime.tryParse(value?.toString()??'')?.toLocal();
  if(date==null) {return 'Date indisponible';}
  String two(int n)=>n.toString().padLeft(2,'0');
  return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}
String _value(String key,dynamic value)=>key=='business_status'?_states[value]??value.toString():value?.toString()??'—';
Widget _facts(Map values)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  for(final entry in values.entries)if(_fields.containsKey(entry.key))
    Padding(padding:const EdgeInsets.only(bottom:4),child:Text('${_fields[entry.key]} : ${_value(entry.key.toString(),entry.value)}')),
]);

class SupervisionScreen extends StatefulWidget {
  const SupervisionScreen({super.key,this.service});
  final SupervisionService? service;
  @override
  State<SupervisionScreen> createState()=>_SupervisionScreenState();
}
class _SupervisionScreenState extends State<SupervisionScreen> {
  late final service=widget.service??SupervisionService(api:ApiService());
  List<Map<String,dynamic>> rows=[];
  Map<int,String> names={};
  bool loading=true,journal=false,hasMore=false;
  String state='NEEDS_RECONCILIATION';
  int page=1;
  int? authorFilter,deciderFilter;
  String actionFilter='';
  DateTimeRange? dateFilter;
  String? error;
  @override
  void initState() {super.initState();initialize();}
  @override
  void dispose() {if(widget.service==null) {service.api.close();}super.dispose();}
  String author(dynamic id)=>names[id]??'Utilisateur $id';
  Future<void> initialize() async {
    try {await service.initialize();names=await service.memberNames();await load();}
    catch (_) {if(mounted) {setState(() {rows=[];loading=false;error='Supervision indisponible. Vérifiez votre connexion et votre session.';});}}
  }
  Future<void> load() async {
    if(mounted) {setState(() {loading=true;error=null;rows=[];});}
    try {
      final result=journal?await service.activity(page:page,author:authorFilter,decider:deciderFilter,
        action:actionFilter,since:dateFilter?.start,until:dateFilter?.end.add(const Duration(days:1)).subtract(const Duration(microseconds:1))):
        await service.declarations(state:state,page:page);
      if(mounted) {setState(() {rows=[for(final row in result['results'] as List)Map<String,dynamic>.from(row as Map)];hasMore=result['next']!=null;});}
    } catch (_) {if(mounted) {setState(()=>error='Le serveur est indisponible. Aucune décision n’a été prise.');}}
    finally {if(mounted) {setState(()=>loading=false);}}
  }
  Future<void> open(Map<String,dynamic> row) async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>_DeclarationDetail(
      service:service,operationId:row['operation_uuid'] as String,names:names)));
    if(mounted) {await load();}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Supervision et activité')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Données reçues par le serveur. Les opérations encore uniquement sur la tablette ne sont pas visibles ici.'),
      const SizedBox(height:12),
      if(service.owner) Wrap(spacing:8,children:[
        ChoiceChip(label:const Text('Rapprochements'),selected:!journal,onSelected:loading?null:(_){setState(() {journal=false;page=1;});load();}),
        ChoiceChip(label:const Text('Journal d’activité'),selected:journal,onSelected:loading?null:(_){setState(() {journal=true;page=1;});load();}),
      ]),
      if(!journal) DropdownButtonFormField<String>(isExpanded:true,initialValue:state,
        decoration:const InputDecoration(labelText:'État des déclarations'),items:[for(final entry in _states.entries)DropdownMenuItem(value:entry.key,child:Text(entry.value))],
        onChanged:loading?null:(value){if(value!=null) {setState(() {state=value;page=1;});load();}}),
      if(journal) ...[
        DropdownButtonFormField<int>(isExpanded:true,key:ValueKey('author-$authorFilter'),initialValue:authorFilter,
          decoration:const InputDecoration(labelText:'Auteur original'),items:[const DropdownMenuItem(value:null,child:Text('Tous les auteurs')),
            for(final entry in names.entries)DropdownMenuItem(value:entry.key,child:Text(entry.value,maxLines:1,overflow:TextOverflow.ellipsis))],
          onChanged:loading?null:(value){setState(() {authorFilter=value;page=1;});load();}),
        DropdownButtonFormField<int>(isExpanded:true,key:ValueKey('decider-$deciderFilter'),initialValue:deciderFilter,
          decoration:const InputDecoration(labelText:'Décideur'),items:[const DropdownMenuItem(value:null,child:Text('Tous les décideurs')),
            for(final entry in names.entries)DropdownMenuItem(value:entry.key,child:Text(entry.value,maxLines:1,overflow:TextOverflow.ellipsis))],
          onChanged:loading?null:(value){setState(() {deciderFilter=value;page=1;});load();}),
        DropdownButtonFormField<String>(isExpanded:true,key:ValueKey('action-$actionFilter'),initialValue:actionFilter,
          decoration:const InputDecoration(labelText:'Action'),items:[const DropdownMenuItem(value:'',child:Text('Toutes les actions')),
            for(final entry in _actions.entries)DropdownMenuItem(value:entry.key,child:Text(entry.value,maxLines:1,overflow:TextOverflow.ellipsis))],
          onChanged:loading?null:(value){setState(() {actionFilter=value??'';page=1;});load();}),
        Wrap(spacing:12,children:[TextButton(onPressed:loading?null:() async {
          final selected=await showDateRangePicker(context:context,firstDate:DateTime(2010),lastDate:DateTime.now(),initialDateRange:dateFilter);
          if(selected!=null && mounted) {setState(() {dateFilter=selected;page=1;});load();}
        },child:Text(dateFilter==null?'Choisir une période':'${_date(dateFilter!.start)} → ${_date(dateFilter!.end)}')),
          TextButton(onPressed:loading?null:(){setState(() {authorFilter=null;deciderFilter=null;actionFilter='';dateFilter=null;page=1;});load();},child:const Text('Effacer les filtres'))]),
      ],
      if(loading) const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator())),
      if(error!=null) ...[Text(error!,style:const TextStyle(color:Colors.red)),TextButton(onPressed:initialize,child:const Text('Réessayer'))],
      if(!loading && error==null && rows.isEmpty) Text(journal?'Aucune activité reçue.':'Aucune déclaration dans cet état.'),
      for(final row in rows)if(journal) _ActivityCard(event:row,author:author) else Card(child:ListTile(
        title:Text(_entities[row['entity_type']]??'Déclaration terrain'),
        subtitle:Text('${_states[(row['receipt'] as Map)['business_status']]??'Reçu'}\nAuteur : ${author(row['original_author_id'])}\nFait : ${_date(row['business_occurred_at'])}\nReçu : ${_date(row['received_at'])}'),
        isThreeLine:true,trailing:const Icon(Icons.chevron_right),onTap:()=>open(row))),
      if(!loading && error==null) Wrap(spacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
        Text('Page $page'),TextButton(onPressed:page>1?(){setState(()=>page--);load();}:null,child:const Text('Précédente')),
        TextButton(onPressed:hasMore?(){setState(()=>page++);load();}:null,child:const Text('Suivante')),
        TextButton(onPressed:load,child:const Text('Actualiser')),
      ]),
    ]));
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.event,required this.author});
  final Map<String,dynamic> event;
  final String Function(dynamic) author;
  @override
  Widget build(BuildContext context)=>Card(child:ExpansionTile(
    title:Text(_actions[event['action']]??'Action enregistrée'),
    subtitle:Text('${_date(event['received_at'])}\nAuteur : ${author(event['actor_user_id'])}${event['decision_actor_id']==null?'':' • Décideur : ${author(event['decision_actor_id'])}'}'),
    children:[Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if((event['reason_text']?.toString()??'').isNotEmpty) Text('Motif : ${event['reason_text']}'),
      const Text('Avant',style:TextStyle(fontWeight:FontWeight.bold)),_facts(event['before_data'] as Map? ??{}),
      const Text('Après',style:TextStyle(fontWeight:FontWeight.bold)),_facts(event['after_data'] as Map? ??{}),
    ]))],
  ));
}

class _DeclarationDetail extends StatefulWidget {
  const _DeclarationDetail({required this.service,required this.operationId,required this.names});
  final SupervisionService service;
  final String operationId;
  final Map<int,String> names;
  @override
  State<_DeclarationDetail> createState()=>_DeclarationDetailState();
}
class _DeclarationDetailState extends State<_DeclarationDetail> {
  Map<String,dynamic>? row;
  List<Map<String,dynamic>> events=[];
  int page=1;bool more=false,loading=true;
  String? error;
  @override
  void initState() {super.initState();load();}
  Future<void> load() async {
    setState(()=>loading=true);
    try {
      final detail=await widget.service.detail(widget.operationId);
      final activity=widget.service.owner?await widget.service.activity(operationId:widget.operationId,page:page):null;
      if(mounted) {setState(() {row=detail;error=null;events=[for(final event in activity?['results'] as List? ??[])Map<String,dynamic>.from(event as Map)];more=activity?['next']!=null;});}
    } catch (_) {if(mounted) {setState(() {row=null;error='Impossible de charger cette déclaration. Rouvrez la supervision.';});}}
    finally {if(mounted) {setState(()=>loading=false);}}
  }
  Future<void> decide() async {
    final saved=await showDialog<bool>(context:context,builder:(_)=>_DecisionDialog(service:widget.service,row:row!));
    if(saved==true && mounted) {await load();}
  }
  @override
  Widget build(BuildContext context) {
    final receipt=row?['receipt'] as Map?;
    final recognized=receipt?['cash_recognition'] as Map?;
    final applied=receipt?['applied_at']!=null;
    return Scaffold(appBar:AppBar(title:const Text('Déclaration et historique')),body:ListView(padding:const EdgeInsets.all(16),children:[
      if(loading) const Center(child:CircularProgressIndicator()),
      if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
      if(row!=null) ...[
        Text(_entities[row!['entity_type']]??'Déclaration terrain',style:Theme.of(context).textTheme.titleLarge),
        Text(_states[receipt!['business_status']]??'Reçu'),
        Text('Auteur original : ${widget.names[row!['original_author_id']]??'Utilisateur ${row!['original_author_id']}'}'),
        Text('Fait : ${_date(row!['business_occurred_at'])} • reçu : ${_date(row!['received_at'])}'),
        const SizedBox(height:12),const Text('Déclaration originale conservée',style:TextStyle(fontWeight:FontWeight.bold)),
        _facts(row!['original_payload'] as Map),
        if(recognized!=null) ...[const Divider(),_facts(recognized)],
        if((receipt['reason_text']?.toString()??'').isNotEmpty) Text('Dernier motif : ${receipt['reason_text']}'),
        if(!loading && receipt?['business_status']!='SUPERSEDED' && receipt?['business_status']!='NOT_APPLIED' &&
          (!applied || recognized!=null || {'VENTE_ANIMAUX','VENTE_OEUFS','MORTALITE','DON','VOL'}.contains(row!['entity_type'])))
          FilledButton(onPressed:decide,child:const Text('Prendre une décision avec motif')),
        const Divider(),const Text('Historique de cette opération',style:TextStyle(fontWeight:FontWeight.bold)),
        if(widget.service.owner) ...[
          for(final event in events) _ActivityCard(event:event,author:(id)=>widget.names[id]??'Utilisateur $id'),
          Wrap(spacing:12,children:[Text('Page $page'),TextButton(onPressed:loading || page<=1?null:(){page--;load();},child:const Text('Précédente')),
            TextButton(onPressed:loading || !more?null:(){page++;load();},child:const Text('Suivante'))]),
        ] else for(final decision in row!['decisions'] as List? ??[]) ListTile(
          title:Text(_actions[(decision as Map)['action']]??'Décision'),subtitle:Text('${_date(decision['decided_at'])}\n${decision['reason']}')),
      ],
    ]));
  }
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.service,required this.row});
  final SupervisionService service;
  final Map<String,dynamic> row;
  @override
  State<_DecisionDialog> createState()=>_DecisionDialogState();
}
class _DecisionDialogState extends State<_DecisionDialog> {
  final form=GlobalKey<FormState>(),reason=TextEditingController(),amount=TextEditingController();
  final editors=<String,TextEditingController>{};
  late String action=availableActions.first;
  List<String> get availableActions {
    final receipt=widget.row['receipt'] as Map;
    final cash=receipt['cash_recognition'];
    if(cash is Map) {
      return [if(cash['montant_a_rapprocher']!='0.00') 'CASH_ALLOCATION',
        if(cash['montant_affecte']!='0.00') 'REVERSE'];
    }
    return receipt['applied_at']!=null?['REVERSE']:['APPLY_ORIGINAL','CORRECTION','CANCEL'];
  }
  Map<String,dynamic>? sale;
  List<Map<String,dynamic>> sales=[];
  int salesPage=1;bool moreSales=false,busy=false;
  String? error;
  PendingReconciliationDecision? pending;
  Map<String,dynamic>? currentTask;
  @override
  void initState() {
    super.initState();
    final original=widget.row['original_payload'] as Map;
    for(final entry in original.entries) {
      if(_fields.containsKey(entry.key) && entry.key!='montant_recu' && entry.value is! Map && entry.value is! List) {
        editors[entry.key.toString()]=TextEditingController(text:entry.value?.toString()??'');
      }
    }
    if(action=='CASH_ALLOCATION') {loadSales();}
    if(widget.row['entity_type']=='TASK') {loadTask();}
  }
  @override
  void dispose() {reason.dispose();amount.dispose();for(final controller in editors.values) {controller.dispose();}super.dispose();}
  Future<void> loadSales() async {
    setState(()=>busy=true);
    try {
      final result=await widget.service.cashSales(widget.row['operation_uuid'] as String,page:salesPage);
      if(mounted) {setState(() {sales=[for(final row in result['results'] as List)Map<String,dynamic>.from(row as Map)];sale=null;moreSales=result['next']!=null;});}
    } catch (_) {if(mounted) {setState(()=>error='Impossible de charger les ventes de ce client.');}}
    finally {if(mounted) {setState(()=>busy=false);}}
  }
  Future<void> loadTask() async {
    setState(()=>busy=true);
    try {
      final task=await widget.service.task((widget.row['original_payload'] as Map)['task_id'] as int);
      if(mounted) {setState(()=>currentTask=task);}
    } catch (_) {if(mounted) {setState(()=>error='Impossible de charger l’état actuel de la tâche.');}}
    finally {if(mounted) {setState(()=>busy=false);}}
  }
  String? validateField(String key,String? value) {
    if({'nom','quantite','nombre_conditionnements','nombre_alveoles','oeufs_supplementaires','prix_unitaire','prix_total','montant','prix_unitaire_conditionnement'}.contains(key) && (value??'').trim().isEmpty) {return 'Valeur requise.';}
    if({'quantite','nombre_conditionnements','nombre_alveoles','oeufs_supplementaires'}.contains(key) && !RegExp(r'^[0-9]{1,9}$').hasMatch(value??'')) {return 'Indiquez un nombre entier.';}
    if({'prix_unitaire','prix_total','montant','prix_unitaire_conditionnement'}.contains(key) && !RegExp(r'^[0-9]{1,10}([.,][0-9]{1,2})?$').hasMatch(value??'')) {return 'Deux décimales au maximum.';}
    return null;
  }
  Future<void> submit() async {
    if(busy || !form.currentState!.validate()) {return;}
    if(action=='CORRECTION' && widget.row['entity_type']=='TASK' && currentTask==null) {
      setState(()=>error='Rechargez la tâche avant de confirmer une correction.');return;
    }
    if(pending==null) {
      final payload=<String,dynamic>{};
      if(action=='CORRECTION') {
        payload.addAll(Map<String,dynamic>.from(widget.row['original_payload'] as Map));
        for(final entry in editors.entries) {
          final value=entry.value.text.trim();
          payload[entry.key]={'quantite','nombre_conditionnements','nombre_alveoles','oeufs_supplementaires'}.contains(entry.key)?int.parse(value):
            {'prix_unitaire','prix_total','montant','prix_unitaire_conditionnement'}.contains(entry.key)?value.replaceAll(',','.'):value;
        }
      } else if(action=='CASH_ALLOCATION') {
        payload.addAll({'vente_ref':{'server_id':sale!['reference_id']},'vente_type':sale!['entity_type'],'montant':amount.text.trim().replaceAll(',','.')});
      }
      pending=PendingReconciliationDecision(operationId:widget.row['operation_uuid'] as String,
        version:widget.row['decision_version'] as int,action:action,reason:reason.text,payload:payload,
        expectedEntityVersion:action=='CORRECTION' && currentTask!=null?currentTask!['version'].toString():'');
    }
    setState(() {busy=true;error=null;});
    try {await widget.service.decide(pending!);if(mounted) {Navigator.pop(context,true);}}
    catch (_) {if(mounted) {setState(()=>error='Décision non confirmée. Réessayez la même décision, ou fermez puis rechargez l’état du serveur.');}}
    finally {if(mounted) {setState(()=>busy=false);}}
  }
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Décision de rapprochement'),
    content:SizedBox(width:460,child:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('L’auteur et la déclaration d’origine restent conservés. Votre décision sera enregistrée avec son motif.'),
      DropdownButtonFormField<String>(isExpanded:true,initialValue:action,
        decoration:const InputDecoration(labelText:'Décision'),items:[for(final value in availableActions)DropdownMenuItem(value:value,child:Text(_actions[value]!))],
        onChanged:busy || pending!=null?null:(value){if(value!=null) {setState(()=>action=value);if(value=='CASH_ALLOCATION' && sales.isEmpty) {loadSales();}}}),
      if(action=='REVERSE') Text((widget.row['receipt'] as Map)['cash_recognition']!=null?
        'Les affectations seront annulées. Le paiement et le montant physique reçu restent conservés.':
        'L’effet appliqué sera compensé. La déclaration et ses écritures d’origine restent dans l’historique.'),
      if(currentTask!=null) Text('État actuel de la tâche : ${{'TODO':'À faire','IN_PROGRESS':'En cours','DONE':'Terminée','CANCELLED':'Annulée'}[currentTask!['status']]??'À vérifier'}'),
      if(action=='CORRECTION') for(final entry in editors.entries)if(entry.key=='status')
        DropdownButtonFormField<String>(isExpanded:true,initialValue:entry.value.text,decoration:const InputDecoration(labelText:'État observé de la tâche'),
          items:[for(final status in {'TODO':'À faire','IN_PROGRESS':'En cours','DONE':'Terminée'}.entries)DropdownMenuItem(value:status.key,child:Text(status.value))],
          onChanged:busy || pending!=null?null:(value){if(value!=null) {entry.value.text=value;}})
      else TextFormField(key:ValueKey('correction-${entry.key}'),controller:entry.value,enabled:!busy && pending==null,
        decoration:InputDecoration(labelText:_fields[entry.key]),validator:(value)=>validateField(entry.key,value)),
      if(action=='CASH_ALLOCATION') ...[
        DropdownButtonFormField<Map<String,dynamic>>(isExpanded:true,key:ValueKey('allocation-sales-$salesPage'),initialValue:sale,
          decoration:const InputDecoration(labelText:'Vente du client à régler'),items:[for(final row in sales)DropdownMenuItem(value:row,child:Text('${_entities[row['entity_type']]} • ${_date(row['date'])} • dû ${row['reste_a_payer']}'))],
          onChanged:busy || pending!=null?null:(value)=>setState(()=>sale=value),validator:(value)=>value==null?'Choisissez la vente à régler.':null),
        if(moreSales) TextButton(onPressed:busy || pending!=null?null:(){salesPage++;loadSales();},child:const Text('Afficher les ventes suivantes')),
        TextFormField(controller:amount,enabled:!busy && pending==null,decoration:const InputDecoration(labelText:'Montant à affecter'),
          keyboardType:const TextInputType.numberWithOptions(decimal:true),validator:(value)=>validateField('montant',value)),
      ],
      TextFormField(key:const ValueKey('decision-reason'),controller:reason,enabled:!busy && pending==null,maxLength:10000,
        decoration:const InputDecoration(labelText:'Motif obligatoire'),validator:(value)=>(value??'').trim().length<3?'Indiquez le motif de votre décision.':null),
      if(error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
      if(busy) const CircularProgressIndicator(),
    ])))),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context,false),child:const Text('Fermer')),
      FilledButton(onPressed:busy?null:submit,child:Text(pending==null?'Enregistrer la décision':'Réessayer la même décision'))]);
}
