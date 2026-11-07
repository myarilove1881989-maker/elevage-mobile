import '../offline/sync_state.dart';

/// Presentation-only edge detector. It neither changes nor schedules sync.
/// A historical success, reconnection, partial batch or summary refresh cannot
/// celebrate: a witnessed busy cycle must finish with a newer success and zero
/// entries in every existing counter.
class SyncFeedbackTracker {
  bool _running = false, _workBefore = false, _workInCycle = false;
  DateTime? _baseline, _shown;
  bool observe({
    required SyncSummary summary,
    required bool busy,
    required bool unavailable,
    bool? networkAvailable,
  }) {
    final work =
        summary.pending > 0 ||
        summary.awaitingValidation > 0 ||
        summary.conflicts > 0 ||
        summary.blocked > 0;
    if (!_running && busy) {
      _running = true;
      _baseline = summary.lastSuccess;
      _workInCycle = _workBefore || work;
    }
    if (busy) {
      _workInCycle = _workInCycle || work;
      return false;
    }
    if (!_running) {
      _workBefore = work;
      return false;
    }
    _running = false;
    _workBefore = work;
    final success = summary.lastSuccess;
    final complete =
        _workInCycle &&
        !work &&
        !unavailable &&
        networkAvailable != false &&
        success != null &&
        (_baseline == null || success.isAfter(_baseline!)) &&
        (_shown == null || success.isAfter(_shown!));
    _workInCycle = false;
    if (complete) _shown = success;
    return complete;
  }
}
