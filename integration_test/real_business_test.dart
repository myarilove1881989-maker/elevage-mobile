import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app_elevage/offline/device_identity.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'package:app_elevage/offline/offline_database.dart';
import 'package:app_elevage/offline/outbox.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/screens/offline_tablet_screen.dart';
import 'grant_diagnostic_client.dart';

void main() {
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native encrypted queue applies real PostgreSQL business once with original authors',(tester) async {
    const base='https://10.0.2.2:9443/api';
    const certificate=String.fromEnvironment('NATIVE_TEST_CA');
    expect(certificate,isNotEmpty);
    IOClient client() {
      final context=SecurityContext(withTrustedRoots:false)
        ..setTrustedCertificatesBytes(base64Decode(certificate));
      return IOClient(HttpClient(context:context));
    }
    var controlledOffset=Duration.zero;
    DateTime controlledNow()=>DateTime.now().toUtc().add(controlledOffset);
    const secrets=AndroidOperatorSecretStore();
    final native=AndroidDeviceIdentity();
    TabletController controller() {
      late FoundationApi api;
      api=FoundationApi(baseUrl:base,deviceIdentity:native,secrets:secrets,clock:controlledNow,
        client:GrantDiagnosticClient(client(),expected:() {
          final person=api.personal!;
          return {'sub':'${person.userId}','exploitation_id':person.farmId,
            'device_id':(person.capabilities['primary_device'] as Map)['id'],
            'write_generation':person.capabilities['write_generation'],
            'rights_version':(person.capabilities['membership'] as Map)['version']};
        }));
      return TabletController(api:api,secrets:secrets,transportClient:client,automaticSyncEnabled:false,
        clock:controlledNow,cacheOpener:({required int farmId,required Uri server})=>
          openAndroidFarmDatabase(farmId:farmId,server:server,clock:controlledNow));
    }
    void stage(String value) {binding.reportData={'real_business_complete':false,'stage':value};}
    stage('REAL_LOGIN');
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Validation métier isolée'))));
    var tablet=controller();
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    final fixture=await tablet.api.request('GET','/test-fixture/state/');
    final ownerAgenda=await tablet.api.request('GET','/cache-page/?collection=tasks');
    expect((ownerAgenda['results'] as List).map((e)=>(e as Map)['id']).toSet(),{fixture['task'],fixture['paul_task']});
    final ownerLots=await tablet.api.request('GET','/cache-page/?collection=lots');
    expect((ownerLots['results'] as List).any((e)=>(e as Map)['id']==fixture['foreign_lot']),isFalse);
    await tablet.preparePrimaryTablet();
    expect(tablet.farmId,fixture['farm']);
    await tablet.signIn('native-jean','SyntheticNativeI-2026-only');
    await tablet.prepareOperator('123456');await tablet.refreshCache();
    final jeanAgenda=await tablet.api.request('GET','/cache-page/?collection=tasks');
    expect((jeanAgenda['results'] as List).map((e)=>(e as Map)['id']).toList(),[fixture['task']]);
    await tablet.signIn('native-paul','SyntheticNativeI-2026-only');
    await tablet.prepareOperator('654321');await tablet.refreshCache();
    final paulAgenda=await tablet.api.request('GET','/cache-page/?collection=tasks');
    expect((paulAgenda['results'] as List).map((e)=>(e as Map)['id']).toList(),[fixture['paul_task']]);
    tablet.api.personal=null;
    stage('REAL_NETWORK_DISCONNECT');
    debugPrint('REAL_NETWORK_DISCONNECT_READY');
    await Future<void>.delayed(const Duration(seconds:2));
    final offlineProbe=client();
    try {
      await expectLater(offlineProbe.get(Uri.parse('$base/test-fixture/state/')).timeout(const Duration(seconds:3)),
        throwsA(isA<TimeoutException>()));
    } finally {offlineProbe.close();}
    debugPrint('REAL_NETWORK_DISCONNECTED_CONFIRMED');
    stage('REAL_OFFLINE_JEAN');
    Future<void> tapVisible(Finder target) async {
      await Scrollable.ensureVisible(tester.element(target),alignment:0.5);
      await tester.pumpAndSettle();await tester.tap(target);await tester.pumpAndSettle();
    }
    final jeanName=tablet.profiles.singleWhere((e)=>e['user_id']==fixture['jean'])['display_name'] as String;
    await tester.pumpWidget(MaterialApp(home:OfflineTabletScreen(controller:tablet)));
    await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && find.text(jeanName).evaluate().isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(find.text(jeanName),findsOneWidget);await tapVisible(find.text(jeanName));
    await tester.enterText(find.byType(TextField).last,'123456');
    await tester.tap(find.text('Valider'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.operators!.session==null;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(tablet.operators!.session!.userId,fixture['jean']);
    expect(tablet.api.personal,isNull);
    expect((await tablet.readPage('tasks')).map((e)=>(e['data'] as Map)['id']).toList(),[fixture['task']]);
    await tapVisible(find.text('Enregistrer un client'));
    await tester.enterText(find.byType(TextFormField).first,'Client réel Jean');
    await tester.tap(find.text('Enregistrer sur la tablette'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    final clientJean=tablet.outboxRows.single;
    expect(clientJean.authorId,fixture['jean']);expect(clientJean.declaration['entity_type'],'CLIENT');
    await tapVisible(find.text('Enregistrer une opération terrain'));
    for(var attempt=0;attempt<300 && find.text('Opération réalisée sur le terrain').evaluate().isEmpty;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    await tapVisible(find.descendant(of:find.byType(AlertDialog),matching:find.byType(DropdownButtonFormField<String>)).first);
    await tester.tap(find.text('Achat').last);await tester.pumpAndSettle();
    await tapVisible(find.byType(DropdownButtonFormField<Map<String,dynamic>>).first);
    await tester.tap(find.text('Espèce synthétique native').last);await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ACHAT-nom_lot')),'Lot natif acheté');
    await tester.ensureVisible(find.byKey(const ValueKey('ACHAT-quantite')));
    await tester.enterText(find.byKey(const ValueKey('ACHAT-quantite')),'20');
    await tester.ensureVisible(find.byKey(const ValueKey('ACHAT-prix_unitaire')));
    await tester.enterText(find.byKey(const ValueKey('ACHAT-prix_unitaire')),'1000,00');
    await tester.tap(find.text('Conserver sur la tablette'));await tester.pumpAndSettle();
    for(var attempt=0;attempt<300 && tablet.outboxRows.length<2;attempt++) {
      await tester.pump(const Duration(milliseconds:100));
    }
    expect(tablet.outboxRows,hasLength(2));
    final purchase=tablet.outboxRows.singleWhere((e)=>e.declaration['entity_type']=='ACHAT');
    expect(purchase.authorId,fixture['jean']);expect((purchase.declaration['payload'] as Map)['prix_total'],'20000.00');
    debugPrint('REAL_NATIVE_UI_OFFLINE_SAVED client=1 purchase=1 author=Jean network_blocked=true');
    // The actual screen owns its controller; replace it before opening a fresh controller.
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Reprise du parcours métier'))));
    await closeAndroidFarmDatabase(farmId:fixture['farm'] as int,server:Uri.parse(base));
    tablet=controller();await tablet.initialize();
    await tablet.unlockProfile(fixture['jean'] as int,'Jean','123456');
    final sale=await tablet.declare(entityType:'VENTE_ANIMAUX',operationType:'CREATE',
      payload:{'lot_ref':{'local_uuid':purchase.declaration['local_entity_id']},
        'client_ref':{'local_uuid':clientJean.declaration['local_entity_id']},
        'quantite':3,'prix_unitaire':'10000.00'},
      dependencies:[purchase.operationId,clientJean.operationId],businessOccurredAt:controlledNow());
    final cash=await tablet.declare(entityType:'ENCAISSEMENT',operationType:'CREATE',
      payload:{'client_ref':{'local_uuid':clientJean.declaration['local_entity_id']},
        'vente_ref':{'local_uuid':sale.declaration['local_entity_id']},'montant_recu':'50000.00','mode':'ESPECES'},
      dependencies:[clientJean.operationId,sale.operationId],businessOccurredAt:controlledNow());
    final eggs=await tablet.declare(entityType:'VENTE_OEUFS',operationType:'CREATE',
      payload:{'lot_ref':{'server_id':fixture['egg_lot']},
        'client_ref':{'local_uuid':clientJean.declaration['local_entity_id']},
        'conditionnement':'UNITE','nombre_conditionnements':4,'prix_unitaire_conditionnement':'0.13'},
      dependencies:[clientJean.operationId],businessOccurredAt:DateTime.parse(fixture['egg_sale_at'] as String));
    final task=await tablet.declare(entityType:'TASK',operationType:'UPDATE',
      payload:{'task_id':fixture['task'],'status':'DONE','report':'Compte rendu réel Jean'},
      expectedServerVersion:'1',businessOccurredAt:controlledNow());
    final projected=(await tablet.readPage('lots')).singleWhere((e)=>(e['data'] as Map)['nom']=='Lot natif acheté')['data'] as Map;
    expect(projected['stock'],0);expect(projected['projected_stock'],17);
    tablet.lock();
    await tablet.unlockProfile(fixture['paul'] as int,'Paul','654321');
    expect((await tablet.readPage('tasks')).map((e)=>(e['data'] as Map)['id']).toList(),[fixture['paul_task']]);
    final clientPaul=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
      payload:{'nom':'Client réel Paul'},businessOccurredAt:controlledNow());
    final originals=[clientJean,purchase,sale,cash,eggs,task,clientPaul];
    tablet.lock();
    stage('REAL_ENCRYPTED_RESTART');
    tablet.api.close();tablet.dispose();
    await closeAndroidFarmDatabase(farmId:fixture['farm'] as int,server:Uri.parse(base));
    tablet=controller();await tablet.initialize();
    expect(tablet.api.personal,isNull);expect(tablet.operators!.session,isNull);
    final queue=tablet.cache! as OutboxStore;
    expect((await queue.listOutbox()).length,7);
    for(final original in originals) {
      expect((await queue.listOutbox()).singleWhere((e)=>e.operationId==original.operationId).declaration,original.declaration);
    }
    debugPrint('REAL_NETWORK_RESTORE_READY');
    await Future<void>.delayed(const Duration(seconds:2));
    final onlineProbe=client();
    try {
      final reached=await onlineProbe.get(Uri.parse('$base/test-fixture/state/')).timeout(const Duration(seconds:5));
      expect(reached.statusCode,401);
    } finally {onlineProbe.close();}
    debugPrint('REAL_NETWORK_RESTORED_CONFIRMED');
    stage('REAL_EXPIRED_PERSONAL_TOKENS');
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    final expired=await tablet.api.request('POST','/test-fixture/expired-tokens/');
    tablet.api.personal=OnlineOperatorIdentity(userId:fixture['jean'] as int,farmId:fixture['farm'] as int,
      role:'OPERATEUR',capabilities:{},access:expired['access'] as String,refresh:expired['refresh'] as String);
    await expectLater(tablet.api.request('GET','/cache-page/?collection=clients'),
      throwsA(isA<FoundationApiException>().having((e)=>e.status,'HTTP status',401)));
    expect(tablet.api.personal,isNull);expect(await queue.listOutbox(),hasLength(7));
    stage('REAL_DEVICE_SYNC');
    await Future.wait([tablet.syncOutbox(),tablet.syncOutbox()]);
    final rows=await queue.listOutbox();
    expect(rows.every((e)=>e.transportStatus=='SERVER_RECEIVED'),isTrue);
    expect(rows.singleWhere((e)=>e.operationId==cash.operationId).businessStatus,'NEEDS_RECONCILIATION');
    expect(rows.where((e)=>e.businessStatus=='CONFIRMED'),hasLength(6));
    expect(tablet.api.personal,isNull);expect(tablet.operators!.session,isNull);
    await tablet.syncOutbox();
    stage('REAL_SERVER_VERIFICATION');
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    final verified=await tablet.api.request('POST','/test-fixture/verify/',
      data:{'operation_ids':originals.map((e)=>e.operationId).toList()});
    expect(verified['verified'],isTrue);expect(verified['device_bearer'],isFalse);
    expect(verified['fifo'],[2,2]);expect(verified['stock'],17);
    expect(verified['cash_received'],'50000.00');expect(verified['cash_allocated'],'30000.00');
    expect(verified['cash_review'],'20000.00');
    stage('REAL_ALL_FIELD_OPERATIONS');
    tablet.api.personal=null;
    debugPrint('REAL_FIELD_NETWORK_DISCONNECT_READY');
    await Future<void>.delayed(const Duration(seconds:2));
    final fieldOfflineProbe=client();
    try {
      await expectLater(fieldOfflineProbe.get(Uri.parse('$base/test-fixture/state/')).timeout(const Duration(seconds:3)),
        throwsA(isA<TimeoutException>()));
    } finally {fieldOfflineProbe.close();}
    debugPrint('REAL_FIELD_NETWORK_DISCONNECTED_CONFIRMED');
    await tablet.unlockProfile(fixture['jean'] as int,'Jean','123456');
    final lotRef={'local_uuid':purchase.declaration['local_entity_id']};
    final expense=await tablet.declare(entityType:'DEPENSE',operationType:'CREATE',
      payload:{'lot_ref':lotRef,'categorie_id':fixture['category'],'montant':'123.45'},
      dependencies:[purchase.operationId],businessOccurredAt:controlledNow());
    final feed=await tablet.declare(entityType:'ALIMENTATION',operationType:'CREATE',
      payload:{'lot_ref':lotRef,'aliment':'Aliment natif','quantite_kg':'1.234','prix_kg':'10.00',
        'depense_ref':{'local_uuid':expense.declaration['local_entity_id']}},
      dependencies:[purchase.operationId,expense.operationId],businessOccurredAt:controlledNow());
    final weighing=await tablet.declare(entityType:'PESEE',operationType:'CREATE',
      payload:{'lot_ref':lotRef,'nombre_animaux_peses':2,'poids_total_kg':'1.234'},
      dependencies:[purchase.operationId],businessOccurredAt:controlledNow());
    final collection=await tablet.declare(entityType:'COLLECTE_OEUFS',operationType:'CREATE',
      payload:{'lot_ref':{'server_id':fixture['egg_lot']},'nombre_collecte':12,
        'nombre_casses':2,'nombre_declasses':1,'nombre_consommes_donnes':1},
      businessOccurredAt:controlledNow());
    tablet.lock();
    await tablet.unlockProfile(fixture['paul'] as int,'Paul','654321');
    final mortality=await tablet.declare(entityType:'MORTALITE',operationType:'CREATE',
      payload:{'lot_ref':lotRef,'quantite':2},dependencies:[purchase.operationId],businessOccurredAt:controlledNow());
    final birth=await tablet.declare(entityType:'NAISSANCE',operationType:'CREATE',
      payload:{'lot_ref':lotRef,'total_naissances':5,'mort_nes':2,'nom_nouveau_lot':'Naissances natives'},
      dependencies:[purchase.operationId],businessOccurredAt:controlledNow());
    final donation=await tablet.declare(entityType:'DON',operationType:'CREATE',
      payload:{'lot_ref':lotRef,'quantite':1},dependencies:[purchase.operationId],businessOccurredAt:controlledNow());
    final theft=await tablet.declare(entityType:'VOL',operationType:'CREATE',
      payload:{'lot_ref':lotRef,'quantite':1},dependencies:[purchase.operationId],businessOccurredAt:controlledNow());
    final outside=await tablet.declare(entityType:'VOL',operationType:'CREATE',
      payload:{'lot_ref':{'server_id':fixture['foreign_lot']},'quantite':1},businessOccurredAt:controlledNow());
    final before=(await tablet.readPage('lots')).singleWhere((e)=>(e['data'] as Map)['nom']=='Lot natif acheté')['data'] as Map;
    expect(before['stock'],17);expect(before['projected_stock'],13);
    final beforeEggs=(await tablet.readPage('lots')).singleWhere((e)=>(e['data'] as Map)['id']==fixture['egg_lot'])['data'] as Map;
    expect(beforeEggs['stock_oeufs'],101);expect(beforeEggs['projected_egg_stock'],109);
    final fieldOperations=[expense,feed,weighing,collection,mortality,birth,donation,theft,outside];
    tablet.lock();expect(tablet.api.personal,isNull);
    tablet.api.close();tablet.dispose();
    await closeAndroidFarmDatabase(farmId:fixture['farm'] as int,server:Uri.parse(base));
    tablet=controller();await tablet.initialize();
    final fieldQueue=tablet.cache! as OutboxStore;
    for(final original in fieldOperations) {
      expect((await fieldQueue.listOutbox()).singleWhere((e)=>e.operationId==original.operationId).declaration,original.declaration);
    }
    debugPrint('REAL_FIELD_NETWORK_RESTORE_READY');
    await Future<void>.delayed(const Duration(seconds:2));
    final fieldOnlineProbe=client();
    try {
      final reached=await fieldOnlineProbe.get(Uri.parse('$base/test-fixture/state/')).timeout(const Duration(seconds:5));
      expect(reached.statusCode,401);
    } finally {fieldOnlineProbe.close();}
    debugPrint('REAL_FIELD_NETWORK_RESTORED_CONFIRMED');
    await tablet.syncOutbox();await tablet.syncOutbox();
    final fieldRows=await fieldQueue.listOutbox();
    expect(fieldRows,hasLength(16));
    for(final original in fieldOperations) {
      expect(fieldRows.singleWhere((e)=>e.operationId==original.operationId).businessStatus,
        original.operationId==outside.operationId?'NEEDS_RECONCILIATION':'CONFIRMED');
    }
    await tablet.unlockProfile(fixture['paul'] as int,'Paul','654321');
    final after=(await tablet.readPage('lots')).singleWhere((e)=>(e['data'] as Map)['nom']=='Lot natif acheté')['data'] as Map;
    expect(after['stock'],13);expect(after['projected_stock'],13);
    final afterEggs=(await tablet.readPage('lots')).singleWhere((e)=>(e['data'] as Map)['id']==fixture['egg_lot'])['data'] as Map;
    expect(afterEggs['stock_oeufs'],109);expect(afterEggs['projected_egg_stock'],109);tablet.lock();
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    final fullJourney=await tablet.api.request('POST','/test-fixture/verify-full-journey/',
      data:{'operation_ids':fieldOperations.map((e)=>e.operationId).toList()});
    expect(fullJourney['verified'],isTrue);expect(fullJourney['parent_stock'],13);expect(fullJourney['newborn_stock'],3);
    expect(fullJourney['foreign_stock'],9);expect(fullJourney['foreign_reference_applied'],isFalse);
    expect(fullJourney['egg_stock'],109);
    stage('REAL_CONTROLLED_GRANT_EXPIRY');
    tablet.api.personal=null;
    await tablet.unlockProfile(fixture['jean'] as int,'Jean','123456');
    final oldJean=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
      payload:{'nom':'Client ancien Jean'},businessOccurredAt:controlledNow());
    tablet.lock();
    await tablet.unlockProfile(fixture['paul'] as int,'Paul','654321');
    final oldPaul=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
      payload:{'nom':'Client ancien Paul'},businessOccurredAt:controlledNow());
    tablet.lock();
    for(final seconds in [21600,86400,345600]) {
      await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
      final advanced=await tablet.api.request('POST','/test-fixture/advance-clock/',data:{'seconds':seconds});
      expect(advanced['controlled_seconds'],seconds);
      controlledOffset=Duration(seconds:seconds);tablet.api.personal=null;
      tablet.api.close();tablet.dispose();
      await closeAndroidFarmDatabase(farmId:fixture['farm'] as int,server:Uri.parse(base));
      tablet=controller();await tablet.initialize();
      final persisted=await (tablet.cache! as OutboxStore).listOutbox();
      for(final original in [oldJean,oldPaul]) {
        expect(persisted.singleWhere((e)=>e.operationId==original.operationId).declaration,original.declaration);
      }
      if(seconds<345600) {
        await tablet.unlockProfile(fixture['jean'] as int,'Jean','123456');tablet.lock();
      } else {
        await expectLater(tablet.unlockProfile(fixture['jean'] as int,'Jean','123456'),throwsStateError);
        await expectLater(tablet.declare(entityType:'CLIENT',operationType:'CREATE',
          payload:{'nom':'Écriture expirée interdite'},businessOccurredAt:controlledNow()),throwsStateError);
      }
    }
    final expiryQueue=tablet.cache! as OutboxStore;
    await tablet.syncOutbox();await tablet.syncOutbox();
    for(final original in [oldJean,oldPaul]) {
      expect((await expiryQueue.listOutbox()).singleWhere((e)=>e.operationId==original.operationId).businessStatus,'CONFIRMED');
    }
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    final late=await tablet.api.request('POST','/test-fixture/verify-expired-grants/',
      data:{'operation_ids':[oldJean.operationId,oldPaul.operationId]});
    expect(late['verified'],isTrue);expect(late['grants_expired_at_receipt'],isTrue);
    await tablet.signIn('native-jean','SyntheticNativeI-2026-only');await tablet.prepareOperator('123456');
    await tablet.signIn('native-paul','SyntheticNativeI-2026-only');await tablet.prepareOperator('654321');
    await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
    stage('REAL_DISABLED_ORIGINAL_AUTHOR');
    await tablet.unlockProfile(fixture['jean'] as int,'Jean','123456');
    final disabled=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
      payload:{'nom':'Client Jean désactivé'},businessOccurredAt:controlledNow());
    tablet.lock();
    await tablet.api.request('PATCH','/memberships/${fixture['jean_membership']}/',data:{'is_active':false});
    await tablet.syncOutbox();
    final retained=(await expiryQueue.listOutbox()).singleWhere((e)=>e.operationId==disabled.operationId);
    expect(retained.businessStatus,'NEEDS_RECONCILIATION');expect(retained.authorId,fixture['jean']);
    expect(retained.declaration,disabled.declaration);
    final decision=await tablet.api.request('POST','/offline/reconciliation/${disabled.operationId}/',data:{
      'decision_uuid':newOperationUuid(),'expected_decision_version':0,'action':'APPLY_ORIGINAL',
      'reason':'Vérification explicite des faits originaux de Jean','payload':<String,dynamic>{}});
    expect((decision['receipt'] as Map)['business_status'],'CONFIRMED');
    expect((decision['receipt'] as Map)['decision_actor_id'],fixture['owner']);
    stage('REAL_REVOKED_DEVICE_RECOVERY');
    await tablet.unlockProfile(fixture['paul'] as int,'Paul','654321');
    final recover=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
      payload:{'nom':'Client Paul récupéré'},businessOccurredAt:controlledNow());
    tablet.lock();
    await tablet.api.request('POST','/devices/${tablet.deviceId}/revoke/',data:{'reason':'Révocation explicite pendant validation isolée'});
    await tablet.syncOutbox();
    final blocked=(await expiryQueue.listOutbox()).singleWhere((e)=>e.operationId==recover.operationId);
    expect(blocked.transportStatus,isNot('SERVER_RECEIVED'));expect(blocked.declaration,recover.declaration);
    expect(await tablet.recoverPending('Récupération explicite après révocation'),1);
    expect(tablet.knownDeviceRevoked,isTrue);
    await expectLater(tablet.syncOutbox(),throwsStateError);
    final recovery=await tablet.api.request('POST','/test-fixture/verify-recovery/',
      data:{'disabled_id':disabled.operationId,'recovered_id':recover.operationId});
    expect(recovery['verified'],isTrue);expect(recovery['reactivated'],isFalse);expect(recovery['recovered_applied'],isFalse);
    binding.reportData={'real_business_complete':true,'stage':'COMPLETE','originals':7,
      'jean':6,'paul':1,'server_verified':true,'fifo_verified':true,'cash_verified':true,
      'full_field_journey_verified':true,
      'controlled_grant_expiry_verified':true,
      'real_network_disconnect_verified':true,
      'projected_stock_verified':true,'agenda_scopes_verified':true,'farm_isolation_verified':true,
      'real_native_ui_verified':true,
      'expired_tokens_verified':true,'disabled_author_verified':true,'revoked_recovery_verified':true};
    debugPrint('REAL_NATIVE_BUSINESS_COMPLETE originals=7 jean=6 paul=1 server_verified=true');
    tablet.api.close();tablet.dispose();
    await closeAndroidFarmDatabase(farmId:fixture['farm'] as int,server:Uri.parse(base));
  });
}
