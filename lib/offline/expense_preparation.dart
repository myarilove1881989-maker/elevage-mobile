import 'expense_business_date.dart';
import 'expense_input_contract.dart';

enum ExpensePreparationError {
  invalidReference,
  foreignContext,
  invalidParent,
  missingCategory,
  invalidCache,
  changedContext,
  invalidInput,
}

class ExpensePreparationException implements Exception {
  final ExpensePreparationError code;
  final Map<String, ExpenseInputError> fieldErrors;
  ExpensePreparationException(
    this.code, [
    Map<String, ExpenseInputError> errors = const {},
  ]) : fieldErrors = Map.unmodifiable(errors);
}

/// Selection provenance only, never an authorization or a session token.
class ExpenseSelectionContext {
  final int farmId;
  final int authorId;
  const ExpenseSelectionContext._(this.farmId, this.authorId);
  factory ExpenseSelectionContext({
    required int farmId,
    required int authorId,
  }) {
    if (farmId <= 0 || authorId <= 0) {
      throw ExpensePreparationException(ExpensePreparationError.foreignContext);
    }
    return ExpenseSelectionContext._(farmId, authorId);
  }
  bool matches(ExpenseSelectionContext other) =>
      farmId == other.farmId && authorId == other.authorId;
}

void _sameContext(
  ExpenseSelectionContext origin,
  ExpenseSelectionContext current,
) {
  if (!origin.matches(current)) {
    throw ExpensePreparationException(ExpensePreparationError.foreignContext);
  }
}

void _knownFarm(Map data, ExpenseSelectionContext origin) {
  for (final key in ['exploitation', 'exploitation_id']) {
    if (data.containsKey(key) && data[key] != origin.farmId) {
      throw ExpensePreparationException(ExpensePreparationError.foreignContext);
    }
  }
}

String _uuid(Object? value) {
  if (value is! String) {
    throw ExpensePreparationException(ExpensePreparationError.invalidReference);
  }
  final result = ExpenseInputContract.validate(
    lotRef: {'local_uuid': value},
    categoryId: 1,
    amount: '1',
  );
  if (!result.isValid) {
    throw ExpensePreparationException(ExpensePreparationError.invalidReference);
  }
  return (result.payload!['lot_ref'] as Map)['local_uuid'] as String;
}

class ExpenseLotSelection {
  final ExpenseSelectionContext origin;
  final Map<String, Object> reference;
  final List<String> dependencies;
  final String name;
  final String state;
  final bool isFinished;
  final String? originatingEntityType;
  ExpenseLotSelection._(
    this.origin,
    Map<String, Object> reference,
    List<String> dependencies,
    this.name,
    this.state,
    this.isFinished,
    this.originatingEntityType,
  ) : reference = Map.unmodifiable(reference),
      dependencies = List.unmodifiable(dependencies);

  /// Adapts the existing projectedPage('lots') shape. A local lot requires its
  /// ORIGINAL creator declaration to establish author/farm and dependency.
  factory ExpenseLotSelection.fromProjectedRow(
    Map<String, dynamic> row, {
    required ExpenseSelectionContext origin,
    Map<String, dynamic>? parentDeclaration,
    int? deviceId,
    int? generation,
  }) {
    final raw = row['data'];
    if (raw is! Map ||
        raw['nom'] is! String ||
        (raw['nom'] as String).isEmpty) {
      throw ExpensePreparationException(
        ExpensePreparationError.invalidReference,
      );
    }
    _knownFarm(raw, origin);
    final state = row['state'];
    if (state is! String) {
      throw ExpensePreparationException(
        ExpensePreparationError.invalidReference,
      );
    }
    final finished = raw['statut'] == 'TERMINE' || raw['date_fin'] != null;
    if (raw['id'] is int && (raw['id'] as int) > 0) {
      if (!{
            'CONFIRMED',
            'CONFIRMED_CACHE',
            'NEEDS_RECONCILIATION',
          }.contains(state) ||
          row['dependency'] != null) {
        throw ExpensePreparationException(
          ExpensePreparationError.invalidReference,
        );
      }
      // A mapping hint local_uuid may exist on a confirmed row. It does not
      // mutate any earlier local selection or declaration.
      return ExpenseLotSelection._(
        origin,
        {'server_id': raw['id'] as int},
        [],
        raw['nom'] as String,
        state,
        finished,
        null,
      );
    }
    final localId = _uuid(raw['id']);
    if (_uuid(row['local_uuid']) != localId ||
        !{
          'UNREVIEWED',
          'WAITING_DEPENDENCY',
          'NEEDS_RECONCILIATION',
        }.contains(state) ||
        parentDeclaration == null) {
      throw ExpensePreparationException(ExpensePreparationError.invalidParent);
    }
    final parentId = _uuid(parentDeclaration['client_operation_id']);
    if (_uuid(row['dependency']) != parentId ||
        _uuid(parentDeclaration['local_entity_id']) != localId ||
        parentDeclaration['operation_type'] != 'CREATE' ||
        !{'ACHAT', 'NAISSANCE'}.contains(parentDeclaration['entity_type'])) {
      throw ExpensePreparationException(ExpensePreparationError.invalidParent);
    }
    final author = parentDeclaration['author_user_id'];
    final sharedDevice =
        deviceId != null &&
        deviceId > 0 &&
        generation != null &&
        generation > 0 &&
        parentDeclaration['device_id'] == deviceId &&
        parentDeclaration['device_generation'] == generation;
    if (parentDeclaration['exploitation_id'] != origin.farmId ||
        author is! int ||
        author <= 0 ||
        ((deviceId != null ||
                generation != null ||
                author != origin.authorId) &&
            !sharedDevice)) {
      throw ExpensePreparationException(ExpensePreparationError.foreignContext);
    }
    final payload = parentDeclaration['payload'];
    if (payload is! Map) {
      throw ExpensePreparationException(ExpensePreparationError.invalidParent);
    }
    final type = parentDeclaration['entity_type'] as String;
    if (type == 'ACHAT') {
      if (payload['quantite'] is! int || (payload['quantite'] as int) <= 0) {
        throw ExpensePreparationException(
          ExpensePreparationError.invalidParent,
        );
      }
    } else {
      if (payload['total_naissances'] is! int ||
          payload['mort_nes'] is! int ||
          (payload['mort_nes'] as int) < 0 ||
          (payload['total_naissances'] as int) <=
              (payload['mort_nes'] as int)) {
        throw ExpensePreparationException(
          ExpensePreparationError.invalidParent,
        );
      }
    }
    return ExpenseLotSelection._(
      origin,
      {'local_uuid': localId},
      [parentId],
      raw['nom'] as String,
      state,
      finished,
      type,
    );
  }
}

enum ExpenseCacheFreshness { current, stale, unknown }

class ExpenseCategorySelection {
  final ExpenseSelectionContext origin;
  final int id;
  final String name;
  ExpenseCategorySelection._(this.origin, this.id, this.name);
}

typedef ExpenseCachedPageReader =
    Future<List<Map<String, dynamic>>> Function(
      String collection, {
      required int offset,
      required int limit,
    });

class ExpenseCategoryCatalog {
  final ExpenseSelectionContext origin;
  final ExpenseCacheFreshness freshness;
  final List<ExpenseCategorySelection> categories;
  ExpenseCategoryCatalog._(
    this.origin,
    this.freshness,
    List<ExpenseCategorySelection> categories,
  ) : categories = List.unmodifiable(categories);
  bool get isEmpty => categories.isEmpty;
  bool get needsFreshnessNotice => freshness != ExpenseCacheFreshness.current;

  ExpenseCategorySelection select(int id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    // Never choose a replacement for a disappeared or absent category.
    throw ExpensePreparationException(ExpensePreparationError.missingCategory);
  }

  /// Read-only adapter over the existing expense_categories collection.
  /// Freshness is supplied explicitly: received_at alone cannot establish TTL.
  /// Continue until an EMPTY page, including after a short page.
  static Future<ExpenseCategoryCatalog> readAll({
    required ExpenseCachedPageReader readPage,
    required ExpenseSelectionContext origin,
    required ExpenseSelectionContext Function() currentContext,
    required ExpenseCacheFreshness freshness,
    int pageSize = 50,
  }) async {
    if (pageSize < 1 || pageSize > 200) {
      throw ExpensePreparationException(ExpensePreparationError.invalidCache);
    }
    final categories = <ExpenseCategorySelection>[];
    final ids = <int>{};
    var offset = 0;
    while (true) {
      if (!origin.matches(currentContext())) {
        throw ExpensePreparationException(
          ExpensePreparationError.changedContext,
        );
      }
      final rows = await readPage(
        'expense_categories',
        offset: offset,
        limit: pageSize,
      );
      if (!origin.matches(currentContext())) {
        throw ExpensePreparationException(
          ExpensePreparationError.changedContext,
        );
      }
      if (rows.length > pageSize) {
        throw ExpensePreparationException(ExpensePreparationError.invalidCache);
      }
      if (rows.isEmpty) break;
      for (final row in rows) {
        final data = row['data'];
        if (data is! Map ||
            data['id'] is! int ||
            (data['id'] as int) <= 0 ||
            data['nom'] is! String ||
            (data['nom'] as String).isEmpty ||
            !ids.add(data['id'] as int)) {
          throw ExpensePreparationException(
            ExpensePreparationError.invalidCache,
          );
        }
        _knownFarm(data, origin);
        categories.add(
          ExpenseCategorySelection._(
            origin,
            data['id'] as int,
            data['nom'] as String,
          ),
        );
      }
      offset += rows.length;
    }
    return ExpenseCategoryCatalog._(origin, freshness, categories);
  }
}

class PreparedExpense {
  final ExpenseSelectionContext origin;
  final Map<String, Object> payload;
  final DateTime businessOccurredAt;
  final List<String> dependencies;
  final ExpenseLotSelection lot;
  final ExpenseCategorySelection category;
  final ExpenseCacheFreshness categoryCacheFreshness;
  PreparedExpense._(
    this.origin,
    this.payload,
    this.businessOccurredAt,
    List<String> dependencies,
    this.lot,
    this.category,
    this.categoryCacheFreshness,
  ) : dependencies = List.unmodifiable(dependencies);
}

class ExpensePreparation {
  static PreparedExpense compose({
    required ExpenseSelectionContext currentContext,
    required ExpenseLotSelection lot,
    required ExpenseCategoryCatalog categories,
    required int categoryId,
    required String amount,
    String? note,
    required ExpenseBusinessDay day,
    required ExpenseBusinessDate dates,
    required DateTime nowUtc,
  }) {
    _sameContext(lot.origin, currentContext);
    _sameContext(categories.origin, currentContext);
    final category = categories.select(categoryId);
    final validated = ExpenseInputContract.validate(
      lotRef: lot.reference,
      categoryId: category.id,
      amount: amount,
      note: note,
    );
    if (!validated.isValid) {
      throw ExpensePreparationException(
        ExpensePreparationError.invalidInput,
        validated.errors,
      );
    }
    dates.representativeUtc(day, nowUtc: nowUtc);
    final occurred = nowUtc;
    return PreparedExpense._(
      lot.origin,
      validated.payload!,
      occurred,
      lot.dependencies,
      lot,
      category,
      categories.freshness,
    );
  }
}
