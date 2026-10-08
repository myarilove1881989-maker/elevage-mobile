import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
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
import 'grant_diagnostic_client.dart';

void main() {
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real process crashes and signed APK update preserve encrypted pending facts',(tester) async {
    const base='https://10.0.2.2:9444/api';
    const ca=String.fromEnvironment('NATIVE_TEST_CA');
    expect(ca,isNotEmpty);
    const secrets=AndroidOperatorSecretStore();
    final native=AndroidDeviceIdentity();
    IOClient client()=>IOClient(HttpClient(context:SecurityContext(withTrustedRoots:false)
      ..setTrustedCertificatesBytes(base64Decode(ca))));
    late FoundationApi api;
    api=FoundationApi(baseUrl:base,deviceIdentity:native,secrets:secrets,
      client:GrantDiagnosticClient(client(),expected:() {
        final person=api.personal!;
        return {'sub':'${person.userId}','exploitation_id':person.farmId,
          'device_id':(person.capabilities['primary_device'] as Map)['id'],
          'write_generation':person.capabilities['write_generation'],
          'rights_version':(person.capabilities['membership'] as Map)['version']};
      }));
    final tablet=TabletController(api:api,secrets:secrets,transportClient:client,automaticSyncEnabled:false);
    const control='synthetic_native_resilience_control_9444';
    final encoded=await secrets.read(control);
    final state=encoded==null?<String,dynamic>{}:Map<String,dynamic>.from(jsonDecode(encoded) as Map);
    Future<void> save() async {await secrets.write(control,jsonEncode(state));}
    Future<String> digest(OutboxEntry row) async=>(await Sha256().hash(utf8.encode(canonicalDeclaration(row.declaration))))
      .bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    binding.reportData={'resilience_complete':false,'stage':state['phase']??'SETUP'};
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Text('Reprise native isolée'))));
    if(state.isEmpty) {
      await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
      final fixture=await api.request('GET','/test-fixture/state/');
      await tablet.preparePrimaryTablet();
      await tablet.signIn('native-jean','SyntheticNativeI-2026-only');
      await tablet.prepareOperator('123456');api.personal=null;
      await tablet.unlockProfile(fixture['jean'] as int,'Jean','123456');
      final first=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Client conservé avant crash'},businessOccurredAt:DateTime.now().toUtc());
      state.addAll({'phase':'WRITE_INTERRUPTED','farm':tablet.farmId,'jean':fixture['jean'],
        'first_id':first.operationId,'first_digest':await digest(first),
        'installation':await native.publicIdentity(),'crash_id':newOperationUuid()});
      await save();
      final db=tablet.cache! as FarmDatabase;
      await db.customStatement('CREATE TABLE synthetic_crash_projection(id INTEGER PRIMARY KEY)');
      await tablet.declare(entityType:'CLIENT',operationType:'CREATE',operationId:state['crash_id'] as String,
        payload:{'nom':'Client écriture interrompue'},businessOccurredAt:DateTime.now().toUtc(),project:() async {
          await db.customStatement('INSERT INTO synthetic_crash_projection VALUES(1)');
          debugPrint('REAL_WRITE_CRASH_READY transaction_open=true');
          await Completer<void>().future;
        });
      throw StateError('Host did not interrupt the open transaction');
    }
    await tablet.initialize();
    expect(await native.publicIdentity(),state['installation']);
    final db=tablet.cache! as FarmDatabase;
    var rows=await db.listOutbox();
    expect(await digest(rows.singleWhere((e)=>e.operationId==state['first_id'])),state['first_digest']);
    if(state['phase']=='WRITE_INTERRUPTED') {
      expect(rows,hasLength(1));expect(rows.single.authorId,state['jean']);
      expect(rows.where((e)=>e.operationId==state['crash_id']),isEmpty);
      expect(await db.customSelect('SELECT * FROM synthetic_crash_projection').get(),isEmpty);
      expect((await db.customSelect('SELECT next_sequence FROM local_sequence_counter WHERE singleton=1').getSingle())
        .read<int>('next_sequence'),2);
      await tablet.unlockProfile(state['jean'] as int,'Jean','123456');
      final second=await tablet.declare(entityType:'CLIENT',operationType:'CREATE',
        payload:{'nom':'Client conservé pendant mise à jour'},businessOccurredAt:DateTime.now().toUtc());
      expect(second.sequence,2);
      state.addAll({'phase':'UPDATE_PENDING','second_id':second.operationId,'second_digest':await digest(second)});
      await save();tablet.lock();
      binding.reportData={'stage':'UPDATE_PENDING','update_pending_ready':true,'pending':2,
        'write_crash_rollback':true,'native_identity_preserved':true};
      debugPrint('REAL_UPDATE_PENDING_READY pending=2 write_rollback=true');
    } else if(state['phase']=='UPDATE_PENDING') {
      expect(rows,hasLength(2));expect(rows.every((e)=>e.transportStatus=='LOCAL_PENDING'),isTrue);
      expect(await digest(rows.singleWhere((e)=>e.operationId==state['second_id'])),state['second_digest']);
      expect(rows.every((e)=>e.authorId==state['jean']),isTrue);
      debugPrint('REAL_APK_UPDATE_PRESERVED pending=2 identity=true');
      debugPrint('REAL_BACKEND_DOWN_READY pending=2');
      // The host suspends this test's server process after the marker, then resumes it after the failure marker.
      await Future<void>.delayed(const Duration(seconds:3));
      await tablet.syncOutbox();
      rows=await db.listOutbox();
      expect(rows,hasLength(2));expect(rows.every((e)=>e.transportStatus=='RETRY_WAIT'),isTrue);
      expect(tablet.sync!.error,isNotNull);
      expect(await digest(rows.singleWhere((e)=>e.operationId==state['second_id'])),state['second_digest']);
      debugPrint('REAL_BACKEND_UNAVAILABLE_RETAINED pending=2');
      await Future<void>.delayed(const Duration(seconds:12));
      state['phase']='SYNC_INTERRUPTED';await save();
      debugPrint('REAL_SYNC_CRASH_READY pending=2');
      await tablet.syncOutbox();
      throw StateError('Host did not interrupt after actual server persistence');
    } else if(state['phase']=='SYNC_INTERRUPTED') {
      expect(rows,hasLength(2));
      expect(rows.every((e)=>e.transportStatus=='RETRY_WAIT' && e.lastError=='INTERRUPTED_REQUEST'),isTrue);
      expect(await digest(rows.singleWhere((e)=>e.operationId==state['second_id'])),state['second_digest']);
      await tablet.syncOutbox();
      rows=await db.listOutbox();
      expect(rows.every((e)=>e.transportStatus=='SERVER_RECEIVED' && e.businessStatus=='CONFIRMED'),isTrue);
      await tablet.signIn('native-owner','SyntheticNativeI-2026-only');
      final verified=await api.request('POST','/test-fixture/verify-resilience/',
        data:{'operation_ids':[state['first_id'],state['second_id']]});
      expect(verified['verified'],isTrue);expect(verified['effects'],2);expect(verified['duplicate_effects'],isFalse);
      state['phase']='COMPLETE';await save();
      binding.reportData={'stage':'COMPLETE','resilience_complete':true,'write_crash_rollback':true,
        'apk_update_preserved':true,'native_identity_preserved':true,'backend_unavailable_preserved':true,
        'sync_crash_recovered':true,'lost_response_idempotent':true,'originals':2,'effects':2};
      debugPrint('REAL_NATIVE_RESILIENCE_COMPLETE originals=2 effects=2 crash_write=true update=true crash_sync=true');
    } else {throw StateError('Unexpected resilience phase');}
    api.close();tablet.dispose();
    await closeAndroidFarmDatabase(farmId:state['farm'] as int,server:Uri.parse(base));
  });
}
