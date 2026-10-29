/// Pure DEPENSE/CREATE field contract. Dates, dependencies and authorization
/// belong to the caller; this component never persists or submits an operation.
enum ExpenseInputError {
  required,
  invalid,
  precision,
  nonPositive,
  tooLarge,
  tooLong,
}

class ExpenseInputResult {
  final Map<String, Object>? payload;
  final Map<String, ExpenseInputError> errors;

  ExpenseInputResult._(this.payload, Map<String, ExpenseInputError> errors)
    : errors = Map.unmodifiable(errors);

  bool get isValid => payload != null;
}

class ExpenseInputContract {
  static final _amount = RegExp(r'^([0-9]+)(?:[.,]([0-9]+))?$');
  static final _uuid = RegExp(
    r'^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
  );
  // Python str.strip(), used by DRF CharField. No NFC/NFD transformation.
  static final _edgeWhitespace = RegExp(
    r'^[\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+|[\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+$',
  );
  static final _maximum = BigInt.parse('999999999999');

  static ExpenseInputResult validate({
    Map<String, Object?>? lotRef,
    Object? categoryId,
    required String amount,
    String? note,
  }) {
    final errors = <String, ExpenseInputError>{};
    Map<String, Object>? lot;
    if (lotRef == null || lotRef.isEmpty) {
      errors['lot_ref'] = ExpenseInputError.required;
    } else if (lotRef.length == 1 &&
        lotRef.containsKey('server_id') &&
        lotRef['server_id'] is int &&
        (lotRef['server_id'] as int) > 0) {
      lot = Map.unmodifiable({'server_id': lotRef['server_id'] as int});
    } else if (lotRef.length == 1 &&
        lotRef.containsKey('local_uuid') &&
        lotRef['local_uuid'] is String &&
        _uuid.hasMatch(lotRef['local_uuid'] as String)) {
      final hex = (lotRef['local_uuid'] as String)
          .replaceAll('-', '')
          .toLowerCase();
      lot = Map.unmodifiable({
        'local_uuid':
            '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}',
      });
    } else {
      errors['lot_ref'] = ExpenseInputError.invalid;
    }
    if (categoryId == null) {
      errors['categorie_id'] = ExpenseInputError.required;
    } else if (categoryId is! int || categoryId <= 0) {
      errors['categorie_id'] = ExpenseInputError.invalid;
    }

    String? canonical;
    final match = _amount.firstMatch(amount);
    if (amount.isEmpty) {
      errors['montant'] = ExpenseInputError.required;
    } else if (match == null || match.end != amount.length) {
      errors['montant'] = ExpenseInputError.invalid;
    } else {
      final fraction = match.group(2) ?? '';
      if (fraction.length > 2) {
        errors['montant'] = ExpenseInputError.precision;
      } else {
        final units =
            BigInt.parse(match.group(1)!) * BigInt.from(100) +
            BigInt.parse(fraction.padRight(2, '0'));
        if (units <= BigInt.zero) {
          errors['montant'] = ExpenseInputError.nonPositive;
        } else if (units > _maximum) {
          errors['montant'] = ExpenseInputError.tooLarge;
        } else {
          canonical =
              '${units ~/ BigInt.from(100)}.${(units % BigInt.from(100)).toString().padLeft(2, '0')}';
        }
      }
    }
    final normalizedNote = (note ?? '').replaceAll(_edgeWhitespace, '');
    // Dart strings are UTF-16; unpaired surrogates are not valid Unicode.
    if (!_validUnicode(normalizedNote) || normalizedNote.contains('\u0000')) {
      errors['note'] = ExpenseInputError.invalid;
    } else if (normalizedNote.runes.length > 255) {
      errors['note'] = ExpenseInputError.tooLong;
    }
    if (errors.isNotEmpty) {
      return ExpenseInputResult._(null, errors);
    }
    return ExpenseInputResult._(
      Map.unmodifiable({
        'lot_ref': lot!,
        'categorie_id': categoryId as int,
        'montant': canonical!,
        'note': normalizedNote,
      }),
      errors,
    );
  }

  static bool _validUnicode(String value) {
    final units = value.codeUnits;
    for (var i = 0; i < units.length; i++) {
      if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          return false;
        }
      } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
        return false;
      }
    }
    return true;
  }
}
