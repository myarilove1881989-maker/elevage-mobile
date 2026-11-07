import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import 'micro_feedback.dart';

enum FarmAnimal { hen, pig, cow, goat, sheep }

class FarmLoginLoading extends StatefulWidget {
  const FarmLoginLoading({super.key, required this.active, this.chooseAnimal});
  final bool active;
  final FarmAnimal Function()? chooseAnimal;
  @override
  State<FarmLoginLoading> createState() => _FarmLoginLoadingState();
}

class _FarmLoginLoadingState extends State<FarmLoginLoading>
    with TickerProviderStateMixin {
  Timer? _delay;
  AnimationController? _walk;
  bool _visible = false;
  FarmAnimal _animal = FarmAnimal.hen;
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_preferenceChanged);
    if (widget.active) _start();
  }

  void _start() {
    _animal =
        widget.chooseAnimal?.call() ??
        FarmAnimal.values[math.Random().nextInt(FarmAnimal.values.length)];
    _delay = Timer(const Duration(milliseconds: 300), () {
      if (mounted && widget.active) {
        setState(() {
          _visible = true;
          _configure();
        });
      }
    });
  }

  void _configure() {
    if (!_visible || !microMotionAllowed(context)) {
      _walk?.dispose();
      _walk = null;
    } else {
      _walk ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat();
    }
  }

  void _preferenceChanged() {
    if (mounted) setState(_configure);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(FarmLoginLoading old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active) return;
    _delay?.cancel();
    _visible = false;
    _configure();
    if (widget.active) _start();
  }

  @override
  void dispose() {
    _delay?.cancel();
    _walk?.dispose();
    AppSettings.instance.removeListener(_preferenceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    Widget animal(double phase) =>
        FarmAnimalFrame(animal: _animal, phase: phase);
    final walk = _walk;
    return Semantics(
      liveRegion: true,
      label: 'Connexion à votre exploitation…',
      child: ExcludeSemantics(
        child: Padding(
          key: const Key('farm-login-loading'),
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                child: walk == null
                    ? animal(0)
                    : AnimatedBuilder(
                        animation: walk,
                        builder: (_, _) => animal(walk.value),
                      ),
              ),
              const Text(
                'Connexion à votre exploitation…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xff315d79)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small local vector animal, walking on the spot. Reusable in the review app.
class FarmAnimalFrame extends StatelessWidget {
  const FarmAnimalFrame({super.key, required this.animal, this.phase = 0});
  final FarmAnimal animal;
  final double phase;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    height: 54,
    child: CustomPaint(painter: _AnimalPainter(animal, phase)),
  );
}

class _AnimalPainter extends CustomPainter {
  const _AnimalPainter(this.animal, this.phase);
  final FarmAnimal animal;
  final double phase;
  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 76, size.height / 54);
    final p = Paint()..isAntiAlias = true;
    void oval(Rect rect, Color color) {
      p
        ..style = PaintingStyle.fill
        ..color = color;
      c.drawOval(rect, p);
    }

    void dot(double x, double y, double radius, Color color) {
      p
        ..style = PaintingStyle.fill
        ..color = color;
      c.drawCircle(Offset(x, y), radius, p);
    }

    void line(
      double x,
      double y,
      double xx,
      double yy,
      Color color, [
      double width = 2,
    ]) {
      p
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      c.drawLine(Offset(x, y), Offset(xx, yy), p);
    }

    void triangle(Offset a, Offset b, Offset d, Color color) {
      p
        ..style = PaintingStyle.fill
        ..color = color;
      c.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(d.dx, d.dy)
          ..close(),
        p,
      );
    }

    const ink = Color(0xff173e51),
        cream = Color(0xffe6e5d9),
        tan = Color(0xffbd9c78);
    final step = math.sin(phase * math.pi * 2) * 2.5;
    oval(const Rect.fromLTWH(10, 47, 54, 3), const Color(0xffe4eee8));
    c.save();
    c.translate(0, -math.sin(phase * math.pi * 2).abs());
    if (animal == FarmAnimal.hen) {
      line(31, 35, 30 + step, 46, tan);
      line(42, 35, 43 - step, 46, tan);
      triangle(
        const Offset(22, 25),
        const Offset(10, 14),
        const Offset(14, 33),
        const Color(0xff315d79),
      );
      oval(const Rect.fromLTWH(18, 19, 36, 24), cream);
      oval(const Rect.fromLTWH(26, 25, 19, 13), const Color(0xffc8b98c));
      dot(53, 20, 10, cream);
      dot(49, 10, 3, const Color(0xffb65f55));
      dot(55, 9, 3, const Color(0xffb65f55));
      triangle(
        const Offset(61, 19),
        const Offset(70, 23),
        const Offset(61, 26),
        const Color(0xffc39244),
      );
      dot(56, 18, 1.6, ink);
    } else {
      for (var i = 0; i < 4; i++) {
        final x = 23.0 + i * 9;
        line(x, 33, x + (i.isEven ? step : -step), 46, ink, 3);
      }
      final body = animal == FarmAnimal.pig
          ? const Color(0xffdba8a9)
          : animal == FarmAnimal.goat
          ? tan
          : cream;
      oval(const Rect.fromLTWH(13, 19, 43, 24), body);
      if (animal == FarmAnimal.sheep) {
        for (var i = 0; i < 6; i++) {
          dot(
            20 + i * 5.2,
            23 + (i.isEven ? 1 : -2),
            8,
            const Color(0xffefeee6),
          );
        }
        oval(const Rect.fromLTWH(49, 21, 17, 21), const Color(0xff6d7d80));
        oval(const Rect.fromLTWH(44, 21, 12, 5), ink);
      } else {
        oval(const Rect.fromLTWH(48, 17, 18, 23), body);
        triangle(
          const Offset(50, 19),
          const Offset(48, 9),
          const Offset(57, 16),
          body,
        );
        if (animal == FarmAnimal.pig) {
          oval(const Rect.fromLTWH(58, 26, 12, 9), const Color(0xffbf878d));
          dot(62, 30, 1, ink);
          dot(66, 30, 1, ink);
          p
            ..style = PaintingStyle.stroke
            ..color = body
            ..strokeWidth = 2;
          c.drawPath(
            Path()
              ..moveTo(14, 27)
              ..cubicTo(3, 24, 5, 15, 10, 19)
              ..cubicTo(14, 24, 4, 26, 6, 20),
            p,
          );
        } else {
          line(52, 18, 51, 10, ink);
          line(62, 18, 65, 10, ink);
          if (animal == FarmAnimal.cow) {
            oval(const Rect.fromLTWH(22, 23, 10, 9), ink);
            oval(const Rect.fromLTWH(39, 29, 9, 7), ink);
            oval(const Rect.fromLTWH(56, 29, 12, 8), const Color(0xffceb1a2));
            line(13, 27, 8, 37, ink);
          } else {
            triangle(
              const Offset(57, 37),
              const Offset(61, 45),
              const Offset(64, 36),
              ink,
            );
            line(13, 24, 8, 19, tan);
          }
        }
      }
      dot(60, 24, 1.5, ink);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_AnimalPainter old) =>
      old.animal != animal || old.phase != phase;
}
