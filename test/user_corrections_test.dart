import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/token_service.dart';
import 'package:app_elevage/services/app_settings.dart';
import 'package:app_elevage/services/money_input.dart';
import 'package:app_elevage/services/payment_reminder.dart';
import 'package:app_elevage/services/expired_draft.dart';
import 'package:app_elevage/screens/health_agenda_screen.dart';
import 'package:app_elevage/widgets/v2_components.dart';
import 'health_agenda_form_test.dart' show HealthAgendaApi,revealHealth;
import 'production_tracking_test.dart' show testApp;
import 'sale_product_test.dart' show SaleApiFake,saleApp;

class MemoryTokens implements TokenStore,RefreshTokenStore {
  String? access,refresh;
  @override Future<void> saveToken(String value)async{access=value;}
  @override Future<String?> getToken()async=>access;
  @override Future<void> clearToken()async{access=null;refresh=null;}
  @override Future<void> saveRefreshToken(String value)async{refresh=value;}
  @override Future<String?> getRefreshToken()async=>refresh;
}
class NewResponsibleApi extends HealthAgendaApi {
  @override Future<dynamic> get(String path)async=>{'/tasks/health-responsibles/','/tasks/health-assignees/'}.contains(path)?[]:super.get(path);
  @override Future<dynamic> post(String path,Map<String,dynamic> data)async {
    if(path=='/tasks/health-responsibles/'){requests.add({...data});return {'id':9,'name':data['name'],'profession':data['profession']};}
    return super.post(path,data);
  }
}
class RepeatMovementApi extends SaleApiFake {
  int posts=0;bool fail=false;String? cost='1200.00';
  @override Future<Map<String,dynamic>> getLotDetail(int id)async=>{'prix_unitaire_origine':cost};
  @override Future<bool> createMouvement({required int lotId,required String type,required int quantite,required double prixUnitaire,required DateTime date,int? clientId})async {
    if(fail)throw const ApiConnectionException();posts++;animalPrice=prixUnitaire;return true;
  }
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp((){SharedPreferences.setMockInitialValues({});ApiService.token=null;globalToken=null;AppSettings.instance.languageCode='fr';AppSettings.instance.currencyCode='XAF';});
  test('expired draft is ephemeral and only recoverable by the same account',(){
    ExpiredDraft.remember('owner-a','Montant : 123,45');
    expect(ExpiredDraft.take('owner-b'),isNull);
    expect(ExpiredDraft.take('owner-a'),'Montant : 123,45');
    expect(ExpiredDraft.take('owner-a'),isNull);
  });
  test('French grouping and canonical exact decimal preserve fraction and caret',(){
    final f=MoneyInputFormatter();final next=f.formatEditUpdate(TextEditingValue.empty,const TextEditingValue(text:'170000,50',selection:TextSelection.collapsed(offset:9)));
    expect(next.text,'170 000,50');expect(next.selection.extentOffset,next.text.length);
    expect(MoneyInput.canonical(next.text),'170000.50');
    final invalid=f.formatEditUpdate(next,const TextEditingValue(text:'170000,501',selection:TextSelection.collapsed(offset:10)));
    expect(MoneyInput.canonical(invalid.text),'170000.501');
    expect(MoneyInput.canonical('1 234 567,01'),'1234567.01');
    final middle=f.formatEditUpdate(next,const TextEditingValue(text:'1710 000,50',selection:TextSelection.collapsed(offset:3)));
    expect(MoneyInput.canonical(middle.text),'1710000.50');expect(middle.selection.extentOffset,4);
  });
  test('English formatting uses comma groups and dot decimal without rounding',(){
    AppSettings.instance.languageCode='en';final f=MoneyInputFormatter();
    final v=f.formatEditUpdate(TextEditingValue.empty,const TextEditingValue(text:'170000.50',selection:TextSelection.collapsed(offset:9)));
    expect(v.text,'170,000.50');expect(MoneyInput.canonical(v.text),'170000.50');
  });
  test('reminder uses configured currency and refuses fully paid invoice',(){
    AppSettings.instance.currencyCode='EUR';
    final value=paymentReminder(customer:'Client Démo',description:'4 animaux',total:170000.50,paid:50000,remaining:120000.50,farm:'Ferme Démo');
    expect(value,contains('€'));expect(value,contains('120'));expect(value,contains('Ferme Démo'));expect(value,isNot(contains('FCFA')));
    expect(()=>paymentReminder(customer:'A',description:'Achat',total:10,paid:10,remaining:0,farm:'F'),throwsArgumentError);
  });
  test('simultaneous access expiry performs one refresh and keeps presentation identity',()async{
    final store=MemoryTokens();int refreshes=0;final api=ApiService(tokenStore:store,client:MockClient((request)async{
      if(request.url.path.endsWith('/token/'))return http.Response(jsonEncode({'access':'old','refresh':'refresh-demo'}),200);
      if(request.url.path.endsWith('/token/refresh/')){refreshes++;await Future<void>.delayed(const Duration(milliseconds:20));return http.Response(jsonEncode({'access':'new'}),200);}
      return request.headers['Authorization']=='Bearer new'?http.Response('[]',200):http.Response('{}',401);
    }));
    await api.login('demo','synthetic');final identity=ApiService.sessionIdentity;
    await Future.wait(List.generate(3,(_)=>api.getLots()));
    expect(refreshes,1);expect(ApiService.token,'new');expect(ApiService.sessionIdentity,identity);expect(store.refresh,'refresh-demo');
    await api.logout();api.close();
  });
  test('revoked refresh expires once',()async{
    final store=MemoryTokens()..access='expired'..refresh='revoked';
    final api=ApiService(tokenStore:store,client:MockClient((r)async=>http.Response('{}',r.url.path.endsWith('/token/refresh/')?403:401)));
    await api.loadToken();final before=ApiService.sessionExpired.value;
    await Future.wait(List.generate(3,(_)=>api.getLots().then<void>((_)=>fail('must reject'),onError:(Object e)=>expect(e,isA<ApiHttpException>()))));
    expect(ApiService.sessionExpired.value,before+1);expect(store.refresh,isNull);api.close();
  });
  test('late 401 cannot replay an old operation under another account',()async{
    final response=Completer<http.Response>();int writes=0;
    final store=MemoryTokens()..access='old-account'..refresh='old-refresh';
    final api=ApiService(tokenStore:store,client:MockClient((r)async {writes++;return response.future;}));
    await api.loadToken();final pending=api.post('/mouvements/',{'quantite':1});
    await Future<void>.delayed(Duration.zero);
    await api.usePersonalOnlineSession('other-account','other');
    response.complete(http.Response('{}',401));
    await expectLater(pending,throwsA(isA<ApiHttpException>()));
    expect(writes,1);expect(ApiService.token,'other-account');
    await api.logout();api.close();
  });
  test('network failure during refresh preserves credentials',()async{
    final store=MemoryTokens()..access='expired'..refresh='valid-refresh';
    final api=ApiService(tokenStore:store,client:MockClient((r)async {
      if(r.url.path.endsWith('/token/refresh/'))throw http.ClientException('synthetic network failure');
      return http.Response('{}',401);
    }));
    await api.loadToken();final before=ApiService.sessionExpired.value;
    await expectLater(api.getLots(),throwsA(isA<ApiConnectionException>()));
    expect(ApiService.token,'expired');expect(store.refresh,'valid-refresh');expect(ApiService.sessionExpired.value,before);
    await api.logout();api.close();
  });
  testWidgets('new external health responsible is selected immediately and plan has explicit dates',(tester)async{
    ApiService.token='health-demo';final api=NewResponsibleApi();
    await tester.pumpWidget(testApp(HealthPlanForm(api:api,lotId:10)));await tester.pumpAndSettle();
    await revealHealth(tester,'health-add-responsible');await tester.tap(find.byKey(const Key('health-add-responsible')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('responsible-name')),'Dr Démo');await tester.tap(find.byKey(const Key('responsible-save')));await tester.pumpAndSettle();
    expect(find.text('Dr Démo'),findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('health-product')),-250,scrollable:find.byType(Scrollable).first);await Scrollable.ensureVisible(tester.element(find.byKey(const Key('health-product'))),alignment:0.5);await tester.pumpAndSettle();await tester.tap(find.byKey(const Key('health-product')));await tester.pumpAndSettle();await tester.tap(find.text('Vaccin test').last);await tester.pumpAndSettle();
    await revealHealth(tester,'health-dates');tester.widget<V2DateSelection>(find.byKey(const Key('health-dates'))).onChanged({'2030-05-01','2030-05-03'});await tester.pumpAndSettle();
    await revealHealth(tester,'health-save');await tester.tap(find.byKey(const Key('health-save')));await tester.pumpAndSettle();
    final plan=api.requests.last;expect(plan['responsible_id'],9);expect(plan.containsKey('assigned_to'),false);expect(plan['dates'],['2030-05-01','2030-05-03']);expect(plan['planned_time'],null);
    await tester.pumpWidget(const SizedBox());api.close();
  });
  testWidgets('mortality prefills origin cost and two confirmed movements keep context',(tester)async{
    ApiService.token='movement-demo';final api=RepeatMovementApi();await tester.pumpWidget(saleApp(api));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('movementTypeDropdown')));await tester.pumpAndSettle();await tester.tap(find.text('Mortalité').last);await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('movementLotDropdown')));await tester.pumpAndSettle();await tester.tap(find.text('Chair A').last);await tester.pumpAndSettle();
    final price=find.byKey(const Key('animalSalePrice'));await tester.ensureVisible(price);expect(tester.widget<TextField>(price).controller!.text,'1 200,00');
    for(var i=0;i<2;i++){
      final qty=find.byKey(const Key('animalSaleQuantity'));await tester.ensureVisible(qty);await tester.enterText(qty,'1');
      final save=find.byKey(const Key('saveMovement'));await tester.ensureVisible(save);await tester.tap(save);await tester.pumpAndSettle();
    }
    expect(api.posts,2);expect(api.animalPrice,1200);expect(find.byKey(const Key('movementLotDropdown')),findsOneWidget);
    api.cost='0.00';await tester.enterText(price,'0');api.fail=true;
    final qty=find.byKey(const Key('animalSaleQuantity'));await tester.ensureVisible(qty);await tester.enterText(qty,'1');await tester.ensureVisible(find.byKey(const Key('saveMovement')));await tester.tap(find.byKey(const Key('saveMovement')));await tester.pumpAndSettle();
    expect(api.posts,2);expect(tester.widget<TextField>(qty).controller!.text,'1');
    await tester.pumpWidget(const SizedBox());api.close();
  });
}
