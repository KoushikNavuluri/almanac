import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'common.dart';

/// The signature: a living forecast sky. The sun sits higher on better days, clouds roll in
/// when sleep was short, and on partly cloudy days they literally thin out as the real clock
/// passes noon.
class SkyView extends StatefulWidget {
  const SkyView({super.key, required this.score, required this.condition, required this.height, required this.child});
  final int? score;
  final String condition;
  final double height;
  final Widget child;

  @override
  State<SkyView> createState() => _SkyViewState();
}

class _SkyViewState extends State<SkyView> with TickerProviderStateMixin {
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 90));
  late final AnimationController _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionOff(context)) {
      _ambient.stop();
      _rise.value = 1;
    } else {
      if (!_ambient.isAnimating) _ambient.repeat();
      if (_rise.value == 0) _rise.forward();
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_ambient, _rise]),
            builder: (_, __) => CustomPaint(
              painter: SkyPainter(
                t: _ambient.value,
                rise: Curves.easeOutCubic.transform(_rise.value),
                score: widget.score,
                condition: widget.condition,
                hour: DateTime.now().hour,
              ),
            ),
          ),
        ),
        widget.child,
      ]),
    );
  }
}

class SkyPainter extends CustomPainter {
  SkyPainter({required this.t, required this.rise, required this.score, required this.condition, required this.hour});
  final double t, rise;
  final int? score;
  final String condition;
  final int hour;

  static const _skies = <String, List<Color>>{
    'bright': [Color(0xFFEE9B43), Color(0xFFF3D567), Color(0xFFF6E7A6)],
    'clear': [Color(0xFF19798B), Color(0xFF5FA7A8), Color(0xFFF3D567)],
    'partly': [Color(0xFF172767), Color(0xFF19798B), Color(0xFFEE9B43)],
    'overcast': [Color(0xFF2A3566), Color(0xFF56608A), Color(0xFF9AA0B9)],
    'storm': [Color(0xFF121838), Color(0xFF2B2F5E), Color(0xFFB80422)],
    'unknown': [Color(0xFF172767), Color(0xFF2A3566), Color(0xFF56608A)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final cols = _skies[condition] ?? _skies['partly']!;
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: cols, stops: const [0, 0.62, 1]).createShader(rect),
    );

    // Isobars, like the pressure lines on a weather map, sliding slowly.
    final iso = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = C.card.withValues(alpha: 0.16);
    for (var i = 0; i < 5; i++) {
      final y0 = h * 0.22 + i * h * 0.14;
      final p = Path();
      for (var x = 0.0; x <= w + 4; x += 4) {
        final y = y0 + math.sin(x / w * math.pi * 4 + t * math.pi * 2 + i) * (10 + i * 2.0);
        if (x == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      canvas.drawPath(p, iso);
    }

    final s = score ?? 50;
    final k = w / 390;
    final sunX = w * 0.78;
    final sunY = h * (0.74 - s / 100 * 0.42) + (1 - rise) * h * 0.3;

    // Glow, pulsing gently.
    final pulse = 0.75 + 0.25 * math.sin(t * math.pi * 2 * 18);
    final glowR = 92 * k;
    canvas.drawCircle(
      Offset(sunX, sunY),
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFFF3D567).withValues(alpha: 0.95 * pulse),
          const Color(0xFFEE9B43).withValues(alpha: 0.35 * pulse),
          const Color(0x00EE9B43),
        ], stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: glowR)),
    );
    // Rays, turning once a cycle.
    final ray = Paint()
      ..color = C.sun.withValues(alpha: 0.85)
      ..strokeWidth = 2.2 * k
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2 + t * math.pi * 2;
      canvas.drawLine(
        Offset(sunX + math.cos(a) * 40 * k, sunY + math.sin(a) * 40 * k),
        Offset(sunX + math.cos(a) * 52 * k, sunY + math.sin(a) * 52 * k),
        ray,
      );
    }
    canvas.drawCircle(Offset(sunX, sunY), 30 * k, Paint()..color = C.sun);

    // Clouds: short sleep and a low calm reserve roll them in.
    final clouds = score == null ? 2 : (s >= 82 ? 0 : s >= 72 ? 1 : s >= 60 ? 3 : 4);
    final thin = condition == 'partly' ? math.max(0.35, 1 - math.max(0, hour - 9) * 0.08) : 1.0;
    for (var i = 0; i < clouds; i++) {
      final speed = 1.0 + i * 0.35;
      final x = ((t * speed + i * 0.27) % 1.0) * (w * 1.6) - w * 0.35;
      final y = sunY + 10 * k + (i % 2) * 34 * k - i * 6 * k;
      final sc = (1 - i * 0.12) * k;
      final paint = Paint()..color = C.card.withValues(alpha: (0.9 - i * 0.12) * thin);
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(sc);
      canvas.drawOval(Rect.fromCenter(center: const Offset(60, 30), width: 116, height: 40), paint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(38, 20), width: 52, height: 40), paint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(74, 14), width: 60, height: 48), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.t != t || old.rise != rise || old.score != score || old.condition != condition || old.hour != hour;
}
