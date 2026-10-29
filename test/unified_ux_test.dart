import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/screens/farmer_access_screen.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/screens/login_screen.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/operation_history_screen.dart';
import 'package:app_elevage/screens/owner_operation_history_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/farmer_runtime.dart';
import 'package:app_elevage/services/server_connection.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:app_elevage/services/initial_password.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'foundation_api_test.dart' show TestIdentity,TestSecretStore;
import 'online_expense_form_test.dart' show OnlineExpenseServer;
Widget testApp(Widget home)=>MaterialApp(debugShowCheckedModeBanner:false,locale:const Locale('fr'),
  supportedLocales:const [Locale('fr'),Locale('en')],theme:ThemeData(fontFamily:'Roboto'),
  localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],home:home);



Map<String,dynamic> caps()=>{'user':2,'exploitation':1,'role':'OPERATEUR','offline_policy_enabled':false,
  'membership':{'id':2,'username':'eleveur-fictif','version':1},'credential_version':1,
  'permission_contract':{'version':1,'user':2,'exploitation':1,'role':'OPERATEUR','rights_version':1,
    'permissions':['finance.read','purchases.create','expenses.create','mortality.create']}};
class VisualRuntime extends FarmerRuntime {
  VisualRuntime():super(tablet:TabletController(api:FoundationApi(baseUrl:Config.apiUrl,deviceIdentity:TestIdentity(),
      secrets:TestSecretStore(),client:MockClient((_) async=>http.Response('{}',200))),secrets:TestSecretStore(),
      automaticSyncEnabled:false),connection:ServerConnection(baseUrl:Config.apiUrl,
      interval:const Duration(days:1),client:MockClient((_) async=>http.Response('{"status":"ok"}',200))),
      tokenStore:TokenService(useSecureStorage:false));
  bool initial=false;
  @override
  Future<FarmerApiService> signIn(String account,String code) async {
    if(initial) throw const InitialPasswordRequired('synthetic-limited');
    username=account;
    tablet.api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',capabilities:caps(),access:'synthetic-access',refresh:'synthetic-refresh');
    final api=FarmerApiService(this);await api.usePersonalOnlineSession('synthetic-access',account);
    connection.start();await connection.probe();return api;
  }
  @override
  Future<http.Response> request(http.BaseRequest request) async {
    final path=request.url.path;
    Object body=[];
    if(path.endsWith('/capabilities/')) body=caps();
    if(path.endsWith('/dashboard/')) body={'kpis':{'stock':81,'chiffre_affaires':125000,'depenses':32000}};
    if(path.endsWith('/total-dettes/')) body={'total_dettes':12500};
    return http.Response(jsonEncode(body),200);
  }
}
class HistoryVisualApi extends ApiService {
  @override Future<dynamic> get(String endpoint) async=>{'results':[
    {'id':1,'operation_id':'00000000-0000-4000-8000-000000000012','actor_user_id':2,
      'entity_type':'core.depense','occurred_at':'2026-10-27T08:00:00Z',
      'after_data':{'montant':'12500.00','note':'Transport du lot','date':'2026-10-27','business_status':'CONFIRMED'}},
    {'id':2,'operation_id':'00000000-0000-4000-8000-000000000013','actor_user_id':2,
      'entity_type':'core.achat','occurred_at':'2026-10-27T09:00:00Z',
      'after_data':{'nom_lot':'Poulets — octobre','quantite':40,'business_status':'CONFIRMED'}}], 'next':null};
}
Future<void> capture(WidgetTester tester,GlobalKey key,String name) async {
  await tester.runAsync(() async {
    final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
    final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    await File('../captures/$name.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
  });
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fonts='D:/ElevAge-Android-Validation-20261023-01/operation-20261025/flutter-sdk/bin/cache/artifacts/material_fonts';
    final roboto=FontLoader('Roboto');
    for(final name in ['roboto-regular.ttf','roboto-medium.ttf','roboto-bold.ttf']) {
      roboto.addFont(File('$fonts/$name').readAsBytes().then((bytes)=>ByteData.sublistView(bytes)));
    }
    await roboto.load();
    final icons=FontLoader('MaterialIcons')..addFont(File('$fonts/materialicons-regular.otf').readAsBytes().then((bytes)=>ByteData.sublistView(bytes)));
    await icons.load();
  });
  setUp(() {SharedPreferences.setMockInitialValues({});tzdata.initializeTimeZones();ApiService.token='synthetic-employee';globalToken=null;});
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();ApiService.farmerSession=false;});
  testWidgets('one operator login opens historical dashboard directly, without technical step',(tester) async {
    await tester.binding.setSurfaceSize(const Size(1280,800));
    final runtime=VisualRuntime();final key=GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key:key,child:testApp(FarmerAccessScreen(runtime:runtime))));
    await tester.pumpAndSettle();
    expect(find.text('Élev’Age — Espace éleveur'),findsOneWidget);
    expect(find.textContaining('HTTP'),findsNothing);expect(find.textContaining('PIN'),findsNothing);
    await capture(tester,key,'02-espace-eleveur');
    await tester.enterText(find.byType(TextField).at(0),'eleveur-fictif');
    await tester.enterText(find.byType(TextField).at(1),'1234');
    await tester.tap(find.text('Se connecter'));await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen),findsOneWidget);
    expect(find.text('Ouvrir mon espace en ligne'),findsNothing);
    expect(tester.takeException(),isNull);
    await capture(tester,key,'03-tableau-de-bord');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(runtime.signedIn,isTrue);
    // Returning from Wi-Fi settings preserves the open account.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen),findsOneWidget);
    expect(find.byType(LoginScreen),findsNothing);
    runtime.handleAppLifecycleState(AppLifecycleState.detached);
    expect(runtime.signedIn,isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });
  testWidgets('access and historical expense remain usable on narrow portrait screen',(tester) async {
    await tester.binding.setSurfaceSize(const Size(360,740));
    final runtime=VisualRuntime();final key=GlobalKey();
    await tester.pumpWidget(testApp(RepaintBoundary(key:key,child:FarmerAccessScreen(runtime:runtime))));
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    await capture(tester,key,'07-acces-portrait');
    final server=OnlineExpenseServer();
    await tester.pumpWidget(testApp(RepaintBoundary(key:key,child:AddDepenseScreen(apiService:server.api))));
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    await capture(tester,key,'08-depenses-portrait');
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
    server.api.close();runtime.dispose();
  });
  testWidgets('first access requires changing provisional code before a dashboard can open',(tester) async {
    final runtime=VisualRuntime()..initial=true;
    await tester.pumpWidget(testApp(FarmerAccessScreen(runtime:runtime)));
    await tester.enterText(find.byType(TextField).at(0),'eleveur-fictif');
    await tester.enterText(find.byType(TextField).at(1),'1234');
    await tester.tap(find.text('Se connecter'));await tester.pumpAndSettle();
    expect(find.text('Choisir votre code personnel'),findsOneWidget);
    expect(find.byType(DashboardScreen),findsNothing);
    await tester.enterText(find.byType(TextField).at(0),'4321');
    await tester.enterText(find.byType(TextField).at(1),'4321');
    await tester.tap(find.text('Enregistrer mon code'));await tester.pumpAndSettle();
    expect(find.textContaining('Code personnel modifié'),findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,isEmpty);
    runtime.initial=false;
    await tester.enterText(find.byType(TextField).at(1),'4321');
    await tester.tap(find.text('Se connecter'));await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('entry card remains on historical home and Agenda only disappears from vertical menu',(tester) async {
    final api=ApiService();final key=GlobalKey();
    await tester.binding.setSurfaceSize(const Size(1280,800));
    await tester.pumpWidget(testApp(RepaintBoundary(key:key,child:LoginScreen(apiService:api))));
    await tester.pumpAndSettle();expect(find.text('Espace éleveur'),findsOneWidget);
    expect(find.text('Accéder à mon compte'),findsOneWidget);
    await tester.runAsync(()=>precacheImage(const AssetImage('assets/images/elevage_logo.png'),tester.element(find.byType(LoginScreen))));
    await tester.pumpAndSettle();await capture(tester,key,'01-accueil');
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FarmNavigation(actions:{FarmDestination.agenda:(){},FarmDestination.dashboard:(){}}))));
    expect(find.text('Agenda'),findsNothing);expect(find.text('Tableau de bord'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);api.close();
  });
  testWidgets('expense fields and history filters keep shared visual language and all inputs',(tester) async {
    await tester.binding.setSurfaceSize(const Size(1280,800));final key=GlobalKey();
    final server=OnlineExpenseServer();
    await tester.pumpWidget(testApp(RepaintBoundary(key:key,child:AddDepenseScreen(apiService:server.api))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-amount')),findsOneWidget);
    expect(find.byKey(const Key('expense-note')),findsOneWidget);
    expect(find.byWidgetPredicate((w)=>w is DropdownButtonFormField),findsNWidgets(2));
    await capture(tester,key,'04-depenses');expect(tester.takeException(),isNull);
    final history=HistoryVisualApi();
    await tester.pumpWidget(testApp(RepaintBoundary(key:key,child:OperationHistoryScreen(api:history))));
    await tester.pumpAndSettle();expect(find.text('Type d’opération'),findsOneWidget);expect(find.text('État'),findsOneWidget);
    await capture(tester,key,'05-historique');expect(tester.takeException(),isNull);
    await tester.pumpWidget(testApp(RepaintBoundary(key:key,child:OwnerOperationHistoryScreen(api:HistoryVisualApiEmpty()))));
    await tester.pumpAndSettle();await capture(tester,key,'06-historique-proprietaire');expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);server.api.close();history.close();
  });
}
class HistoryVisualApiEmpty extends ApiService {
  @override Future<dynamic> get(String endpoint) async=>{'results':[],'next':null};
}
