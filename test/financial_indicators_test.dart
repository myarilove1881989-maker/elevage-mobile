import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/services/financial_indicators.dart';
void main() {
  test('money ratio ignores legacy purchase quantity and legacy margin',() {
    expect(operatingBalanceRate({'chiffre_affaires':100,'depenses':40,'performance':999,'marge':-100}),60);
    expect(operatingBalanceRate({'chiffre_affaires':'100.00','depenses':'140.00'}),-40);
  });
  test('zero, missing and non-finite revenue do not imply a zero percent profit',() {
    for(final value in [null,0,-1,double.infinity,double.nan]) {
      expect(operatingBalanceRate({'chiffre_affaires':value,'depenses':40}),isNull);
    }
    expect(operatingBalanceRate({'chiffre_affaires':100}),isNull);
  });
}
