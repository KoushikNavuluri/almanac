import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/insights.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';

TextPainter _tp(String text, TextStyle style) => TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();

String _hourLabel(double h) {
  final hi = h.round();
  if (hi == 12) return '12p';
  return hi < 12 ? '${hi}a' : '${hi - 12}p';
}

/// Hour-by-hour energy, drawn like the temperature line on a weather page.
class EnergyStrip extends StatelessWidget {
  const EnergyStrip({super.key, required this.curve, this.compact = false});
  final EnergyCurve curve;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowH = (now.hour + now.minute / 60).clamp(6.0, 23.5).toDouble();
    return Semantics(
      label: 'Energy forecast. Peak around ${fmtClock(curve.peak.h * 60)}, dip around ${fmtClock(curve.dip.h * 60)}.',
      child: SizedBox(
        height: compact ? 96 : 122,
        width: double.infinity,
        child: CustomPaint(painter: _EnergyPainter(curve, nowH)),
      ),
    );
  }
}

class _EnergyPainter extends CustomPainter {
  _EnergyPainter(this.c, this.nowH);
  final EnergyCurve c;
  final double nowH;

  @override
  void paint(Canvas canvas, Size size) {
    const padT = 24.0, padB = 22.0;
    final w = size.width, h = size.height;
    double x(double hr) => (hr - 6) / 17.5 * w;
    double y(double v) => padT + (1 - v) * (h - padT - padB);

    final line = Path();
    for (var i = 0; i < c.pts.length; i++) {
      final p = c.pts[i];
      if (i == 0) {
        line.moveTo(x(p.h), y(p.v));
      } else {
        line.lineTo(x(p.h), y(p.v));
      }
    }
    final fill = Path.from(line)
      ..lineTo(w, h - padB)
      ..lineTo(0, h - padB)
      ..close();
    final area = Rect.fromLTWH(0, padT, w, h - padT - padB);
    canvas.drawPath(
      fill,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x47EE9B43), Color(0x00EE9B43)]).createShader(area),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [C.navy, C.teal, C.amber, C.crimson],
          stops: [0, 0.45, 0.75, 1],
        ).createShader(area),
    );

    final label = T.ui(12, color: C.muted, weight: FontWeight.w600);
    for (final hr in [6.0, 9.0, 12.0, 15.0, 18.0, 21.0]) {
      final tp = _tp(_hourLabel(hr), label);
      final lx = hr == 6 ? 0.0 : x(hr) - tp.width / 2;
      tp.paint(canvas, Offset(lx, h - tp.height));
    }

    final marks = [
      (c.peak, 'Peak ${fmtClock(c.peak.h * 60).replaceAll(':00', '')}', C.crimson, true),
      (c.dip, 'Dip ${fmtClock(c.dip.h * 60).replaceAll(':00', '')}', C.navy, false),
      (c.second, 'Second wind', C.crimson, true),
    ];
    for (final m in marks) {
      final px = x(m.$1.h), py = y(m.$1.v);
      canvas.drawCircle(Offset(px, py), 4, Paint()..color = C.card);
      canvas.drawCircle(
        Offset(px, py),
        4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = m.$3,
      );
      final tp = _tp(m.$2, T.ui(12, color: m.$3, weight: FontWeight.w800));
      final lx = (px - tp.width / 2).clamp(0.0, w - tp.width).toDouble();
      tp.paint(canvas, Offset(lx, m.$4 ? py - 8 - tp.height : py + 7));
    }

    // Now marker.
    final nx = x(nowH);
    final dash = Paint()
      ..color = C.crimson
      ..strokeWidth = 1.5;
    for (var yy = padT - 10; yy < h - padB; yy += 6) {
      canvas.drawLine(Offset(nx, yy), Offset(nx, math.min(yy + 3, h - padB)), dash);
    }
    final nearest = c.pts.reduce((a, b) => (b.h - nowH).abs() < (a.h - nowH).abs() ? b : a);
    canvas.drawCircle(Offset(nx, y(nearest.v)), 5, Paint()..color = C.crimson);
  }

  @override
  bool shouldRepaint(_EnergyPainter old) => old.c != c || old.nowH != nowH;
}

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color = C.navy, this.width = 88, this.height = 28, this.stroke = 1.8});
  final List<double?> values;
  final Color color;
  final double width, height, stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _SparkPainter(values, color, stroke)),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.stroke);
  final List<double?> values;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    final vals = values.whereType<double>().toList();
    if (vals.length < 2) {
      final p = Paint()
        ..color = C.rule
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
      return;
    }
    final mn = vals.reduce(math.min), mx = vals.reduce(math.max);
    final span = (mx - mn) == 0 ? 1 : (mx - mn);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      pts.add(Offset(i / (values.length - 1) * size.width, size.height - 3 - (v - mn) / span * (size.height - 6)));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.85),
    );
    canvas.drawCircle(pts.last, 3, Paint()..color = C.crimson);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// Interactive history chart: your normal band, the line, and a scrub-to-read tooltip.
class MetricChart extends StatefulWidget {
  const MetricChart({
    super.key,
    required this.values,
    required this.dates,
    required this.color,
    required this.format,
    required this.axisFormat,
    this.bandLow,
    this.bandHigh,
    this.scale = 1,
  });
  final List<double?> values;
  final List<String> dates;
  final Color color;
  final String Function(double raw) format;
  final String Function(double scaled) axisFormat;
  final double? bandLow, bandHigh;
  final double scale;

  @override
  State<MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<MetricChart> {
  int? _sel;

  void _pick(Offset local, double width) {
    if (widget.values.length < 2) return;
    const left = 44.0;
    final f = ((local.dx - left) / (width - left - 6)).clamp(0.0, 1.0);
    setState(() => _sel = (f * (widget.values.length - 1)).round());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return GestureDetector(
        onTapDown: (d) => _pick(d.localPosition, box.maxWidth),
        onHorizontalDragUpdate: (d) => _pick(d.localPosition, box.maxWidth),
        onHorizontalDragEnd: (_) => setState(() => _sel = null),
        onTapUp: (_) => Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _sel = null);
        }),
        child: CustomPaint(
          size: Size(box.maxWidth, 190),
          painter: _ChartPainter(widget, _sel),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.w, this.sel);
  final MetricChart w;
  final int? sel;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 6.0, top = 12.0, bottom = 26.0;
    final vals = w.values.map((v) => v == null ? null : v * w.scale).toList();
    final present = vals.whereType<double>().toList();
    final label = T.ui(12, color: C.muted, weight: FontWeight.w500);
    if (present.length < 2) {
      final tp = _tp('Not enough readings yet', T.ui(14, color: C.muted));
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }
    var mn = present.reduce(math.min), mx = present.reduce(math.max);
    if (w.bandLow != null) mn = math.min(mn, w.bandLow! * w.scale);
    if (w.bandHigh != null) mx = math.max(mx, w.bandHigh! * w.scale);
    final pad = (mx - mn) * 0.12 + 0.0001;
    mn -= pad;
    mx += pad;
    final plotW = size.width - left - right, plotH = size.height - top - bottom;
    double px(int i) => left + i / (vals.length - 1) * plotW;
    double py(double v) => top + (1 - (v - mn) / (mx - mn)) * plotH;

    if (w.bandLow != null && w.bandHigh != null) {
      canvas.drawRect(
        Rect.fromLTRB(left, py(w.bandHigh! * w.scale), size.width - right, py(w.bandLow! * w.scale)),
        Paint()..color = C.teal.withValues(alpha: 0.12),
      );
    }
    for (var i = 0; i < 4; i++) {
      final v = mn + (mx - mn) * (i + 0.5) / 4;
      final tp = _tp(w.axisFormat(v), label);
      tp.paint(canvas, Offset(left - 8 - tp.width, py(v) - tp.height / 2));
    }
    final idxs = [0, (vals.length * 0.33).round(), (vals.length * 0.66).round(), vals.length - 1];
    for (final i in idxs.toSet()) {
      if (i < 0 || i >= w.dates.length) continue;
      final tp = _tp(fmtDate(w.dates[i]), label);
      final x = (px(i) - tp.width / 2).clamp(left, size.width - tp.width).toDouble();
      tp.paint(canvas, Offset(x, size.height - tp.height));
    }

    final line = Path();
    var started = false;
    Offset? last;
    for (var i = 0; i < vals.length; i++) {
      final v = vals[i];
      if (v == null) continue;
      final o = Offset(px(i), py(v));
      if (!started) {
        line.moveTo(o.dx, o.dy);
        started = true;
      } else {
        line.lineTo(o.dx, o.dy);
      }
      last = o;
    }
    final fill = Path.from(line);
    if (last != null) {
      fill
        ..lineTo(last.dx, top + plotH)
        ..lineTo(px(vals.indexWhere((v) => v != null)), top + plotH)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x59EE9B43), Color(0x00EE9B43)])
              .createShader(Rect.fromLTWH(left, top, plotW, plotH)),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..color = w.color,
    );
    if (last != null) {
      canvas.drawCircle(last, 6, Paint()..color = C.card);
      canvas.drawCircle(last, 4.5, Paint()..color = C.crimson);
    }

    final s = sel;
    if (s != null && s >= 0 && s < vals.length && w.values[s] != null) {
      final x = px(s), y = py(vals[s]!);
      final dash = Paint()
        ..color = C.crimson
        ..strokeWidth = 1.2;
      for (var yy = top; yy < top + plotH; yy += 6) {
        canvas.drawLine(Offset(x, yy), Offset(x, yy + 3), dash);
      }
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = C.crimson);
      final t1 = _tp(fmtDate(w.dates[s], weekday: true), T.ui(12, color: C.card, weight: FontWeight.w600));
      final t2 = _tp(w.format(w.values[s]!), T.ui(14, color: C.card, weight: FontWeight.w800));
      final bw = math.max(t1.width, t2.width) + 20, bh = t1.height + t2.height + 14;
      final bx = (x - bw / 2).clamp(left, size.width - bw).toDouble();
      final by = (y - bh - 12).clamp(0.0, size.height - bh).toDouble();
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(12)), Paint()..color = C.ink);
      t1.paint(canvas, Offset(bx + 10, by + 7));
      t2.paint(canvas, Offset(bx + 10, by + 7 + t1.height));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.sel != sel || old.w != w;
}

/// A short confetti burst for finished experiments.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.trigger});
  final int trigger;
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
  List<_Bit> _bits = [];

  @override
  void didUpdateWidget(ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger > 0) {
      final r = math.Random();
      const cols = [C.sun, C.amber, C.coral, C.crimson, C.teal, C.navy];
      _bits = List.generate(46, (i) => _Bit(0.5 + (r.nextDouble() - 0.5) * 0.3, (r.nextDouble() - 0.5) * 340, 260 + r.nextDouble() * 380, r.nextDouble() * 12 - 6, cols[i % cols.length], 6 + r.nextDouble() * 6));
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => _c.isAnimating ? CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_bits, _c.value)) : const SizedBox.shrink(),
      ),
    );
  }
}

class _Bit {
  _Bit(this.x, this.dx, this.dy, this.rot, this.color, this.size);
  final double x, dx, dy, rot, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final e = Curves.easeOut.transform(t);
    for (final b in bits) {
      final up = t < 0.3 ? -140 * (t / 0.3) : -140 + (b.dy + 140) * ((t - 0.3) / 0.7);
      final o = Offset(size.width * b.x + b.dx * e, size.height * 0.3 + up);
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(b.rot * e);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.45),
        Paint()..color = b.color.withValues(alpha: (1 - math.max(0, t - 0.6) / 0.4).clamp(0.0, 1.0).toDouble()),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
