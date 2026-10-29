import 'package:app_elevage/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'unified_access_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('first laying visit after cold offline login uses prepared encrypted views', () async {
    SharedPreferences.setMockInitialValues({}); tzdata.initializeTimeZones();
    final h=UnifiedAccessHarness()..layingFixture=true;
    await h.start(); var runtime=await h.runtime();
    try {
      await h.db.replaceConfirmedCache('lots',[{'id':7,'nom':'Pondeuses','espece':1,'type_production':'OEUFS','stock':50}]);
      await runtime.signIn('synthetic','1234');
      expect(h.preparedReads.where((p)=>p.contains('/oeufs/')).length,4);
      runtime.dispose(); await h.db.close(); h.db=h.openDatabase();
      h.down=true; await h.controller(); runtime=await h.runtime();
      final api=await runtime.signIn('synthetic','1234');
      final end=DateTime.now(),start=DateTime.now().subtract(const Duration(days:6));
      expect((await api.get('/farm-profile/'))['nom'],'Ferme partagée');
      expect((await api.getEggStatistics(7,start:start,end:end))['stock_oeufs'],38);
      expect((await api.getEggCollections(7,start:start,end:end)).single['nombre_collecte'],40);
      expect((await api.getDatedEggStock(7))['stock_global'],38);
      expect((await api.getEggKpis(7,start:start,end:end))['production_jour'],40);
      expect(api.lastReadWasCached,true);
      expect(await h.db.screenSnapshot(userId:3,credentialVersion:1,path:'/farm-profile/'),isNull);
    } finally {
      runtime.dispose(); await h.db.close(); await h.directory.delete(recursive:true);
      ApiService.token=null; globalToken=null; ApiService.clearLocalPresentationIdentity(); ApiService.farmerSession=false;
    }
  });
}
