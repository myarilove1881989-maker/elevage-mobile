import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/services/farm_session.dart';
import 'package:app_elevage/offline/sync_state.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'package:app_elevage/widgets/lot_lifecycle_actions.dart';
import 'package:app_elevage/screens/lot_list_screen.dart';

FarmSession session({bool operator=false}){
 final role=operator?'OPERATEUR':'OWNER';
 final codes=operator?['finance.read','history.read','weights.create']:PermissionContract.catalogue.where((x)=>x!='agenda.progress').toList();
 final rights=PermissionContract.decode({'version':2,'rights_version':1,'user':1,'exploitation':7,'role':role,'permissions':codes},userId:1,farmId:7,role:role,rightsVersion:1,allowHttpV2:true);
 return FarmSession(userId:1,farmId:7,role:role,origin:SessionOrigin.personalHttp,network:NetworkState.available,sync:const SyncSummary(),permissions:rights);
}
class ListApi extends ApiService{
 @override Future<List<dynamic>> getLots()async=>[{'id':1,'nom':'Actif','stock':20},{'id':2,'nom':'Ancien cycle','stock':5,'date_fin':'2026-01-01'}];
 @override Future<dynamic> get(String path)async=>throw StateError('No mutation access in this synthetic read fixture');
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(()async{final loader=FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));await loader.load();});
 setUp(()=>ApiService.token='synthetic-owner');tearDown(()=>ApiService.token=null);
 for(final width in [360.0,800.0,1366.0,1920.0]){
  testWidgets('compact business bar and complete drawer reachable at width $width',(tester)async{
   await tester.binding.setSurfaceSize(Size(width,900));var exits=0;
   final actions={for(final d in farmNavigationOrder)d:(){if(d==FarmDestination.logout)exits++;}};
   await tester.pumpWidget(MaterialApp(locale:const Locale('fr'),supportedLocales:const [Locale('fr'),Locale('en')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],home:Scaffold(body:Column(children:[
    SizedBox(height:52,child:FarmNavigation(key:const Key('horizontal'),horizontal:true,session:session(),actions:actions)),
    Expanded(child:SingleChildScrollView(child:FarmNavigation(key:const Key('vertical'),session:session(),actions:actions)))
   ]))));await tester.pumpAndSettle();
   final horizontal=find.byKey(const Key('horizontal'));final vertical=find.byKey(const Key('vertical'));
   final expected=['Lots','Achats','Dépenses','Production','Mouvements','Facturation','Historique','Agenda','Paramètres','Tuto','Quitter'];
   expect(tester.widgetList<ListTile>(find.descendant(of:vertical,matching:find.byType(ListTile))).map((x)=>(x.title as Text).data),expected);
   expect(tester.widgetList<Text>(find.descendant(of:horizontal,matching:find.byType(Text))).map((x)=>x.data),expected.take(8));
   final verticalIcons=tester.widgetList<Icon>(find.descendant(of:vertical,matching:find.byType(Icon))).map((x)=>x.icon).toList();
   final horizontalIcons=tester.widgetList<Icon>(find.descendant(of:horizontal,matching:find.byType(Icon))).map((x)=>x.icon).toList();expect(horizontalIcons,verticalIcons.take(8));
   expect(find.text('Tableau de bord'),findsNothing);expect(find.text('Gestion des utilisateurs'),findsNothing);
   final horizontalScroll=tester.widget<SingleChildScrollView>(find.descendant(of:horizontal,matching:find.byType(SingleChildScrollView)));
   if(width>=1366)expect(horizontalScroll.controller!.position.maxScrollExtent,0);
   expect(tester.getSize(find.descendant(of:horizontal,matching:find.byType(LayoutBuilder)).first).height,52);
   await tester.dragUntilVisible(find.byKey(const ValueKey('navigation-agenda-horizontal')),find.descendant(of:horizontal,matching:find.byType(SingleChildScrollView)),const Offset(-300,0));
   final agendaRect=tester.getRect(find.byKey(const ValueKey('navigation-agenda-horizontal')));
   expect(agendaRect.right,lessThanOrEqualTo(width));
   await tester.tap(find.descendant(of:vertical,matching:find.text('Quitter')));expect(exits,1);
   expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());await tester.binding.setSurfaceSize(null);
  });
 }
 testWidgets('operator sees only accessible menu entries',(tester)async{
  await tester.pumpWidget(MaterialApp(locale:const Locale('fr'),supportedLocales:const [Locale('fr'),Locale('en')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],home:Scaffold(body:FarmNavigation(session:session(operator:true),actions:{for(final d in farmNavigationOrder)d:(){}}))));
  expect(find.text('Achats'),findsNothing);expect(find.text('Dépenses'),findsNothing);expect(find.text('Mouvements'),findsNothing);expect(find.text('Agenda'),findsNothing);
  expect(find.text('Facturation'),findsOneWidget);expect(find.text('Paramètres'),findsOneWidget);
 });
 testWidgets('close requires confirmation, permits empty reason and refreshes into reopen',(tester)async{
  var writes=0,refreshes=0;Map<String,dynamic>? payload;final pending=Completer<http.Response>();
  final lot=<String,dynamic>{'id':8,'nom':'Cycle'};
  final api=ApiService(client:MockClient((request)async{
   if(request.method=='GET')return http.Response(jsonEncode({'id':8,'farm':7,'revision':4,'closed':false,'stock_animaux':20,'stock_oeufs':0,'creances':'150','date_minimum':'2026-01-01','message':'Historique et créances conservés.'}),200);
   writes++;payload=jsonDecode(request.body) as Map<String,dynamic>;return pending.future;
  }));
  await tester.pumpWidget(MaterialApp(locale:const Locale('fr'),supportedLocales:const [Locale('fr'),Locale('en')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],home:Scaffold(body:StatefulBuilder(builder:(context,setState)=>LotLifecycleActions(api:api,lot:lot,access:Future.value(true),onChanged:(){refreshes++;setState(()=>lot['date_fin']='2026-11-02');})))));
  await tester.pumpAndSettle();await tester.tap(find.text('Clôturer le lot'));await tester.pumpAndSettle();
  expect(writes,0);expect(find.textContaining('aucune vente'),findsOneWidget);
  await tester.tap(find.text('Annuler'));await tester.pumpAndSettle();expect(writes,0);
  await tester.tap(find.text('Clôturer le lot'));await tester.pumpAndSettle();await tester.tap(find.text('Confirmer la clôture'));await tester.pump();
  expect(writes,1);expect(payload!['reason'],'');expect(payload!['confirm'],true);expect(payload!['farm'],7);expect(payload!['expected_revision'],4);
  expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
  pending.complete(http.Response('{}',200));await tester.pumpAndSettle();expect(refreshes,1);expect(find.text('Réouvrir le lot'),findsOneWidget);
  await tester.pumpWidget(const SizedBox());api.close();
 });
 testWidgets('closed lots remain available through their own filter',(tester)async{
  final api=ListApi();await tester.pumpWidget(MaterialApp(locale:const Locale('fr'),supportedLocales:const [Locale('fr'),Locale('en')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],home:LotListScreen(apiService:api)));await tester.pumpAndSettle();
  expect(find.text('Actif'),findsOneWidget);expect(find.text('Ancien cycle'),findsNothing);
  await tester.tap(find.text('Lots clôturés'));await tester.pumpAndSettle();expect(find.text('Ancien cycle'),findsOneWidget);expect(find.text('Actif'),findsNothing);
  await tester.pumpWidget(const SizedBox());api.close();
 });
}
