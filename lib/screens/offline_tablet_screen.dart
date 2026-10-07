import 'package:flutter/material.dart';
import '../config.dart';
import '../offline/device_identity.dart';
import '../offline/foundation_api.dart';
import '../offline/local_operator_session.dart';
import '../offline/tablet_controller.dart';

class OfflineTabletScreen extends StatefulWidget {
  const OfflineTabletScreen({super.key,this.controller});
  final TabletController? controller;
  @override
  State<OfflineTabletScreen> createState()=>_OfflineTabletScreenState();
}

class _OfflineTabletScreenState extends State<OfflineTabletScreen> with WidgetsBindingObserver {
  late final TabletController tablet;
  final username=TextEditingController(),password=TextEditingController();
  bool busy=false;
  String? message;
  String collection='lots';
  int offset=0;
  List<Map<String,dynamic>> rows=[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const secrets=AndroidOperatorSecretStore();
    tablet=widget.controller ?? TabletController(api:FoundationApi(baseUrl:Config.validatedApiUrl(Config.apiUrl),
      deviceIdentity:AndroidDeviceIdentity(),secrets:secrets),secrets:secrets);
    _run(tablet.initialize);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state!=AppLifecycleState.resumed) { tablet.lock(); if(mounted) setState(()=>rows=[]); }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tablet.lock();tablet.api.close();tablet.dispose();
    username.dispose();password.dispose();super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if(busy) return;
    setState(() {busy=true;message=null;});
    try { await action(); }
    catch(error) {
      if(mounted) {
        setState(()=>message=error is StateError?error.message.toString():
          error is FoundationApiException?error.toString():'Connexion ou stockage sécurisé indisponible.');
      }
    } finally { if(mounted) setState(()=>busy=false); }
  }

  Future<String?> _pinDialog({String title='PIN personnel'}) async {
    final pin=TextEditingController();
    final value=await showDialog<String>(context:context,builder:(dialog)=>AlertDialog(
      title:Text(title),content:TextField(controller:pin,obscureText:true,keyboardType:TextInputType.number,
        maxLength:12,autofocus:true,decoration:const InputDecoration(labelText:'6 à 12 chiffres')),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),
        FilledButton(onPressed:()=>Navigator.pop(dialog,pin.text),child:const Text('Valider'))]));
    pin.clear();pin.dispose();return value;
  }

  Future<void> _read() async {rows=await tablet.readPage(collection,offset:offset);}

  @override
  Widget build(BuildContext context)=>AnimatedBuilder(animation:tablet,builder:(context,_) {
    final session=tablet.operators?.session;
    return Scaffold(appBar:AppBar(title:const Text('Tablette de l’exploitation'),actions:[
      if(session!=null) IconButton(tooltip:'Verrouiller / changer d’opérateur',icon:const Icon(Icons.lock_outline),
        onPressed:busy?null:()=>setState(() {tablet.lock();rows=[];})),
    ]),body:ListView(padding:const EdgeInsets.all(16),children:[
      if(busy) const LinearProgressIndicator(),
      if(message!=null) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(message!,style:const TextStyle(color:Colors.red))),
      Text(tablet.farmId==null?'Cette tablette doit être préparée par le propriétaire.':
        'Exploitation ${tablet.farmId} • données conservées sur cette tablette'),
      const SizedBox(height:16),
      if(session==null) ...[
        for(final profile in tablet.profiles) ListTile(leading:const Icon(Icons.person_outline),
          title:Text(profile['display_name'] as String),subtitle:const Text('Ouvrir avec mon PIN'),
          enabled:!busy,onTap:() async {
            final pin=await _pinDialog();
            if(pin==null || !mounted) return;
            await _run(() async {
              await tablet.unlockProfile(profile['user_id'] as int,profile['display_name'] as String,pin);
              offset=0;await _read();
            });
          }),
        const Divider(),
        const Text('Préparation avec une connexion Internet'),
        TextField(controller:username,autocorrect:false,decoration:const InputDecoration(labelText:'Compte personnel')),
        TextField(controller:password,obscureText:true,enableSuggestions:false,autocorrect:false,
          decoration:const InputDecoration(labelText:'Mot de passe')),
        FilledButton(onPressed:busy?null:()=>_run(() async {
          try {await tablet.signIn(username.text.trim(),password.text);} finally {password.clear();}
        }),child:const Text('Me connecter')),
        if(tablet.api.personal?.role=='OWNER') ...[
          OutlinedButton(onPressed:busy?null:()=>_run(tablet.preparePrimaryTablet),child:const Text('Préparer cette tablette principale')),
          const Text('L’activation hors ligne de l’exploitation doit être décidée par le propriétaire. '
            'La préparation de tablette ne l’active pas automatiquement.'),
          OutlinedButton(onPressed:busy || tablet.cache==null?null:()=>_run(tablet.refreshCache),child:const Text('Actualiser les données confirmées')),
        ],
        if(tablet.api.personal?.role=='OPERATEUR') OutlinedButton(onPressed:busy?null:() async {
          final pin=await _pinDialog(title:'Préparer ou renouveler mon profil');
          if(pin==null || !mounted) return;
          await _run(()=>tablet.prepareOperator(pin));
        },child:const Text('Préparer mon accès par PIN')),
      ] else ...[
        Text('Profil ouvert : ${tablet.selectedName}',style:Theme.of(context).textTheme.titleMedium),
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
        const Text('Données confirmées lors du dernier chargement. Une connexion est nécessaire pour les actualiser.'),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(initialValue:collection,decoration:const InputDecoration(labelText:'Consulter'),
          items:const [DropdownMenuItem(value:'lots',child:Text('Lots')),DropdownMenuItem(value:'clients',child:Text('Clients')),
            DropdownMenuItem(value:'species',child:Text('Espèces')),DropdownMenuItem(value:'tasks',child:Text('Agenda'))],
          onChanged:busy?null:(value) { if(value==null) return;collection=value;offset=0;_run(_read); }),
        for(final row in rows) ListTile(title:Text(((row['data'] as Map)['nom']??(row['data'] as Map)['title']??'Donnée').toString()),
          subtitle:Text(collection=='lots'?'Stock confirmé : ${(row['data'] as Map)['stock']}':
            collection=='tasks'?'${(row['data'] as Map)['date']} • ${(row['data'] as Map)['status']}':'Confirmé lors du dernier chargement')),
        if(rows.isEmpty) const Padding(padding:EdgeInsets.all(16),child:Text('Aucune donnée confirmée sur cette page.')),
        Row(children:[TextButton(onPressed:busy || offset==0?null:()=>_run(() async {offset-=50;await _read();}),child:const Text('Précédent')),
          TextButton(onPressed:busy || rows.length<50?null:()=>_run(() async {offset+=50;await _read();}),child:const Text('Suivant'))]),
        OutlinedButton(onPressed:busy?null:()=>_run(() async {await tablet.refreshCache();offset=0;await _read();}),child:const Text('Actualiser avec Internet')),
      ],
    ]));
  });
}
