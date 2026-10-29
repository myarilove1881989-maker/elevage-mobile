import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/terrain_entry_gate.dart';
import 'package:app_elevage/screens/add_achat_screen.dart';
import 'production_tracking_test.dart' show testApp;
import 'terrain_entry_routing_test.dart' show RoutingApi;

void main() {
  testWidgets('owner keeps historical purchase form without save or automatic writes', (tester) async {
    final api=RoutingApi()..policy=false..role='OWNER'..rights=[];
    await tester.pumpWidget(testApp(AddAchatScreen(apiService:api)));
    await tester.pumpAndSettle();
    expect(find.byType(Form),findsOneWidget);
    expect(find.byType(TextFormField),findsWidgets);
    expect(find.byType(ElevatedButton),findsNothing);
    expect(api.reads,greaterThan(0));expect(api.writes,0);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  for(final role in ['OWNER','OPERATEUR','DENIED','UNAVAILABLE']) {
    testWidgets('commands follow verified rights for $role', (tester) async {
      final api=RoutingApi()..policy=false;
      if(role=='OWNER') {api.role='OWNER';api.rights=[];}
      if(role=='DENIED') api.rights=[];
      if(role=='UNAVAILABLE') api.unavailable=true;
      await tester.pumpWidget(testApp(Scaffold(body:BusinessCommand(api:api,actions:const {'purchases.create'},child:const Text('COMMAND_VISIBLE')))));
      await tester.pumpAndSettle();
      expect(find.text('COMMAND_VISIBLE'),role=='OPERATEUR'?findsOneWidget:findsNothing);
      expect(api.writes,0);await tester.pumpWidget(const SizedBox());api.close();
    });
  }
  testWidgets('access failure can retry without losing historical entry', (tester) async {
    final api=RoutingApi()..policy=false..unavailable=true;
    await tester.pumpWidget(testApp(AddAchatScreen(apiService:api)));await tester.pumpAndSettle();
    expect(find.text('Réessayer'),findsOneWidget);expect(api.writes,0);
    api.unavailable=false;
    await tester.tap(find.text('Réessayer'));await tester.pumpAndSettle();
    expect(find.byType(Form),findsOneWidget);expect(api.writes,0);
    await tester.pumpWidget(const SizedBox());api.close();
  });
}
