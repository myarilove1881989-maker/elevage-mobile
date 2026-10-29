import '../offline/tablet_controller.dart';
import '../offline/sync_state.dart';
import 'permission_contract.dart';

enum SessionOrigin { personalHttp, tabletProfile }

enum NetworkState { unknown, available, unavailable }

/// Presentation identity only. This never authorizes a command or signs a grant.
class FarmSession {
  FarmSession({
    required this.userId,
    required this.farmId,
    required this.role,
    required this.origin,
    required this.network,
    required this.sync,
    this.permissions,
    this.deviceId,
    this.profileName,
    this.syncing = false,
  }) {
    if (userId < 1 ||
        farmId < 1 ||
        !{'OWNER', 'OPERATEUR'}.contains(role) ||
        (permissions != null &&
            (permissions!.userId != userId ||
                permissions!.farmId != farmId ||
                permissions!.role != role))) {
      throw StateError('Session incohérente.');
    }
  }
  final int userId, farmId;
  final String role;
  final SessionOrigin origin;
  final PermissionContract? permissions;
  final int? deviceId;
  final String? profileName;
  final NetworkState network;
  final SyncSummary sync;
  final bool syncing;
  bool get canManageUsers =>
      origin == SessionOrigin.personalHttp &&
      role == 'OWNER' &&
      permissions?.allows('users.manage') == true;
  bool get canCancelTask =>
      origin == SessionOrigin.personalHttp && role == 'OWNER';
  // Presentation only; every command still passes verified grant checks in the outbox.
  bool get fineOfflineRightsActivated => origin == SessionOrigin.tabletProfile && permissions != null;

  static FarmSession? fromTablet(TabletController tablet) {
    final profile = tablet.operators?.session;
    if (profile == null || tablet.farmId == null) return null;
    return FarmSession(
      userId: profile.userId,
      farmId: tablet.farmId!,
      role: 'OPERATEUR',
      origin: SessionOrigin.tabletProfile,
      permissions: profile.grant.finePermissions,
      deviceId: tablet.deviceId,
      profileName: tablet.selectedName,
      network: tablet.sync?.networkAvailable == true
          ? NetworkState.available
          : tablet.sync?.networkAvailable == false
          ? NetworkState.unavailable
          : NetworkState.unknown,
      sync: tablet.sync?.summary ?? const SyncSummary(),
      syncing: tablet.sync?.busy ?? false,
    );
  }
}
