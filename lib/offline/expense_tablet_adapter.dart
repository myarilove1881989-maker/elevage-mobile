import 'expense_consistent_catalog.dart';
import 'expense_intention.dart';
import 'expense_intention_session.dart';
import 'expense_preparation.dart';
import 'farm_cache.dart';
import 'outbox.dart';
import 'tablet_controller.dart';

/// Reads existing sources only; never prepares a profile/grant or opens a PIN.
class ExpenseTabletSessionObserver {
  final TabletController tablet;
  List<Object?>? _last;
  int _epoch = 0;
  ExpenseTabletSessionObserver(this.tablet);

  ExpenseSessionObservation observe() {
    final operators = tablet.operators;
    final personal = operators?.session; // existing expiry/clock-floor guard
    final grant = personal?.grant;
    final http = tablet.api.personal;
    final matches = grant == null
        ? <Map<String, dynamic>>[]
        : tablet.profiles.where((p) => p['user_id'] == grant.userId).toList();
    final profile = matches.length == 1 ? matches.single : null;
    final membership = http?.capabilities['membership'];
    final profileValid =
        grant != null &&
        profile != null &&
        profile['membership_id'] == grant.claims['membership_id'] &&
        profile['rights_version'] == grant.rightsVersion &&
        profile['write_generation'] == grant.generation &&
        profile['display_name'] is String &&
        profile['display_name'] == tablet.selectedName;
    // Offline PIN sessions need no HTTP connection. An HTTP identity, if
    // present, must not conflict with the explicitly opened personal profile.
    final httpValid =
        http == null ||
        (grant != null &&
            http.role == 'OPERATEUR' &&
            http.userId == grant.userId &&
            http.farmId == grant.farmId &&
            membership is Map &&
            membership['id'] == grant.claims['membership_id'] &&
            membership['version'] == grant.rightsVersion &&
            membership['is_active'] != false);
    final valid =
        !tablet.isDisposed &&
        profileValid &&
        httpValid &&
        tablet.cache != null &&
        operators != null &&
        tablet.farmId == grant.farmId &&
        tablet.deviceId == grant.deviceId &&
        tablet.generation == grant.generation &&
        operators.farmId == grant.farmId &&
        operators.deviceId == grant.deviceId &&
        operators.generation == grant.generation;
    final vector = <Object?>[
      tablet.sessionEpoch,
      tablet.api.personalEpoch,
      operators?.sessionEpoch,
      operators,
      personal,
      http,
      profile,
      tablet.cache,
      tablet.farmId,
      tablet.deviceId,
      tablet.generation,
      tablet.selectedName,
      tablet.knownDeviceRevoked,
      tablet.recovering,
      tablet.isDisposed,
      profile == null ? null : canonicalDeclaration(profile),
      membership is Map ? canonicalDeclaration(membership) : null,
    ];
    if (_last == null ||
        _last!.length != vector.length ||
        List.generate(
          vector.length,
          (i) => i,
        ).any((i) => _last![i] != vector[i])) {
      _epoch++;
      _last = List.unmodifiable(vector);
    }
    return ExpenseSessionObservation(
      personalSession: personal,
      preparedProfileIdentity: profile,
      cacheIdentity: tablet.cache,
      farmId: tablet.farmId ?? 0,
      deviceId: tablet.deviceId ?? 0,
      generation: tablet.generation ?? 0,
      epoch: _epoch,
      explicitlyPrepared: valid,
      pinUnlocked: personal != null,
      revoked: tablet.knownDeviceRevoked,
      recovering: tablet.recovering,
    );
  }

  ExpenseCapturedSession capture() =>
      ExpenseCapturedSession.capture(observe(), tablet.clock().toUtc());
}

/// Trusted register/cache read adapters. Captures the actual store identity,
/// never the UI's bounded outboxRows list. No write/store interface is exposed.
class ExpenseTabletReadBridge {
  final ExpenseTabletSessionObserver observer;
  final ExpenseCapturedSession captured;
  final FarmCache _cache;
  ExpenseTabletReadBridge(this.observer, this.captured)
    : _cache = observer.tablet.cache ?? (throw StateError('Cache absent.')) {
    _check();
  }
  void _check() {
    captured.checkIdentity(observer.observe());
    if (!identical(_cache, observer.tablet.cache)) {
      throw const ExpenseSessionException(ExpenseSessionFailure.contextChanged);
    }
  }

  Future<List<OutboxEntry>> ledgerPage({
    required int authorId,
    required int offset,
    required int limit,
  }) async {
    _check();
    if (authorId != captured.authorId || _cache is! OutboxStore) {
      throw const ExpenseSessionException(ExpenseSessionFailure.contextChanged);
    }
    try {
      final rows = await (_cache as OutboxStore).listOutbox(
        authorId: authorId,
        offset: offset,
        limit: limit,
      );
      _check();
      return rows;
    } catch (_) {
      _check();
      rethrow;
    }
  }

  Future<ExpenseCheckedCatalog> categories({
    ExpenseCacheFreshness freshness = ExpenseCacheFreshness.unknown,
  }) => ExpenseConsistentCatalog.read(
    captured: captured,
    observe: observer.observe,
    freshness: freshness,
    // No local transactional category revision is available. Never invent it.
    readPage: (collection, {required offset, required limit}) async {
      _check();
      try {
        final rows = await _cache.cachedPage(
          collection,
          offset: offset,
          limit: limit,
        );
        _check();
        return rows;
      } catch (_) {
        _check();
        rethrow;
      }
    },
  );

  /// Internal common ledger page for resolving lot provenance. The selection
  /// layer checks farm/device/generation before using a creator declaration.
  /// The personal expense register continues to use ledgerPage(authorId: ...).
  Future<List<OutboxEntry>> lotCreatorsPage({
    required int offset,
    required int limit,
  }) async {
    _check();
    if (_cache is! OutboxStore) {
      throw const ExpenseSessionException(ExpenseSessionFailure.contextChanged);
    }
    final rows = await (_cache as OutboxStore).listOutbox(
      offset: offset,
      limit: limit,
    );
    _check();
    // Keep page boundaries independent of filtering (an empty filtered page
    // must not prematurely stop traversal of the common ledger).
    return rows;
  }

  /// Explicit READ-ONLY resumption after the same original grant/profile has
  /// been manually reopened. Does not unsuspend or reassign the old intention.
  Future<ExpenseDurableResult> recoverOriginal(
    ExpenseIntention original,
    ExpenseIntentionCoordinator owner,
  ) async {
    _check();
    final origin = original.context;
    if (owner.pendingOperationId != original.operationId ||
        captured.authorId != origin.authorId ||
        captured.membershipId != origin.membershipId ||
        captured.farmId != origin.farmId ||
        captured.deviceId != origin.deviceId ||
        captured.generation != origin.generation ||
        captured.grantId != origin.grantId ||
        captured.rightsVersion != origin.rightsVersion ||
        captured.grant.token != origin.grant.token) {
      throw const ExpenseSessionException(ExpenseSessionFailure.contextChanged);
    }
    final seen = <String>{};
    var offset = 0;
    while (true) {
      final rows = await ledgerPage(
        authorId: origin.authorId,
        offset: offset,
        limit: 50,
      );
      if (rows.isEmpty) {
        return const ExpenseDurableResult(
          ExpenseDurableState.uncertain,
          issue: 'absenceNotProven',
        );
      }
      for (final row in rows) {
        if (!seen.add(row.operationId)) {
          return const ExpenseDurableResult(
            ExpenseDurableState.uncertain,
            issue: 'integrityMismatch',
          );
        }
        if (row.operationId == original.operationId) {
          try {
            return owner.verifyOriginalEntry(original, row);
          } on ExpenseIntentionException {
            return const ExpenseDurableResult(
              ExpenseDurableState.uncertain,
              issue: 'integrityMismatch',
            );
          }
        }
      }
      offset += rows.length;
    }
  }
}

/// Typed arguments corresponding to the EXISTING declare signature, not a
/// new payload/envelope. No method here invokes that signature.
class ExpenseDeclarationParameters {
  final String operationId, localEntityId;
  final String entityType = 'DEPENSE',
      operationType = 'CREATE',
      expectedServerVersion = '';
  final Map<String, Object> payload;
  final DateTime businessOccurredAt;
  final List<String> dependencies;
  final ExpenseCapturedSession origin;
  ExpenseDeclarationParameters._(ExpenseIntention intention)
    : operationId = intention.operationId,
      localEntityId = intention.operationId,
      payload = intention.prepared.payload,
      businessOccurredAt = intention.prepared.businessOccurredAt,
      dependencies = intention.prepared.dependencies,
      origin = intention.context;
  static ExpenseDeclarationParameters reserve(
    ExpenseIntentionCoordinator coordinator,
  ) => ExpenseDeclarationParameters._(
    coordinator.validateForFutureDeclaration(),
  );
}

abstract interface class ExpenseDeclarationSimulation {
  Future<void> inspectContract(ExpenseDeclarationParameters parameters);
}

/// Simulation only. No concrete implementation invokes declare or enqueue.
Future<void> simulateExpenseBoundary({
  required ExpenseIntentionCoordinator coordinator,
  required ExpenseDeclarationParameters parameters,
  required ExpenseDeclarationSimulation simulation,
  required ExpenseTabletSessionObserver observer,
}) async {
  final intention = coordinator.current;
  if (intention == null ||
      !intention.busy ||
      intention.operationId != parameters.operationId ||
      !identical(intention.context, parameters.origin)) {
    throw const ExpenseIntentionException(ExpenseIntentionFailure.unresolved);
  }
  parameters.origin.checkForValidation(
    observer.observe(),
    observer.tablet.clock().toUtc(),
  );
  coordinator
      .markUncertain(); // BEFORE any simulated potentially durable boundary
  try {
    await simulation.inspectContract(parameters);
    parameters.origin.checkIdentity(observer.observe());
  } catch (_) {
    parameters.origin.checkIdentity(observer.observe());
    rethrow;
  }
}
