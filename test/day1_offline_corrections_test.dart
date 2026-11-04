import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_elevage/services/api_service.dart';
import 'package:app_elevage/services/egg_collection_version.dart';
import 'unified_access_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp((){SharedPreferences.setMockInitialValues({});tz.initializeTimeZones();});
  tearDown((){ApiService.token=null;globalToken=null;ApiService.farmerSession=false;ApiService.clearLocalPresentationIdentity();});
  test('synced weights are prepared before first visit and survive cold offline login',() async {
    final h=UnifiedAccessHarness();await h.start();var runtime=await h.runtime();
    try {
      await h.db.replaceConfirmedCache('lots',[{'id':7,'nom':'Chair','stock':10,'type_production':'CHAIR'}]);
      await runtime.signIn('synthetic','1234');
      expect(h.preparedReads.any((p)=>p.endsWith('/production/pesees/?lot=7')),true);
      runtime.dispose();await h.db.close();h.db=h.openDatabase();h.down=true;
      await h.controller();runtime=await h.runtime();final api=await runtime.signIn('synthetic','1234');
      expect((await api.getProductionWeights(7))['pesees'].single['id'],17);
      expect(api.lastReadWasCached,true);
    } finally {runtime.dispose();await h.db.close();await h.directory.delete(recursive:true);}
  });
  test('offline egg creation, reopening and correction keep original and project only delta',() async {
    final h=UnifiedAccessHarness()..codes=[...rights,'egg_collections.create','egg_collections.update'];
    await h.start();var runtime=await h.runtime();
    try {
      await h.db.replaceConfirmedCache('lots',[{'id':7,'nom':'Ponte','stock':150,'stock_oeufs':0,'type_production':'OEUFS'}]);
      final api=await runtime.signIn('synthetic','1234');h.down=true;await runtime.connection.probe();
      await h.db.customStatement("DELETE FROM screen_snapshots WHERE path='/lots/7/'");
      expect((await api.getLotDetail(7))['offline_summary_only'],true);
      await api.createEggCollection(lotId:7,collectedAt:DateTime.now(),total:120,broken:3);
      final collection=Map<String,dynamic>.from((await api.getEggCollections(7)).single as Map);
      expect(collection['nombre_commercialisable'],117);
      expect((await api.getLotDetail(7))['projected_egg_stock'],117);
      await api.updateEggCollection(collection,{...eggValues(collection),'nombre_collecte':110});
      final rows=await h.db.listOutbox(authorId:2);expect(rows.length,2);
      expect(rows.first.declaration['operation_type'],'UPDATE');
      expect(rows.first.declaration['dependencies'],[rows.last.operationId]);
      expect(rows.last.declaration['payload']['nombre_collecte'],120);
      expect((await api.getEggCollections(7)).single['nombre_collecte'],110);
      expect((await api.getLotDetail(7))['projected_egg_stock'],107);
      expect(h.onlineWrites,isEmpty);
      runtime.dispose();await h.db.close();h.db=h.openDatabase();await h.controller();runtime=await h.runtime();
      final restored=await runtime.signIn('synthetic','1234');
      expect((await restored.getEggCollections(7)).single['nombre_collecte'],110);
      expect((await restored.getLotDetail(7))['projected_egg_stock'],107);
      Map<String,dynamic> receipt(entry,int quantity,int revision)=>{
        'client_operation_id':entry.operationId,'author_user_id':2,
        'transport_status':'SERVER_RECEIVED','business_status':'CONFIRMED',
        'received_at':h.now.toIso8601String(),'applied_at':h.now.toIso8601String(),
        'server_entity_id':'90','server_version':'farm:$revision','reason_code':'',
        'stock_snapshots':[{'id':7,'nom':'Ponte','exploitation':1,'stock':150,
          'stock_oeufs':quantity,'confirmed_business_revision':revision}]};
      final originalReceipt=receipt(rows.last,117,1),updatedReceipt=receipt(rows.first,107,2);
      await h.db.acceptReceipts([originalReceipt]);
      expect((await restored.getLotDetail(7))['projected_egg_stock'],107);
      await h.db.acceptReceipts([updatedReceipt]);
      expect((await restored.getLotDetail(7))['projected_egg_stock'],107);
      await h.db.acceptReceipts([originalReceipt,updatedReceipt]);
      expect((await restored.getLotDetail(7))['projected_egg_stock'],107);
      expect((await restored.getEggCollections(7)).length,1);

    } finally {runtime.dispose();await h.db.close();await h.directory.delete(recursive:true);}
  });
}
