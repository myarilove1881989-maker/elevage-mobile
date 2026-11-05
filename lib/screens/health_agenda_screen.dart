import '../widgets/v2_components.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../offline/health_task_state.dart';
import '../services/permission_contract.dart';
import '../services/farmer_runtime.dart';
import '../services/health_notifications.dart';
import '../offline/outbox.dart' show newOperationUuid;
import 'vaccination_screen.dart';

class HealthAgendaScreen extends StatefulWidget {
  const HealthAgendaScreen({super.key,required this.api,this.lotId,this.startPlanning=false});
  final ApiService api;final int? lotId;final bool startPlanning;
  @override State<HealthAgendaScreen> createState()=>_HealthAgendaScreenState();
}
class _HealthAgendaScreenState extends State<HealthAgendaScreen> {
  List<Map<String,dynamic>> rows=[];PermissionContract? rights;String? error,identity;
  bool loading=true,reminders=false,started=false;String? reminderWarning;
  @override void initState(){super.initState();load();}
  bool get current=>identity==ApiService.sessionIdentity;
  Future<void> load() async {
    final captured=ApiService.sessionIdentity;
    try {
      final caps=await widget.api.get('/me/capabilities/');
      final policy=PermissionContract.decode(Map<String,dynamic>.from(caps['permission_contract'] as Map),userId:caps['user'] as int,
        farmId:caps['exploitation'] as int,role:caps['role'] as String,rightsVersion:caps['membership']['version'] as int,allowHttpV2:true);
      if(!policy.allows('agenda.read'))throw StateError('Consultation de l’agenda non autorisée.');
      final tasks=await widget.api.get('/tasks/') as List;
      if(!mounted || captured!=ApiService.sessionIdentity)return;
      final health=[for(final task in tasks)if(task['health'] is Map && (widget.lotId==null || task['health']['lot']==widget.lotId))Map<String,dynamic>.from(task as Map)];
      final coordinator=HealthReminderCoordinator.current;
      if(coordinator!=null) {
        try {
        reminders=await coordinator.enabled(policy.farmId,policy.userId);
        final until=widget.api is FarmerApiService?(widget.api as FarmerApiService).runtime.grant?.expiresAt:null;
        await coordinator.sync(farm:policy.farmId,user:policy.userId,tasks:tasks,isCurrent:()=>captured==ApiService.sessionIdentity && policy.allows('agenda.read'),validUntil:until);
        }catch(_){reminderWarning='Rappels locaux indisponibles ; l’agenda reste consultable.';try{await coordinator.suspend();}catch(_){}}
      }
      if(!mounted || captured!=ApiService.sessionIdentity)return;
      setState(() {identity=captured;rights=policy;rows=health;error=null;loading=false;});
      if(widget.startPlanning && !started && policy.allows('agenda.plan')){started=true;await planning();}
    }catch(e){await HealthReminderCoordinator.current?.suspend();if(mounted)setState(() {loading=false;rows=[];rights=null;identity=null;error=e is StateError?'${e.message}':'Agenda indisponible. Actualisez après reconnexion.';});}
  }
  Future<void> planning([Map<String,dynamic>? task]) async {
    if(!current || rights?.allows('agenda.plan')!=true)return;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>HealthPlanForm(api:widget.api,lotId:widget.lotId,initial:task)));if(mounted)await load();
  }
  Future<void> cancel(Map<String,dynamic> task) async {
    final captured=ApiService.sessionIdentity;
    final reason=TextEditingController();bool busy=false;String? message;
    final route=DialogRoute<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update)=>V2AlertDialog(title:const Text('Annuler le rendez-vous'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[V2Field(child:TextField(controller:reason,decoration:const V2InputDecoration(labelText:'Motif obligatoire',))),if(message!=null)Text(message!)]),
      actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(dialog),child:const Text('Fermer')),TextButton(onPressed:busy?null:()async{
        if(reason.text.trim().length<3 || !current || captured!=ApiService.sessionIdentity)return;update(()=>busy=true);
        try {await widget.api.cancelTask(task['id'] as int,version:task['version'] as int,reason:reason.text.trim());if(dialog.mounted)Navigator.pop(dialog);await load();}
        catch(_){if(dialog.mounted)update(() {busy=false;message='Résultat à vérifier. Actualisez l’agenda avant de recommencer.';});}
      },child:const Text('Confirmer'))])));await Navigator.of(context).push(route);await route.completed;reason.dispose();
  }
  Future<void> progress(Map<String,dynamic> task) async {
    final captured=ApiService.sessionIdentity;
    final report=TextEditingController(text:'${task['report']??''}');String status='${task['status']}';
    final choices=status=='DONE'?['DONE']:status=='IN_PROGRESS'?['IN_PROGRESS','DONE']:['TODO','IN_PROGRESS'];
    bool busy=false;Map<String,dynamic>? pending;String? message;
    final route=DialogRoute<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update)=>V2AlertDialog(title:const Text('Avancement de la tâche'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Terminer la tâche ne déclare aucune vaccination et ne consomme aucune dose.'),
        V2Field(child:DropdownButtonFormField<String>(initialValue:status,items:[for(final s in choices)DropdownMenuItem(value:s,child:Text({'TODO':'À faire','IN_PROGRESS':'En cours','DONE':'Terminée'}[s]!))],
          onChanged:pending!=null || busy?null:(v)=>update(()=>status=v!))),
        V2Field(child:TextField(controller:report,enabled:pending==null && !busy,maxLength:10000,decoration:const V2InputDecoration(labelText:'Compte rendu',))),if(message!=null)Text(message!),
      ])),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(dialog),child:const Text('Fermer')),TextButton(onPressed:busy?null:()async{
        if(!current || captured!=ApiService.sessionIdentity)return;pending??={'status':status,'report':report.text,'expected_version':task['version'],
          if(widget.api.hasUnifiedOfflineSession)...{'operation_uuid':newOperationUuid(),'reported_at':DateTime.now().toUtc().toIso8601String()}};
        update(()=>busy=true);
        try {await widget.api.patch('/tasks/${task['id']}/',pending!);if(dialog.mounted)Navigator.pop(dialog);await load();}
        catch(_){if(dialog.mounted)update(() {busy=false;message='Résultat à vérifier ; les mêmes informations sont conservées.';});}
      },child:const Text('Enregistrer'))])));await Navigator.of(context).push(route);await route.completed;report.dispose();
  }
  Future<void> history(Map task) async {
    try {final data=await widget.api.get('/tasks/${task['id']}/health-history/');if(!mounted || !current)return;
      await showDialog<void>(context:context,builder:(dialog)=>V2AlertDialog(title:const Text('Historique des reports et annulations'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final row in data as List)
          Text('${v2Moment(row['date'])} — opérateur ${row['operator']}\n${row['reason']}\nDate : ${v2Day(row['before']['date'])} → ${v2Day(row['after']['date'])}\nÉtat : ${row['after']['status']??''}')])),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Fermer'))]));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Historique détaillé à charger avec Internet.')));}
  }
  @override Widget build(BuildContext context)=>V2Scaffold(appBar:V2AppBar(title:const Text('Agenda sanitaire')),body:RefreshIndicator(onRefresh:load,
    child:ListView(padding:const EdgeInsets.all(16),children:[
      if(loading)const LinearProgressIndicator(),if(error!=null)Text(error!),if(reminderWarning!=null)Text(reminderWarning!),
      if(current && rights?.allows('agenda.plan')==true)ElevatedButton(key:const Key('health-plan-create'),onPressed:()=>planning(),child:const Text('Programmer une vaccination')),
      if(HealthReminderCoordinator.current!=null && rights!=null && current)SwitchListTile(key:const Key('health-reminders'),title:const Text('Rappels locaux pour mes tâches attribuées'),
        subtitle:const Text('Selon les réglages du téléphone'),value:reminders,onChanged:(value)async{
          final enabled=await HealthReminderCoordinator.current!.setEnabled(rights!.farmId,rights!.userId,value);if(mounted && current)setState(()=>reminders=enabled);await load();}),
      const V2Help(title:'Agenda et vaccinations',child:Text('Une tâche terminée ne constitue pas une vaccination réalisée. Les vaccinations locales attendent la confirmation du serveur. Les rappels locaux existants conservent leurs conditions horaires.')),
      if(!loading && rows.isEmpty && error==null)const Text('Aucun rendez-vous sanitaire disponible.'),
      for(final task in rows)...[
        Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${task['title']}',style:Theme.of(context).textTheme.titleMedium),
          Text('Prévu : ${v2Day(task['date'])}${task['health']['planned_time']==null?'':' · ${task['health']['planned_time'].toString().substring(0,5)}'}\nLot : ${task['health']['lot_name']} — responsable : ${task['assigned_to']}\nÉtat de tâche : ${{'TODO':'À faire','IN_PROGRESS':'En cours','DONE':'Terminée','CANCELLED':'Annulée'}[task['status']]??task['status']}'),
          if(task['status']=='CANCELLED')Text('Motif : ${task['cancellation_reason']??''}'),
          if(healthTaskOverdue(task,DateTime.now().toUtc()))const Text('Vaccination en retard'),
          if(task['health']['actual'] is Map)Text('Réalisée : ${v2Day(task['health']['actual']['date'])} par ${task['health']['actual']['operator_name']}\nÉcart : ${task['health']['actual']['difference_days']} jour(s)'),
          if(task['health']['fulfilled']!=true)const Text('Aucune vaccination confirmée pour ce rendez-vous.'),
          if(task['_health_vaccination_pending']==true)const Text('Vaccination locale : confirmation serveur en attente.'),
          if(task['_health_pending']==true)const Text('Avancement local : confirmation serveur en attente.'),
          if(task['_health_conflict']==true)const Text('Conflit conservé dans le registre des opérations : à examiner.'),
          if(task['health']['interval_days']!=null)Text('Intervalle explicitement choisi : ${task['health']['interval_days']} jour(s), jusqu’au ${v2Day(task['health']['series_end'])}'),
          Wrap(spacing:8,children:[
            TextButton(onPressed:()=>history(task),child:const Text('Historique')),
            if(current && rights?.allows('agenda.plan')==true && task['status']!='CANCELLED' && task['health']['fulfilled']!=true)TextButton(onPressed:()=>planning(task),child:const Text('Reporter / réattribuer')),
            if(current && rights?.role=='OWNER' && task['status']!='CANCELLED')TextButton(onPressed:()=>cancel(task),child:const Text('Annuler avec motif')),
            if(current && rights?.allows('agenda.progress')==true && task['assigned_to']==rights?.userId && task['status']!='CANCELLED' && task['_health_pending']!=true)TextButton(onPressed:()=>progress(task),child:const Text('Avancement')),
            if(current && rights?.allows('vaccinations.create')==true && (rights?.role=='OWNER' || (rights?.allows('agenda.progress')==true && task['assigned_to']==rights?.userId)) && task['status']!='CANCELLED' && task['health']['fulfilled']!=true && task['_health_vaccination_pending']!=true)
              TextButton(key:Key('health-vaccinate-${task['id']}'),onPressed:()async{
                await Navigator.push(context,MaterialPageRoute(builder:(_)=>VaccinationForm(api:widget.api,lotId:task['health']['lot'] as int,plannedTask:task)));await load();
              },child:const Text('Enregistrer la vaccination réelle')),
          ]),
        ]))),
      ],
    ])));
}

class HealthPlanForm extends StatefulWidget {
  const HealthPlanForm({super.key,required this.api,this.lotId,this.initial});
  final ApiService api;final int? lotId;final Map<String,dynamic>? initial;
  @override State<HealthPlanForm> createState()=>_HealthPlanFormState();
}
class _HealthPlanFormState extends State<HealthPlanForm> {
  Map<String,dynamic>? catalog,pending;List<dynamic> assignees=[];String? product,error;int? lot,assignee;bool busy=false;
  final selectedDates=<String>{};
  final uuid=newOperationUuid();
  final originIdentity=ApiService.sessionIdentity;
  bool get sameIdentity=>originIdentity==ApiService.sessionIdentity;
  final date=TextEditingController(text:DateTime.now().toIso8601String().split('T').first),time=TextEditingController(),
    interval=TextEditingController(),end=TextEditingController(),notes=TextEditingController(),reason=TextEditingController();
  @override void initState(){super.initState();lot=widget.lotId;final task=widget.initial;
    if(task!=null){lot=task['health']['lot'] as int;product=task['health']['product'] as String;assignee=task['assigned_to'] as int?;date.text='${task['date']}';time.text='${task['health']['planned_time']??''}';notes.text='${task['description']??''}';}else{selectedDates.add(date.text);}load();}
  Future<void> load()async {
    try {
      final data=await widget.api.get('/vaccine-supplies/'),people=await widget.api.get('/tasks/health-assignees/');
      if(!mounted || !sameIdentity)return;
      if(data is! Map || data['products'] is! List || data['lots'] is! List || people is! List)throw StateError('Références sanitaires indisponibles.');
      setState(() {catalog=Map<String,dynamic>.from(data);assignees=people;
        if(!assignees.any((r)=>r['user']==assignee))assignee=null;
        if(widget.initial==null && !(catalog!['lots'] as List).any((r)=>r['id']==lot))lot=null;});
    }catch(_){if(mounted)setState(()=>error='La planification nécessite des références et des responsables autorisés chargés avec Internet.');}
  }
  Future<void> save()async {
    if(!sameIdentity){setState(()=>error='Profil modifié. Rouvrez le formulaire avec l’identité d’origine.');return;}
    if(busy)return;setState(()=>busy=true);
    try {
      if(pending==null) {
        if(catalog==null || lot==null || assignee==null || (widget.initial==null && product==null))throw StateError('Choisissez le vaccin, le lot et le responsable.');
        final target=(catalog!['lots'] as List).where((r)=>r['id']==lot).toList();
        if(target.length!=1)throw StateError('Lot absent ou clôturé.');
        final day=DateTime.tryParse(date.text.trim());if(day==null || day.toIso8601String().split('T').first!=date.text.trim())throw StateError('Vérifiez la date prévue.');
        if(time.text.isNotEmpty && !RegExp(r'^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$').hasMatch(time.text.trim()))throw StateError('Heure attendue : HH:MM.');
        if(widget.initial!=null && reason.text.trim().length<3)throw StateError('Indiquez le motif du report ou de la réattribution.');
        if(widget.initial==null && selectedDates.isEmpty)throw StateError('Choisissez au moins une date.');
        pending={'operation_uuid':uuid,if(widget.initial!=null)'date':date.text.trim(),
          'planned_time':widget.initial==null?null:time.text.trim().isEmpty?null:time.text.trim(),
          'assigned_to':assignee,'observations':notes.text,
          if(widget.initial==null)...{'dates':selectedDates.toList()..sort(),'product':product,'lot':lot,'species':target.single['espece_id']}
          else ...{'expected_version':widget.initial!['version'],'reason':reason.text.trim()}};
      }
      final result=await widget.api.post(widget.initial==null?'/tasks/health-plan/':'/tasks/${widget.initial!['id']}/health-move/',pending!);
      final valid=widget.initial==null?result is List && result.length==(pending!['dates'] as List).length && result.every((r)=>r is Map && r['id'] is int && r['local_only']!=true):result is Map && result['id'] is int && result['local_only']!=true;
      if(!valid)throw StateError('Résultat non confirmé.');
      if(mounted && sameIdentity)v2Confirmed(context,message:'Programmation enregistrée');
    }catch(e){if(mounted)setState(()=>error=pending==null && e is StateError?'${e.message}':'Planification non confirmée. Les mêmes informations sont conservées pour vérification.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){for(final c in [date,time,interval,end,notes,reason])c.dispose();super.dispose();}
  @override Widget build(BuildContext context) {
    final editable=!busy && pending==null;
    Widget field(String key,String label,TextEditingController c)=>V2Field(child:TextField(key:Key(key),enabled:editable,controller:c,decoration:V2InputDecoration(labelText:label,)));
    return V2Scaffold(protectDraft:true,busy:busy,appBar:V2AppBar(title:Text(widget.initial==null?'Programmer une vaccination':'Reporter / réattribuer')),body:ListView(padding:const EdgeInsets.all(16),children:[
      if(error!=null)Text(error!),if(catalog==null)const Text('Chargement des références et des responsables…'),
      if(catalog!=null)...[
        if(widget.initial==null)V2Field(child:DropdownButtonFormField<String>(key:const Key('health-product'),initialValue:product,isExpanded:true,decoration:const V2InputDecoration(labelText:'Vaccin',),
          items:[for(final p in catalog!['products'] as List)if(p['archived']!=true)DropdownMenuItem(value:p['id'] as String,child:Text('${p['name']}'))],onChanged:editable?(v)=>setState(()=>product=v):null)),
        if(widget.initial==null)V2Field(child:DropdownButtonFormField<int>(key:const Key('health-lot'),initialValue:lot,isExpanded:true,decoration:const V2InputDecoration(labelText:'Espèce et lot',),
          items:[for(final l in catalog!['lots'] as List)DropdownMenuItem(value:l['id'] as int,child:Text('${l['nom']} — ${((catalog!['species'] as List? ?? const []).where((s)=>s['id']==l['espece_id']).map((s)=>s['nom']).firstOrNull)??'Espèce non renseignée'}'))],onChanged:editable?(v)=>setState(()=>lot=v):null)),
        if(widget.initial==null)V2DateSelection(key:const Key('health-dates'),selected:selectedDates,enabled:editable,onChanged:(value)=>setState((){selectedDates..clear()..addAll(value);})),
        if(widget.initial!=null)V2DateField(key:const Key('health-date'),controller:date,label:'Date prévue',enabled:editable),
        V2Field(child:DropdownButtonFormField<int>(key:const Key('health-assignee'),initialValue:assignee,isExpanded:true,decoration:const V2InputDecoration(labelText:'Responsable autorisé',),
          items:[for(final p in assignees)DropdownMenuItem(value:p['user'] as int,child:Text('${p['name']}'))],onChanged:editable?(v)=>setState(()=>assignee=v):null)),
        field('health-notes','Observations facultatives',notes),if(widget.initial!=null)field('health-reason','Motif obligatoire',reason),
        const V2Help(title:'Programmation sanitaire',child:Text('Une échéance est une intervention prévue. Elle ne déclare aucune vaccination et ne consomme aucune dose. La programmation nécessite Internet.')),
        ElevatedButton(key:const Key('health-save'),onPressed:busy?null:save,child:Text(pending==null?'Enregistrer':'Renvoyer les mêmes informations')),
      ],
    ]));
  }
}
