import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/physical_stock_cards.dart';
import 'physical_stock_summary_test.dart' show feedData,vaccines;
import 'health_agenda_form_test.dart' show healthTask;
class StockApi extends ApiService {
  bool allowed=true,foreign=false,emitReadEvents=false;final events=ChangeNotifier();
  @override Listenable get sessionChanges=>events;final calls=<String>[];Map<String,dynamic>? patchData;
  @override Future<dynamic> get(String path)async {
    calls.add(path);
    if(path=='/me/capabilities/')return {'user':2,'exploitation':1,'role':'OWNER','membership':{'version':1},'permission_contract':{'version':2,'user':2,'exploitation':1,'role':'OWNER','rights_version':1,'permissions':[if(allowed)'stocks.read','agenda.read','agenda.plan','finance.read']}};
    if(path=='/feed-supplies/?presentation=1' && emitReadEvents)events.notifyListeners();
    if(path=='/feed-supplies/?presentation=1')return {...feedData(),'lots':[{'id':10,'espece_id':4}],'exploitation':foreign?9:1,'pending_operations':['uuid'],'review_operations':[]};
    if(path=='/vaccine-supplies/') {final d=vaccines();for(final v in d['vials'])v['usable_until']=DateTime.now().toUtc().add(const Duration(days:5)).toIso8601String();return d;}
    if(path=='/tasks/')return [healthTask()];
    if(path.contains('/history/'))return {'results':[{'kind':'ENTRY','quantity':'500','at':'2026-11-03','operator':2,'reason':'','lot':null}],'next_before':null};
    throw StateError(path);
  }
  @override Future<dynamic> patch(String path,Map<String,dynamic> data)async {patchData=data;return data;}
}
void main(){
  setUpAll(tzdata.initializeTimeZones);
  setUp((){ApiService.token='synthetic-stock';globalToken=null;SharedPreferences.setMockInitialValues({});});
  tearDown((){ApiService.token=null;});
  Widget app(StockApi api,{int? species,int? lot})=>MaterialApp(home:Scaffold(body:SingleChildScrollView(child:PhysicalStockCards(api:api,species:species,lot:lot))));
  testWidgets('phone cards show physical quantities confirmed pending estimate and retain explicit detail labels',(t)async{
    t.view.physicalSize=const Size(390,900);t.view.devicePixelRatio=1;addTearDown(t.view.reset);
    final api=StockApi();await t.pumpWidget(app(api));await t.pumpAndSettle();expect(find.text('Stock d’aliments'),findsOneWidget);expect(find.text('Stock de vaccins'),findsOneWidget);
    expect(find.text('710.125 kg confirmés'),findsOneWidget);expect(find.text('Estimé : 630.125 kg'),findsOneWidget);expect(find.textContaining('1 en attente'),findsOneWidget);expect(find.textContaining('XOF'),findsNothing);
    await t.tap(find.text('Stock d’aliments'));await t.pumpAndSettle();expect(find.textContaining('Partagé : 600.000 kg'),findsOneWidget);expect(find.text('Configurer le seuil'),findsOneWidget);
    await t.tap(find.text('Historique'));await t.pumpAndSettle();expect(find.text('Entrée · 500'),findsOneWidget);expect(t.takeException(),null);await t.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('selected lot shows shared plus reserved without another lot',(t)async{final api=StockApi();await t.pumpWidget(app(api,species:4,lot:10));await t.pumpAndSettle();expect(find.text('550.125 kg confirmés'),findsOneWidget);await t.pumpWidget(const SizedBox());api.close();});
  testWidgets('revoked permission and foreign farm do not disclose stock',(t)async{final api=StockApi()..allowed=false;await t.pumpWidget(app(api));await t.pumpAndSettle();expect(find.textContaining('Stocks indisponibles'),findsOneWidget);expect(api.calls.contains('/feed-supplies/?presentation=1'),false);await t.pumpWidget(const SizedBox());api.close();
    final other=StockApi()..foreign=true;await t.pumpWidget(app(other));await t.pumpAndSettle();expect(find.textContaining('Stocks indisponibles'),findsOneWidget);expect(find.text('710.125 kg confirmés'),findsNothing);await t.pumpWidget(const SizedBox());other.close();});
  testWidgets('large browser cards remain readable without overflow',(t)async{t.view.resetPhysicalSize();t.view.physicalSize=const Size(1400,1000);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);final api=StockApi();await t.pumpWidget(app(api));await t.pumpAndSettle();expect(find.text('Stock de vaccins'),findsOneWidget);expect(t.takeException(),null);await t.pumpWidget(const SizedBox());api.close();});
  testWidgets('threshold changes only product setting and dialog closes cleanly',(t)async{final api=StockApi();await t.pumpWidget(app(api));await t.pumpAndSettle();await t.tap(find.text('Stock d’aliments'));await t.pumpAndSettle();await t.tap(find.text('Configurer le seuil'));await t.pumpAndSettle();await t.enterText(find.byType(TextField),'75.125');await t.tap(find.text('Enregistrer'));await t.pumpAndSettle();expect(api.patchData,{'alert_threshold':'75.125','expected_threshold':'450.000'});expect(t.takeException(),null);await t.pumpWidget(const SizedBox());api.close();});
  testWidgets('lot-only filter resolves species before including shared stock',(t)async{final api=StockApi();await t.pumpWidget(app(api,lot:10));await t.pumpAndSettle();expect(find.text('550.125 kg confirmés'),findsOneWidget);await t.pumpWidget(const SizedBox());api.close();});
  testWidgets('open stock detail hides prior farm after a profile switch',(t)async{final api=StockApi();await t.pumpWidget(app(api));await t.pumpAndSettle();await t.tap(find.text('Stock d’aliments'));await t.pumpAndSettle();expect(find.textContaining('Partagé : 600.000 kg'),findsOneWidget);ApiService.token='other-synthetic-profile';await t.pump(const Duration(seconds:2));await t.pumpAndSettle();expect(find.textContaining('Partagé : 600.000 kg'),findsNothing);expect(find.textContaining('Profil ou droits modifiés'),findsOneWidget);await t.pumpWidget(const SizedBox());api.close();});

  testWidgets('ordinary cache refresh events do not create a stock request loop',(t)async{final api=StockApi()..emitReadEvents=true;await t.pumpWidget(app(api));await t.pumpAndSettle();expect(api.calls.where((p)=>p=='/feed-supplies/?presentation=1'),hasLength(1));expect(find.text('710.125 kg confirmés'),findsOneWidget);await t.pumpWidget(const SizedBox());api.close();});

  testWidgets('alert horizons start empty and only explicit settings persist per farm and user',(t)async{final api=StockApi();await t.pumpWidget(app(api));await t.pumpAndSettle();await t.ensureVisible(find.text('Configurer les alertes visuelles'));await t.tap(find.text('Configurer les alertes visuelles'));await t.pumpAndSettle();final fields=find.byType(TextField);expect(t.widget<TextField>(fields.at(0)).controller!.text,'');expect(t.widget<TextField>(fields.at(1)).controller!.text,'');await t.enterText(fields.at(0),'1');await t.enterText(fields.at(1),'7');await t.tap(find.text('Enregistrer'));await t.pumpAndSettle();final prefs=await SharedPreferences.getInstance();expect(prefs.getInt('stock-alerts:1:2:expiry'),1);expect(prefs.getInt('stock-alerts:1:2:upcoming'),7);expect(api.patchData,null);expect(t.takeException(),null);await t.pumpWidget(const SizedBox());api.close();});

}
