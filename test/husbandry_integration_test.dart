import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/husbandry/technical_screen.dart';
import 'package:app_elevage/husbandry/reproduction_screen.dart';
import 'package:app_elevage/husbandry/husbandry_entry.dart';
import 'package:app_elevage/widgets/dashboard_metric_grid.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'package:app_elevage/pisciculture/aquatic_navigation.dart';
import 'package:app_elevage/pisciculture/activity_selector.dart';
import 'package:app_elevage/pisciculture/aquatic_workspace.dart';
import 'aquatic_phase1_test.dart' show FakeAquatic, owner;
import 'package:app_elevage/theme/design_system_v2.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app_elevage/widgets/dashboard_kpi_card.dart';
import 'physical_stock_cards_test.dart' show StockApi;
import 'aquatic_phase3c_test.dart' show FakeCommerce;
import 'package:app_elevage/pisciculture/commerce_panel.dart';
import 'package:app_elevage/widgets/physical_stock_cards.dart';
import 'package:timezone/data/latest.dart' as tzdata;

const species={'id':1,'name':'Porc','family':'PIG','reproduction':true};
const lot={'id':2,'nom':'Truies','espece':1};
class HusbandryFake extends ApiService {
 final writes=<Map<String,dynamic>>[];
 bool fail=false;
 final parameters=<Map<String,dynamic>>[
  {'id':'p1','name':'Température ambiante','code':'temperature','kind':'NUMBER','unit':'°C','predefined':true},
  {'id':'p2','name':'Humidité relative','code':'humidity','kind':'NUMBER','unit':'%','predefined':true},
  {'id':'p3','name':'Ventilation','code':'ventilation','kind':'TEXT','unit':'','predefined':true},
  {'id':'p4','name':'État du sol','code':'housing','kind':'TEXT','unit':'','predefined':true},
  {'id':'p5','name':"Disponibilité de l’eau",'code':'water','kind':'BOOL','unit':'','predefined':true},
 ];
 final readings=<Map<String,dynamic>>[];
 @override Future<List<dynamic>> getActiveLots()async=>[lot];
 @override Future<dynamic> get(String endpoint)async {
  if(endpoint=='/lots/2/')return {'naissances_issues':[]};
  final p=Uri.parse(endpoint).path;
  if(p.endsWith('/capabilities/'))return {'read':true,'write':true,'species':[species]};
  List<dynamic> rows;
  if(p.endsWith('/parameters/')){rows=parameters;}
  else if(p.endsWith('/rules/')){rows=[];}
  else if(p.endsWith('/readings/')){rows=readings;}
  else if(p.endsWith('/cycles/')){rows=[{'id':'cycle1','name':'Cycle 2026','lot':2,'mode':'COLLECTIVE','female_count':3,'started_on':'2026-01-01','expected_on':null,'status':'OPEN','version':1,'identity':null,'totals':{'born_alive':0,'stillborn':0,'weaned':0,'preweaning_mortality':null}}];}
  else if(p.endsWith('/events/')||p.endsWith('/identities/')){rows=[];}
  else {throw StateError('Unexpected local request $endpoint');}
  return {'results':rows,'next_cursor':null};
 }
 @override Future<dynamic> post(String endpoint,dynamic body)async {
  final b=Map<String,dynamic>.from(body as Map);writes.add({'path':endpoint,...b});
  if(fail)throw const ApiConnectionException();
  if(endpoint.endsWith('/readings/')){readings.add({'id':'r1','occurred_at':b['occurred_at'],'note':b['note'],'values':(b['values'] as List).map((v)=>{...parameters.firstWhere((p)=>p['id']==v['parameter']),'parameter':v['parameter'],'value':v['value'],'alert':false}).toList()});}
  return {'id':'new','version':2};
 }
}
Widget app(Widget child,{GlobalKey? boundary})=>RepaintBoundary(key:boundary,child:MaterialApp(debugShowCheckedModeBanner:false,theme:designSystemV2(),locale:const Locale('fr'),supportedLocales:const [Locale('fr'),Locale('en')],localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],home:child));
Future<void> disposeApp(WidgetTester t,ApiService api)async{await t.pumpWidget(const SizedBox());api.close();}
Future<void> shot(WidgetTester t,GlobalKey key,String name)async{ await t.runAsync(() async {
 final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:1);
 final data=await image.toByteData(format:ui.ImageByteFormat.png);
 final dir=Directory('D:/ElevAge-Integration-Technique-Reproduction-20261119/qualification/screenshots')..createSync(recursive:true);
 File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());image.dispose();
});
}
void noop(bool value){}
void main(){
 setUpAll(()async{
  tzdata.initializeTimeZones();
  await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')..addFont(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((b)=>ByteData.sublistView(b)))).load();
 });
 setUp((){SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-local';globalToken=ApiService.token;});
 tearDown((){ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();});
 testWidgets('empty reading refused, zero transmitted and missing values omitted',(t)async{
  final api=HusbandryFake();await t.pumpWidget(app(TechnicalScreen(api:api,lot:lot,species:species)));await t.pumpAndSettle();
  final save=find.widgetWithText(FilledButton,'Enregistrer');await t.ensureVisible(save);await t.tap(save);await t.pumpAndSettle();
  expect(find.text('Renseignez au moins une valeur.'),findsOneWidget);expect(api.writes,isEmpty);
  await t.enterText(find.byType(TextField).first,'0');await t.ensureVisible(save);await t.tap(save);await t.pumpAndSettle();
  expect(api.writes.single['values'],[{'parameter':'p1','value':'0'}]);expect(find.text('Température ambiante : 0 °C'),findsOneWidget);await t.tap(find.text('Évolution'));await t.pumpAndSettle();expect(find.byWidgetPredicate((w)=>w is CustomPaint && w.painter is NumericEvolutionPainter),findsOneWidget);expect(t.takeException(),isNull);
  await disposeApp(t,api);
 });
 testWidgets('failed reading retains operation UUID on retry',(t)async{
  final api=HusbandryFake()..fail=true;await t.pumpWidget(app(TechnicalScreen(api:api,lot:lot,species:species)));await t.pumpAndSettle();
  await t.enterText(find.byType(TextField).first,'23,5');final save=find.widgetWithText(FilledButton,'Enregistrer');await t.ensureVisible(save);await t.tap(save);await t.pumpAndSettle();
  expect(find.text('Connexion indisponible. Réessayez.'),findsOneWidget);api.fail=false;await t.ensureVisible(save);await t.tap(save);await t.pumpAndSettle();
  expect(api.writes[0]['operation_uuid'],api.writes[1]['operation_uuid']);expect(api.writes.last['values'],[{'parameter':'p1','value':'23.5'}]);await disposeApp(t,api);
 });
 testWidgets('Production contextual reproduction keeps selected lot without another selector',(t)async{
  final api=HusbandryFake();await t.pumpWidget(app(HusbandryEntry(api:api,reproduction:true,initialSpeciesId:1,initialLotId:2)));await t.pumpAndSettle();
  expect(find.byType(ReproductionScreen),findsOneWidget);expect(find.text('Porc · Truies'),findsOneWidget);expect(find.text('Ouvrir'),findsNothing);expect(api.writes,isEmpty);expect(t.takeException(),isNull);await disposeApp(t,api);
 });
 test('Technique is placed exactly between Production and Mouvements',(){final i=farmHorizontalNavigationOrder.indexOf(FarmDestination.production);expect(farmHorizontalNavigationOrder[i+1],FarmDestination.technical);expect(farmHorizontalNavigationOrder[i+2],FarmDestination.movements);});
 for(final size in [const Size(1440,1000),const Size(800,1280),const Size(390,844)]){
  testWidgets('Technique and reproduction fit ${size.width}',(t)async{
   t.view.physicalSize=size;t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
   final api=HusbandryFake();final boundary=GlobalKey();await t.pumpWidget(app(TechnicalScreen(api:api,lot:lot,species:species),boundary:boundary));await t.pumpAndSettle();expect(t.takeException(),isNull);await shot(t,boundary,'technique-${size.width.toInt()}');
   await t.tap(find.text('Historique'));await t.pumpAndSettle();expect(find.text('Aucun relevé.'),findsOneWidget);expect(t.takeException(),isNull);
   await t.pumpWidget(app(ReproductionScreen(api:api,lot:lot,species:species),boundary:boundary));await t.pumpAndSettle();expect(t.takeException(),isNull);await shot(t,boundary,'reproduction-${size.width.toInt()}');
   await t.tap(find.text('Ajouter un événement'));await t.pumpAndSettle();expect(find.text('Saillie / Insémination'),findsWidgets);expect(t.takeException(),isNull);await shot(t,boundary,'reproduction-dialog-${size.width.toInt()}');await disposeApp(t,api);
  });
 }


 for(final kind in ['Mise bas','Sevrage']){
  testWidgets('$kind sends one event with no stock API call',(t)async{
   final api=HusbandryFake();await t.pumpWidget(app(ReproductionScreen(api:api,lot:lot,species:species)));await t.pumpAndSettle();await t.tap(find.text('Ajouter un événement'));await t.pumpAndSettle();
   await t.tap(find.byType(DropdownButtonFormField<String>).first);await t.pumpAndSettle();await t.tap(find.text(kind).last);await t.pumpAndSettle();
   final field=find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText==(kind=='Mise bas'?'Mort-nés':'Nombre sevré'));
   if(kind=='Mise bas'){expect(find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText=='Lot des nouveau-nés (si vivants)'),findsNothing);await t.enterText(field,'3');}else {final number=find.byType(TextField).first;await t.enterText(number,'8');}
   final save=find.widgetWithText(FilledButton,'Enregistrer');await t.ensureVisible(save);await t.tap(save);await t.pumpAndSettle();
   expect(api.writes.length,1);expect(api.writes.single['path'],'/elevage/v1/reproduction/events/');final data=api.writes.single['data'] as Map;
   if(kind=='Mise bas'){expect(data['born_alive'],0);expect(data['stillborn'],3);expect(data.containsKey('new_lot_name'),false);}else {expect(data,{'count':8});}
   expect(t.takeException(),isNull);await disposeApp(t,api);
  });
 }

 testWidgets('live birth reveals required new-lot fields only for a positive count',(t)async{
  final api=HusbandryFake();await t.pumpWidget(app(ReproductionScreen(api:api,lot:lot,species:species)));await t.pumpAndSettle();await t.tap(find.text('Ajouter un événement'));await t.pumpAndSettle();
  await t.tap(find.byType(DropdownButtonFormField<String>).first);await t.pumpAndSettle();await t.tap(find.text('Mise bas').last);await t.pumpAndSettle();
  final newborn=find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText=='Lot des nouveau-nés (si vivants)');expect(newborn,findsNothing);
  await t.enterText(find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText=='Nés vivants'),'5');await t.pumpAndSettle();expect(newborn,findsOneWidget);
  await t.enterText(newborn,'Porcelets recette');final save=find.widgetWithText(FilledButton,'Enregistrer');await t.ensureVisible(save);await t.tap(save);await t.pumpAndSettle();
  expect((api.writes.single['data'] as Map)['new_lot_name'],'Porcelets recette');expect((api.writes.single['data'] as Map)['born_alive'],5);expect(t.takeException(),isNull);await disposeApp(t,api);
 });

 testWidgets('Pisciculture payment card opens existing invoice and payment form',(t)async{
  final fake=FakeCommerce();await t.pumpWidget(app(Scaffold(body:SingleChildScrollView(child:CommercePanel(service:fake,owner:true,rights:const ['cash.create'],installations:const [],cohorts:const [],species:const [],initialSection:'payments')))));await t.pumpAndSettle();
  expect(find.text('FAC-2026-00123 · Client test'),findsOneWidget);expect(find.textContaining('Solde : 55.00'),findsOneWidget);expect(find.text('Paiement 2026-11-13 : 20.00'),findsOneWidget);
  await t.tap(find.text('Enregistrer un paiement'));await t.pumpAndSettle();expect(find.byType(CommerceEditor),findsOneWidget);expect(fake.writes,isEmpty);expect(t.takeException(),isNull);await t.pumpWidget(const SizedBox());fake.api.close();
 });
 testWidgets('desktop top bar keeps six destinations in one 64px row',(t)async{
  t.view.physicalSize=const Size(1440,1000);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final key=GlobalKey();await t.pumpWidget(app(Scaffold(appBar:FarmTopBar(actions:{for(final d in farmHorizontalNavigationOrder)d:(){}},session:owner(),connection:const SizedBox(width:64,child:Text('En ligne')),onRefresh:(){},onLogout:(){}),body:const ActivitySelector(aquatic:false,onSelect:noop)),boundary:key));await t.pumpAndSettle();
  expect(t.getSize(find.byType(AppBar)).height,64);final y=<double>[];
  for(final d in farmHorizontalNavigationOrder){final f=find.byKey(d==FarmDestination.production?const Key('topProductionTrackingButton'):ValueKey('navigation-${d.name}-horizontal'));expect(f,findsOneWidget);y.add(t.getCenter(f).dy);}
  expect(y.toSet().length,1);final a=t.getRect(find.byKey(const ValueKey('activity-terrestrial'))),b=t.getRect(find.byKey(const ValueKey('activity-aquatic')));expect(a.width,720);expect(b.width,720);expect(t.takeException(),isNull);await shot(t,key,'desktop-navigation-1440');
 });
 for(final size in [const Size(1440,1000),const Size(800,1280),const Size(390,844)]){
  testWidgets('all Pisciculture menus fit ${size.width} and navigation writes nothing',(t)async{
   t.view.physicalSize=size;t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
   final service=FakeAquatic(),key=GlobalKey<AquaticWorkspaceState>(),boundary=GlobalKey();
   await t.pumpWidget(app(Scaffold(body:AquaticWorkspace(key:key,service:service,capabilities:{'can_enable':true,'write':<String>[]})),boundary:boundary));await t.pumpAndSettle();
   for(final group in aquaticMenuGroups.entries.where((g)=>g.key!='purchases_hub')){key.currentState!.showPage(group.key);await t.pumpAndSettle();for(final item in group.value){expect(find.text(item.title),findsWidgets);}expect(t.takeException(),isNull);if(group.key=='production_hub'||group.key=='technical_hub')await shot(t,boundary,'pisciculture-${group.key}-${size.width.toInt()}');}
   expect(service.writes,isEmpty);await t.pumpWidget(const SizedBox());
  });
 }

 testWidgets('Gestion has three working entries and retains existing stock indicators',(t)async{
  t.view.physicalSize=const Size(800,1280);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final api=StockApi();bool opened=false;final key=GlobalKey();
  await t.pumpWidget(app(Scaffold(body:SingleChildScrollView(child:DashboardMetricGrid(children:[for(var i=0;i<4;i++)DashboardKpiCard(title:['Stock total',"Chiffre d’affaires",'Dépenses','Solde clients'][i],icon:[Icons.inventory_2_outlined,Icons.trending_up,Icons.account_balance_wallet_outlined,Icons.credit_card_outlined][i],color:V2Colors.green,content:const Text('0')),PhysicalStockCards(api:api,compact:true,onReproduction:()=>opened=true)]))),boundary:key));await t.pumpAndSettle();
  expect(find.text('Gestion'),findsOneWidget);expect(find.byTooltip('Alimentation'),findsOneWidget);expect(find.byTooltip('Vaccination'),findsOneWidget);expect(find.byTooltip('Reproduction'),findsOneWidget);expect(t.takeException(),isNull);await shot(t,key,'gestion-tablette-800');
  await t.tap(find.byTooltip('Reproduction'));expect(opened,true);opened=false;
  await t.tap(find.text('Gestion'));await t.pumpAndSettle();expect(find.text('Suivi des aliments'),findsOneWidget);expect(find.text('Suivi des vaccins'),findsOneWidget);expect(find.text('Suivi des reproductions'),findsOneWidget);
  await t.tap(find.byKey(const Key('management-reproduction')));expect(opened,true);expect(t.takeException(),isNull);await disposeApp(t,api);
 });
 testWidgets('portrait management card centered and exactly equal to other cards',(t)async{
  t.view.physicalSize=const Size(800,1280);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(app(Scaffold(body:DashboardMetricGrid(children:List.generate(5,(i)=>Card(key:ValueKey('metric-$i'),child:Text('$i')))))));await t.pumpAndSettle();
  final a=t.getRect(find.byKey(const ValueKey('metric-0'))),b=t.getRect(find.byKey(const ValueKey('metric-4')));expect(b.width,closeTo(a.width,0.001));expect(b.height,closeTo(a.height,0.001));expect(b.center.dx,400);expect(t.takeException(),isNull);
 });
}
