import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/services/api_service.dart';
import 'unified_access_harness.dart';
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});tzdata.initializeTimeZones();});
  tearDown(() {ApiService.token=null;globalToken=null;ApiService.farmerSession=false;});
  test('first offline opening of prepared lots has complete details without an earlier visit',() async {
    final h=UnifiedAccessHarness();await h.start();
    await h.db.beginCacheRefresh('lots');
    await h.db.stageConfirmedPage('lots',[{'id':7,'nom':'Lot fictif','stock':10},
      {'id':8,'nom':'Deuxième lot','stock':10}]);
    await h.db.commitCacheRefresh('lots');
    final runtime=await h.runtime();
    try {
      expect(await h.db.screenSnapshot(userId:2,credentialVersion:1,path:'/lots/7/'),isNull);
      final api=await runtime.signIn('synthetic','1234');
      expect(await h.db.screenSnapshot(userId:2,credentialVersion:1,path:'/lots/7/'),isNotNull);
      expect(await h.db.screenSnapshot(userId:2,credentialVersion:1,path:'/lots/8/'),isNotNull);
      expect(await h.db.screenSnapshot(userId:3,credentialVersion:1,path:'/lots/7/'),isNull);
      expect(await h.db.screenSnapshot(userId:2,credentialVersion:2,path:'/lots/7/'),isNull);
      h.down=true;await runtime.connection.probe();
      final detail=await api.getLotDetail(7);
      expect(detail['id'],7);expect(detail['stock'],10);
      expect((detail['achats'] as List).single['prix_total'],'100.00');
      expect(detail['kpis']['depenses'],'0.00');
      expect((await api.getLotDetail(8))['id'],8);
      await expectLater(api.getLotDetail(999),throwsA(anything));
      expect(runtime.prepared,isTrue);
    } finally {
      runtime.connection.pause();runtime.tablet.setForeground(false);
      await runtime.tablet.sync?.waitForIdle();runtime.dispose();
      await h.db.close();await h.directory.delete(recursive:true);
    }
  });
}
