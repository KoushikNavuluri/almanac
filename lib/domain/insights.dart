import 'dart:math' as math;

import '../models/day_record.dart';
import '../utils/format.dart';
import 'metrics.dart';

enum Tone { great, good, neutral, soft, watch }

class Baseline {
  const Baseline(this.mean, this.sd, this.n);
  final double mean, sd;
  final int n;
  bool get ok => n >= 5;
}

class MetricStatus {
  const MetricStatus(this.word, this.tone);
  final String word;
  final Tone tone;
}

class Condition {
  const Condition(this.id, this.label, this.line);
  final String id, label, line;
}

class EnergyPoint {
  const EnergyPoint(this.h, this.v);
  final double h, v;
}

class EnergyCurve {
  const EnergyCurve(this.pts, this.peak, this.dip, this.second);
  final List<EnergyPoint> pts;
  final EnergyPoint peak, dip, second;
}

class Split {
  const Split(this.yes, this.no, this.nYes, this.nNo);
  final double yes, no;
  final int nYes, nNo;
  double get diff => yes - no;
  bool get ok => nYes >= 3 && nNo >= 3;
}

class Reading {
  const Reading(this.value, this.date, this.isToday);
  final double value;
  final String date;
  final bool isToday;
}

class Impact {
  const Impact(this.delta, this.unit, this.metric);
  final int delta;
  final String unit, metric;
}

abstract class Viz {
  const Viz();
}

class BarsViz extends Viz {
  const BarsViz(this.aLabel, this.a, this.bLabel, this.b, this.unit, {this.decimals = 0});
  final String aLabel, bLabel, unit;
  final double a, b;
  final int decimals;
}

class BigViz extends Viz {
  const BigViz(this.value, this.label);
  final String value, label;
}

class SparkViz extends Viz {
  const SparkViz(this.metric);
  final String metric;
}

class ClockViz extends Viz {
  const ClockViz(this.minutes);
  final double minutes;
}

class RouteViz extends Viz {
  const RouteViz(this.km, this.reached, this.next, this.nextKm);
  final double km;
  final String reached;
  final String? next;
  final double? nextKm;
}

class Discovery {
  const Discovery({
    required this.id,
    required this.kind,
    required this.head,
    required this.body,
    required this.basis,
    required this.metric,
    this.experiment,
    this.ask,
    this.viz,
    this.ai = false,
  });
  final String id, kind, head, body, basis, metric;
  final String? experiment, ask;
  final Viz? viz;
  final bool ai;
}

class ExperimentRun {
  ExperimentRun({required this.id, required this.start, Map<String, bool>? checkins}) : checkins = checkins ?? {};
  final String id;
  final String start;
  final Map<String, bool> checkins;

  Map<String, dynamic> toJson() => {'id': id, 'start': start, 'checkins': checkins};

  factory ExperimentRun.fromJson(Map<String, dynamic> j) => ExperimentRun(
        id: j['id'] as String,
        start: j['start'] as String,
        checkins: Map<String, bool>.from((j['checkins'] as Map?) ?? const {}),
      );
}

class ExperimentProgress {
  const ExperimentProgress({
    required this.dates,
    required this.todayIndex,
    required this.done,
    required this.kept,
    required this.answered,
    this.measured,
    this.baseline,
    this.nights = 0,
  });

  /// The 7 calendar days of the experiment.
  final List<String> dates;

  /// 0-based index of today inside [dates], or dates.length when the week is over.
  final int todayIndex;
  final bool done;
  final int kept, answered;
  final double? measured, baseline;
  final int nights;
}

double _mean(Iterable<double> v) {
  final l = v.toList();
  return l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;
}

double _sd(Iterable<double> v) {
  final l = v.toList();
  if (l.length < 2) return 0;
  final m = _mean(l);
  return math.sqrt(_mean(l.map((x) => (x - m) * (x - m))));
}

const _destinations = [
  (km: 42.0, to: 'a full marathon'),
  (km: 148.0, to: 'Warangal'),
  (km: 275.0, to: 'Vijayawada'),
  (km: 570.0, to: 'Bengaluru'),
  (km: 625.0, to: 'Chennai'),
  (km: 710.0, to: 'Mumbai'),
  (km: 1500.0, to: 'Delhi'),
];

/// Every claim Almanac makes is computed here from the person's own records.
class Insights {
  Insights(List<DayRecord> input, {DateTime? now, this.weightKg})
      : now = now ?? DateTime.now(),
        records = (List<DayRecord>.of(input)..sort((a, b) => a.date.compareTo(b.date))) {
    final key = isoDate(this.now);
    today = records.isNotEmpty && records.last.date == key ? records.last : null;
    history = today == null ? records : records.sublist(0, records.length - 1);
    _byDate = {for (final r in records) r.date: r};
  }

  final DateTime now;
  final double? weightKg;
  final List<DayRecord> records;
  late final DayRecord? today;
  late final List<DayRecord> history;
  late final Map<String, DayRecord> _byDate;
  final Map<String, Baseline> _baselines = {};

  bool get isEmpty => records.every((r) => r.sleepMin == null && r.steps == null && r.meals.isEmpty && r.rhr == null);
  int get nightsWithSleep => records.where((r) => r.sleepMin != null).length;
  double get proteinTarget => ((weightKg ?? 68) * 0.83).roundToDouble();
  bool get inIndia => now.timeZoneOffset == const Duration(hours: 5, minutes: 30);

  List<DayRecord> get last30 => history.length > 30 ? history.sublist(history.length - 30) : history;

  DayRecord? byDate(String iso) => _byDate[iso];
  DayRecord? prevOf(DayRecord r) => _byDate[isoDate(addDays(r.day, -1))];

  Baseline baseline(String key, {int days = 30}) => _baselines.putIfAbsent('$key:$days', () {
        final rows = history.length > days ? history.sublist(history.length - days) : history;
        final vals = rows.map((r) => r.value(key)).whereType<double>().toList();
        final sd = _sd(vals);
        return Baseline(_mean(vals), sd == 0 ? 1 : sd, vals.length);
      });

  /// Latest value for a metric: today's record first, then the most recent day that has it.
  Reading? reading(String key) {
    final t = today;
    final tv = t?.value(key);
    if (t != null && tv != null) return Reading(tv, t.date, true);
    for (final r in history.reversed) {
      final v = r.value(key);
      if (v != null) return Reading(v, r.date, false);
    }
    return null;
  }

  static const _dayMetrics = {'steps', 'kcal', 'protein', 'lastMealMin'};

  MetricStatus status(String key, [double? value]) {
    final rd = value == null ? reading(key) : null;
    final v = value ?? rd?.value;
    if (v == null) return const MetricStatus('no reading yet', Tone.neutral);
    if (rd != null && rd.isToday && (today?.partial ?? false) && _dayMetrics.contains(key)) {
      return const MetricStatus('day still going', Tone.neutral);
    }
    final b = baseline(key);
    if (!b.ok) return const MetricStatus('learning your normal', Tone.neutral);
    final z = (v - b.mean) / b.sd;
    final score = (metrics[key]?.lowerIsBetter ?? false) ? -z : z;
    if (score <= -1.2) return const MetricStatus('well off your normal', Tone.watch);
    if (score <= -0.5) return const MetricStatus('a bit off your normal', Tone.soft);
    if (score >= 1.2) return const MetricStatus('one of your best', Tone.great);
    if (score >= 0.5) return const MetricStatus('better than usual', Tone.good);
    return const MetricStatus('right on your normal', Tone.neutral);
  }

  // ---------------------------------------------------------------- forecast

  int? readiness([DayRecord? r]) {
    final rec = r ?? today;
    if (rec == null) return null;
    double? z(String k) {
      final v = rec.value(k);
      final b = baseline(k);
      if (v == null || !b.ok) return null;
      return (v - b.mean) / b.sd;
    }

    var score = 84.0;
    var parts = 0;
    final zh = z('hrv'), zr = z('rhr'), zs = z('sleepMin');
    if (zh != null) {
      score += zh * 5;
      parts++;
    }
    if (zr != null) {
      score -= zr * 3;
      parts++;
    }
    if (zs != null) {
      score += zs * 3;
      parts++;
    }
    if (parts == 0) return null;
    if ((rec.deep ?? 999) < 60) score -= 3;
    return score.clamp(18, 98).round();
  }

  Condition condition(int? score) {
    if (score == null) return const Condition('unknown', 'No forecast yet', 'Sync a night of sleep to see it');
    if (score >= 82) return const Condition('bright', 'Bright', 'Clear skies all day');
    if (score >= 72) return const Condition('clear', 'Clear', 'Steady, with a light breeze');
    if (score >= 60) return const Condition('partly', 'Partly cloudy', 'Foggy start, clearing by noon');
    if (score >= 48) return const Condition('overcast', 'Overcast', 'Low ceiling. Go easy');
    return const Condition('storm', 'Stormy', 'Rest is the plan today');
  }

  EnergyCurve energyCurve() {
    final score = readiness() ?? 72;
    final w = today?.wake;
    final wakeH = w != null ? (w % 1440) / 60 : 7.0;
    final deepLow = (today?.deep ?? 80) < 60;
    final amp = 0.55 + score / 200;
    final pts = <EnergyPoint>[];
    for (var h = 6.0; h <= 23.5; h += 0.5) {
      final t = h - wakeH;
      final rise = 1 / (1 + math.exp(-(t - 1.0) * 1.8));
      final peak1 = math.exp(-((t - 3.6) * (t - 3.6)) / 6);
      final dip = math.exp(-((t - 7.4) * (t - 7.4)) / 1.6) * (0.55 + (deepLow ? 0.2 : 0));
      final peak2 = math.exp(-((t - 10.6) * (t - 10.6)) / 5) * 0.75;
      final fall = 1 / (1 + math.exp((t - 15.5) * 1.1));
      final v = (rise * 0.45 + peak1 * 0.4 + peak2 * 0.35 - dip * 0.35) * fall * amp;
      pts.add(EnergyPoint(h, v.clamp(0.05, 1.0).toDouble()));
    }
    EnergyPoint pick(bool Function(EnergyPoint) where, bool max) =>
        pts.where(where).reduce((a, b) => max ? (b.v > a.v ? b : a) : (b.v < a.v ? b : a));
    return EnergyCurve(
      pts,
      pick((p) => p.h < 13, true),
      pick((p) => p.h > 12 && p.h < 17, false),
      pick((p) => p.h > 15 && p.h < 21, true),
    );
  }

  // ---------------------------------------------------------------- patterns

  Split split(bool Function(DayRecord prev) pred, String key, {bool Function(DayRecord prev)? known}) {
    final yes = <double>[], no = <double>[];
    for (final r in history) {
      final p = prevOf(r);
      final v = r.value(key);
      if (p == null || v == null) continue;
      if (known != null && !known(p)) continue;
      (pred(p) ? yes : no).add(v);
    }
    return Split(_mean(yes), _mean(no), yes.length, no.length);
  }

  late final Split lateDinnerDeep = split((p) => p.lateDinner, 'deep', known: (p) => p.lastMealMin != null);
  late final Split lateDinnerHrv = split((p) => p.lateDinner, 'hrv', known: (p) => p.lastMealMin != null);
  late final Split lateDinnerRhr = split((p) => p.lateDinner, 'rhr', known: (p) => p.lastMealMin != null);
  late final Split bigDaySleep = split((p) => (p.steps ?? 0) > 9000, 'sleepMin', known: (p) => p.steps != null);
  late final Split chaiSleep = split((p) => p.caffeineLate, 'sleepMin', known: (p) => p.meals.isNotEmpty);

  double? get socialJetLagMin {
    double? mid(DayRecord r) {
      final b = r.bedtime, s = r.sleepMin;
      if (b == null || s == null) return null;
      return b + (s + (r.awake ?? 0)) / 2;
    }

    final we = history.where((r) => r.weekday >= 6).map(mid).whereType<double>().toList();
    final wd = history.where((r) => r.weekday >= 2 && r.weekday <= 5).map(mid).whereType<double>().toList();
    if (we.length < 2 || wd.length < 3) return null;
    return _mean(we) - _mean(wd);
  }

  String jetLagPlace(double mins) {
    if (!inIndia) {
      final h = (mins / 60).toStringAsFixed(1);
      return 'a time zone ${h}h east';
    }
    if (mins >= 80) return 'Bangkok';
    if (mins >= 50) return 'Yangon';
    return 'Kathmandu';
  }

  ({double a, double b, double pct})? get hrvTrend {
    final rows = history.where((r) => r.hrv != null).toList();
    if (rows.length < 20) return null;
    final a = _mean(rows.take(14).map((r) => r.hrv!));
    final b = _mean(rows.skip(rows.length - 14).map((r) => r.hrv!));
    if (a == 0) return null;
    return (a: a, b: b, pct: (b - a) / a * 100);
  }

  double get beats30 => last30.where((r) => r.rhr != null).fold<double>(0, (s, r) => s + (r.rhr! + 13) * 1440);
  int get rhrDays30 => last30.where((r) => r.rhr != null).length;
  double get remHours30 => last30.fold<double>(0, (s, r) => s + (r.rem ?? 0)) / 60;
  double get stepsTotal => records.fold<double>(0, (s, r) => s + (r.steps ?? 0));
  double get km => stepsTotal * 0.76 / 1000;

  ({String reached, String? next, double? nextKm}) get walkedTo {
    var reached = 'the corner shop';
    String? next;
    double? nextKm;
    for (final d in _destinations) {
      if (km >= d.km) {
        reached = d.to;
      } else {
        next = d.to;
        nextKm = d.km;
        break;
      }
    }
    return (reached: reached, next: next, nextKm: nextKm);
  }

  DayRecord? get bestNight {
    DayRecord? best;
    for (final r in history) {
      if (r.sleepMin == null) continue;
      if (best == null || r.sleepMin! > best.sleepMin!) best = r;
    }
    return best;
  }

  int get best7hStreak {
    var cur = 0, best = 0;
    for (final r in history) {
      cur = (r.sleepMin ?? 0) >= 420 ? cur + 1 : 0;
      best = math.max(best, cur);
    }
    return best;
  }

  // ---------------------------------------------------------------- words

  String forecasterNote(String depth) {
    final t = today;
    final sleep = t?.sleepMin;
    if (t == null || sleep == null) {
      return 'No sleep reading for last night yet. Wear your tracker tonight and sync in the morning. The forecast writes itself from there.';
    }
    final s = baseline('sleepMin'), d = baseline('deep'), h = baseline('hrv'), r = baseline('rhr');
    if (!s.ok) {
      return 'You slept ${fmtDur(sleep)}. Give me a few more nights and I can tell you what that means for you.';
    }
    final gap = (sleep - s.mean).round();
    final y = prevOf(t);
    final causes = <String>[];
    if (y != null && y.lateDinner) {
      final name = y.dinnerName;
      causes.add('dinner at ${fmtClock(y.lastMealMin!)}${name != null ? ' ($name)' : ''}');
    }
    if (y != null && y.caffeineLate) causes.add('caffeine after 4 PM');
    if (y != null && y.steps != null && y.steps! < 5500) causes.add('a quiet ${fmtInt(y.steps!)}-step day');
    final dip = fmtClock(energyCurve().dip.h * 60);

    if (depth == 'nerdy') {
      final parts = <String>['TST ${fmtDur(sleep)} (${signed(gap)} min vs 30-day mean)'];
      if (t.deep != null && d.ok) parts.add('N3 ${t.deep!.round()} min (${signed(t.deep! - d.mean)})');
      if (t.hrv != null && h.ok) parts.add('RMSSD ${t.hrv!.round()} ms (${signed(t.hrv! - h.mean)})');
      if (t.rhr != null && r.ok) parts.add('RHR ${t.rhr!.round()} bpm (${signed(t.rhr! - r.mean)})');
      final cause = causes.isNotEmpty ? ' Likely contributors: ${causes.join(' and ')}.' : '';
      return '${parts.join(', ')}.$cause Expect the post-lunch trough near $dip.';
    }

    final b = StringBuffer();
    if (gap <= -20) {
      b.write('You slept ${-gap} minutes less than usual');
    } else if (gap >= 20) {
      b.write('You slept $gap minutes more than usual');
    } else {
      b.write('You slept about your usual ${fmtDur(sleep)}');
    }
    final deep = t.deep;
    if (deep != null && d.ok && deep < d.mean - d.sd * 0.6) {
      b.write(', and deep sleep took the hit.');
    } else if (deep != null && d.ok && deep > d.mean + d.sd * 0.6) {
      b.write(', with extra deep sleep. Nice.');
    } else {
      b.write('.');
    }
    if (causes.isNotEmpty && gap < 0) b.write(' Likely culprit: ${causes.first}.');
    final score = readiness();
    if (score != null) {
      if (score >= 80) {
        b.write(' Clear day ahead. Use it.');
      } else if (score >= 60) {
        b.write(' Foggy start, clearing by noon. Guard your $dip.');
      } else {
        b.write(' Low ceiling today. Go easy and get to bed early.');
      }
    }
    return b.toString();
  }

  List<Discovery> discoveries() {
    final out = <Discovery>[];
    final ld = lateDinnerDeep;
    if (ld.ok && ld.diff < -5) {
      final hrv = lateDinnerHrv;
      out.add(Discovery(
        id: 'late-dinner', kind: 'Pattern', metric: 'deep', experiment: 'kitchen',
        head: 'Late dinners cost you ${(-ld.diff).round()} min of deep sleep',
        body: 'After dinners past 10 PM your repair shift runs short${hrv.ok && hrv.diff < -1 ? ', and your calm reserve drops ${(-hrv.diff).round()} ms' : ''}.',
        viz: BarsViz('Late dinner', ld.yes, 'Done by 10', ld.no, 'min deep'),
        basis: '${ld.nYes} late nights vs ${ld.nNo} earlier ones',
        ask: 'Does late dinner hurt my sleep?',
      ));
    }
    if (rhrDays30 >= 7) {
      final scaled = beats30 * 30 / rhrDays30;
      out.add(Discovery(
        id: 'heartbeats', kind: 'Fun fact', metric: 'rhr',
        head: 'Your heart beat about ${(scaled / 1e6).toStringAsFixed(1)} million times this month',
        body: 'No breaks, no weekends.${today?.breathing != null && today?.sleepMin != null ? ' Last night you also took about ${fmtInt(today!.breathing! * today!.sleepMin!)} breaths without thinking once.' : ''}',
        viz: BigViz(fmtInt(scaled), 'beats in 30 days (estimated)'),
        basis: 'Resting heart rate + typical daytime lift, last 30 days',
        ask: 'Tell me a fun fact about my heart',
      ));
    }
    final tr = hrvTrend;
    if (tr != null && tr.pct.abs() >= 3) {
      final up = tr.pct > 0;
      out.add(Discovery(
        id: 'hrv-trend', kind: 'Trend', metric: 'hrv',
        head: 'Your calm reserve is ${up ? 'up' : 'down'} ${tr.pct.abs().round()}% in 8 weeks',
        body: up
            ? 'From ${tr.a.round()} to ${tr.b.round()} ms. Your body is bouncing back faster than it used to.'
            : 'From ${tr.a.round()} to ${tr.b.round()} ms. Stress, late meals or short nights are piling up a little.',
        viz: const SparkViz('hrv'),
        basis: 'First 2 weeks vs last 2 weeks',
        ask: "What's HRV, simply?",
      ));
    }
    final jl = socialJetLagMin;
    if (jl != null && jl >= 30) {
      final place = jetLagPlace(jl);
      out.add(Discovery(
        id: 'jetlag', kind: 'Fun fact', metric: 'rem', experiment: 'weekend',
        head: 'Every weekend you fly to $place',
        body: 'Your sleep shifts ${jl.round()} min later on weekends. Monday morning pays the jet lag.',
        viz: ClockViz(jl),
        basis: 'Mid-sleep time, weekends vs Tue–Fri',
        ask: 'Why are my Mondays rough?',
      ));
    }
    final bd = bigDaySleep;
    if (bd.ok && bd.diff > 8) {
      out.add(Discovery(
        id: 'big-day', kind: 'Pattern', metric: 'sleepMin', experiment: 'walk',
        head: '9k-step days buy you ${bd.diff.round()} extra minutes of sleep',
        body: 'Move more in the day, sleep longer at night. Your body keeps that deal most of the time.',
        viz: BarsViz('9k+ day', bd.yes / 60, 'Quieter day', bd.no / 60, 'h sleep', decimals: 1),
        basis: '${bd.nYes} big days vs ${bd.nNo} quieter ones',
        ask: 'How much should I walk?',
      ));
    }
    if (km >= 20) {
      final w = walkedTo;
      out.add(Discovery(
        id: 'walked', kind: 'Milestone', metric: 'steps',
        head: "You've walked as far as ${w.reached}",
        body: '${km.round()} km on foot, one errand at a time.${w.next != null ? ' ${w.next} is ${(w.nextKm! - km).round()} km away.' : ''}',
        viz: RouteViz(km, w.reached, w.next, w.nextKm),
        basis: '${fmtInt(stepsTotal)} steps × a 76 cm stride',
        ask: 'How much should I walk?',
      ));
    }
    final ch = chaiSleep;
    if (ch.ok && ch.diff < -8) {
      out.add(Discovery(
        id: 'chai', kind: 'Pattern', metric: 'sleepMin', experiment: 'chai',
        head: 'Caffeine after 4 PM trims ${(-ch.diff).round()} min off your night',
        body: 'Caffeine is still half-working 5 hours later. Your late-caffeine nights run short more often than not.',
        viz: BarsViz('Late caffeine', ch.yes / 60, 'None late', ch.no / 60, 'h sleep', decimals: 1),
        basis: '${ch.nYes} late-caffeine days in your meal logs',
        ask: 'Is my evening chai a problem?',
      ));
    }
    if (remHours30 >= 5) {
      out.add(Discovery(
        id: 'dreams', kind: 'Fun fact', metric: 'rem',
        head: 'You spent ${remHours30.round()} hours dreaming this month',
        body: "That's a full season of a show, watched with your eyes closed. REM is where your brain sorts the day.",
        viz: BigViz('${remHours30.round()}h', 'of REM in 30 days'),
        basis: 'REM minutes, last 30 nights',
        ask: 'What is REM sleep for?',
      ));
    }
    final best = bestNight;
    if (best != null && nightsWithSleep >= 14) {
      final before = prevOf(best)?.dinnerName;
      out.add(Discovery(
        id: 'best-night', kind: 'Milestone', metric: 'sleepMin',
        head: 'Your best night: ${fmtDate(best.date, long: true)}',
        body: '${fmtDur(best.sleepMin!)} asleep${best.deep != null ? ', ${best.deep!.round()} min of deep sleep' : ''}.${before != null ? ' Dinner the night before: $before.' : ''} Worth remembering.',
        viz: BigViz(fmtDur(best.sleepMin!), 'asleep'),
        basis: 'Out of $nightsWithSleep nights',
        ask: 'Am I sleeping enough?',
      ));
    }
    return out;
  }

  Impact? experimentImpact(String id) {
    switch (id) {
      case 'kitchen':
        final s = lateDinnerDeep;
        return s.ok && s.diff < 0 ? Impact((-s.diff).round(), 'min deep sleep', 'deep') : null;
      case 'walk':
        final s = bigDaySleep;
        return s.ok && s.diff > 0 ? Impact(s.diff.round(), 'min sleep', 'sleepMin') : null;
      case 'chai':
        final s = chaiSleep;
        return s.ok && s.diff < 0 ? Impact((-s.diff).round(), 'min sleep', 'sleepMin') : null;
      case 'weekend':
        final j = socialJetLagMin;
        return j != null && j > 0 ? Impact(j.round(), 'min of weekend drift to undo', 'rem') : null;
    }
    return null;
  }

  ExperimentProgress progress(ExperimentRun run) {
    final info = experiments[run.id]!;
    final start = parseIso(run.start);
    final dates = List.generate(info.days, (i) => isoDate(addDays(start, i)));
    final elapsed = daysBetween(start, now);
    final todayIndex = elapsed.clamp(0, info.days);
    final answered = run.checkins.length;
    final kept = run.checkins.values.where((v) => v).length;
    final done = elapsed >= info.days || answered >= info.days;
    // What happened on the nights after kept days, vs the 30 days before the start.
    final vals = <double>[];
    for (final d in dates) {
      if (run.checkins[d] != true) continue;
      final next = _byDate[isoDate(addDays(parseIso(d), 1))];
      final v = next?.value(info.metric);
      if (v != null) vals.add(v);
    }
    final before = records.where((r) => r.date.compareTo(run.start) < 0).toList();
    final pre = (before.length > 30 ? before.sublist(before.length - 30) : before)
        .map((r) => r.value(info.metric))
        .whereType<double>()
        .toList();
    return ExperimentProgress(
      dates: dates,
      todayIndex: todayIndex,
      done: done,
      kept: kept,
      answered: answered,
      measured: vals.isEmpty ? null : _mean(vals),
      baseline: pre.length < 5 ? null : _mean(pre),
      nights: vals.length,
    );
  }
}
