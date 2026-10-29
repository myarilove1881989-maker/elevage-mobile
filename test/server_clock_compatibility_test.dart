import 'package:flutter_test/flutter_test.dart';
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;
void main() {
  test('Android107 rejects a fresh grant when tablet lags 1.2 seconds', () async {
    await expectLater(fineGrant(credentialVersion:2, issuedAt:syntheticNow,
      now:syntheticNow.subtract(const Duration(milliseconds:1200)),
      duration:const Duration(days:7)), throwsStateError);
  });
  test('signed five second margin works without widening expiry or signature checks', () async {
    final tabletNow=syntheticNow.subtract(const Duration(milliseconds:1200));
    final grant=await fineGrant(credentialVersion:2,
      issuedAt:syntheticNow.subtract(const Duration(seconds:5)),now:tabletNow,
      duration:const Duration(days:7));
    expect(grant.validAt(tabletNow),isTrue);
    expect(grant.claims['exp']-grant.claims['iat'],7*86400);
    expect(grant.validAt(grant.expiresAt),isFalse);
    await expectLater(fineGrant(credentialVersion:2,tamper:true,
      issuedAt:syntheticNow.subtract(const Duration(seconds:5)),now:tabletNow,
      duration:const Duration(days:7)),throwsStateError);
  });
}
