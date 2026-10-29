import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/screens/client_detail_screen.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/app_settings.dart';

class CashApi extends ApiService {
  int calls=0;Completer<bool>? hold;
  @override
  Future<Map<String,dynamic>> getClientBalance(int id) async=>{'balance':20};
  @override
  Future<List<dynamic>> getClientVentes(int id) async=>[{'id':51,'vente_id':51,'montant_total':20,
    'montant_paye':0,'reste':20,'status':'IMPAYE','quantite':1}];
  @override
  Future<dynamic> get(String path) async=>path=='/me/capabilities/'?{
    'user':2,'exploitation':1,'role':'OPERATEUR','offline_policy_enabled':false,
    'membership':{'version':1},'permission_contract':{'version':1,'user':2,'exploitation':1,
      'role':'OPERATEUR','rights_version':1,'permissions':['cash.create','finance.read']}}:[];
  @override
  Future<bool> createPayment(int clientId,int venteId,double amount,{String? mode}) async {
    calls++;return hold!.future;
  }
}
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});AppSettings.instance.languageCode='fr';ApiService.token='synthetic';});
  tearDown(() {ApiService.token=null;});
  testWidgets('failed first payment restores the same dialog and blocks double submission while waiting',(tester) async {
    tester.view.physicalSize=const Size(1280,1000);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
    final api=CashApi();addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home:ClientDetailScreen(apiService:api,clientId:11,nom:'Synthetic',telephone:'')));
    await tester.pumpAndSettle();
    final pay=find.widgetWithText(ElevatedButton,'Pay');
    await tester.ensureVisible(pay);await tester.tap(pay);await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'5');
    api.hold=Completer<bool>();
    await tester.tap(find.widgetWithText(ElevatedButton,'Confirm'));await tester.pump();
    expect(api.calls,1);expect(find.byType(CircularProgressIndicator),findsOneWidget);
    final pending=tester.widget<ElevatedButton>(find.byType(ElevatedButton).last);expect(pending.onPressed,isNull);
    api.hold!.completeError(StateError('Synthetic reference refresh failure'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog),findsOneWidget);
    expect(find.byType(CircularProgressIndicator),findsNothing);
    expect(find.textContaining('Paiement non enregistré'),findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton,'Confirm')).onPressed,isNotNull);
    expect(api.calls,1);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });
}
