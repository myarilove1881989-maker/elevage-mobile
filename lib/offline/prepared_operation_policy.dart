import '../services/permission_contract.dart';
import 'offline_grant.dart';

enum PreparedOperationDecision { allowed, denied, legacyTransitionRequired }

/// HTTP preparation adapter and fine signed policy. Existing V1 grants are never rewritten.
PreparedOperationDecision preparedOperationDecision(VerifiedOfflineGrant grant,
    String kind, String operation, DateTime now, {bool revoked = false}) {
  if (revoked || !grant.validAt(now)) {
    return PreparedOperationDecision.denied;
  }
  if (grant.hasFineContract) {
    final raw = (grant.claims['capabilities'] as Map)['permission_contract'];
    if (raw is Map && raw['version'] == 2) {
      return grant.permitsOperation(kind,operation,now)
        ? PreparedOperationDecision.allowed : PreparedOperationDecision.denied;
    }
  }
  final action = PermissionContract.operationAction(kind,operation);
  if (action == null) return PreparedOperationDecision.denied;
  final contract = (grant.claims['capabilities'] as Map)['permission_contract'];
  if (contract == null) return PreparedOperationDecision.legacyTransitionRequired;
  if (contract is! Map<String,dynamic>) return PreparedOperationDecision.denied;
  try {
    final rights = PermissionContract.decode(contract,userId:grant.userId,farmId:grant.farmId,
      role:'OPERATEUR',rightsVersion:grant.rightsVersion);
    return rights.allows(action) ? PreparedOperationDecision.allowed : PreparedOperationDecision.denied;
  } catch (_) {
    return PreparedOperationDecision.denied;
  }
}
