import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/screens/add_depense_screen.dart';
import 'package:app_elevage/screens/vaccination_screen.dart';
import 'production_tracking_test.dart' show testApp;
import 'feed_distribution_test.dart' show FeedApiFake;
import 'online_expense_form_test.dart' show OnlineExpenseServer,selectExpense;
import 'vaccine_projection_test.dart' show vaccineSnapshot,vaccine,vialA,vialB;

Future<void> reveal(WidgetTester tester,String key) async {
  final finder=find.byKey(Key(key));
  if(finder.evaluate().isEmpty)await tester.scrollUntilVisible(finder,250,scrollable:find.byType(Scrollable).first);
  await tester.ensureVisible(finder);await tester.pumpAndSettle();
}
class VaccineApi extends FeedApiFake {
  bool lose=true;final bodies=<Map<String,dynamic>>[];
  @override Future<dynamic> get(String path) async {
    if(path=='/vaccine-supplies/') {
      final snapshot=vaccineSnapshot();
      for(final vial in snapshot['vials'] as List)vial['usable_until']=DateTime.now().toUtc().add(const Duration(days:1)).toIso8601String();
      return snapshot;
    }
    final result=await super.get(path) as Map<String,dynamic>;
    result['permission_contract']['permissions']=['finance.read','vaccinations.create','vaccinations.update','vaccinations.delete','vaccinations.loss'];return result;
  }
  @override Future<dynamic> post(String path,Map<String,dynamic> body) async {
    bodies.add({...body});if(lose)throw StateError('Réponse perdue');return {'id':1};
  }
}
void main(){
  setUp(() {tzdata.initializeTimeZones();SharedPreferences.setMockInitialValues({});ApiService.token='synthetic-employee';globalToken=null;});
  tearDown(() {ApiService.token=null;globalToken=null;});
  testWidgets('renamed vaccine category creates one exact expense and retains supply UUID on retry',(tester) async {
    final server=OnlineExpenseServer()..vaccine=true..lost=true;
    await tester.pumpWidget(testApp(AddDepenseScreen(apiService:server.api)));await tester.pumpAndSettle();await selectExpense(tester);
    await reveal(tester,'vaccine-product');await tester.tap(find.byKey(const Key('vaccine-product')));await tester.pumpAndSettle();await tester.tap(find.text('Vaccin test').last);await tester.pumpAndSettle();
    await reveal(tester,'vaccine-species');await tester.tap(find.byKey(const Key('vaccine-species')));await tester.pumpAndSettle();await tester.tap(find.text('Poulet').last);await tester.pumpAndSettle();
    for(final field in {'vaccine-count':'10','vaccine-doses':'20','vaccine-batch':'FABRICANT-TEST','vaccine-expiry':'2030-11-30'}.entries) {await reveal(tester,field.key);await tester.enterText(find.byKey(Key(field.key)),field.value);}
    await reveal(tester,'expense-submit');await tester.tap(find.byKey(const Key('expense-submit')));await tester.pumpAndSettle();
    expect(server.posts,1);expect(server.saved!['montant'],'12.34');expect(server.saved!['vaccine_supply']['vial_count'],10);
    final body={...server.saved!};server.lost=false;await reveal(tester,'feed-retry');await tester.tap(find.byKey(const Key('feed-retry')));await tester.pumpAndSettle();
    expect(server.posts,2);expect(server.saved,body);expect(body.containsKey('feed_supply'),false);expect(find.byKey(const Key('feed-retry')),findsNothing);
    await tester.pumpWidget(const SizedBox());server.api.close();
  });
  testWidgets('35 doses across two existing vials retain exact original on uncertain save',(tester) async {
    final api=VaccineApi();await tester.pumpWidget(testApp(VaccinationForm(api:api,lotId:10)));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vaccination-product')));await tester.pumpAndSettle();await tester.tap(find.text('Vaccin test').last);await tester.pumpAndSettle();
    for(final field in {'vaccination-animals':'35','used-$vialA':'20','used-$vialB':'15'}.entries) {await reveal(tester,field.key);await tester.enterText(find.byKey(Key(field.key)),field.value);}
    await reveal(tester,'save-vaccination');await tester.tap(find.byKey(const Key('save-vaccination')));await tester.pumpAndSettle();expect(api.bodies,hasLength(1));
    expect(api.bodies[0]['allocations'],[{'vial':vialA,'doses':20,'lost':0},{'vial':vialB,'doses':15,'lost':0}]);
    expect(api.bodies[0]['product'],vaccine);expect(api.bodies[0].containsKey('operator'),false);
    api.lose=false;await reveal(tester,'save-vaccination');await tester.tap(find.byKey(const Key('save-vaccination')));await tester.pumpAndSettle();
    expect(api.bodies,hasLength(2));expect(api.bodies[0],api.bodies[1]);await tester.pumpWidget(const SizedBox());api.close();
  });
}
