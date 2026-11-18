import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/app_settings.dart';

bool microMotionAllowed(BuildContext context) =>
    AppSettings.instance.animationsEnabled &&
    !MediaQuery.disableAnimationsOf(context) &&
    !MediaQuery.accessibleNavigationOf(context) &&
    TickerMode.valuesOf(context).enabled;

/// A presentation receipt, never a network request or a business confirmation.
class MicroFeedback {
  static final _seen = Expando<Set<Object>>();
  static final _active = Expando<_ActiveCue>();

  static void confirmed(BuildContext context, {Object? operation}) =>
      _show(context, operation: operation ?? 'confirmed-route', confetti: true);

  static void dismissSync(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final cue = _active[overlay];
    if (cue != null && cue.isSync) {
      cue.close();
      _active[overlay] = null;
    }
  }

  static void synchronized(BuildContext context, {required Object operation}) =>
      _show(context, operation: operation, message: 'Données synchronisées');

  static void _show(
    BuildContext context, {
    required Object operation,
    bool confetti = false,
    String? message,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final scope = ModalRoute.of(context) ?? overlay;
    final seen = _seen[scope] ??= <Object>{};
    if (!seen.add(operation)) return;
    _active[overlay]?.close();
    late final _ActiveCue cue;
    late final OverlayEntry entry;
    void forget() {
      if (identical(_active[overlay], cue)) _active[overlay] = null;
    }

    entry = OverlayEntry(
      builder: (context) => Positioned(
        right: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 80,
        child: IgnorePointer(
          child: _CuePresentation(
            confetti: confetti,
            message: message,
            onFinished: () {
              cue.close();
              forget();
            },
            onDisposed: forget,
          ),
        ),
      ),
    );
    cue = _ActiveCue(entry, isSync: message != null);
    _active[overlay] = cue;
    overlay.insert(entry);
  }
}

class _ActiveCue {
  _ActiveCue(this.entry, {required this.isSync});
  final bool isSync;
  final OverlayEntry entry;
  bool closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
    entry.dispose();
  }
}

class _CuePresentation extends StatefulWidget {
  const _CuePresentation({
    required this.confetti,
    this.message,
    required this.onFinished,
    required this.onDisposed,
  });
  final bool confetti;
  final String? message;
  final VoidCallback onFinished, onDisposed;
  @override
  State<_CuePresentation> createState() => _CuePresentationState();
}

class _CuePresentationState extends State<_CuePresentation>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_preferenceChanged);
    _expiry = Timer(
      Duration(milliseconds: widget.message == null ? 780 : 2200),
      widget.onFinished,
    );
  }

  void _preferenceChanged() {
    if (mounted) setState(_configure);
  }

  void _configure() {
    if (!microMotionAllowed(context)) {
      _controller?.dispose();
      _controller = null;
    } else {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      )..forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _controller?.dispose();
    AppSettings.instance.removeListener(_preferenceChanged);
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget mark(double progress) => ConfirmationFrame(
      progress: progress,
      confetti: widget.confetti && microMotionAllowed(context),
      size: widget.message == null ? 72 : 34,
    );
    final controller = _controller;
    final visual = RepaintBoundary(
      child: controller == null
          ? mark(1)
          : AnimatedBuilder(
              animation: controller,
              builder: (_, _) => mark(controller.value),
            ),
    );
    return Semantics(
      liveRegion: widget.message != null,
      label: widget.message ?? 'Opération confirmée',
      child: ExcludeSemantics(
        child: Material(
          key: const Key('micro-confirmation'),
          color: Theme.of(context).colorScheme.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                visual,
                if (widget.message != null) ...[
                  const SizedBox(width: 8),
                  Text(widget.message!, style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Local vector frame also used by the review gallery. No fonts or assets needed.
class ConfirmationFrame extends StatelessWidget {
  const ConfirmationFrame({
    super.key,
    required this.progress,
    this.confetti = false,
    this.size = 72,
  });
  final double progress, size;
  final bool confetti;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _ConfirmationPainter(progress, confetti)),
  );
}

class _ConfirmationPainter extends CustomPainter {
  const _ConfirmationPainter(this.progress, this.confetti);
  final double progress;
  final bool confetti;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 72, size.height / 72);
    final t = progress.clamp(0.0, 1.0);
    final paint = Paint()..color = const Color(0xffe8f5eb);
    canvas.drawCircle(const Offset(36, 36), 21, paint);
    final check = Path()
      ..moveTo(25, 36)
      ..lineTo(33, 44)
      ..lineTo(48, 28);
    final segment = check.computeMetrics().first;
    paint
      ..color = const Color(0xff13833e)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      segment.extractPath(0, segment.length * (t / .65).clamp(0.0, 1.0)),
      paint,
    );
    if (confetti && t < 1) {
      paint.style = PaintingStyle.fill;
      final fade = (1 - t).clamp(0.0, 1.0);
      for (var i = 0; i < 6; i++) {
        final angle = i * math.pi / 3 - .4;
        final distance = 18 + 14 * Curves.easeOut.transform(t);
        paint.color = [
          const Color(0xff2e9855),
          const Color(0xff315d79),
          const Color(0xffb5a66c),
        ][i % 3].withValues(alpha: fade);
        canvas.save();
        canvas.translate(
          36 + math.cos(angle) * distance,
          34 + math.sin(angle) * distance + t * 5,
        );
        canvas.rotate(angle + t * 1.5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-1.5, -3, 3, 6),
            const Radius.circular(1),
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_ConfirmationPainter old) =>
      old.progress != progress || old.confetti != confetti;
}
