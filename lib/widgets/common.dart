import 'package:flutter/material.dart';

import '../domain/insights.dart';
import '../domain/metrics.dart';
import '../screens/experiment_screen.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import 'package:url_launcher/url_launcher.dart';

bool motionOff(BuildContext context) => AppScope.of(context).reduceMotion || MediaQuery.of(context).disableAnimations;

Route<T> slideRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
          child: child,
        );
      },
    );

void showToast(BuildContext context, String message, {bool good = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    duration: const Duration(milliseconds: 2600),
    content: Row(children: [
      Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(color: good ? C.teal : C.crimson, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 13, color: C.card),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: T.ui(14, color: C.card))),
    ]),
  ));
}

class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.color = C.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: T.kicker(color: color));
}

/// Scales down slightly while pressed. Every tappable surface uses it.
class Press extends StatefulWidget {
  const Press({super.key, required this.child, required this.onTap, this.semantics});
  final Widget child;
  final VoidCallback? onTap;
  final String? semantics;
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedOpacity(opacity: enabled ? 1 : 0.45, duration: const Duration(milliseconds: 150), child: widget.child),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.onTap, this.icon, this.bg = C.navy, this.fg = C.card, this.height = 48, this.expand = false, this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color bg, fg;
  final double height;
  final bool expand, busy;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 18, color: fg),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label, style: T.ui(15, color: fg, weight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
      ],
    );
    return Press(
      onTap: busy ? null : onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: content,
      ),
    );
  }
}

class PaperCard extends StatelessWidget {
  const PaperCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = C.card, this.onTap, this.radius = 22, this.border = true});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final VoidCallback? onTap;
  final double radius;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: C.rule) : null,
      ),
      child: child,
    );
    return onTap == null ? box : Press(onTap: onTap, child: box);
  }
}

const _toneColors = {
  Tone.great: (Color(0x2419798B), C.tealInk, C.teal),
  Tone.good: (Color(0x1A19798B), C.tealInk, C.teal),
  Tone.neutral: (Color(0x12172767), C.navy, C.navy),
  Tone.soft: (Color(0x2EEE9B43), Color(0xFF7A3F05), C.amber),
  Tone.watch: (Color(0x24E74B47), C.crimson, C.coral),
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final MetricStatus status;
  @override
  Widget build(BuildContext context) {
    final t = _toneColors[status.tone]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: t.$1, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: t.$3, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(status.word, style: T.ui(12, color: t.$2, weight: FontWeight.w800)),
      ]),
    );
  }
}

/// A pill segmented control with a sliding thumb.
class Segmented<V> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged, this.small = false});
  final V value;
  final Map<V, String> options;
  final ValueChanged<V> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final entries = options.entries.toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0x12172767), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in entries)
            Semantics(
              selected: e.key == value,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 6 : 9),
                  decoration: BoxDecoration(color: e.key == value ? C.navy : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                  child: Text(e.value, style: T.ui(small ? 13 : 14, color: e.key == value ? C.card : C.navy, weight: FontWeight.w800)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.format, required this.style, this.duration = const Duration(milliseconds: 700)});
  final double value;
  final String Function(double) format;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (motionOff(context)) return Text(format(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(format(v), style: style),
    );
  }
}

class BackBar extends StatelessWidget {
  const BackBar({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(children: [
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: C.ink),
        ),
        Expanded(child: Center(child: Text(title.toUpperCase(), style: T.kicker(), overflow: TextOverflow.ellipsis))),
        SizedBox(width: 52, child: trailing),
      ]),
    );
  }
}

class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.message, this.onRetry, this.actionLabel = 'Try again'});
  final String message;
  final VoidCallback? onRetry;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0x1AE74B47), borderRadius: BorderRadius.circular(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.cloud_off_rounded, size: 20, color: C.crimson),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message, style: T.ui(14, color: C.ink, weight: FontWeight.w600, height: 1.4)),
            if (onRetry != null) ...[
              const SizedBox(height: 6),
              Press(onTap: onRetry, child: Text(actionLabel, style: T.ui(14, color: C.crimson, weight: FontWeight.w800))),
            ],
          ]),
        ),
      ]),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.gemini, this.model});
  final bool gemini;
  final String? model;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(gemini ? Icons.auto_awesome : Icons.phone_android_rounded, size: 13, color: C.muted),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          gemini ? 'Written by Gemini${model != null ? ' · $model' : ''}' : 'Computed on this phone',
          style: T.ui(12, color: C.muted, weight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

class HelpCard extends StatelessWidget {
  const HelpCard({super.key, required this.emergency});
  final bool emergency;
  @override
  Widget build(BuildContext context) {
    final number = emergency ? '112' : '14416';
    return PaperCard(
      color: C.crimson,
      border: false,
      onTap: () => launchUrl(Uri.parse('tel:$number')),
      child: Row(children: [
        const Icon(Icons.support_rounded, color: C.card),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emergency ? 'Emergency: 112' : 'Tele-MANAS: 14416', style: T.ui(15, color: C.card, weight: FontWeight.w800)),
            Text(emergency ? "Tap to call now. Don't wait on a wearable." : 'Free, 24×7, in 20+ Indian languages. Tap to call.', style: T.ui(13, color: C.card, weight: FontWeight.w500)),
          ]),
        ),
        const Icon(Icons.call_rounded, color: C.card),
      ]),
    );
  }
}

/// A 7-day experiment, offered wherever the data suggests it.
class ExperimentCard extends StatelessWidget {
  const ExperimentCard({super.key, required this.id, this.dark = false});
  final String id;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final info = experiments[id]!;
    final run = app.runs[id];
    final impact = app.insights.experimentImpact(id);
    final prog = run == null ? null : app.insights.progress(run);
    final fg = dark ? C.card : C.ink;
    final accent = dark ? C.sun : C.crimson;
    void open() => Navigator.of(context).push(slideRoute(ExperimentScreen(id: id)));
    return PaperCard(
      color: dark ? C.navy : C.card,
      border: !dark,
      onTap: open,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.science_outlined, size: 16, color: accent),
          const SizedBox(width: 6),
          Kicker('7-day experiment', color: accent),
        ]),
        const SizedBox(height: 8),
        Text(info.title, style: T.display(30, color: fg)),
        const SizedBox(height: 4),
        Text(info.why, style: T.serif(15, color: dark ? C.card.withValues(alpha: 0.85) : C.muted)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text(
              impact != null ? 'Your data says: +${impact.delta} ${impact.unit}' : 'Not enough data to predict yet',
              style: T.ui(13, color: dark ? C.sun : C.teal, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          if (run == null)
            Pill(
              label: 'Start',
              bg: C.crimson,
              height: 42,
              onTap: () {
                app.startExperiment(id);
                showToast(context, 'Experiment started: ${info.title}', good: true);
                open();
              },
            )
          else
            Pill(
              label: prog!.done ? 'See result' : 'Day ${prog.todayIndex + 1} of ${info.days}',
              bg: dark ? C.card : C.navy,
              fg: dark ? C.navy : C.card,
              height: 42,
              onTap: open,
            ),
        ]),
      ]),
    );
  }
}
