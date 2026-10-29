import 'package:flutter_test/flutter_test.dart';
import 'package:app_elevage/offline/expense_input_contract.dart';

void main() {
  ExpenseInputResult valid(String amount, {String? note}) =>
      ExpenseInputContract.validate(
        lotRef: {'server_id': 17},
        categoryId: 4,
        amount: amount,
        note: note,
      );
  for (final entry in {
    '1': '1.00',
    '1,5': '1.50',
    '1.50': '1.50',
    '0,01': '0.01',
    '9999999999,99': '9999999999.99',
    '00012.3': '12.30',
    '9007199254.73': '9007199254.73',
    '0.1': '0.10',
  }.entries) {
    test('exact amount ${entry.key}', () {
      final result = valid(entry.key);
      expect(result.errors, isEmpty);
      expect(result.payload!['montant'], entry.value);
    });
  }
  for (final input in [
    '',
    '10000000000',
    '9999999999.999',
    '1,999',
    '0',
    '0.00',
    '-10',
    '+1',
    '1e3',
    'NaN',
    'Infinity',
    '1 000',
    '1\u00a0000',
    '1,000.50',
    '1.000,50',
    ' 1',
    '1 ',
    '1\n',
    '.5',
    '1.',
    '1,',
    '１',
    '1_000',
    '1\t2',
  ]) {
    test('reject amount $input', () {
      final result = valid(input);
      expect(result.isValid, isFalse);
      expect(result.payload, isNull);
      expect(result.errors.keys, ['montant']);
    });
  }
  test('precise error types', () {
    expect(valid('1.999').errors['montant'], ExpenseInputError.precision);
    expect(valid('0').errors['montant'], ExpenseInputError.nonPositive);
    expect(valid('10000000000').errors['montant'], ExpenseInputError.tooLarge);
  });
  test('required fields and simultaneous errors', () {
    final result = ExpenseInputContract.validate(amount: '0');
    expect(result.errors, {
      'lot_ref': ExpenseInputError.required,
      'categorie_id': ExpenseInputError.required,
      'montant': ExpenseInputError.nonPositive,
    });
  });
  for (final id in [0, -1, 1.0, '17', true]) {
    test('invalid identifiers $id (${id.runtimeType})', () {
      final result = ExpenseInputContract.validate(
        lotRef: {'server_id': id},
        categoryId: id,
        amount: '1',
      );
      expect(result.errors.keys, containsAll(['lot_ref', 'categorie_id']));
    });
  }
  for (final ref in <Map<String, Object?>>[
    {},
    {'server_id': 17, 'local_uuid': '12345678-1234-1234-1234-123456789abc'},
    {'other': 1},
    {'local_uuid': 'bad'},
    {'local_uuid': null},
    {'local_uuid': '12345678-1234-1234-1234-123456789abc\n'},
  ]) {
    test('reject reference $ref', () {
      expect(
        ExpenseInputContract.validate(
          lotRef: ref,
          categoryId: 4,
          amount: '1',
        ).errors,
        contains('lot_ref'),
      );
    });
  }
  test('canonical local UUID; no dependencies or dates', () {
    final result = ExpenseInputContract.validate(
      lotRef: {'local_uuid': '12345678123412341234123456789ABC'},
      categoryId: 4,
      amount: '1',
    );
    expect(result.payload, {
      'lot_ref': {'local_uuid': '12345678-1234-1234-1234-123456789abc'},
      'categorie_id': 4,
      'montant': '1.00',
      'note': '',
    });
  });
  test('exact payload and immutable nested values', () {
    final ref = <String, Object?>{'server_id': 17};
    final result = ExpenseInputContract.validate(
      lotRef: ref,
      categoryId: 4,
      amount: '1234,50',
      note: ' Transport ',
    );
    ref['server_id'] = 99;
    expect(result.payload, {
      'lot_ref': {'server_id': 17},
      'categorie_id': 4,
      'montant': '1234.50',
      'note': 'Transport',
    });
    expect(() => result.payload!['date'] = 'x', throwsUnsupportedError);
    expect(
      () => (result.payload!['lot_ref'] as Map)['server_id'] = 99,
      throwsUnsupportedError,
    );
    expect(
      () => result.errors['date'] = ExpenseInputError.invalid,
      throwsUnsupportedError,
    );
  });
  test('optional note and DRF whitespace semantics', () {
    expect(valid('1').payload!['note'], '');
    expect(
      valid('1', note: '\u0085\u001c Transport \u3000').payload!['note'],
      'Transport',
    );
    expect(valid('1', note: '\ufeff').payload!['note'], '\ufeff');
    expect(valid('1', note: 'a\nb').payload!['note'], 'a\nb');
  });
  test('255 Unicode code points, no grapheme or UTF16 counting', () {
    expect(valid('1', note: 'é' * 255).isValid, isTrue);
    expect(valid('1', note: '😀' * 255).isValid, isTrue);
    expect(
      valid('1', note: 'é' * 256).errors['note'],
      ExpenseInputError.tooLong,
    );
    expect(
      valid('1', note: '😀' * 256).errors['note'],
      ExpenseInputError.tooLong,
    );
    expect(valid('1', note: '${'e\u0301' * 127}x').isValid, isTrue);
    expect(
      valid('1', note: 'e\u0301' * 128).errors['note'],
      ExpenseInputError.tooLong,
    );
    expect(valid('1', note: 'e\u0301').payload!['note'], 'e\u0301');
    expect(valid('1', note: 'Élev’Age 👨‍👩‍👧‍👦').isValid, isTrue);
  });
  test('invalid Unicode and NUL rejected', () {
    for (final note in ['\u0000', '\ud800', '\udc00', '\ud800a']) {
      expect(valid('1', note: note).errors['note'], ExpenseInputError.invalid);
    }
  });
}
