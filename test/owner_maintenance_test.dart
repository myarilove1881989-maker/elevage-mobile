import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/widgets/owner_maintenance_actions.dart';
import 'package:app_elevage/widgets/terrain_entry_gate.dart';

void main(){
  setUp(()=>ApiService.token='synthetic-owner');
  tearDown(()=>ApiService.token=null);
  test('HTTP owner can write without a primary device; operator keeps its constraint',() async {
    for(final role in ['OWNER','OPERATEUR']){
      final api=ApiService(client:MockClient((request) async {
        expect(request.headers['Accept'],contains('elevage-contract=2'));
        return http.Response(jsonEncode({'user':1,'exploitation':7,'role':role,'membership':{'version':3},
          'offline_policy_enabled':true,'permission_contract':{'version':2,'user':1,'exploitation':7,'role':role,
          'rights_version':3,'permissions':['finance.read','weights.create',if(role=='OWNER')'lots.create']}}),200);
      }));
      final access=await TerrainEntryAccess.read(api,{'weights.create'});
      expect(access.tabletRequired,role=='OPERATEUR');
      expect(access.message==null,role=='OWNER');api.close();
    }
  });
  Future<void> mount(WidgetTester tester,ApiService api) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OwnerMaintenanceActions(
      api:api,kind:'lots',id:8,label:'le lot',access:Future.value(true)))));
    await tester.pumpAndSettle();
  }
  Map<String,dynamic> schema()=>{'farm':7,'revision':9,'fields':[{'name':'nom','label':'Nom','type':'text','value':'Lot initial'}],
    'consequences':'Les données associées seront supprimées. Les paiements sont protégés.'};
  testWidgets('sensitive delete requires confirmation and sends exactly one bound request',(tester) async {
    var writes=0;var payload=<String,dynamic>{};final result=Completer<http.Response>();
    final api=ApiService(client:MockClient((request)async {
      if(request.method=='GET')return http.Response(jsonEncode(schema()),200);
      writes++;payload=jsonDecode(request.body) as Map<String,dynamic>;return result.future;
    }));
    await mount(tester,api);
    await tester.tap(find.byKey(const ValueKey('owner-delete-lots-8')));await tester.pumpAndSettle();
    expect(find.textContaining('paiements sont protégés'),findsOneWidget);expect(writes,0);
    await tester.tap(find.text('Annuler'));await tester.pumpAndSettle();expect(writes,0);
    await tester.tap(find.byKey(const ValueKey('owner-delete-lots-8')));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField),'Lot créé par erreur');
    await tester.tap(find.text('Confirmer la suppression'));await tester.pump();
    expect(writes,1);expect(payload,containsPair('confirm',true));expect(payload['farm'],7);expect(payload['expected_revision'],9);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    result.complete(http.Response('{}',200));await tester.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('refused update preserves the draft and displays the server reason',(tester) async {
    final api=ApiService(client:MockClient((request)async=>request.method=='GET'
      ?http.Response(jsonEncode(schema()),200):http.Response(jsonEncode({'error':'Vente déjà payée, correction refusée'}),400)));
    await mount(tester,api);await tester.tap(find.byKey(const ValueKey('owner-edit-lots-8')));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0),'Nom corrigé');
    await tester.enterText(find.byType(TextFormField).at(1),'Correction autorisée');
    await tester.tap(find.text('Enregistrer'));await tester.pumpAndSettle();
    expect(find.text('Nom corrigé'),findsOneWidget);expect(find.textContaining('Vente déjà payée'),findsOneWidget);
    expect(find.byType(AlertDialog),findsOneWidget);await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('session change prevents submission of an old dialog',(tester) async {
    var writes=0;
    final api=ApiService(client:MockClient((request)async{if(request.method!='GET')writes++;return http.Response(jsonEncode(schema()),200);}));
    await mount(tester,api);await tester.tap(find.byKey(const ValueKey('owner-edit-lots-8')));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1),'Correction autorisée');ApiService.token='other-synthetic-user';
    await tester.tap(find.text('Enregistrer'));await tester.pumpAndSettle();expect(writes,0);
    expect(find.textContaining('La session a changé'),findsOneWidget);await tester.pumpWidget(const SizedBox());api.close();
  });
}
