import 'package:flutter_test/flutter_test.dart';
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;

void main() {
  test('signed authorization with synchronized clocks is accepted', () async {
    final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow);
    expect(g.userId,2);
  });
  test('three second client lag is currently refused', () async {
    await expectLater(fineGrant(issuedAt:syntheticNow,now:syntheticNow.subtract(const Duration(seconds:3))),throwsStateError);
  });
  test('three second client lead is accepted', () async {
    final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow.add(const Duration(seconds:3)));
    expect(g.userId,2);
  });
  test('genuinely future issuance is refused', () async {
    await expectLater(fineGrant(issuedAt:syntheticNow.add(const Duration(minutes:5))),throwsStateError);
  });
  test('expired signed authorization is refused at expiry', () async {
    await expectLater(fineGrant(issuedAt:syntheticNow.subtract(const Duration(hours:24)),duration:const Duration(hours:24)),throwsStateError);
  });
  test('invalid signature is refused', () async {
    await expectLater(fineGrant(tamper:true),throwsStateError);
  });
  test('other user is refused', () async {
    await expectLater(fineGrant(expectedUser:3),throwsStateError);
  });
  test('other signed device is refused', () async {
    await expectLater(fineGrant(changed:{'device_id':8}),throwsStateError);
  });
  test('other farm is refused', () async {
    await expectLater(fineGrant(expectedFarm:2),throwsStateError);
  });
  test('other generation is refused', () async {
    await expectLater(fineGrant(expectedGeneration:2),throwsStateError);
  });
  test('other signed rights version is refused', () async {
    await expectLater(fineGrant(changed:{'rights_version':2}),throwsStateError);
  });
}
