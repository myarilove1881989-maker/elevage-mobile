import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:app_elevage/services/api_service.dart';
import 'unified_access_harness.dart';
void main() {
  setUp(() {SharedPreferences.setMockInitialValues({});tzdata.initializeTimeZones();});
  test('cash uses explicit mode and authenticated egg reference; mismatch cannot enqueue',() async {
    final h=UnifiedAccessHarness();await h.start();h.codes.add('cash.create');
    final runtime=await h.runtime();
    try {
      final api=await runtime.signIn('synthetic','1234');
      await h.db.replaceConfirmedCache('sales',[{'id':51,'entity_type':'VENTE_OEUFS','reference_id':91,'client_id':11,'montant_total':'20.00','reste_a_payer':'20.00','confirmed_business_revision':0}]);
      h.down=true;await runtime.connection.probe();
      await expectLater(api.createPayment(11,51,5),throwsA(anything));
      expect(await h.db.listOutbox(),isEmpty);
      await expectLater(api.createPayment(12,51,5,mode:'ESPECES'),throwsA(anything));
      expect(await h.db.listOutbox(),isEmpty);
      expect(await api.createPayment(11,51,5,mode:'ESPECES'),isTrue);
      await expectLater(api.createPayment(11,51,5,mode:'ESPECES'),throwsA(anything));
      expect((await h.db.listOutbox()).length,1);
      final original=(await h.db.listOutbox()).single.declaration;
      expect(original['entity_type'],'ENCAISSEMENT');
      expect(original['payload']['vente_ref'],{'server_id':91});
      expect(original['payload']['vente_type'],'VENTE_OEUFS');
      expect(original['payload']['montant_recu'],'5.00');
      expect(original['payload']['mode'],'ESPECES');
    } finally {
      runtime.dispose();await h.db.close();await h.directory.delete(recursive:true);
      ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();ApiService.farmerSession=false;
    }
  });
  test('new confirmed sale can be paid in the same session; no arbitrary reference accepted',() async {
    final h=UnifiedAccessHarness();await h.start();h.codes.add('cash.create');
    final runtime=await h.runtime();
    try {
      final api=await runtime.signIn('synthetic','1234');
      // This sale did not exist at login. The authenticated cache maps the legacy
      // financial sale to the egg sale reference required by signed V2 cash.
      h.serverSales=[{'id':51,'entity_type':'VENTE_OEUFS','reference_id':91,'client_id':11,
        'montant_total':'20.00','reste_a_payer':'20.00','confirmed_business_revision':0}];
      await expectLater(api.createPayment(12,51,5,mode:'ESPECES'),throwsA(anything));
      expect(await h.db.listOutbox(),isEmpty);
      expect(await api.createPayment(11,51,5,mode:'ESPECES'),isTrue);
      runtime.connection.pause();runtime.tablet.setForeground(false);
      await runtime.tablet.sync?.waitForIdle();
      final original=(await h.db.listOutbox()).single.declaration;
      expect(original['payload']['vente_ref'],{'server_id':91});
      expect(runtime.signedIn,isTrue);
      expect(h.onlineWrites,isEmpty);
      h.down=true;await runtime.connection.probe();
      await expectLater(api.createPayment(11,99,5,mode:'ESPECES'),throwsA(anything));
      expect((await h.db.listOutbox()).length,1);
    } finally {
      runtime.connection.pause();runtime.tablet.setForeground(false);
      await runtime.tablet.sync?.waitForIdle();runtime.dispose();
      await h.db.close();await h.directory.delete(recursive:true);
      ApiService.token=null;globalToken=null;ApiService.clearLocalPresentationIdentity();ApiService.farmerSession=false;
    }
  });

}
