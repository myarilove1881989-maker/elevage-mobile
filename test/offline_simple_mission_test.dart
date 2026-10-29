import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'shared_tablet_test.dart' show SharedTabletHarness;
import 'offline_fine_permissions_test.dart' show fineGrant;
import 'seven_day_integration_test.dart' show SevenDayHarness;

class CancellationHarness extends SharedTabletHarness {
  final cancelled=<String,String>{};
  @override
  Future<void> start() async {
    await super.start();
    await db.replaceConfirmedCache('lots',[{'id':42,'nom':'Porcs','exploitation':1,
      'stock':100,'stock_oeufs':0,'confirmed_business_revision':0}]);
  }
  @override
  Map<String,dynamic> receipt(Map<String,dynamic> operation) {
    final reverse=operation['operation_type']=='REVERSE';
    final payload=operation['payload'] as Map;
    if(reverse) cancelled[payload['original_operation_id'] as String]=operation['client_operation_id'] as String;
    final data=super.receipt({...operation,'entity_type':'DEPENSE'});
    if(operation['entity_type']=='VENTE_ANIMAUX') {
      final isCancelled=cancelled.containsKey(operation['client_operation_id']);
      data['business_status']=isCancelled?'SUPERSEDED':'CONFIRMED';
      data['reason_code']=isCancelled?'BUSINESS_EFFECT_REVERSED':'';
      data['cancellation_operation_id']=cancelled[operation['client_operation_id']];
      data['server_version']='farm:${originals.length}';
      data['stock_snapshots']=[{'id':42,'nom':'Porcs','exploitation':1,
        'stock':cancelled.isEmpty?90:100,'stock_oeufs':0,'confirmed_business_revision':originals.length}];
    }
    return data;
  }
  Future<void> enableCancellation() async {
    codes=[...codes,'animal_sales.cancel'];
    late Map<String,dynamic> response;
    final grant=await fineGrant(codes:codes,now:now,duration:const Duration(days:7),issued:(r)=>response=r);
    await db.saveOperatorProfile(grant,'Paul');
    secrets.values['offline_grant_${Uri.encodeComponent(SevenDayHarness.base)}_1_2']=jsonEncode({
      'token':grant.token,'public_key':response['public_key'],'key_id':response['key_id'],
      'device_id':7,'generation':1,'rights_version':1});
    await tablet.unlockProfile(2,'Paul','123456');
  }
  Future<OutboxEntry> cancel(OutboxEntry original)=>tablet.declare(entityType:'VENTE_ANIMAUX',operationType:'REVERSE',
    payload:{'original_operation_id':original.operationId,'reason':'Erreur de quantité',
      'lot_ref':(original.declaration['payload'] as Map)['lot_ref']},
    dependencies:[original.operationId],businessOccurredAt:now);
}

class ScreenTablet extends TabletController {
  ScreenTablet(SevenDayHarness h):super(api:h.api,secrets:h.secrets,clock:()=>h.now,automaticSyncEnabled:false) {
    operators=h.tablet.operators;cache=h.db;farmId=1;deviceId=7;generation=1;profiles=h.tablet.profiles;selectedName='Paul';
  }
  @override
  Future<void> initialize() async {}
}

class ProfileChangeHarness extends SharedTabletHarness {
  @override
  Future<http.Response> transport(http.Request request) async {
    final response=await super.transport(request);
    if(request.url.path.endsWith('/status/') && response.statusCode==200) {
      final data=jsonDecode(response.body) as Map;
      for(final state in data['profiles'] as List) {
        if(state['user_id']==3) {state['rights_version']=2;state['permissions']=['finance.read'];}
      }
      return http.Response(jsonEncode(data),200);
    }
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('five minutes use only user interaction; network notifications do not reset the timer',(tester) async {
    late SevenDayHarness h;
    await tester.runAsync(() async {h=SevenDayHarness();await h.start();});
    try {
      h.tablet.userActivity();h.now=h.now.add(const Duration(minutes:4));await tester.pump(const Duration(minutes:4));
      h.tablet.sync!.setForeground(false);h.now=h.now.add(const Duration(seconds:59));await tester.pump(const Duration(seconds:59));
      expect(h.tablet.operators!.session,isNotNull);
      h.now=h.now.add(const Duration(seconds:1));await tester.pump(const Duration(seconds:1));expect(h.tablet.operators!.session,isNull);
      await tester.runAsync(()=>h.tablet.unlockProfile(2,'Paul','123456'));
      h.tablet.userActivity();h.now=h.now.add(const Duration(minutes:4));await tester.pump(const Duration(minutes:4));h.tablet.userActivity();
      h.now=h.now.add(const Duration(minutes:4));await tester.pump(const Duration(minutes:4));expect(h.tablet.operators!.session,isNotNull);
      h.now=h.now.add(const Duration(minutes:1));await tester.pump(const Duration(minutes:1));expect(h.tablet.operators!.session,isNull);
    } finally {await tester.runAsync(h.close);}
  });
  test('offline sale and cancellation retain two originals and confirmed restored stock after retry',() async {
    final h=CancellationHarness();await h.start();
    try {
      await h.enableCancellation();await h.sale();final sale=(await h.db.listOutbox()).single;
      await h.cancel(sale);
      expect((await h.db.listOutbox()).length,2);
      expect((await h.tablet.readPage('lots')).single['data']['projected_stock'],90);
      h.lost=true;await h.reconnect();
      h.now=h.now.add(const Duration(seconds:40));await h.tablet.sync!.trigger(manual:true);
      expect((await h.db.listOutbox()).every((r)=>r.transportStatus=='SERVER_RECEIVED'),isTrue);
      expect((await h.tablet.readPage('lots')).single['data']['stock'],100);
      await h.tablet.sync!.trigger(manual:true);
      expect(h.originals.length,2);
      expect((await h.db.listOutbox()).firstWhere((r)=>r.operationId==sale.operationId).businessStatus,'SUPERSEDED');
      expect((await h.db.listOutbox()).firstWhere((r)=>r.operationId==sale.operationId).declaration,sale.declaration);
    } finally {await h.close();}
  });
  test('without cancel permission no cancellation original can be recorded',() async {
    final h=CancellationHarness();await h.start();
    try {await h.sale();await expectLater(h.cancel((await h.db.listOutbox()).single),throwsStateError);
      expect((await h.db.listOutbox()).length,1);
    } finally {await h.close();}
  });
  test('online cancellation refreshes its original status in the same synchronization',() async {
    final h=CancellationHarness();await h.start();
    try {
      await h.enableCancellation();await h.sale();await h.reconnect();
      final original=(await h.db.listOutbox()).single;
      expect(original.businessStatus,'CONFIRMED');
      await h.cancel(original);h.now=h.now.add(const Duration(seconds:40));
      await h.tablet.sync!.trigger(manual:true);
      final saved=(await h.db.listOutbox()).firstWhere((entry)=>entry.operationId==original.operationId);
      expect(saved.businessStatus,'SUPERSEDED');
      expect((await h.tablet.readPage('lots')).single['data']['stock'],100);
    } finally {await h.close();}
  });
  test('changed rights of a closed colleague profile block its old PIN grant across restart',() async {
    final h=ProfileChangeHarness();await h.start();
    try {
      await h.jean();await h.sale();await h.reconnect();
      expect(h.api.personal,isNull);
      await expectLater(h.tablet.unlockProfile(3,'Jean','654321'),throwsStateError);
      await h.reopen();
      await expectLater(h.tablet.unlockProfile(3,'Jean','654321'),throwsStateError);
      expect((await h.db.listOutbox()).single.authorId,2);
    } finally {await h.close();}
  });
  testWidgets('brief background preserves session and detached closes private views',(tester) async {
    late SevenDayHarness h;late ScreenTablet tablet;
    await tester.runAsync(() async {h=SevenDayHarness();await h.start();tablet=ScreenTablet(h);});
    await tester.pumpWidget(MaterialApp(home:OfflineTabletScreen(controller:tablet)));
    await tester.pump();
    final context=tester.element(find.byType(OfflineTabletScreen));
    unawaited(showDialog<void>(context:context,builder:(_)=>const AlertDialog(content:Text('Saisie personnelle ouverte'))));
    await tester.pumpAndSettle();expect(find.text('Saisie personnelle ouverte'),findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(tablet.operators!.session,isNotNull);expect(find.text('Saisie personnelle ouverte'),findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pumpAndSettle();
    expect(tablet.operators!.session,isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();expect(tablet.operators!.session,isNull);
    expect(find.text('Saisie personnelle ouverte'),findsNothing);
    await tester.runAsync(()=>tablet.unlockProfile(2,'Paul','123456'));
    await tester.pump();
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const Scaffold(
      body:TextField(decoration:InputDecoration(labelText:'Formulaire personnel ouvert'))))));
    await tester.pumpAndSettle();
    tablet.userActivity();h.now=h.now.add(const Duration(minutes:4));await tester.pump(const Duration(minutes:4));
    await tester.tap(find.byType(TextField));await tester.pump();
    h.now=h.now.add(const Duration(minutes:4,seconds:59));await tester.pump(const Duration(minutes:4,seconds:59));
    expect(tablet.operators!.session,isNotNull);
    h.now=h.now.add(const Duration(seconds:1));await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(tablet.operators!.session,isNull);expect(find.text('Formulaire personnel ouvert'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    // Drain the real database worker after the UI has stopped requesting reads.
    await tester.runAsync(()=>h.db.projectedPage('lots'));
    await tester.runAsync(h.close);
  });
}
