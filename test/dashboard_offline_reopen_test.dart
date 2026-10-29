import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/services/api_service.dart';
import 'unified_access_harness.dart';
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});tzdata.initializeTimeZones();});
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.farmerSession=false;});
  test('all dashboard requests survive inactivity lock and fresh offline sign-in',() async {
    final h=UnifiedAccessHarness();await h.start();h.codes.add('agenda.read');var runtime=await h.runtime();
    try {
      var api=await runtime.signIn('synthetic','1234');
      Future<List<Object>> dashboardReads() => Future.wait<Object>([
        api.getDashboard(),api.getLots(),api.getEspeces(),api.getTotalDettes(),api.getTasks()]);
      for(final path in ['/dashboard/','/clients/total-dettes/','/tasks/?active=true']) {
        expect(await h.db.screenSnapshot(userId:2,credentialVersion:1,path:path),isNotNull,reason:path);
      }
      h.down=true;await runtime.connection.probe();
      h.now=h.now.add(const Duration(minutes:5));
      expect(runtime.tablet.checkInactivity(),isTrue);
      expect(runtime.signedIn,isFalse);
      runtime.dispose();await h.db.close();h.db=h.openDatabase();
      await h.controller();runtime=await h.runtime();
      api=await runtime.signIn('synthetic','1234');
      final result=await dashboardReads();
      expect(result[0],{'stock_total':10});expect(result[3],25.5);
      expect(runtime.signedIn,isTrue);
    } finally {
      runtime.connection.pause();runtime.tablet.setForeground(false);
      await runtime.tablet.sync?.waitForIdle();runtime.dispose();
      await h.db.close();await h.directory.delete(recursive:true);
    }
  });
}
