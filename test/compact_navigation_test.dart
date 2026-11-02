import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/screens/dashboard_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/permission_contract.dart';
import 'package:app_elevage/widgets/farm_navigation.dart';
import 'package:app_elevage/widgets/connection_indicator.dart';
import 'production_tracking_test.dart' show ProductionTrackingApiFake,testApp;

class CompactOwnerApi extends ProductionTrackingApiFake {
 @override Future<dynamic> get(String endpoint) async {
  if(endpoint!='/me/capabilities/')throw StateError('Synthetic fixture only');
  return {'user':1,'exploitation':1,'role':'OWNER','offline_policy_enabled':false,'membership':{'version':1},
   'permission_contract':{'version':2,'user':1,'exploitation':1,'role':'OWNER','rights_version':1,
     'permissions':PermissionContract.catalogue.where((x)=>x!='agenda.progress').toList()}};
 }
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(()async{
  final font=FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));await font.load();
  final sdk=Platform.environment['FLUTTER_ROOT'];
  final icons=FontLoader('MaterialIcons')..addFont(File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((bytes)=>ByteData.sublistView(bytes)));await icons.load();
 });
 setUp((){SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-owner';globalToken=ApiService.token;});
 tearDown((){ApiService.token=null;globalToken=null;});
 for(final width in [360.0,800.0,1366.0,1920.0]){
  testWidgets('dashboard compact navigation and toolbar at $width',(tester)async{
   tester.view.physicalSize=Size(width,768);tester.view.devicePixelRatio=1;
   addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
   final api=CompactOwnerApi();final boundaryKey=GlobalKey();
   await tester.pumpWidget(testApp(RepaintBoundary(key:boundaryKey,child:DashboardScreen(apiService:api))));await tester.pumpAndSettle();
   final horizontal=find.byWidgetPredicate((w)=>w is FarmNavigation && w.horizontal);
   final scroll=find.descendant(of:horizontal,matching:find.byType(SingleChildScrollView));
   final controller=tester.widget<SingleChildScrollView>(scroll).controller!;
   expect(tester.getSize(horizontal).height,52);
   expect(tester.widgetList<Text>(find.descendant(of:horizontal,matching:find.byType(Text))).map((w)=>w.data),
    ['Lots','Achats','Dépenses','Production','Mouvements','Facturation','Historique','Agenda']);
   if(width>=1366){
    expect(controller.position.maxScrollExtent,0);
    final lots=tester.getRect(find.byKey(const ValueKey('navigation-lots-horizontal')));
    final agenda=tester.getRect(find.byKey(const ValueKey('navigation-agenda-horizontal')));
    expect(lots.left,closeTo(width-agenda.right,1));
   }
   final wifi=tester.getRect(find.byType(ConnectionIndicator));
   final refresh=tester.getRect(find.byTooltip('Actualiser'));
   final logout=tester.getRect(find.byKey(const Key('topLogoutButton')));
   expect(wifi.right,lessThanOrEqualTo(refresh.left));expect(refresh.right,lessThanOrEqualTo(logout.left));
   expect(logout.right,lessThanOrEqualTo(width));expect(find.text('Élev’Age'),findsOneWidget);
   expect(tester.takeException(),isNull);
   final folder=Platform.environment['ELEVAGE_NAV_PROOF_DIR'];
   if(folder!=null)await tester.runAsync(()async{
    final boundary=boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image=await boundary.toImage(pixelRatio:1);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    await File('$folder/navigation-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());image.dispose();
   });
   await tester.pumpWidget(const SizedBox());api.close();
  });
 }
}
