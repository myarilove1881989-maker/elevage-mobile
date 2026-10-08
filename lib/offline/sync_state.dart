/// Storage contract remains usable by standalone Dart encryption validation.
abstract interface class SyncStateStore {
  Future<SyncSummary> syncSummary();
  Future<void> recordSyncSuccess(DateTime time);
}

class SyncSummary {
  const SyncSummary({this.pending=0,this.awaitingValidation=0,this.conflicts=0,this.blocked=0,this.lastSuccess});
  final int pending,awaitingValidation,conflicts,blocked;
  final DateTime? lastSuccess;
}
