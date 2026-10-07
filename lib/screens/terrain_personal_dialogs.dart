part of 'offline_tablet_screen.dart';

String _taskStatus(dynamic status)=>const {'TODO':'À faire','IN_PROGRESS':'En cours','DONE':'Terminée','CANCELLED':'Annulée'}[status]??'État inconnu';

class _TerrainClientDialog extends StatefulWidget {
  const _TerrainClientDialog();
  @override
  State<_TerrainClientDialog> createState()=>_TerrainClientDialogState();
}
class _TerrainClientDialogState extends State<_TerrainClientDialog> {
  final form=GlobalKey<FormState>();
  final name=TextEditingController(),phone=TextEditingController(),city=TextEditingController();
  @override
  void dispose() {name.dispose();phone.dispose();city.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>AlertDialog(title:const Text('Client sur la tablette'),
    content:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Confirmation serveur en attente. Votre auteur personnel sera conservé.'),
      TextFormField(controller:name,maxLength:255,decoration:const InputDecoration(labelText:'Nom'),
        validator:(value)=>value==null || value.trim().isEmpty?'Indiquez le nom du client.':null),
      TextFormField(controller:phone,maxLength:20,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Téléphone')),
      TextFormField(controller:city,maxLength:100,decoration:const InputDecoration(labelText:'Ville')),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
      FilledButton(onPressed:(){if(form.currentState!.validate()) {Navigator.pop(context,<String,dynamic>{'nom':name.text.trim(),'telephone':phone.text.trim(),'ville':city.text.trim()});}},child:const Text('Enregistrer sur la tablette'))]);
}

class _TerrainTaskDialog extends StatefulWidget {
  const _TerrainTaskDialog({required this.task});
  final Map<String,dynamic> task;
  @override
  State<_TerrainTaskDialog> createState()=>_TerrainTaskDialogState();
}
class _TerrainTaskDialogState extends State<_TerrainTaskDialog> {
  late final report=TextEditingController(text:widget.task['report'] as String? ?? '');
  late String status=widget.task['status'] as String;
  @override
  void dispose() {report.dispose();super.dispose();}
  @override
  Widget build(BuildContext context) {
    final choices=widget.task['status']=='DONE'?['DONE']:widget.task['status']=='IN_PROGRESS'?['IN_PROGRESS','DONE']:['TODO','IN_PROGRESS'];
    return AlertDialog(title:Text(widget.task['title'] as String),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Compte rendu conservé sur cette tablette. Un changement du propriétaire peut nécessiter un rapprochement.'),
      DropdownButtonFormField<String>(initialValue:status,decoration:const InputDecoration(labelText:'État'),
        items:[for(final value in choices)DropdownMenuItem(value:value,child:Text(_taskStatus(value)))],
        onChanged:(value){if(value!=null) {setState(()=>status=value);}}),
      TextField(controller:report,maxLength:10000,maxLines:4,decoration:const InputDecoration(labelText:'Compte rendu')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
      FilledButton(onPressed:()=>Navigator.pop(context,<String,dynamic>{'status':status,'report':report.text}),child:const Text('Conserver mon compte rendu'))]);
  }
}
