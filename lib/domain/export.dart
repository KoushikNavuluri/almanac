import '../ai/chat_models.dart';
import '../models/day_record.dart';
import '../utils/format.dart';
import 'insights.dart';

String _csvCell(String v) => v.contains(',') || v.contains('"') || v.contains('\n') ? '"${v.replaceAll('"', '""')}"' : v;

String recordsCsv(List<DayRecord> records) {
  const cols = [
    'date', 'sleep_min', 'deep_min', 'rem_min', 'light_min', 'awake_min', 'bedtime', 'wake_time',
    'hrv_ms', 'resting_hr_bpm', 'spo2_pct', 'breaths_per_min', 'steps', 'kcal', 'protein_g', 'last_meal', 'meals',
  ];
  String n(double? v, [int dp = 0]) => v == null ? '' : v.toStringAsFixed(dp);
  final lines = <String>[cols.join(',')];
  for (final r in records) {
    lines.add([
      r.date,
      n(r.sleepMin),
      n(r.deep),
      n(r.rem),
      n(r.light),
      n(r.awake),
      r.bedtime == null ? '' : fmtClock(r.bedtime!),
      r.wake == null ? '' : fmtClock(r.wake!),
      n(r.hrv),
      n(r.rhr),
      n(r.spo2, 1),
      n(r.breathing, 1),
      n(r.steps),
      n(r.kcal),
      n(r.protein),
      r.lastMealMin == null ? '' : fmtClock(r.lastMealMin!),
      _csvCell(r.meals.map((m) => '${fmtClock(m.minute.toDouble())} ${m.name}').join(' | ')),
    ].join(','));
  }
  return lines.join('\n');
}

String weeklyEdition(Insights ins, {DailyBrief? brief, String name = ''}) {
  final week = ins.records.length > 7 ? ins.records.sublist(ins.records.length - 7) : ins.records;
  double? avg(String k) {
    final v = week.map((r) => r.value(k)).whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  final score = ins.readiness();
  final c = ins.condition(score);
  final b = StringBuffer()
    ..writeln('# Almanac · Weekly edition')
    ..writeln('${name.isNotEmpty ? '$name · ' : ''}week ending ${fmtDate(isoDate(ins.now), long: true)} ${ins.now.year}')
    ..writeln()
    ..writeln('## Today')
    ..writeln(score == null ? 'No forecast yet.' : '$score · ${c.label}. ${c.line}.')
    ..writeln()
    ..writeln(brief?.noteSimple ?? ins.forecasterNote('simple'))
    ..writeln()
    ..writeln('## The week in numbers');
  final sleep = avg('sleepMin'), deep = avg('deep'), hrv = avg('hrv'), rhr = avg('rhr'), steps = avg('steps');
  if (sleep != null) b.writeln('- Sleep: ${fmtDur(sleep)} a night');
  if (deep != null) b.writeln('- Deep sleep: ${deep.round()} min');
  if (hrv != null) b.writeln('- Calm reserve (HRV): ${hrv.round()} ms');
  if (rhr != null) b.writeln('- Resting heart: ${rhr.round()} bpm');
  if (steps != null) b.writeln('- Steps: ${fmtInt(steps)} a day');
  b.writeln('- Dinners after 10 PM: ${week.where((r) => r.lateDinner).length}');
  final stories = ins.discoveries().take(3).toList();
  if (stories.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Top stories');
    for (final d in stories) {
      b.writeln('- **${d.head}.** ${d.body}');
    }
  }
  if (brief != null && brief.tipBody.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Try this')
      ..writeln('**${brief.tipTitle}.** ${brief.tipBody}');
  }
  b
    ..writeln()
    ..writeln('---')
    ..writeln('Computed on-device by Almanac from Health Connect data. Wearable numbers are estimates. Not medical advice.');
  return b.toString();
}
