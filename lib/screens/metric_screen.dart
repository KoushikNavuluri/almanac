import 'package:flutter/material.dart';

import '../domain/insights.dart';
import '../domain/metrics.dart';
import '../models/day_record.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'ai_settings_screen.dart';

String _special(Insights ins, String k) {
  switch (k) {
    case 'deep':
      {
        final s = ins.lateDinnerDeep;
        return s.ok ? ' After late dinners it averages ${s.yes.round()} min. After earlier ones, ${s.no.round()}.' : '';
      }
    case 'hrv':
      {
        final s = ins.lateDinnerHrv;
        return s.ok && s.diff < 0 ? ' Late dinners pull it down about ${(-s.diff).round()} ms the next night.' : '';
      }
    case 'rhr':
      {
        final s = ins.lateDinnerRhr;
        return s.ok ? ' It runs ${s.diff.abs().toStringAsFixed(1)} bpm ${s.diff >= 0 ? 'higher' : 'lower'} after late dinners.' : '';
      }
    case 'sleepMin':
      return ' Your longest run of 7h+ nights: ${ins.best7hStreak} in a row.';
    case 'steps':
      {
        final s = ins.bigDaySleep;
        return s.ok ? ' On 9k+ days you sleep ${s.diff.abs().round()} min ${s.diff >= 0 ? 'longer' : 'shorter'} that night.' : '';
      }
    case 'lastMealMin':
      {
        final late = ins.history.where((x) => x.lateDinner).length;
        final known = ins.history.where((x) => x.lastMealMin != null).length;
        return ' $late of your last $known logged dinners finished after 10 PM.';
      }
    case 'protein':
      return ' Your target is about ${ins.proteinTarget.round()} g a day.';
  }
  return '';
}

String yoursSays(Insights ins, String k) {
  final info = metrics[k]!;
  final b = ins.baseline(k);
  final r = ins.reading(k);
  final unit = info.unit.isEmpty || k == 'sleepMin' ? '' : ' ${info.unit}';
  if (!b.ok) {
    return 'I need at least 5 days of readings to learn your normal. ${r == null ? 'No readings yet.' : 'Latest: ${fmtValue(k, r.value)}$unit.'}';
  }
  double? avg(List<DayRecord> rows) {
    final v = rows.map((x) => x.value(k)).whereType<double>().toList();
    if (v.length < 4) return null;
    return v.reduce((a, c) => a + c) / v.length;
  }

  final h = ins.history;
  final recent = avg(h.length >= 14 ? h.sublist(h.length - 14) : h);
  final prior = h.length >= 28 ? avg(h.sublist(h.length - 28, h.length - 14)) : null;
  var trend = '';
  if (recent != null && prior != null) {
    final delta = recent - prior;
    final better = (info.lowerIsBetter ? -delta : delta) > 0;
    if ((delta.abs() / b.sd) < 0.25) {
      trend = ' Steady over the last two weeks.';
    } else {
      trend = better ? ' Quietly improving over the last two weeks.' : ' Slipping a little over the last two weeks.';
    }
  }
  final lo = fmtValue(k, b.mean - b.sd), hi = fmtValue(k, b.mean + b.sd);
  const dayMetrics = {'steps', 'kcal', 'protein', 'lastMealMin'};
  var latest = '';
  if (r != null) {
    final partialToday = r.isToday && (ins.today?.partial ?? false) && dayMetrics.contains(k);
    latest = partialToday ? ' Today so far: ${fmtValue(k, r.value)}$unit.' : ' Latest: ${fmtValue(k, r.value)}$unit, ${ins.status(k).word}.';
  }
  return 'Your normal sits between $lo and $hi$unit.$latest$trend${_special(ins, k)}';
}

class MetricScreen extends StatefulWidget {
  const MetricScreen({super.key, required this.metricKey});
  final String metricKey;
  @override
  State<MetricScreen> createState() => _MetricScreenState();
}

class _MetricScreenState extends State<MetricScreen> {
  int _range = 30;

  String _axis(String k, double v) {
    switch (k) {
      case 'sleepMin':
        return '${v.toStringAsFixed(1)}h';
      case 'lastMealMin':
        return fmtClock(v).replaceAll(':00', '').replaceAll(' ', '');
      case 'steps':
      case 'kcal':
        return v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k' : v.round().toString();
      case 'spo2':
      case 'breathing':
        return v.toStringAsFixed(1);
      default:
        return v.round().toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ins = app.insights;
    final k = widget.metricKey;
    final info = metrics[k]!;
    final color = C.group(info.group);
    final r = ins.reading(k);
    final b = ins.baseline(k);
    final recs = app.records;
    final rows = recs.length > _range ? recs.sublist(recs.length - _range) : recs;
    final explanation = app.explanationFor(k);
    final explainError = app.explainErrors[k];
    final double scale = k == 'sleepMin' ? 1 / 60 : 1.0;

    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            BackBar(title: '${info.group} · ${info.tag}'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(info.name, style: T.display(56, color: color, height: 0.88)),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (r == null)
                    Text('–', style: T.display(88, color: C.ink, height: 0.8))
                  else
                    CountUp(value: r.value, format: (v) => fmtValue(k, v), style: T.display(88, color: C.ink, height: 0.8)),
                  if (info.unit.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(info.unit, style: T.display(28, color: C.muted)),
                  ],
                ]),
                if (r != null && !r.isToday) ...[
                  const SizedBox(height: 6),
                  Text('Latest reading: ${fmtDate(r.date, weekday: true)}', style: T.ui(13, color: C.muted)),
                ],
                const SizedBox(height: 12),
                StatusChip(ins.status(k)),
                const SizedBox(height: 22),
                PaperCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Expanded(child: Kicker('In plain words')),
                      Segmented<String>(value: app.depth, options: const {'simple': 'Simple', 'nerdy': 'Nerdy'}, onChanged: app.setDepth, small: true),
                    ]),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        app.depth == 'nerdy' ? info.nerdy : info.simple,
                        key: ValueKey(app.depth),
                        style: T.serif(18, height: 1.55),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                if (app.aiReady)
                  PaperCard(
                    color: const Color(0x0F172767),
                    border: false,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(Icons.auto_awesome, size: 16, color: C.crimson),
                        SizedBox(width: 6),
                        Kicker('What yours say', color: C.crimson),
                      ]),
                      const SizedBox(height: 10),
                      if (explanation != null) ...[
                        Text(explanation, style: T.serif(16, height: 1.6)),
                        const SizedBox(height: 8),
                        SourceBadge(gemini: true, model: app.model),
                      ] else if (app.isExplaining(k))
                        Row(children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.crimson)),
                          const SizedBox(width: 10),
                          Text('Reading your ${info.name.toLowerCase()}…', style: T.ui(14, color: C.muted)),
                        ])
                      else
                        Pill(label: 'Explain my numbers', icon: Icons.auto_awesome, onTap: () => app.explainMetric(k)),
                      if (explainError != null) ...[
                        const SizedBox(height: 10),
                        ErrorNote(message: explainError, onRetry: () => app.explainMetric(k)),
                      ],
                    ]),
                  )
                else
                  PaperCard(
                    color: const Color(0x0F172767),
                    border: false,
                    onTap: () => Navigator.of(context).push(slideRoute(const AiSettingsScreen())),
                    child: Row(children: [
                      const Icon(Icons.key_rounded, size: 18, color: C.navy),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Add your Gemini key and the forecaster will explain your own ${info.name.toLowerCase()} in plain words.', style: T.ui(14, color: C.navy, height: 1.4))),
                    ]),
                  ),
                const SizedBox(height: 26),
                Row(children: [
                  Expanded(child: Text('Yours, lately', style: T.display(30))),
                  Segmented<int>(value: _range, options: const {14: '2 wk', 30: '30 d', 60: '60 d'}, onChanged: (v) => setState(() => _range = v), small: true),
                ]),
                const SizedBox(height: 10),
                PaperCard(
                  padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
                  child: MetricChart(
                    values: rows.map((x) => x.value(k)).toList(),
                    dates: rows.map((x) => x.date).toList(),
                    color: color,
                    format: (v) => '${fmtValue(k, v)}${info.unit.isEmpty ? '' : ' ${info.unit}'}',
                    axisFormat: (v) => _axis(k, v),
                    bandLow: b.ok ? b.mean - b.sd : null,
                    bandHigh: b.ok ? b.mean + b.sd : null,
                    scale: scale,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                  Container(width: 20, height: 12, decoration: BoxDecoration(color: C.teal.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3))),
                  Text('Your normal range', style: T.ui(12, color: C.muted)),
                  const SizedBox(width: 8),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: C.crimson, shape: BoxShape.circle)),
                  Text('Latest · tap the chart to read a day', style: T.ui(12, color: C.muted)),
                ]),
                const SizedBox(height: 16),
                Text(yoursSays(ins, k), style: T.serif(16, height: 1.65)),
                const SizedBox(height: 22),
                _InfoBox(icon: Icons.menu_book_rounded, title: "What's normal for adults", body: info.norm, foot: 'Source: ${info.source}', color: const Color(0x0F172767)),
                const SizedBox(height: 12),
                _InfoBox(icon: Icons.lightbulb_outline_rounded, title: 'Fun fact', body: info.fact, color: C.sun.withValues(alpha: 0.45)),
                if (info.experiment != null) ...[
                  const SizedBox(height: 26),
                  const Kicker('Move this number', color: C.crimson),
                  const SizedBox(height: 8),
                  ExperimentCard(id: info.experiment!),
                ],
                const SizedBox(height: 22),
                Text('Wearable numbers are estimates. Use them for trends, not diagnosis.', style: T.ui(12, color: C.muted, weight: FontWeight.w500)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.title, required this.body, required this.color, this.foot});
  final IconData icon;
  final String title, body;
  final String? foot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final f = foot;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: C.navy),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.ui(14, weight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(body, style: T.ui(15, weight: FontWeight.w500, height: 1.45)),
            if (f != null) ...[
              const SizedBox(height: 4),
              Text(f, style: T.ui(12, color: C.muted)),
            ],
          ]),
        ),
      ]),
    );
  }
}
