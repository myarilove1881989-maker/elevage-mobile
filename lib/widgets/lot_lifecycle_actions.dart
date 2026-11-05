import '../widgets/v2_components.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LotLifecycleActions extends StatefulWidget {
  const LotLifecycleActions({super.key,required this.api,required this.lot,required this.access,required this.onChanged});
  final ApiService api;
  final Map<String,dynamic> lot;
  final Future<bool> access;
  final VoidCallback onChanged;
  @override State<LotLifecycleActions> createState()=>_LotLifecycleActionsState();
}
class _LotLifecycleActionsState extends State<LotLifecycleActions>{
  bool busy=false;
  Future<void> open() async {
    if(busy)return;
    setState(()=>busy=true);
    final identity=ApiService.sessionIdentity;
    try{
      final endpoint='/lots/${widget.lot['id']}/lifecycle/';
      final data=Map<String,dynamic>.from(await widget.api.get(endpoint) as Map);
      if(!mounted || identity!=ApiService.sessionIdentity)return;
      final changed=await showDialog<bool>(context:context,barrierDismissible:false,
        builder:(_)=>_LifecycleDialog(api:widget.api,endpoint:endpoint,data:data,identity:identity));
      if(changed==true && mounted && identity==ApiService.sessionIdentity)widget.onChanged();
    }catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final closed=ApiService.isLotClosed(widget.lot);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(closed)Text('Lot clôturé${widget.lot['date_fin']==null?'':' le ${widget.lot['date_fin']}'}. Historique et créances conservés.',key:const Key('closed-lot-notice')),
      FutureBuilder<bool>(future:widget.access,builder:(_,result)=>result.data!=true?const SizedBox.shrink():TextButton.icon(
        key:const Key('lot-lifecycle-action'),onPressed:busy?null:open,
        icon:Icon(closed?Icons.lock_open:Icons.inventory_outlined),label:Text(closed?'Réouvrir le lot':'Clôturer le lot'))),
    ]);
  }
}
class _LifecycleDialog extends StatefulWidget {
  const _LifecycleDialog({required this.api,required this.endpoint,required this.data,required this.identity});
  final ApiService api;final String endpoint;final Map<String,dynamic> data;final String? identity;
  @override State<_LifecycleDialog> createState()=>_LifecycleDialogState();
}
class _LifecycleDialogState extends State<_LifecycleDialog>{
  final form=GlobalKey<FormState>();
  late final date=TextEditingController(text:DateTime.now().toIso8601String().split('T')[0]);
  final reason=TextEditingController();
  bool sending=false;String? error;
  bool get reopen=>widget.data['closed']==true;
  @override void dispose(){date.dispose();reason.dispose();super.dispose();}
  Future<void> save() async{
    if(sending || !form.currentState!.validate())return;
    if(widget.identity!=ApiService.sessionIdentity){setState(()=>error='La session a changé. Rouvrez le formulaire.');return;}
    setState((){sending=true;error=null;});
    try{
      await widget.api.post(widget.endpoint,{'action':reopen?'REOPEN':'CLOSE','farm':widget.data['farm'],
        'expected_revision':widget.data['revision'],'confirm':true,'reason':reason.text.trim(),if(!reopen)'date_fin':date.text.trim()});
      if(mounted)Navigator.pop(context,true);
    }catch(problem){if(mounted)setState((){sending=false;error='$problem';});}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!sending,child:V2AlertDialog(
    title:Text(reopen?'Réouvrir le lot':'Clôturer le lot'),
    content:SizedBox(width:440,child:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${widget.data['message']}'),const SizedBox(height:12),
      Text('Stock conservé : ${widget.data['stock_animaux']} animaux, ${widget.data['stock_oeufs']} œufs. Créances : ${widget.data['creances']}.'),
      if(!reopen)...[
        const SizedBox(height:12),
        const Text('Même si le stock est non nul, aucune vente, perte ou sortie ne sera créée.'),
        V2Field(child:TextFormField(key:const Key('lot-close-date'),controller:date,enabled:!sending,
          decoration:V2InputDecoration(labelText:'Date de clôture (AAAA-MM-JJ)',helperText:'Au plus tôt : ${widget.data['date_minimum']}',),
          keyboardType:TextInputType.datetime,validator:(value){final d=DateTime.tryParse(value??'');return d==null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value??'')?'Indiquez une date valide.':null;})),
      ],
      V2Field(child:TextFormField(controller:reason,enabled:!sending,maxLength:1000,decoration:const V2InputDecoration(labelText:'Motif (facultatif)',))),
      if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ])))),
    actions:[TextButton(onPressed:sending?null:()=>Navigator.pop(context,false),child:const Text('Annuler')),
      FilledButton(onPressed:sending?null:save,child:Text(sending?'Enregistrement…':reopen?'Confirmer la réouverture':'Confirmer la clôture'))]));
}
