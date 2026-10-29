import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/local_operator_session.dart';
import 'offline_fine_permissions_test.dart' show fineGrant,syntheticNow;
import 'foundation_api_test.dart' show TestSecretStore;
void main() {
  const lab=String.fromEnvironment('APP_ENV')=='lab' && String.fromEnvironment('FLUTTER_APP_FLAVOR')=='lab';
  for(final ms in [0,3000,5000,5001,6000]) {
    test('PIN enrollment respects identical time boundary $ms ms; lab=$lab',() async {
      final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow);
      final store=TestSecretStore();
      final sessions=LocalOperatorSessions(store:store,namespace:'lab-pin-boundary',farmId:1,deviceId:7,generation:1,
        clock:()=>syntheticNow.subtract(Duration(milliseconds:ms)));
      final allowed=ms==0 || lab && ms<=5000;
      if(allowed) {
        await sessions.enroll(g,'983671');
        expect(store.values.length,1);
        expect(await sessions.unlock(g,'983671'),isTrue);
      } else {
        await expectLater(sessions.enroll(g,'983671'),throwsStateError);
        expect(store.values,isEmpty);
        await expectLater(sessions.unlock(g,'983671'),throwsStateError);
      }
    });
  }
  test('PIN enrollment never accepts expired or cross-device grants',() async {
    final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow);
    for(final otherDevice in [false,true]) {
      final store=TestSecretStore();
      final sessions=LocalOperatorSessions(store:store,namespace:'lab-pin-boundary',farmId:1,deviceId:otherDevice?8:7,generation:1,
        clock:()=>otherDevice?syntheticNow:syntheticNow.add(const Duration(hours:24)));
      await expectLater(sessions.enroll(g,'983671'),throwsStateError);
      expect(store.values,isEmpty);
    }
  });
}
