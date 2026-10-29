import 'dart:async';
import 'expense_preparation.dart';
import 'expense_intention_session.dart';
import 'outbox.dart';

enum ExpenseDurableState {
  notRecorded,
  uncertain,
  durable,
  confirmed,
  reconciliation,
  notApplied,
}

enum ExpenseIntentionFailure {
  payloadChanged,
  suspended,
  unresolved,
  integrityMismatch,
  busy,
  invalidUuid,
}

class ExpenseIntentionException implements Exception {
  final ExpenseIntentionFailure code;
  const ExpenseIntentionException(this.code);
}

class ExpenseDurableResult {
  final ExpenseDurableState state;
  final OutboxEntry? entry;
  final String? issue;
  const ExpenseDurableResult(this.state, {this.entry, this.issue});
}

typedef ExpenseLedgerPageReader =
    Future<List<OutboxEntry>> Function({
      required int authorId,
      required int offset,
      required int limit,
    });

class ExpenseIntention {
  final String operationId;
  final ExpenseCapturedSession context;
  final PreparedExpense prepared;
  final String fingerprint;
  ExpenseDurableResult _result = const ExpenseDurableResult(
    ExpenseDurableState.notRecorded,
  );
  bool _suspended = false;
  Future<ExpenseDurableResult>? _active;
  bool _validationReserved = false;
  ExpenseIntention._(this.operationId, this.context, this.prepared)
    : fingerprint = _fingerprint(prepared);
  ExpenseDurableResult get result => _result;
  bool get suspended => _suspended;
  bool get busy => _active != null || _validationReserved;
}

String _fingerprint(PreparedExpense prepared) => canonicalDeclaration({
  'payload': prepared.payload,
  'business_occurred_at': prepared.businessOccurredAt.toIso8601String(),
  'dependencies': prepared.dependencies,
  'author_user_id': prepared.origin.authorId,
  'exploitation_id': prepared.origin.farmId,
});

/// In-memory coordinator. Exposes NO write callback, declare/enqueue method,
/// sequence generator or persistence. Only a future integration may submit.
class ExpenseIntentionCoordinator {
  final ExpenseSessionObservation Function() observe;
  final DateTime Function() utcClock;
  final String Function() _uuid;
  final Set<String> _usedIds = {};
  ExpenseIntention? _current;
  ExpenseIntentionCoordinator({
    required this.observe,
    required this.utcClock,
    String Function()? uuid,
  }) : _uuid = uuid ?? newOperationUuid;

  /// Draft contents are available only to the original, still-open context.
  ExpenseIntention? get current {
    final intention = _current;
    if (intention != null) {
      _guard(intention);
    }
    return intention;
  }

  /// Non-content recovery marker remains stable even while suspended.
  String? get pendingOperationId => _current?.operationId;

  ExpenseIntention begin(PreparedExpense prepared) {
    final existing = _current;
    if (existing != null) {
      _guard(existing, validation: true);
      if (existing.fingerprint != _fingerprint(prepared)) {
        throw const ExpenseIntentionException(
          ExpenseIntentionFailure.payloadChanged,
        );
      }
      return existing; // repeated clicks/retries retain the original UUID
    }
    final context = ExpenseCapturedSession.capture(observe(), utcClock());
    if (!context.matchesPreparation(prepared)) {
      throw const ExpenseSessionException(ExpenseSessionFailure.contextChanged);
    }
    final id = _uuid();
    if (!operationUuidPattern.hasMatch(id) ||
        id.length != 36 ||
        !_usedIds.add(id)) {
      throw const ExpenseIntentionException(
        ExpenseIntentionFailure.invalidUuid,
      );
    }
    return _current = ExpenseIntention._(id, context, prepared);
  }

  void _guard(ExpenseIntention intention, {bool validation = false}) {
    if (!identical(intention, _current) || intention._suspended) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.suspended);
    }
    try {
      if (validation) {
        intention.context.checkForValidation(observe(), utcClock());
      } else {
        intention.context.checkIdentity(observe());
      }
    } on ExpenseSessionException {
      intention._suspended = true;
      rethrow;
    }
  }

  /// Validates eligibility for a future integration; never executes it.
  /// An uncertain/known durable intention must first be explicitly resolved.
  ExpenseIntention validateForFutureDeclaration() {
    final intention = _current;
    if (intention == null) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.unresolved);
    }
    _guard(intention, validation: true);
    if (intention.busy ||
        intention.result.state != ExpenseDurableState.notRecorded) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.unresolved);
    }
    intention._validationReserved = true;
    return intention;
  }

  /// Explicit release ONLY while no submission has been attempted. After a
  /// possible write boundary the caller must use markUncertain instead.
  void releaseUnsubmittedValidation() {
    final intention = _current;
    if (intention == null ||
        intention._active != null ||
        intention.result.state != ExpenseDurableState.notRecorded) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.unresolved);
    }
    intention._validationReserved = false;
  }

  /// Marks an exception/boundary whose durable outcome cannot be established.
  /// It never allocates a replacement UUID or releases the intention.
  void markUncertain() {
    final intention = _current;
    if (intention == null || intention._active != null) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.busy);
    }
    if (intention.result.entry == null) {
      intention._result = const ExpenseDurableResult(
        ExpenseDurableState.uncertain,
      );
    }
    intention._validationReserved = false;
  }

  /// Single-flight read by original UUID/author. Empty pages from listOutbox
  /// cannot establish a transactional absence, so absence stays uncertain.
  Future<ExpenseDurableResult> inspect(
    ExpenseLedgerPageReader readPage, {
    int pageSize = 50,
  }) {
    final intention = _current;
    if (intention == null) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.unresolved);
    }
    _guard(intention);
    if (intention._active != null) return intention._active!;
    if (intention._validationReserved) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.busy);
    }
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    final completion = Completer<ExpenseDurableResult>();
    intention._active =
        completion.future; // set BEFORE the first async boundary
    final previous = intention.result;
    if (previous.entry == null) {
      intention._result = const ExpenseDurableResult(
        ExpenseDurableState.uncertain,
      );
    }
    () async {
      try {
        final result = await _search(intention, readPage, pageSize);
        _guard(intention);
        // Never downgrade an already known durable receipt due to a later
        // missing/partial/failing read. Conflicting rows remain explicit errors.
        intention._result = result.entry == null && previous.entry != null
            ? previous
            : result;
        completion.complete(intention.result);
      } catch (error) {
        if (error is ExpenseSessionException || intention.suspended) {
          intention._suspended = true;
          completion.completeError(error);
        } else {
          try {
            _guard(intention);
          } catch (contextError) {
            completion.completeError(contextError);
            return;
          }
          final issue = error is ExpenseIntentionException
              ? error.code.name
              : 'readFailed';
          if (previous.entry == null) {
            intention._result = ExpenseDurableResult(
              ExpenseDurableState.uncertain,
              issue: issue,
            );
          } else {
            intention._result = ExpenseDurableResult(
              previous.state,
              entry: previous.entry,
              issue: issue,
            );
          }
          completion.complete(intention.result);
        }
      } finally {
        intention._active = null;
      }
    }();
    return completion.future;
  }

  Future<ExpenseDurableResult> _search(
    ExpenseIntention intention,
    ExpenseLedgerPageReader readPage,
    int pageSize,
  ) async {
    var offset = 0;
    final seen = <String>{};
    while (true) {
      _guard(intention);
      final rows = await readPage(
        authorId: intention.context.authorId,
        offset: offset,
        limit: pageSize,
      );
      _guard(intention);
      if (rows.length > pageSize) {
        throw const ExpenseIntentionException(
          ExpenseIntentionFailure.integrityMismatch,
        );
      }
      if (rows.isEmpty) {
        return const ExpenseDurableResult(
          ExpenseDurableState.uncertain,
          issue: 'absenceNotProven',
        );
      }
      for (final row in rows) {
        if (!seen.add(row.operationId)) {
          throw const ExpenseIntentionException(
            ExpenseIntentionFailure.integrityMismatch,
          );
        }
        if (row.operationId == intention.operationId) {
          return _verify(intention, row);
        }
      }
      offset += rows.length; // short pages do not prove completeness
    }
  }

  /// Pure verification for an explicitly authorized original-context read.
  /// Does not resume, reassign or mutate an intention.
  ExpenseDurableResult verifyOriginalEntry(ExpenseIntention intention, OutboxEntry entry) =>
      _verify(intention, entry);

  ExpenseDurableResult _verify(ExpenseIntention intention, OutboxEntry entry) {
    final data = entry.declaration;
    final captured = intention.context;
    final expected = {
      'client_operation_id': intention.operationId,
      'author_user_id': captured.authorId,
      'author_membership_id': captured.membershipId,
      'exploitation_id': captured.farmId,
      'device_id': captured.deviceId,
      'device_generation': captured.generation,
      'offline_authorization_id': captured.grantId,
      'entity_type': 'DEPENSE',
      'operation_type': 'CREATE',
      'local_entity_id': intention.operationId,
    };
    final recorded = data['local_recorded_at'];
    final occurred = data['business_occurred_at'];
    if (expected.entries.any((e) => data[e.key] != e.value) ||
        data['local_sequence'] is! int ||
        (data['local_sequence'] as int) <= 0 ||
        recorded is! String ||
        DateTime.tryParse(recorded)?.isUtc != true ||
        occurred is! String ||
        DateTime.tryParse(occurred) != intention.prepared.businessOccurredAt ||
        canonicalDeclaration(data['payload']) !=
            canonicalDeclaration(intention.prepared.payload) ||
        canonicalDeclaration(data['dependencies']) !=
            canonicalDeclaration(intention.prepared.dependencies) ||
        (data.containsKey('rights_version') &&
            data['rights_version'] != captured.rightsVersion) ||
        !transportStates.contains(entry.transportStatus) ||
        !businessStates.contains(entry.businessStatus)) {
      throw const ExpenseIntentionException(
        ExpenseIntentionFailure.integrityMismatch,
      );
    }
    if (entry.businessStatus == 'CONFIRMED') {
      // Outbox metadata is populated by the existing receipt acceptor. B3
      // neither synthesizes receipts nor cryptographically re-verifies them.
      if (entry.transportStatus != 'SERVER_RECEIVED' ||
          entry.receivedAt == null ||
          entry.appliedAt == null ||
          entry.serverEntityId.isEmpty) {
        throw const ExpenseIntentionException(
          ExpenseIntentionFailure.integrityMismatch,
        );
      }
      return ExpenseDurableResult(ExpenseDurableState.confirmed, entry: entry);
    }
    if (entry.businessStatus == 'NEEDS_RECONCILIATION') {
      return ExpenseDurableResult(
        ExpenseDurableState.reconciliation,
        entry: entry,
      );
    }
    if ({'NOT_APPLIED', 'SUPERSEDED'}.contains(entry.businessStatus)) {
      return ExpenseDurableResult(ExpenseDurableState.notApplied, entry: entry);
    }
    return ExpenseDurableResult(ExpenseDurableState.durable, entry: entry);
  }

  /// Explicit separation between a resolved intention and a new expense.
  /// No automatic retry, discard or reassignment of an uncertain intention.
  void closeResolved() {
    final intention = _current;
    if (intention == null) return;
    if (intention.busy ||
        intention.result.state == ExpenseDurableState.uncertain) {
      throw const ExpenseIntentionException(ExpenseIntentionFailure.unresolved);
    }
    _current = null;
  }
}
