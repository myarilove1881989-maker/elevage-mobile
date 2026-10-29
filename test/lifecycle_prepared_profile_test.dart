import 'package:flutter/widgets.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_elevage/services/api_service.dart';
import 'unified_access_harness.dart';
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});tzdata.initializeTimeZones();});
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.farmerSession=false;});
  test('prepared code profile survives brief background, then expires without losing original',() async {
    final h=UnifiedAccessHarness();await h.start();final runtime=await h.runtime();
    try {
      final api=await runtime.signIn('synthetic','1234');
      h.down=true;await runtime.connection.probe();
      await api.createDepense(lotId:7,categorieId:1,montant:12.34,date:h.now);
      final original=(await h.db.listOutbox()).single.operationId;
      runtime.handleAppLifecycleState(AppLifecycleState.paused);
      expect(runtime.prepared,isTrue);
      h.now=h.now.add(const Duration(minutes:2));
      runtime.handleAppLifecycleState(AppLifecycleState.resumed);
      expect(runtime.signedIn,isTrue);expect(runtime.prepared,isTrue);
      runtime.handleAppLifecycleState(AppLifecycleState.paused);
      h.now=h.now.add(const Duration(minutes:3));
      runtime.handleAppLifecycleState(AppLifecycleState.resumed);
      expect(runtime.signedIn,isFalse);expect(runtime.prepared,isFalse);
      expect((await h.db.listOutbox()).single.operationId,original);
      expect(await h.db.operatorProfiles(),isNotEmpty);
    } finally {
      runtime.connection.pause();runtime.tablet.setForeground(false);
      await runtime.tablet.sync?.waitForIdle();
      runtime.dispose();await h.db.close();await h.directory.delete(recursive:true);
    }
  });
}
