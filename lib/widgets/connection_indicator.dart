import '../offline/sync_state.dart';
import '../services/app_settings.dart';
import 'sync_feedback_tracker.dart';
import 'micro_feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';

/// Presentation only: never probes the network or schedules synchronization.
class ConnectionIndicator extends StatefulWidget {
  const ConnectionIndicator({
    super.key,
    this.networkAvailable,
    this.lastSuccess,
    this.serverUnavailable = false,
    this.syncUnavailable = false,
    this.syncing = false,
    this.pending,
    this.conflicts,
    this.syncSource,
    this.syncSummary,
    this.onSummary,
    this.freshness = const Duration(minutes: 2),
    this.showLabel = false,
    this.clock,
  });

  final Object? syncSource;
  final SyncSummary? syncSummary;
  final bool? networkAvailable;
  final DateTime? lastSuccess;
  final bool serverUnavailable, syncUnavailable, syncing, showLabel;
  final int? pending, conflicts;
  final VoidCallback? onSummary;
  final Duration freshness;
  final DateTime Function()? clock;
  @override
  State<ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<ConnectionIndicator> {
  Timer? _expiry, _cueExpiry;
  bool _syncCueVisible = false;
  int _cueGeneration = 0;
  static final _trackers = Expando<SyncFeedbackTracker>();
  void _motionChanged() { if (mounted) setState(() {}); }
  void _observeSync() {
    final source = widget.syncSource, summary = widget.syncSummary;
    final invalid = source == null || summary == null || widget.syncing ||
        widget.serverUnavailable || widget.syncUnavailable || widget.networkAvailable == false ||
        summary.pending > 0 || summary.awaitingValidation > 0 || summary.conflicts > 0 || summary.blocked > 0;
    if (invalid) {
      _cueGeneration++;
      if (_syncCueVisible) {
        _syncCueVisible = false; _cueExpiry?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) MicroFeedback.dismissSync(context); });
      }
    }
    if (source == null || summary == null) { return; }
    final tracker = _trackers[source] ??= SyncFeedbackTracker();
    if (!tracker.observe(summary: summary, busy: widget.syncing,
        unavailable: widget.serverUnavailable || widget.syncUnavailable,
        networkAvailable: widget.networkAvailable)) { return; }
    _syncCueVisible = true;
    final generation = ++_cueGeneration;
    _cueExpiry?.cancel();
    _cueExpiry = Timer(const Duration(milliseconds: 2200), () { if (mounted) setState(() => _syncCueVisible = false); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _cueGeneration && _syncCueVisible) {
        MicroFeedback.synchronized(context, operation: (source, summary.lastSuccess));
      }
    });
  }
  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
    AppSettings.instance.addListener(_motionChanged);
    _observeSync();
  }

  @override
  void didUpdateWidget(ConnectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _observeSync();
    if (oldWidget.lastSuccess != widget.lastSuccess ||
        oldWidget.freshness != widget.freshness) {
      _scheduleExpiry();
    }
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final time = widget.lastSuccess;
    if (time == null) {
      return;
    }
    final remaining = time.add(widget.freshness).difference(_now);
    if (remaining > Duration.zero) {
      _expiry = Timer(remaining, () {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _expiry?.cancel(); _cueExpiry?.cancel();
    AppSettings.instance.removeListener(_motionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final last = widget.lastSuccess;
    final recent =
        last != null &&
        !last.isAfter(now) &&
        now.difference(last) < widget.freshness;
    final offline = widget.networkAvailable == false;
    final verified =
        recent &&
        !offline &&
        !widget.serverUnavailable &&
        !widget.syncUnavailable;
    final label = offline
        ? 'Hors ligne'
        : widget.serverUnavailable
        ? 'Serveur indisponible'
        : widget.syncUnavailable
        ? 'Synchronisation indisponible'
        : verified
        ? 'Échange serveur récent'
        : 'Serveur non vérifié';
    final color = offline || widget.serverUnavailable || widget.syncUnavailable
        ? Colors.orange.shade800
        : verified
        ? Colors.green.shade700
        : Colors.grey;
    final timestamp = last == null
        ? ''
        : '\nDernier échange réussi : ${last.toLocal()}';
    final description =
        '$label$timestamp\nUn échange passé ne garantit pas la disponibilité actuelle.';
    final pending = widget.pending ?? 0;
    final conflicts = widget.conflicts ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: description,
          child: Semantics(
            label: description,
            child: SizedBox(
              width: 40,
              height: 48,
              child: Center(
                child: _syncCueVisible
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(begin: microMotionAllowed(context) ? 0 : 1, end: 1),
                        duration: microMotionAllowed(context) ? const Duration(milliseconds: 700) : Duration.zero,
                        builder: (_, value, _) => ConfirmationFrame(progress: value, size: 24),
                      )
                    : widget.syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Synchronisation en cours',
                        ),
                      )
                    : Icon(
                        (offline || widget.serverUnavailable || !verified) ? Icons.wifi_off : Icons.wifi,
                        key: const Key('connectionStateIcon'),
                        color: color,
                        size: 22,
                      ),
              ),
            ),
          ),
        ),
        if (widget.showLabel) Text(label, style: TextStyle(color: color)),
        if (pending > 0 || conflicts > 0)
          IconButton(
            onPressed: widget.onSummary,
            tooltip:
                'Sur cette tablette, tous profils : $pending déclarations à transmettre, '
                '$conflicts opérations à vérifier',
            icon: Badge(
              label: Text('${pending > 99 ? '99+' : pending}'),
              isLabelVisible: pending > 0,
              child: Icon(
                conflicts > 0 ? Icons.warning_amber : Icons.outbox_outlined,
                color: conflicts > 0 ? Colors.orange.shade800 : null,
              ),
            ),
          ),
      ],
    );
  }
}
