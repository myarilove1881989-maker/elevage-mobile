import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/widgets/operation_status.dart';
import 'package:app_elevage/offline/prepared_operation_policy.dart';
import 'offline_fine_permissions_test.dart' show fineGrant, syntheticNow;

void main() {
  const lab = String.fromEnvironment('APP_ENV')=='lab' && String.fromEnvironment('FLUTTER_APP_FLAVOR')=='lab';
  for(final seconds in [0,3,5,6]) {
    test('verify and permits: advance $seconds seconds; lab=$lab',() async {
      final time=syntheticNow.subtract(Duration(seconds:seconds));
      final expected=seconds==0 || (lab && seconds<=5);
      if(expected) {
        final g=await fineGrant(issuedAt:syntheticNow,now:time);
        expect(g.permits('can_create_terrain_operation',time),isTrue);
      } else {
        await expectLater(fineGrant(issuedAt:syntheticNow,now:time),throwsStateError);
      }
      final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow);
      expect(g.permits('can_create_terrain_operation',time),expected);
      expect(preparedOperationDecision(g,'CLIENT','CREATE',time),expected ? PreparedOperationDecision.allowed : PreparedOperationDecision.denied);
      expect(preparedOperationDecision(g,'CLIENT','CREATE',time,revoked:true),PreparedOperationDecision.denied);
    });
  }
  test('strict millisecond boundary: five seconds plus one millisecond refused',() async {
    final t=syntheticNow.subtract(const Duration(milliseconds:5001));
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t),throwsStateError);
    final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow);
    expect(g.permits('can_create_terrain_operation',t),isFalse);
  });
  test('expiry remains exact in verify and permits',() async {
    final end=syntheticNow.add(const Duration(hours:24));
    final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow);
    expect(g.permits('can_create_terrain_operation',end),isFalse);
    expect(g.permits('can_create_terrain_operation',end.subtract(const Duration(milliseconds:1))),isTrue);
    await expectLater(fineGrant(issuedAt:syntheticNow,now:end),throwsStateError);
  });
  test('signature and context remain mandatory inside tolerance',() async {
    final t=syntheticNow.subtract(Duration(seconds:lab?3:0));
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t,tamper:true),throwsStateError);
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t,expectedUser:3),throwsStateError);
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t,expectedFarm:2),throwsStateError);
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t,expectedGeneration:2),throwsStateError);
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t,changed:{'device_id':8}),throwsStateError);
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t,changed:{'rights_version':99}),throwsStateError);
    await expectLater(fineGrant(issuedAt:syntheticNow,now:t,duration:const Duration(hours:169)),throwsStateError);
  });
  test('LAB exception cannot apply on another platform',() async {
    debugDefaultTargetPlatformOverride=TargetPlatform.windows;
    try {
      await expectLater(fineGrant(issuedAt:syntheticNow,now:syntheticNow.subtract(const Duration(seconds:3))),throwsStateError);
      final g=await fineGrant(issuedAt:syntheticNow,now:syntheticNow);
      expect(g.permits('can_create_terrain_operation',syntheticNow.subtract(const Duration(seconds:3))),isFalse);
    } finally {debugDefaultTargetPlatformOverride=null;}
  });
  test('invalid authorization message exposes no internal detail',() {
    expect(tabletErrorMessage(StateError('Autorisation hors ligne invalide ou expirée.')),'Autorisation hors ligne invalide ou expirée.');
    expect(tabletErrorMessage(StateError('private internal detail')),'Action indisponible. Les données déjà enregistrées restent conservées.');
  });
}
