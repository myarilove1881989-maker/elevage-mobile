import '../services/api_service.dart';
import 'login_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../offline/device_identity.dart';
import '../offline/foundation_api.dart';
import '../offline/local_operator_session.dart';
import '../offline/tablet_controller.dart';
import '../offline/sync_coordinator.dart';
import '../services/farmer_runtime.dart';
import '../services/initial_password.dart';
import '../services/server_connection.dart';
import '../theme/terre_et_or_theme.dart';
import 'dashboard_screen.dart';
import 'initial_password_screen.dart';

FarmerRuntime createFarmerRuntime() {
  const secrets=AndroidOperatorSecretStore();
  final base=Config.validatedApiUrl(Config.apiUrl);
  final connection=ServerConnection(baseUrl:base);
  final tablet=TabletController(api:FoundationApi(baseUrl:base,deviceIdentity:AndroidDeviceIdentity(),secrets:secrets),
    secrets:secrets,networkChanges:connection.changes);
  return FarmerRuntime(tablet:tablet,connection:connection,networkHints:androidNetworkChanges());
}

class FarmerAccessScreen extends StatefulWidget {
  const FarmerAccessScreen({super.key,this.runtime,this.onAuthenticated});
  final FarmerRuntime? runtime;
  final void Function(FarmerApiService api)? onAuthenticated;
  @override
  State<FarmerAccessScreen> createState()=>_FarmerAccessScreenState();
}
class _FarmerAccessScreenState extends State<FarmerAccessScreen> {
  late final FarmerRuntime runtime=widget.runtime??createFarmerRuntime();
  final account=TextEditingController(),code=TextEditingController();
  bool busy=false,transferred=false;
  String? message;
  Future<void> signIn() async {
    FocusScope.of(context).unfocus();
    if(busy) return;
    setState(() {busy=true;message=null;});
    try {
      final api=await runtime.signIn(account.text.trim(),code.text);
      code.clear();
      if(!mounted) return;
      if(widget.onAuthenticated!=null) {widget.onAuthenticated!(api);return;}
      transferred=true;
      Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>FarmerSessionHost(runtime:runtime,api:api)));
    } on InitialPasswordRequired catch(required) {
      code.clear();
      if(!mounted) return;
      final changed=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>InitialPasswordScreen(
        changeToken:required.changeToken,onChange:runtime.tablet.api.changeInitialPassword)));
      if(mounted) setState(()=>message=changed==true?'Code personnel modifié. Connectez-vous avec votre nouveau code.':'Choisissez votre code personnel pour continuer.');
    } on FoundationApiException catch(error) {
      if(mounted) setState(()=>message={401,403}.contains(error.status)
        ?'Identifiant ou code incorrect, ou accès désactivé. Vérifiez puis réessayez.'
        :'Votre accès doit être préparé par le propriétaire.');
    } catch(error) {
      if(mounted) setState(()=>message=isTransportFailure(error)
        ?'Connexion indisponible. Un premier accès avec Internet est nécessaire.'
        :'Accès indisponible : vérifiez votre code ou demandez au propriétaire de préparer votre accès.');
    } finally {
      code.clear();if(mounted) setState(()=>busy=false);
    }
  }
  @override
  void dispose() {
    account.dispose();code.clear();code.dispose();
    if(!transferred && widget.runtime==null) runtime.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context)=>Theme(data:terreEtOrTheme(context),child:Builder(builder:(context)=>Scaffold(
    appBar:AppBar(title:const Text('Élev’Age — Espace éleveur')),
    body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:480),child:TerreEtOrPanel(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const TerreEtOrHeader(icon:Icons.agriculture_outlined,title:'Bienvenue',subtitle:'Accédez à votre exploitation'),
        TextField(controller:account,enabled:!busy,autocorrect:false,textInputAction:TextInputAction.next,
          decoration:const InputDecoration(labelText:'Identifiant',prefixIcon:Icon(Icons.person_outline))),
        const SizedBox(height:16),
        TextField(controller:code,enabled:!busy,obscureText:true,enableSuggestions:false,autocorrect:false,
          onSubmitted:(_)=>signIn(),decoration:const InputDecoration(labelText:'Code personnel',prefixIcon:Icon(Icons.lock_outline))),
        if(message!=null) Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(message!,key:const Key('farmer-access-message'))),
        const SizedBox(height:20),SizedBox(width:double.infinity,child:FilledButton(
          onPressed:busy?null:signIn,child:Text(busy?'Connexion…':'Se connecter'))),
      ])),
    ))),
  )));
}

class FarmerSessionHost extends StatefulWidget {
  const FarmerSessionHost({super.key,required this.runtime,required this.api});
  final FarmerRuntime runtime;
  final FarmerApiService api;
  @override
  State<FarmerSessionHost> createState()=>_FarmerSessionHostState();
}
class _FarmerSessionHostState extends State<FarmerSessionHost> with WidgetsBindingObserver {
  bool leaving=false;
  Timer? check;
  void _activity(PointerEvent event) {
    if(event is PointerDownEvent || event is PointerMoveEvent || event is PointerSignalEvent) widget.runtime.tablet.userActivity();
  }
  bool _key(KeyEvent event) {widget.runtime.tablet.userActivity();return false;}
  @override
  void initState() {
    super.initState();WidgetsBinding.instance.addObserver(this);
    widget.runtime.tablet.userActivity();
    widget.runtime.addListener(_changed);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_activity);HardwareKeyboard.instance.addHandler(_key);
    check=Timer.periodic(const Duration(seconds:1),(_)=>_changed());
  }
  void _changed() {
    if(!mounted || leaving || widget.runtime.signedIn) return;
    leaving=true;
        // Invalidate only active credentials; keep the encrypted offline store.
    final publicApi=ApiService(tokenStore:widget.runtime.tokenStore);
    publicApi.logout().then((_) {
      if(!mounted) {publicApi.close();return;}
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted) Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder:(_)=>LoginScreen(apiService:publicApi)),(_)=>false);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.runtime.handleAppLifecycleState(state);
  }
  @override
  void dispose() {
    check?.cancel();WidgetsBinding.instance.removeObserver(this);widget.runtime.removeListener(_changed);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_activity);HardwareKeyboard.instance.removeHandler(_key);
    widget.api.close();widget.runtime.dispose();super.dispose();
  }
  @override
  Widget build(BuildContext context)=>PopScope(
    canPop:false,
    onPopInvokedWithResult:(didPop,result) {
      if(!didPop && !leaving) widget.runtime.lock();
    },
    child:DashboardScreen(apiService:widget.api));
}
