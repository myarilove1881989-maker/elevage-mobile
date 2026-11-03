import 'package:flutter/material.dart';
import 'health_agenda_screen.dart';
import '../services/api_service.dart';
import '../offline/outbox.dart' show newOperationUuid;
import '../widgets/terrain_entry_gate.dart';

class VaccinationScreen extends StatefulWidget {
  const VaccinationScreen({super.key,required this.api,required this.lotId,required this.lotName});
  final ApiService api;final int lotId;final String lotName;
  @override State<VaccinationScreen> createState()=>_VaccinationScreenState();
}
class _VaccinationScreenState extends State<VaccinationScreen> {
  Map<String,dynamic>? stock;
  List<dynamic>? rows;String? error;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    final captured=ApiService.sessionIdentity;
    try {final value=await widget.api.get('/vaccine-supplies/');if(mounted && captured==ApiService.sessionIdentity && value is Map<String,dynamic>)setState(()=>stock=value);}catch(_){}
    try {final result=await widget.api.get('/vaccinations/?lot=${widget.lotId}');if(mounted && captured==ApiService.sessionIdentity)setState(() {rows=result as List;error=null;});}
    catch(e){if(mounted)setState(()=>error='Historique indisponible : $e');}
  }
  Future<void> form([Map<String,dynamic>? item]) async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>VaccinationForm(api:widget.api,lotId:widget.lotId,initial:item)));await load();
  }
  Future<void> history(Map row) async {
    try {
      final result=await widget.api.get('/vaccinations/${row['id']}/');
      if(!mounted)return;
      await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Historique conservé'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final version in result['history'] as List)Text('${version['occurred_at']} — opérateur ${version['author']}\n${version['kind']=='VAC_CANCEL'?'Annulation':version['kind']=='VAC_EDIT'?'Correction':'Enregistrement'} : ${version['animals']??''} animaux\n${version['reason']}'),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Fermer'))]));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Historique détaillé indisponible : $e')));}
  }
  Future<void> cancel(Map row) async {
    final reason=TextEditingController();final id=newOperationUuid();Map<String,dynamic>? request;
    await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
      title:const Text('Annuler la vaccination'),content:TextField(key:const Key('vaccination-cancel-reason'),controller:reason,enabled:request==null,decoration:const InputDecoration(labelText:'Motif obligatoire')),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Fermer')),TextButton(onPressed:() async {
        if(reason.text.trim().length<3)return;
        request??={'operation_uuid':id,'expected_version':row['version'],'reason':reason.text.trim(),'confirm':true};
        try {await widget.api.deleteForMaintenance('/vaccinations/${row['id']}/',request!);if(dialog.mounted)Navigator.pop(dialog);await load();}
        catch(e){if(dialog.mounted)update((){});if(mounted)ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content:Text('Résultat à vérifier ; renvoyer conservera la même opération. $e')));}
      },child:const Text('Confirmer'))])));
    reason.dispose();
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Suivi de vaccination — ${widget.lotName}')),
    body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
      BusinessCommand(api:widget.api,actions:const {'agenda.plan'},child:ElevatedButton(key:const Key('plan-vaccination'),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>HealthAgendaScreen(api:widget.api,lotId:widget.lotId,startPlanning:true))),child:const Text('Programmer une vaccination dans l’agenda'))),
      BusinessCommand(api:widget.api,actions:const {'vaccinations.create'},child:ElevatedButton(key:const Key('add-vaccination'),onPressed:()=>form(),child:const Text('Enregistrer une vaccination / perte'))),
      if(stock!=null)ExpansionTile(title:const Text('Consulter les flacons et les péremptions'),children:[for(final vial in stock!['vials'] as List)ListTile(title:Text('${vial['label']}'),subtitle:Text('Physique : ${vial['physical']} — utilisable : ${vial['estimated_usable']??vial['usable']} doses\nPéremption : ${vial['expires_on']} — ouverture : ${vial['opened_at']??'non ouvert'}'))]),
      if(error!=null)Text(error!),if(rows==null && error==null)const LinearProgressIndicator(),
      if(rows?.isEmpty==true)const Text('Aucune vaccination enregistrée.'),
      for(final row in rows??[])Card(child:ListTile(onTap:row['id'] is int?()=>history(row as Map):null,title:Text('${row['vaccine']} ${row['voided']==true?'— annulée':''}'),
        subtitle:Text('${row['vaccinated_at']}\nAnimaux : ${row['animals']} — opérateur : ${row['operator_name']??row['operator']}\n${row['state']??''} ${row['observations']??''}\n${[for(final line in row['allocations'] as List? ?? const []) 'Flacon ${line['vial']} : ${line['doses']} doses, ${line['lost']??0} perdues'].join('\n')}'),
        trailing:row['voided']!=true && row['version'] is String && row['local_only']!=true?BusinessCommand(api:widget.api,actions:const {'vaccinations.update','vaccinations.delete'},child:PopupMenuButton<String>(
          onSelected:(v)=>v=='edit'?form(Map<String,dynamic>.from(row as Map)):cancel(row as Map),itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('Corriger')),PopupMenuItem(value:'cancel',child:Text('Annuler avec motif'))])):null)),
    ])));
}

class VaccinationForm extends StatefulWidget {
  const VaccinationForm({super.key,required this.api,required this.lotId,this.initial,this.plannedTask});
  final ApiService api;final int lotId;final Map<String,dynamic>? initial,plannedTask;
  @override State<VaccinationForm> createState()=>_VaccinationFormState();
}
class _VaccinationFormState extends State<VaccinationForm> {
  List<Map<String,dynamic>> plannedTasks=[];Map<String,dynamic>? selectedTask;
  Map<String,dynamic>? catalog,pending;String? product,error;bool busy=false;
  final operation=newOperationUuid();
  final originIdentity=ApiService.sessionIdentity;
  bool get sameIdentity=>originIdentity==ApiService.sessionIdentity;
  final animals=TextEditingController(),date=TextEditingController(text:DateTime.now().toUtc().toIso8601String()),observations=TextEditingController(),reason=TextEditingController();
  final opened=<String,TextEditingController>{},used=<String,TextEditingController>{},lost=<String,TextEditingController>{},duration=<String,TextEditingController>{};
  @override void initState(){super.initState();selectedTask=widget.plannedTask;if(selectedTask!=null)product=selectedTask!['health']['product'] as String;final item=widget.initial;if(item!=null){product=item['product'] as String;animals.text='${item['animals']}';date.text='${item['vaccinated_at']}';observations.text='${item['observations']??''}';}load();}
  Future<void> load() async {
    try {
      final result=Map<String,dynamic>.from(await widget.api.get('/vaccine-supplies/') as Map);
      if(!mounted || !sameIdentity)return;
      if(result['vaccine_contract']!=1)throw StateError('Contrat indisponible.');
      for(final vial in result['vials'] as List) {
        final id=vial['id'] as String;opened[id]=TextEditingController();used[id]=TextEditingController();lost[id]=TextEditingController();duration[id]=TextEditingController();
        for(final line in widget.initial?['allocations'] as List? ?? const [])if(line['vial']==id){used[id]!.text='${line['doses']}';lost[id]!.text='${line['lost']??0}';}
      }
      try{final tasks=await widget.api.get('/tasks/?active=true');plannedTasks=[for(final task in tasks as List)if(task['health'] is Map && task['health']['lot']==widget.lotId && task['status']!='CANCELLED' && task['health']['fulfilled']!=true && task['_health_vaccination_pending']!=true)Map<String,dynamic>.from(task as Map)];}catch(_){}
      if(selectedTask!=null && !plannedTasks.any((r)=>r['id']==selectedTask!['id']))plannedTasks.add(selectedTask!);
      if(mounted && sameIdentity)setState(()=>catalog=result);
    }catch(e){if(mounted)setState(()=>error='$e');}
  }
  bool eligible(Map vial) {
    final lots=(catalog?['lots'] as List? ?? const []).where((r)=>r['id']==widget.lotId).toList();
    return lots.length==1 && vial['product']==product && vial['species']==lots.single['espece_id'] && (vial['lot']==null || vial['lot']==widget.lotId);
  }
  int count(String text) {if(text.isEmpty)return 0;if(!RegExp(r'^\d+$').hasMatch(text))throw StateError('Nombre entier requis.');return int.parse(text);}
  Future<void> save() async {
    if(!sameIdentity){setState(()=>error='Profil modifié. Rouvrez le formulaire avec l’identité d’origine.');return;}
    if(busy)return;setState(()=>busy=true);
    try {
      if(pending==null) {
        final lots=(catalog!['lots'] as List).where((r)=>r['id']==widget.lotId).toList();
        if(lots.length!=1 || product==null)throw StateError('Choisissez un vaccin et un lot ouvert.');
        final lines=<Map<String,dynamic>>[];
        for(final vial in catalog!['vials'] as List) {
          if(vial['product']!=product || vial['species']!=lots.single['espece_id'] || (vial['lot']!=null && vial['lot']!=widget.lotId))continue;
          final id=vial['id'] as String,u=count(used[id]!.text),l=count(lost[id]!.text);
          if(u+l==0)continue;
          final physical=vial['estimated_physical']??vial['physical'],available=vial['estimated_usable']??vial['usable'];
          if(u>0 && !DateTime.now().isBefore(DateTime.parse(vial['usable_until'] as String)))throw StateError('Flacon arrivé à péremption ou durée dépassée.');
          if(u+l>physical || u>available)throw StateError('Doses insuffisantes ou inutilisables pour ce flacon.');
          if(u==0 && l>0 && l<physical && vial['opened_at']==null && opened[id]!.text.isEmpty)throw StateError('Indiquez la date d’ouverture pour une perte partielle.');
          lines.add({'vial':id,'doses':u,'lost':l,if(vial['opened_at']==null && opened[id]!.text.isNotEmpty)'opened_at':DateTime.parse(opened[id]!.text).toUtc().toIso8601String(),if(vial['opened_at']==null && duration[id]!.text.isNotEmpty)'usable_seconds':count(duration[id]!.text)});
        }
        if(lines.isEmpty || DateTime.tryParse(date.text)==null || (widget.initial!=null && reason.text.trim().length<3))throw StateError('Complétez les flacons, la date et le motif de correction.');
        pending={'operation_uuid':operation,'vaccinated_at':DateTime.parse(date.text).toUtc().toIso8601String(),'animals':count(animals.text),'allocations':lines,'observations':observations.text,
          if(widget.initial==null) ...{'lot':widget.lotId,'product':product,if(selectedTask!=null)...{'task_id':selectedTask!['id'],'task_version':selectedTask!['version']}} else ...{'expected_version':widget.initial!['version'],'reason':reason.text.trim()}};
      }
      final result=widget.initial==null?await widget.api.post('/vaccinations/',pending!):await widget.api.patch('/vaccinations/${widget.initial!['id']}/',pending!);
      if(result is! Map || (result['id']==null && result['local_only']!=true))throw StateError('Enregistrement non confirmé.');
      if(mounted && sameIdentity)Navigator.pop(context,true);
    }catch(e){if(mounted)setState(()=>error=pending==null?'$e':'Résultat à vérifier. La même opération sera renvoyée. $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){for(final c in [animals,date,observations,reason,...opened.values,...used.values,...lost.values,...duration.values])c.dispose();super.dispose();}
  @override Widget build(BuildContext context) {
    final editable=!busy && pending==null;
    Widget text(String key,String label,TextEditingController controller)=>TextField(key:Key(key),enabled:editable,controller:controller,decoration:InputDecoration(labelText:label));
    return Scaffold(appBar:AppBar(title:Text(widget.initial==null?'Vaccination / perte':'Corriger la vaccination')),body:ListView(padding:const EdgeInsets.all(16),children:[
      if(error!=null)Text(error!),if(catalog==null)const Text('Référentiel et flacons requis.'),
      if(catalog!=null)...[
        const Text('Opérateur responsable : votre identité connectée, conservée avec la déclaration.'),
        DropdownButtonFormField<String>(key:const Key('vaccination-product'),initialValue:product,isExpanded:true,decoration:const InputDecoration(labelText:'Vaccin'),
          items:[for(final p in catalog!['products'] as List)if(p['archived']!=true || p['id']==product)DropdownMenuItem(value:p['id'] as String,child:Text('${p['name']}'))],
          onChanged:editable && widget.initial==null && widget.plannedTask==null?(v)=>setState(() {product=v;selectedTask=null;}):null),
        if(widget.initial==null && plannedTasks.any((r)=>r['health']['product']==product))DropdownButtonFormField<int>(key:ValueKey('vaccination-planned-task-$product'),initialValue:selectedTask?['id'] as int? ?? 0,isExpanded:true,decoration:const InputDecoration(labelText:'Rendez-vous sanitaire facultatif'),items:[const DropdownMenuItem(value:0,child:Text('Sans rattachement')),for(final task in plannedTasks)if(task['health']['product']==product)DropdownMenuItem(value:task['id'] as int,child:Text('${task['date']} — ${task['title']}'))],onChanged:editable?(id)=>setState(()=>selectedTask=id==0?null:plannedTasks.singleWhere((r)=>r['id']==id)):null),
        text('vaccination-date','Date et heure (ex. 2026-11-03 08:30)',date),text('vaccination-animals','Nombre d’animaux vaccinés (0 pour perte seule)',animals),
        for(final vial in catalog!['vials'] as List)if(eligible(vial as Map))...[
          Text('Flacon ${vial['label']} — péremption ${vial['expires_on']}\nPhysique confirmé : ${vial['physical']} ; attente : ${vial['pending_doses']??0} ; utilisable estimé : ${vial['estimated_usable']??vial['usable']}\nOuverture : ${vial['opened_at']??'non ouvert'}'),
          text('used-${vial['id']}','Doses administrées',used[vial['id']]!),text('lost-${vial['id']}','Doses perdues / jetées',lost[vial['id']]!),
          if(vial['opened_at']==null)text('opened-${vial['id']}','Ouverture antérieure (date et heure, facultatif sauf perte partielle)',opened[vial['id']]!),
          if(vial['opened_at']==null)text('duration-${vial['id']}','Durée après ouverture en secondes (facultative, selon information connue)',duration[vial['id']]!),
        ],
        const Text('Une première utilisation enregistre l’ouverture à la date indiquée. Aucune durée ou fréquence sanitaire n’est inventée. Les approvisionnements locaux doivent être confirmés avant de sélectionner leurs flacons.'),
        text('vaccination-observations','Observations facultatives',observations),if(widget.initial!=null)text('vaccination-reason','Motif obligatoire',reason),
        ElevatedButton(key:const Key('save-vaccination'),onPressed:busy?null:save,child:Text(pending==null?'Enregistrer':'Renvoyer la même opération')),
      ],
    ]));
  }
}
