import 'local_operator_session.dart';
import 'offline_grant.dart';
import 'prepared_operation_policy.dart';
import 'expense_preparation.dart';

enum ExpenseSessionFailure {
  notPrepared,
  pinLocked,
  contextChanged,
  permissionDenied,
}

class ExpenseSessionException implements Exception {
  final ExpenseSessionFailure code;
  const ExpenseSessionException(this.code);
}

/// Explicit observation supplied by an adapter; no PIN/session is created here.
/// epoch MUST increase on every lock/profile/farm/grant/device transition.
class ExpenseSessionObservation {
  final LocalOperatorSession? personalSession;
  final Object? preparedProfileIdentity;
  final Object? cacheIdentity;
  final int farmId, deviceId, generation, epoch;
  final bool explicitlyPrepared, pinUnlocked, revoked, recovering;
  const ExpenseSessionObservation({
    required this.personalSession,
    required this.preparedProfileIdentity,
    required this.cacheIdentity,
    required this.farmId,
    required this.deviceId,
    required this.generation,
    required this.epoch,
    required this.explicitlyPrepared,
    required this.pinUnlocked,
    this.revoked = false,
    this.recovering = false,
  });
}

class ExpenseCapturedSession {
  final LocalOperatorSession _personal;
  final Object _profile, _cache;
  final VerifiedOfflineGrant grant;
  final int authorId,
      membershipId,
      farmId,
      deviceId,
      generation,
      rightsVersion,
      epoch;
  final String grantId;
  ExpenseCapturedSession._(ExpenseSessionObservation observed)
    : _personal = observed.personalSession!,
      _profile = observed.preparedProfileIdentity!,
      _cache = observed.cacheIdentity!,
      grant = observed.personalSession!.grant,
      authorId = observed.personalSession!.grant.userId,
      membershipId =
          observed.personalSession!.grant.claims['membership_id'] as int,
      farmId = observed.farmId,
      deviceId = observed.deviceId,
      generation = observed.generation,
      rightsVersion = observed.personalSession!.grant.rightsVersion,
      epoch = observed.epoch,
      grantId = observed.personalSession!.grant.claims['jti'] as String;

  static ExpenseCapturedSession capture(
    ExpenseSessionObservation observed,
    DateTime nowUtc,
  ) {
    _usable(observed);
    final captured = ExpenseCapturedSession._(observed);
    captured.checkForValidation(observed, nowUtc);
    return captured;
  }

  static void _usable(ExpenseSessionObservation observed) {
    if (!observed.explicitlyPrepared ||
        observed.preparedProfileIdentity == null ||
        observed.cacheIdentity == null ||
        observed.revoked ||
        observed.recovering) {
      throw const ExpenseSessionException(ExpenseSessionFailure.notPrepared);
    }
    if (!observed.pinUnlocked || observed.personalSession == null) {
      throw const ExpenseSessionException(ExpenseSessionFailure.pinLocked);
    }
  }

  /// Read recovery does not require an unexpired write permission. Original
  /// identities and explicit personal unlock remain mandatory.
  void checkIdentity(ExpenseSessionObservation observed) {
    _usable(observed);
    final current = observed.personalSession!.grant;
    if (observed.epoch != epoch ||
        !identical(_personal, observed.personalSession) ||
        !identical(_profile, observed.preparedProfileIdentity) ||
        !identical(_cache, observed.cacheIdentity) ||
        current.token != grant.token ||
        current.claims['jti'] != grantId ||
        current.userId != authorId ||
        current.claims['membership_id'] != membershipId ||
        current.farmId != farmId ||
        current.deviceId != deviceId ||
        current.generation != generation ||
        current.rightsVersion != rightsVersion ||
        observed.farmId != farmId ||
        observed.deviceId != deviceId ||
        observed.generation != generation ||
        membershipId <= 0 ||
        farmId <= 0 ||
        authorId <= 0 ||
        deviceId <= 0 ||
        generation <= 0) {
      throw const ExpenseSessionException(ExpenseSessionFailure.contextChanged);
    }
  }

  void checkForValidation(ExpenseSessionObservation observed, DateTime nowUtc) {
    checkIdentity(observed);
    // Reuse the signed-grant policy; legacy HTTP/V1 rights are never enough.
    if (!nowUtc.isUtc ||
        !grant.hasFineContract ||
        preparedOperationDecision(
              grant,
              'DEPENSE',
              'CREATE',
              nowUtc,
              revoked: observed.revoked,
            ) !=
            PreparedOperationDecision.allowed) {
      throw const ExpenseSessionException(
        ExpenseSessionFailure.permissionDenied,
      );
    }
  }

  bool matchesPreparation(PreparedExpense expense) =>
      expense.origin.authorId == authorId && expense.origin.farmId == farmId;
}
