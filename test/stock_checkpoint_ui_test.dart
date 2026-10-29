import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'terrain_forms_validation_test.dart' show FormFixture, flush, choose;
import 'production_tracking_test.dart' show testApp;

void main() {
  testWidgets('partial receipts explain the retained baseline and clear the notice only after folding', (tester) async {
    final fixture=FormFixture();await tester.runAsync(fixture.start);
    addTearDown(() async {await tester.pumpWidget(const SizedBox());await tester.runAsync(fixture.finish);});
    await tester.pumpWidget(testApp(OfflineTabletScreen(controller:fixture.tablet)));
    await flush(tester,fixture);
    await choose(tester,'Consulter','Agenda');await flush(tester,fixture);
    await choose(tester,'Consulter','Lots');await flush(tester,fixture);
    final entries=await tester.runAsync(() async {
      final entries=<OutboxEntry>[];
      for(final quantity in [2,1]) {
        entries.add(await fixture.tablet.declare(entityType:'MORTALITE',operationType:'CREATE',
          payload:{'lot_ref':{'server_id':7},'quantite':quantity},businessOccurredAt:fixture.now));
      }
      return entries;
    });
    Map<String,dynamic> receipt(OutboxEntry entry)=>{'client_operation_id':entry.operationId,'author_user_id':2,
      'transport_status':'SERVER_RECEIVED','business_status':'CONFIRMED','server_entity_id':'${entry.sequence}',
      'server_version':'farm:${entry.sequence}','received_at':fixture.now.toIso8601String(),
      'applied_at':fixture.now.toIso8601String(),'stock_snapshots':[{'id':7,'nom':'Lot chair fictif',
        'exploitation':1,'stock':7,'stock_oeufs':0,'type_production':'CHAIR','confirmed_business_revision':2}]};
    await tester.runAsync(() async {
      await fixture.db.acceptReceipts([receipt(entries![0])]);await fixture.tablet.refreshOutbox();
    });
    await flush(tester,fixture);
    await tester.drag(find.byType(ListView).first,const Offset(0,-900));await tester.pumpAndSettle();
    expect(find.text('Mouvements locaux : -3 • stock projeté : 7'),findsOneWidget);
    expect(find.text('Stock confirmé : 10'),findsWidgets);
    expect(find.textContaining('Confirmations partielles'),findsWidgets);
    await tester.runAsync(() async {
      await fixture.db.acceptReceipts([receipt(entries![1])]);await fixture.tablet.refreshOutbox();
    });
    await flush(tester,fixture);
    expect(find.text('Stock confirmé : 7'),findsOneWidget);
    expect(find.textContaining('Confirmations partielles'),findsNothing);
    expect(fixture.requests,0);
  });
}
