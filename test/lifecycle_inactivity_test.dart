import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_elevage/config.dart';
import 'package:app_elevage/offline/foundation_api.dart';
import 'package:app_elevage/offline/tablet_controller.dart';
import 'package:app_elevage/services/farmer_runtime.dart';
import 'package:app_elevage/services/server_connection.dart';
import 'foundation_api_test.dart' show TestIdentity, TestSecretStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Wi-Fi settings and brief background preserve account; exact five minutes expire', () {
    fakeAsync((async) {
      var now=DateTime.utc(2026,10,28,12);
      final store=TestSecretStore();
      final api=FoundationApi(baseUrl:Config.apiUrl,deviceIdentity:TestIdentity(),secrets:store,
        client:MockClient((_) async=>http.Response('{}',200)));
      api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',
        capabilities:const {},access:'synthetic',refresh:'synthetic');
      final tablet=TabletController(api:api,secrets:store,clock:()=>now,automaticSyncEnabled:false);
      final runtime=FarmerRuntime(tablet:tablet,connection:ServerConnection(baseUrl:Config.apiUrl,
        check:() async=>false))..username='synthetic';
      tablet.userActivity();
      runtime.handleAppLifecycleState(AppLifecycleState.inactive);
      runtime.handleAppLifecycleState(AppLifecycleState.hidden);
      runtime.handleAppLifecycleState(AppLifecycleState.paused);
      expect(runtime.signedIn,isTrue);
      now=now.add(const Duration(minutes:2));async.elapse(const Duration(minutes:2));
      runtime.handleAppLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(runtime.signedIn,isTrue);
      now=now.add(const Duration(minutes:3));async.elapse(const Duration(minutes:3));
      expect(runtime.signedIn,isFalse);expect(api.personal,isNull);
      runtime.dispose();async.flushMicrotasks();
    });
  });
  test('resume checks elapsed time even when Android suspended all timer callbacks', () {
    fakeAsync((async) {
      var now=DateTime.utc(2026,10,28,12);
      final store=TestSecretStore();
      final api=FoundationApi(baseUrl:Config.apiUrl,deviceIdentity:TestIdentity(),secrets:store,
        client:MockClient((_) async=>http.Response('{}',200)));
      api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',
        capabilities:const {},access:'synthetic',refresh:'synthetic');
      final tablet=TabletController(api:api,secrets:store,clock:()=>now,automaticSyncEnabled:false);
      final runtime=FarmerRuntime(tablet:tablet,connection:ServerConnection(baseUrl:Config.apiUrl,
        check:() async=>true))..username='synthetic';
      tablet.userActivity();runtime.handleAppLifecycleState(AppLifecycleState.paused);
      now=now.add(const Duration(minutes:6));
      runtime.handleAppLifecycleState(AppLifecycleState.resumed);
      expect(runtime.signedIn,isFalse);expect(api.personal,isNull);
      runtime.dispose();async.flushMicrotasks();
    });
  });
  test('foreground interaction extends inactivity; background and sync do not', () {
    fakeAsync((async) {
      var now=DateTime.utc(2026,10,28,12);
      final store=TestSecretStore();
      final api=FoundationApi(baseUrl:Config.apiUrl,deviceIdentity:TestIdentity(),secrets:store,
        client:MockClient((_) async=>http.Response('{}',200)));
      api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',
        capabilities:const {},access:'synthetic',refresh:'synthetic');
      final tablet=TabletController(api:api,secrets:store,clock:()=>now,automaticSyncEnabled:false);
      tablet.userActivity();now=now.add(const Duration(minutes:4));
      async.elapse(const Duration(minutes:4));tablet.userActivity();
      now=now.add(const Duration(minutes:4));async.elapse(const Duration(minutes:4));
      expect(api.personal,isNotNull);
      tablet.setForeground(false);tablet.userActivity();
      now=now.add(const Duration(minutes:1));async.elapse(const Duration(minutes:1));
      expect(api.personal,isNull);
      api.close();tablet.dispose();async.flushMicrotasks();
    });
  });
  test('closing detaches immediately without erasing prepared credentials', () {
    fakeAsync((async) {
      final store=TestSecretStore();store.values['prepared-profile']='synthetic-preserved';
      final api=FoundationApi(baseUrl:Config.apiUrl,deviceIdentity:TestIdentity(),secrets:store,
        client:MockClient((_) async=>http.Response('{}',200)));
      api.personal=OnlineOperatorIdentity(userId:2,farmId:1,role:'OPERATEUR',
        capabilities:const {},access:'synthetic',refresh:'synthetic');
      final tablet=TabletController(api:api,secrets:store,automaticSyncEnabled:false);
      final runtime=FarmerRuntime(tablet:tablet,connection:ServerConnection(baseUrl:Config.apiUrl,
        check:() async=>true))..username='synthetic';
      tablet.userActivity();runtime.handleAppLifecycleState(AppLifecycleState.detached);
      expect(runtime.signedIn,isFalse);expect(api.personal,isNull);
      expect(store.values['prepared-profile'],'synthetic-preserved');
      runtime.dispose();async.flushMicrotasks();
    });
  });
}
