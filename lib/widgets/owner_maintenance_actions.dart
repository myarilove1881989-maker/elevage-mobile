import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'terrain_entry_gate.dart';
import 'mutation_refresh.dart';

Future<bool> ownerMaintenanceAllowed(ApiService api) async {
  try {
    final access=await TerrainEntryAccess.read(api,{'lots.create'});
    return access.rights.role=='OWNER' && access.rights.httpVersion==2 && access.message==null;
  } catch (_) {return false;}
}

class OwnerMaintenanceActions extends StatefulWidget {
  const OwnerMaintenanceActions({super.key,required this.api,required this.kind,
    required this.label,required this.access,this.id,this.onChanged,this.onDeleted,this.edit=true,this.remove=true});
  final ApiService api;
  final String kind,label;
  final int? id;
  final Future<bool> access;
  final VoidCallback? onChanged,onDeleted;
  final bool edit,remove;
  @override State<OwnerMaintenanceActions> createState()=>_OwnerMaintenanceActionsState();
}
class _OwnerMaintenanceActionsState extends State<OwnerMaintenanceActions> {
  bool busy=false;
  Future<void> open(bool deleting) async {
    if(busy)return;
    setState(()=>busy=true);
    try {
      final identity=ApiService.sessionIdentity;
      final endpoint='/maintenance/${widget.kind}/${widget.id==null?'':'${widget.id}/'}';
      final schema=Map<String,dynamic>.from(await widget.api.get(endpoint) as Map);
      if(!mounted || identity!=ApiService.sessionIdentity)return;
      final changed=await showDialog<bool>(context:context,barrierDismissible:false,
        builder:(_)=>_MaintenanceDialog(api:widget.api,endpoint:endpoint,schema:schema,
          label:widget.label,deleting:deleting,creating:widget.id==null,identity:identity));
      if(changed==true && mounted){if(deleting && widget.onDeleted!=null){widget.onDeleted!();}else{widget.onChanged?.call();}}
    } catch(error) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));
    } finally {if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<bool>(future:widget.access,builder:(context,snapshot){
    if(snapshot.data!=true)return const SizedBox.shrink();
    return Wrap(spacing:8,children:[
      if(widget.edit)TextButton.icon(key:ValueKey('owner-edit-${widget.kind}-${widget.id}'),
        onPressed:busy?null:()=>open(false),icon:Icon(widget.id==null?Icons.add:Icons.edit_outlined),
        label:Text('${widget.id==null?'Créer':'Modifier'} ${widget.label}')),
      if(widget.remove && widget.id!=null)TextButton.icon(key:ValueKey('owner-delete-${widget.kind}-${widget.id}'),
        onPressed:busy?null:()=>open(true),icon:const Icon(Icons.delete_outline),
        label:Text('Supprimer ${widget.label}')),
    ]);
  });
}

class _MaintenanceDialog extends StatefulWidget {
  const _MaintenanceDialog({required this.api,required this.endpoint,required this.schema,
    required this.label,required this.deleting,required this.creating,required this.identity});
  final ApiService api;
  final String endpoint,label;
  final Map<String,dynamic> schema;
  final bool deleting,creating;
  final String? identity;
  @override State<_MaintenanceDialog> createState()=>_MaintenanceDialogState();
}
class _MaintenanceDialogState extends State<_MaintenanceDialog> {
  final form=GlobalKey<FormState>();
  final reason=TextEditingController();
  final controllers=<String,TextEditingController>{};
  final choices=<String,String>{};
  bool submitting=false;
  String? error;
  List<Map<String,dynamic>> get fields=>(widget.schema['fields'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
  @override void initState(){
    super.initState();
    for(final field in fields){
      final name=field['name'] as String;
      if(field['type']=='choice'){
        final available=(field['choices'] as List).map((x)=>'${x['value']}').toList();
        choices[name]=available.contains('${field['value']}')?'${field['value']}':available.isEmpty?'':available.first;
      }else{controllers[name]=TextEditingController(text:'${field['value']??''}');}
    }
    if(widget.creating)reason.text='Création du lot';
  }
  @override void dispose(){for(final controller in controllers.values){controller.dispose();}reason.dispose();super.dispose();}
  Future<void> save() async {
    if(submitting || !form.currentState!.validate())return;
    if(widget.identity!=ApiService.sessionIdentity){setState(()=>error='La session a changé. Fermez ce formulaire et reconnectez-vous.');return;}
    setState((){submitting=true;error=null;});
    final values=<String,dynamic>{};
    for(final field in fields){
      final name=field['name'] as String;
      final text=controllers[name]?.text.trim()??choices[name]??'';
      values[name]=field['type']=='integer' || name=='espece'?int.tryParse(text):field['type']=='decimal'?text.replaceAll(',','.'):text;
    }
    final payload={'confirm':true,'reason':reason.text.trim(),'farm':widget.schema['farm'],'expected_revision':widget.schema['revision'],
      'values':widget.deleting?<String,dynamic>{}:values};
    try {
      if(widget.deleting){await widget.api.deleteForMaintenance(widget.endpoint,payload);}
      else if(widget.creating){await widget.api.post(widget.endpoint,payload);}
      else{await widget.api.patch(widget.endpoint,payload);}
      if(mounted)Navigator.pop(context,true);
    }catch(problem){if(mounted)setState((){error='$problem';submitting=false;});}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!submitting,child:AlertDialog(
    title:Text('${widget.deleting?'Supprimer':widget.creating?'Créer':'Modifier'} ${widget.label}'),
    content:SizedBox(width:480,child:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      if(widget.deleting)Text('${widget.schema['consequences']}'),
      if(!widget.deleting)for(final field in fields)Padding(padding:const EdgeInsets.only(bottom:12),child:
        field['type']=='choice'?DropdownButtonFormField<String>(initialValue:choices[field['name']]!.isEmpty?null:choices[field['name']],
          decoration:InputDecoration(labelText:'${field['label']}'),
          items:[for(final option in field['choices'])DropdownMenuItem(value:'${option['value']}',child:Text('${option['label']}'))],
          onChanged:submitting?null:(value)=>setState(()=>choices[field['name']]=value??''),
          validator:(value)=>value==null||value.isEmpty?'Choisissez une valeur.':null):
        TextFormField(controller:controllers[field['name']],enabled:!submitting,
          decoration:InputDecoration(labelText:'${field['label']}'),
          keyboardType:field['type']=='integer'||field['type']=='decimal'?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,
          validator:(value)=>field['name']!='note' && (value==null||value.trim().isEmpty)?'Champ requis.':null)),
      const SizedBox(height:12),
      TextFormField(controller:reason,enabled:!submitting,decoration:const InputDecoration(labelText:'Motif'),
        validator:(value)=>(value??'').trim().length<3?'Précisez un motif (3 caractères minimum).':null),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
    ])))),
    actions:[TextButton(onPressed:submitting?null:()=>Navigator.pop(context,false),child:const Text('Annuler')),
      FilledButton(onPressed:submitting?null:save,child:Text(submitting?'Enregistrement…':widget.deleting?'Confirmer la suppression':'Enregistrer'))],
  ));
}

class OwnerMaintenanceList extends StatefulWidget {
  const OwnerMaintenanceList({super.key,required this.api,required this.kind,required this.title,required this.access,this.lotId});
  final ApiService api;final String kind,title;final Future<bool> access;final int? lotId;
  @override State<OwnerMaintenanceList> createState()=>_OwnerMaintenanceListState();
}
class _OwnerMaintenanceListState extends State<OwnerMaintenanceList> with MutationRefresh<OwnerMaintenanceList> {
  @override Future<void> refreshAfterMutation()=>load();
  List<dynamic> rows=[];bool loading=true,failed=false;int? nextOffset;
  @override void initState(){super.initState();load();}
  Future<void> load({int offset=0}) async {
    markDataFresh();
    if(!await widget.access || !mounted)return;
    try{
      final data=await widget.api.get('/maintenance/${widget.kind}/?list=1&offset=$offset${widget.lotId==null?'':'&lot=${widget.lotId}'}');
      if(mounted)setState((){rows=offset==0?data['results']:[...rows,...data['results']];nextOffset=data['next_offset'];loading=false;failed=false;});
    }catch(_){if(mounted)setState((){loading=false;failed=true;});}
  }
  @override Widget build(BuildContext context)=>FutureBuilder<bool>(future:widget.access,builder:(context,snapshot){
    if(snapshot.data!=true)return const SizedBox.shrink();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(widget.title,style:Theme.of(context).textTheme.titleMedium),
      if(loading)const LinearProgressIndicator(),
      if(failed)TextButton(onPressed:()=>load(),child:const Text('Chargement impossible. Réessayer')),
      for(final row in rows)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${row['label']}'),Text('${row['date']}'),
        OwnerMaintenanceActions(api:widget.api,kind:widget.kind,id:row['id'] as int,label:'cet enregistrement',access:widget.access,onChanged:()=>load()),
      ]))),
      if(nextOffset!=null)TextButton(onPressed:()=>load(offset:nextOffset!),child:const Text('Afficher la suite')),
    ]);
  });
}
