import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'feed_distribution_test.dart' show FeedApiFake;
import 'production_tracking_test.dart' show testApp;
import 'feed_stock_projection_test.dart' show product;

class StockApi extends FeedApiFake {
  bool lose=false;final requests=<Map<String,dynamic>>[];
  @override Future<dynamic> get(String path)async{
    if(path=='/feed-supplies/')return {'stock_contract':1,'confirmed':true,
      'products':[{'id':product,'name':'Aliment suivi','positions':[{'species_id':1,'lot_id':null,'kg':'500','estimated_kg':'420','pending_kg':'-80'}]}],
      'species':[{'id':1,'nom':'Poulet'}],'lots':[{'id':1,'nom':'Lot A','espece_id':1}]};
    return super.get(path);
  }
  @override Future<dynamic> post(String path,Map<String,dynamic> data)async{
    requests.add({...data});if(lose)throw StateError('Réponse perdue');return {'id':3};
  }
}
void main(){
  testWidgets('existing distribution form shows confirmed and estimated stock and retries exactly',(tester)async{
    final api=StockApi();
    await tester.pumpWidget(testApp(FeedDistributionFormScreen(apiService:api,lotId:1,lotName:'Lot A')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('distribution-stock-product')));await tester.pumpAndSettle();
    await tester.tap(find.text('Aliment suivi').last);await tester.pumpAndSettle();
    expect(find.textContaining('Confirmé : 500 kg'),findsOneWidget);
    expect(find.textContaining('Disponible estimé : 420 kg'),findsOneWidget);
    await tester.enterText(find.byKey(const Key('feedQuantityField')),'421');
    await tester.scrollUntilVisible(find.byKey(const Key('saveFeedDistribution')), 250, scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveFeedDistribution')));await tester.pumpAndSettle();
    expect(api.requests,isEmpty); await tester.pump(const Duration(seconds:5)); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feedQuantityField')),'80');api.lose=true;
    await tester.tap(find.byKey(const Key('saveFeedDistribution')));await tester.pumpAndSettle();
    expect(api.requests,hasLength(1));api.lose=false; await tester.pump(const Duration(seconds:5)); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveFeedDistribution')));await tester.pumpAndSettle();
    expect(api.requests,hasLength(2));expect(api.requests[1],api.requests[0]);
    expect(api.requests.first.containsKey('montant'),isFalse);
    expect(api.requests.first.containsKey('depense'),isFalse);
    await tester.pumpWidget(const SizedBox());api.close();
  });
}
