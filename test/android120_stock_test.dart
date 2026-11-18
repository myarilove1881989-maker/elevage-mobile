import 'dart:async';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/farm_session.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/offline/sync_state.dart';
import 'package:app_elevage/widgets/android_online_stock_cards.dart';
import 'package:app_elevage/widgets/farm_login_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'physical_stock_summary_test.dart' show feedData,vaccines;

class Stocks extends ApiService{
  int farm=1; Completer<void>? gate;
  final reads=<String>[];
  @override Future<dynamic> get(String path)async{
    reads.add(path);if(gate!=null)await gate!.future;
    return {...(path.startsWith('/feed')?feedData():vaccines()),'exploitation':farm};
  }
}
FarmSession session()=>FarmSession(userId:1,farmId:1,role:'OWNER',
  permissions:PermissionContract.decode({'version':2,'user':1,'exploitation':1,'role':'OWNER','rights_version':1,'permissions':['finance.read','stocks.read']},userId:1,farmId:1,role:'OWNER',rightsVersion:1,allowHttpV2:true),
  origin:SessionOrigin.personalHttp,network:NetworkState.available,sync:const SyncSummary());
Widget app(Stocks api)=>MaterialApp(home:Scaffold(body:AndroidOnlineStockCards(api:api,session:session(),species:4,lot:10,revision:1)));
void main(){
 setUpAll(tzdata.initializeTimeZones);
 setUp(()=>ApiService.token='synthetic-stock');
 tearDown(()=>ApiService.token=null);
 testWidgets('stock uses the server scope and only the two read endpoints',(tester)async{
   final api=Stocks();await tester.pumpWidget(app(api));await tester.pumpAndSettle();
   expect(find.textContaining('550.125 kg'),findsOneWidget);
   expect(api.reads,['/feed-supplies/?presentation=1','/vaccine-supplies/']);
   expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());api.close();
 });
 testWidgets('foreign farm never appears as zero stock',(tester)async{
   final api=Stocks()..farm=2;await tester.pumpWidget(app(api));await tester.pumpAndSettle();
   expect(find.textContaining('Stocks physiques indisponibles'),findsOneWidget);
   expect(find.textContaining('550.125'),findsNothing);await tester.pumpWidget(const SizedBox());api.close();
 });
 testWidgets('late response cannot expose the previous account stock',(tester)async{
   final api=Stocks()..gate=Completer<void>();await tester.pumpWidget(app(api));
   ApiService.token='different-account';api.gate!.complete();await tester.pumpAndSettle();
   expect(find.textContaining('550.125'),findsNothing);await tester.pumpWidget(const SizedBox());api.close();
 });
 testWidgets('animal movement advances and stops when the connection ends',(tester)async{
   Widget scene(bool active)=>MaterialApp(home:FarmLoginLoading(active:active,chooseAnimal:()=>FarmAnimal.hen));
   await tester.pumpWidget(scene(true));await tester.pump(const Duration(milliseconds:301));await tester.pump(const Duration(milliseconds:100));
   final phase=tester.widget<FarmAnimalFrame>(find.byType(FarmAnimalFrame)).phase;
   await tester.pump(const Duration(milliseconds:150));
   expect(tester.widget<FarmAnimalFrame>(find.byType(FarmAnimalFrame)).phase,isNot(phase));
   await tester.pumpWidget(scene(false));await tester.pumpAndSettle();
   expect(find.byType(FarmAnimalFrame),findsNothing);expect(tester.hasRunningAnimations,isFalse);
 });
}
