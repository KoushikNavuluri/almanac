import 'package:flutter/material.dart';

import '../domain/insights.dart';
import '../domain/metrics.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/sky.dart';
import 'ai_settings_screen.dart';
import 'metric_screen.dart';

String bestExperiment(Insights ins) {
  var best = 'kitchen';
  var bestDelta = -1;
  for (final id in experiments.keys) {
    if (id == 'weekend') continue;
    final imp = ins.experimentImpact(id);
    if (imp != null && imp.delta > bestDelta) {
      best = id;
      bestDelta = imp.delta;
    }
  }
  return best;
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ins = app.insights;
    final score = ins.readiness();
    final cond = ins.condition(score);
    final top = MediaQuery.of(context).padding.top;
    final brief = app.brief;
    final fresh = (brief != null && brief.dataKey == app.dataKey) ? brief : null;
    if (app.aiReady && fresh == null && !app.briefLoading && app.briefError == null && ins.today != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => app.refreshBrief());
    }
    final tipTitle = fresh?.tipTitle ?? '';
    final tipBody = fresh?.tipBody ?? '';
    final tipModel = fresh?.model;

    return RefreshIndicator(
      color: C.crimson,
      onRefresh: () async {
        await app.sync(force: true);
        await app.refreshBrief(force: true);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SkyView(
            score: score,
            condition: cond.id,
            height: 318 + top,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, top + 14, 20, 30),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Almanac', style: T.display(26, color: C.card).copyWith(letterSpacing: 1.6)),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtDay(ins.now).toUpperCase()} · ${app.isSample ? 'SAMPLE EDITION' : 'YOUR EDITION'}',
                        style: T.kicker(color: C.card.withValues(alpha: 0.85)),
                      ),
                    ]),
                  ),
                  Press(
                    semantics: 'Settings',
                    onTap: () => app.setTab(4),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: C.card.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: C.card.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.tune_rounded, color: C.card, size: 20),
                    ),
                  ),
                ]),
                const Spacer(),
                Kicker("Today's body forecast", color: C.card.withValues(alpha: 0.9)),
                const SizedBox(height: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (score == null)
                    Text('–', style: T.display(120, color: C.card, height: 0.8))
                  else
                    CountUp(value: score.toDouble(), format: (v) => v.round().toString(), style: T.display(132, color: C.card, height: 0.78)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(cond.label, style: T.display(34, color: C.card, height: 0.95)),
                        Text(cond.line, style: T.serif(15, color: C.card.withValues(alpha: 0.92), style: FontStyle.italic, height: 1.3)),
                      ]),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -16),
            child: Container(
              decoration: const BoxDecoration(color: C.paper, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _DataBanner(),
                _ForecasterNote(fresh: fresh != null),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PaperCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Energy, hour by hour', style: T.display(26))),
                    Text('Now ', style: T.ui(12, color: C.muted, weight: FontWeight.w700)),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: C.crimson, shape: BoxShape.circle)),
                  ]),
                  const SizedBox(height: 6),
                  EnergyStrip(curve: ins.energyCurve()),
                ]),
              ),
              const SizedBox(height: 32),
              Text('Last night, plainly.', style: T.display(38)),
              const SizedBox(height: 6),
              const _NightRows(),
              const SizedBox(height: 24),
              const _TodaySoFar(),
              if (tipBody.isNotEmpty) ...[
                const SizedBox(height: 32),
                const Kicker('One thing for today', color: C.crimson),
                const SizedBox(height: 8),
                PaperCard(
                  color: C.sun,
                  border: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tipTitle, style: T.display(30)),
                    const SizedBox(height: 6),
                    Text(tipBody, style: T.serif(16)),
                    const SizedBox(height: 10),
                    SourceBadge(gemini: true, model: tipModel),
                  ]),
                ),
              ],
              const SizedBox(height: 32),
              const Kicker('Try tonight', color: C.crimson),
              const SizedBox(height: 8),
              ExperimentCard(id: bestExperiment(ins), dark: true),
              const _DiscoveryOfTheDay(),
              const SizedBox(height: 28),
              const _Footer(),
              const SizedBox(height: 28),
            ]),
          ),
        ],
      ),
    );
  }
}

class _DataBanner extends StatelessWidget {
  const _DataBanner();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final err = app.syncError;
    Widget? child;
    if (app.syncing) {
      child = Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.crimson)),
        const SizedBox(width: 10),
        Text('Syncing Health Connect…', style: T.ui(14, color: C.muted)),
      ]);
    } else if (err != null) {
      child = ErrorNote(message: err, onRetry: () => app.sync(force: true), actionLabel: 'Sync again');
    } else if (app.isSample) {
      child = PaperCard(
        color: const Color(0x14172767),
        border: false,
        padding: const EdgeInsets.all(14),
        onTap: () => app.setTab(4),
        child: Row(children: [
          const Icon(Icons.science_outlined, size: 18, color: C.navy),
          const SizedBox(width: 10),
          Expanded(child: Text('You are exploring sample data. Connect Health Connect in Me to see yours.', style: T.ui(14, color: C.navy, height: 1.4))),
        ]),
      );
    } else if (app.insights.isEmpty) {
      child = ErrorNote(
        message: 'No readings yet. Make sure your tracker and meal app sync to Health Connect, then pull down to refresh.',
        onRetry: () => app.sync(force: true),
        actionLabel: 'Sync now',
      );
    }
    if (child == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 18), child: child);
  }
}

class _ForecasterNote extends StatelessWidget {
  const _ForecasterNote({required this.fresh});
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = fresh ? app.brief : null;
    final text = b != null ? (app.depth == 'nerdy' ? b.noteNerdy : b.noteSimple) : app.insights.forecasterNote(app.depth);
    final err = app.briefError;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Kicker('From the forecaster', color: C.crimson)),
        Segmented<String>(value: app.depth, options: const {'simple': 'Simple', 'nerdy': 'Nerdy'}, onChanged: app.setDepth, small: true),
      ]),
      const SizedBox(height: 12),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(text, key: ValueKey(text), style: T.serif(18, height: 1.6)),
      ),
      const SizedBox(height: 10),
      if (app.briefLoading)
        Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.crimson)),
          const SizedBox(width: 8),
          Text("The forecaster is writing today's note…", style: T.ui(13, color: C.muted)),
        ])
      else
        SourceBadge(gemini: b != null, model: b?.model),
      if (err != null) ...[
        const SizedBox(height: 10),
        ErrorNote(message: err, onRetry: () => app.refreshBrief(force: true)),
      ],
      if (!app.hasKey) ...[
        const SizedBox(height: 10),
        Press(
          onTap: () => Navigator.of(context).push(slideRoute(const AiSettingsScreen())),
          child: Text('Add your Gemini key for a personal write-up →', style: T.ui(14, color: C.crimson, weight: FontWeight.w800)),
        ),
      ],
      const SizedBox(height: 14),
      Press(
        onTap: () => app.ask('Why do I feel like this today?'),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: C.crimson),
          const SizedBox(width: 8),
          Text('Ask why I feel like this', style: T.ui(14, color: C.crimson, weight: FontWeight.w800)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: C.crimson),
        ]),
      ),
      const SizedBox(height: 26),
    ]);
  }
}

class _NightRows extends StatelessWidget {
  const _NightRows();

  String _line(Insights ins, String key, double v) {
    final b = ins.baseline(key);
    switch (key) {
      case 'sleepMin':
        {
          if (!b.ok) return 'Asleep ${fmtDur(v)}.';
          final gap = (v - b.mean).round();
          if (gap < -10) return 'Asleep ${fmtDur(v)}. About ${-gap} min short of your usual.';
          if (gap > 10) return 'Asleep ${fmtDur(v)}. $gap min more than usual.';
          return 'Asleep ${fmtDur(v)}. Right around your usual.';
        }
      case 'deep':
        return b.ok ? 'Your repair shift ran ${v.round()} min. Usually ${b.mean.round()}.' : 'Your repair shift ran ${v.round()} min.';
      case 'hrv':
        {
          if (!b.ok) return 'Calm reserve read ${v.round()} ms.';
          if (v < b.mean - b.sd * 0.5) return 'Calm reserve dipped. Your body worked through the night instead of resting.';
          if (v > b.mean + b.sd * 0.5) return 'Calm reserve is up. You recovered well.';
          return 'Calm reserve is steady, right where you like it.';
        }
      case 'rhr':
        {
          if (!b.ok) return 'Heart idled at ${v.round()} bpm.';
          final d = v - b.mean;
          final tail = d >= 2 ? ', a few beats busier than normal' : (d <= -2 ? ', calmer than usual' : ', right on your normal');
          return 'Heart idled at ${v.round()} bpm$tail.';
        }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ins = app.insights;
    final day = ins.today;
    const keys = ['sleepMin', 'deep', 'hrv', 'rhr'];
    const units = {'sleepMin': 'asleep', 'deep': 'min deep', 'hrv': 'ms · HRV', 'rhr': 'bpm resting'};
    if (day == null || keys.every((k) => day.value(k) == null)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No overnight readings for last night. Wear your tracker to bed and sync in the morning.', style: T.serif(16, color: C.muted)),
      );
    }
    final rows = <(String, double)>[];
    for (final k in keys) {
      final v = day.value(k);
      if (v != null) rows.add((k, v));
    }
    return Column(children: [
      for (var i = 0; i < rows.length; i++)
        Press(
          onTap: () => Navigator.of(context).push(slideRoute(MetricScreen(metricKey: rows[i].$1))),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: C.rule))),
            child: Row(children: [
              SizedBox(
                width: 96,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(fmtValue(rows[i].$1, rows[i].$2), style: T.display(40)),
                  ),
                  Text(units[rows[i].$1]!.toUpperCase(), style: T.kicker(size: 11)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_line(ins, rows[i].$1, rows[i].$2), style: T.ui(15, weight: FontWeight.w500, height: 1.45)),
                  const SizedBox(height: 6),
                  StatusChip(ins.status(rows[i].$1)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: C.muted),
            ]),
          ),
        ),
    ]);
  }
}

class _TodaySoFar extends StatelessWidget {
  const _TodaySoFar();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ins = app.insights;
    final steps = ins.today?.steps;
    final protein = ins.today?.protein;
    if (steps == null && protein == null) return const SizedBox.shrink();
    Widget tile(String key, Widget big, String sub, Color bg) => Expanded(
          child: Press(
            onTap: () => Navigator.of(context).push(slideRoute(MetricScreen(metricKey: key))),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                big,
                const SizedBox(height: 2),
                Text(sub, style: T.ui(13, weight: FontWeight.w600, height: 1.35)),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Kicker('Today so far'),
      const SizedBox(height: 8),
      Row(children: [
        if (steps != null)
          tile(
            'steps',
            CountUp(value: steps, format: fmtInt, style: T.display(34)),
            steps >= 9000 ? 'steps · sweet spot reached' : 'steps · ${fmtInt(9000 - steps)} to your sweet spot',
            C.amber.withValues(alpha: 0.25),
          ),
        if (steps != null && protein != null) const SizedBox(width: 12),
        if (protein != null)
          tile(
            'protein',
            CountUp(value: protein, format: (v) => '${v.round()}g', style: T.display(34)),
            'protein logged · aim for ${ins.proteinTarget.round()}',
            C.teal.withValues(alpha: 0.15),
          ),
      ]),
    ]);
  }
}

class _DiscoveryOfTheDay extends StatelessWidget {
  const _DiscoveryOfTheDay();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = app.brief;
    final fb = (b != null && b.dataKey == app.dataKey) ? b : null;
    final aiHeads = fb == null ? const <String>[] : fb.discoveries.map((d) => d.head).toList();
    final local = app.insights.discoveries();
    final String? head = aiHeads.isNotEmpty ? aiHeads.first : (local.isNotEmpty ? local.first.head : null);
    if (head == null) return const SizedBox.shrink();
    final count = aiHeads.length + local.length;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: PaperCard(
        color: C.sun,
        border: false,
        padding: const EdgeInsets.all(20),
        onTap: () => app.setTab(1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome, size: 16, color: C.navy),
            SizedBox(width: 6),
            Kicker('Discovery of the day', color: C.navy),
          ]),
          const SizedBox(height: 8),
          Text(head, style: T.display(32, height: 0.95)),
          const SizedBox(height: 12),
          Text(count > 1 ? '${count - 1} more in Discover →' : 'Open Discover →', style: T.ui(14, color: C.crimson, weight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ins = app.insights;
    final t = ins.today;
    final y = t == null ? null : ins.prevOf(t);
    final ls = app.lastSync;
    final line1 = app.isSample
        ? 'Sample data · nothing leaves this phone'
        : ls == null
            ? 'Not synced yet'
            : 'Synced ${fmtTime(ls)} · Health Connect';
    final dinner = y?.dinnerName;
    final at = y?.lastMealMin;
    return Center(
      child: Text(
        dinner != null && at != null ? '$line1\nYesterday\'s dinner: $dinner, ${fmtClock(at)}' : line1,
        textAlign: TextAlign.center,
        style: T.ui(12, color: C.muted, weight: FontWeight.w500, height: 1.5),
      ),
    );
  }
}
