import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/screens/feed_distribution_screen.dart';
import 'feed_distribution_test.dart' show FeedApiFake;
import 'production_tracking_test.dart' show testApp;

class CancelApi extends FeedApiFake {
  final cancellations=<Map<String,dynamic>>[];
  @override Future<dynamic> get(String path) async {
    final data=await super.get(path) as Map<String,dynamic>;
    (data['permission_contract'] as Map)['permissions']=['finance.read','feed.create','feed.update','feed.delete'];
    return data;
  }
  @override Future<dynamic> deleteForMaintenance(String path,Map<String,dynamic> data) async {
    cancellations.add({...data});
    if(cancellations.length==1)throw StateError('Réponse perdue');
    saved.clear();return {'id':1};
  }
}
void main() {
  testWidgets('existing history cancellation requires a reason and retains confirmation and UUID on retry',(tester) async {
    final api=CancelApi();
    api.saved.add({'id':1,'lot':1,'aliment':'Aliment suivi','quantite_kg':'80',
      'distribution_at':'2026-11-03T10:00:00Z','physical_stock':{'distribution_version':'feed:12'}});
    await tester.pumpWidget(testApp(FeedDistributionScreen(apiService:api,lotId:1,lotName:'Lot A')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<bool>));await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler avec motif'));await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));await tester.pumpAndSettle();expect(api.cancellations,isEmpty);
    await tester.enterText(find.byType(TextField),'Annulation vérifiée');
    await tester.tap(find.text('Confirmer'));await tester.pumpAndSettle();expect(api.cancellations,hasLength(1));
    await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));await tester.pumpAndSettle();
    expect(api.cancellations,hasLength(2));expect(api.cancellations[0],api.cancellations[1]);
    expect(api.cancellations.last['confirm'],true);expect(api.cancellations.last['expected_version'],'feed:12');
    expect(find.text('Aliment suivi'),findsNothing);
    await tester.pumpWidget(const SizedBox());api.close();
  });
}
