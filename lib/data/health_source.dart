import 'dart:io';
import 'dart:math' as math;

import 'package:health/health.dart';

import '../models/day_record.dart';
import '../utils/format.dart';

enum HealthAvailability { ready, needsInstall, unsupported }

class HealthException implements Exception {
  HealthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Which app Almanac trusts for each category.
/// 'auto' picks your wearable (Fitbit / Google Health first), a package name pins one app,
/// and for steps 'combined' uses Health Connect's merged phone + tracker total.
class SourcePrefs {
  SourcePrefs({this.sleep = 'auto', this.steps = 'auto', this.heart = 'auto', this.countNaps = true});

  String sleep, steps, heart;

  /// Google Health adds naps to the day's sleep total. On by default to match it.
  bool countNaps;

  String of(String category) {
    switch (category) {
      case 'sleep':
        return sleep;
      case 'steps':
        return steps;
      default:
        return heart;
    }
  }

  void set(String category, String value) {
    switch (category) {
      case 'sleep':
        sleep = value;
      case 'steps':
        steps = value;
      default:
        heart = value;
    }
  }

  Map<String, dynamic> toJson() => {'sleep': sleep, 'steps': steps, 'heart': heart, 'countNaps': countNaps};

  factory SourcePrefs.fromJson(Map<String, dynamic> j) => SourcePrefs(
        sleep: (j['sleep'] ?? 'auto').toString(),
        steps: (j['steps'] ?? 'auto').toString(),
        heart: (j['heart'] ?? 'auto').toString(),
        countNaps: j['countNaps'] != false,
      );
}

/// What one sync produced. [records] covers exactly the requested window, rebuilt from scratch.
class SyncResult {
  SyncResult({
    required this.records,
    required this.weightKg,
    required this.sources,
    required this.used,
    required this.latest,
    required this.failedTypes,
    required this.elapsed,
    required this.days,
  });
  final List<DayRecord> records;
  final double? weightKg;

  /// Category -> friendly names of every app that wrote it.
  final Map<String, Set<String>> sources;

  /// Category -> friendly name of the app Almanac actually used.
  final Map<String, String> used;

  /// Category -> end time of the newest record from the app that was used.
  final Map<String, DateTime> latest;

  /// Readable names of data types whose read failed (usually a missing permission).
  final Set<String> failedTypes;
  final Duration elapsed;
  final int days;
}

typedef SyncProgress = void Function(String category);

// ------------------------------------------------------------------ data check (audit)

class AuditRow {
  AuditRow({required this.source, required this.raw, required this.value, this.detail = '', this.used = false});
  final String source;
  final String raw;
  final String value;
  final String detail;
  final bool used;
}

class AuditSection {
  AuditSection({required this.key, required this.title, required this.rows, this.note = '', this.pref});
  final String key, title, note;
  final List<AuditRow> rows;

  /// The source preference a row tap changes ('sleep', 'steps', 'heart'), or null.
  final String? pref;
}

/// Everything Health Connect holds for one day, app by app, and which app Almanac used.
class DayAudit {
  DayAudit({required this.date, required this.sections, required this.createdAt, required this.failed});
  final String date;
  final List<AuditSection> sections;
  final DateTime createdAt;
  final Set<String> failed;

  String toText() {
    final b = StringBuffer()..writeln('Almanac data check: ${fmtDate(date, weekday: true)} (made at ${fmtTime(createdAt)})');
    for (final s in sections) {
      b
        ..writeln()
        ..writeln(s.title.toUpperCase());
      if (s.rows.isEmpty) b.writeln('  nothing in Health Connect');
      for (final r in s.rows) {
        b.writeln('  ${r.used ? '[used] ' : ''}${r.source}: ${r.value}${r.detail.isEmpty ? '' : ' (${r.detail})'}');
      }
      if (s.note.isNotEmpty) b.writeln('  note: ${s.note}');
    }
    if (failed.isNotEmpty) b.writeln('\nCould not read: ${failed.join(', ')}');
    return b.toString();
  }
}

// ------------------------------------------------------------------ sources

/// "com.fitbit.FitbitMobile" -> "Google Health (Fitbit)".
String prettySource(String raw) {
  final s = raw.trim();
  final l = s.toLowerCase();
  if (s.isEmpty) return 'Unknown app';
  if (l == 'combined') return 'Health Connect, all apps merged';
  if (l.contains('fitbit')) return 'Google Health (Fitbit)';
  if (l.contains('apps.healthdata') || l == 'android' || l.startsWith('com.android.health')) return 'Phone (Health Connect)';
  if (l.contains('apps.fitness')) return 'Google Fit';
  if (l.contains('google') && l.contains('apps.health')) return 'Google Health';
  if (l.contains('cravin')) return "Cravin'";
  if (l.contains('shealth') || l.contains('samsung')) return 'Samsung Health';
  if (l.contains('garmin')) return 'Garmin';
  if (l.contains('whoop')) return 'WHOOP';
  if (l.contains('oura')) return 'Oura';
  if (l.contains('zepp') || l.contains('huami')) return 'Zepp';
  if (!s.contains('.')) return s;
  final last = s.split('.').last;
  return last.isEmpty ? s : last[0].toUpperCase() + last.substring(1);
}

/// Apps that write what a worn tracker measured (as opposed to the phone's own step counter).
bool isWearableSource(String raw) {
  final l = raw.toLowerCase();
  if (l.contains('apps.healthdata') || l.contains('apps.fitness') || l == 'android' || l.startsWith('com.android.health')) return false;
  const marks = [
    'fitbit', 'garmin', 'whoop', 'oura', 'polar', 'coros', 'suunto', 'zepp', 'huami', 'amazfit',
    'withings', 'xiaomi', 'huawei', 'ultrahuman', 'shealth', 'samsung', 'wear', 'apps.health',
  ];
  return marks.any(l.contains);
}

// ------------------------------------------------------------------ internals

class _Reading {
  const _Reading(this.at, this.value);
  final DateTime at;
  final double value;
}

class _SleepCand {
  _SleepCand(this.source);
  final String source;
  final List<HealthDataPoint> main = [];
  final List<HealthDataPoint> naps = [];
  double mainAsleep = 0, mainInBed = 0, napAsleep = 0;
  double deep = 0, rem = 0, light = 0, sleeping = 0, awake = 0;
  bool staged = false;

  double total(bool withNaps) => mainAsleep + (withNaps ? napAsleep : 0);
  double get stagedSum => deep + rem + light + sleeping;

  DateTime? get lastEnd {
    DateTime? t;
    for (final s in [...main, ...naps]) {
      if (t == null || s.dateTo.isAfter(t)) t = s.dateTo;
    }
    return t;
  }
}

class _MealStat {
  int n = 0;
  double kcal = 0;
  double protein = 0;
}

class _Analysis {
  _Analysis(this.keys, this.end);
  final List<String> keys;
  final DateTime end;
  final sleep = <String, Map<String, _SleepCand>>{};
  final steps = <String, Map<String, double>>{};
  final stepCount = <String, Map<String, int>>{};
  final stepLatest = <String, DateTime>{};
  final heart = <String, Map<String, Map<String, List<_Reading>>>>{};
  final meals = <String, List<Meal>>{};
  final mealStats = <String, Map<String, _MealStat>>{};
  final allSources = <String, Set<String>>{};
  DateTime? foodLatest;
  double? weightKg;
}

class _Built {
  _Built(this.records, this.used, this.latest);
  final List<DayRecord> records;

  /// 'sleep' | 'steps' | 'heart' | 'rhr' | 'hrv' | 'spo2' | 'breathing' -> raw source used.
  final Map<String, String> used;
  final Map<String, DateTime> latest;
}

/// Reads Health Connect and folds it into one [DayRecord] per day. Read-only.
///
/// Matching your tracker's app (Google Health / Fitbit) is the goal:
/// - Steps come from your wearable's own records, not Health Connect's phone + tracker blend
///   (that blend is why steps used to read high). Days the tracker has nothing fall back to the blend.
/// - Sleep uses one app per night, merges a night split into several sessions, and counts
///   time asleep the way Fitbit does: time in bed minus time awake. Naps are added to the day's
///   total like Google Health does (switchable).
/// - Heart metrics use one app per metric and the value that app reports for the day.
/// Every choice can be inspected and overridden per category in Me › Data check.
class HealthSource {
  final Health _health = Health();
  bool _configured = false;

  static const sleepTypes = <HealthDataType>[
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
    HealthDataType.SLEEP_OUT_OF_BED,
  ];

  static const heartTypes = <HealthDataType>[
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
  ];

  static const types = <HealthDataType>[
    ...sleepTypes,
    ...heartTypes,
    HealthDataType.STEPS,
    HealthDataType.NUTRITION,
    HealthDataType.WEIGHT,
  ];

  static const typeLabels = <HealthDataType, String>{
    HealthDataType.SLEEP_SESSION: 'Sleep',
    HealthDataType.SLEEP_DEEP: 'Sleep',
    HealthDataType.SLEEP_REM: 'Sleep',
    HealthDataType.SLEEP_LIGHT: 'Sleep',
    HealthDataType.SLEEP_ASLEEP: 'Sleep',
    HealthDataType.SLEEP_AWAKE: 'Sleep',
    HealthDataType.SLEEP_AWAKE_IN_BED: 'Sleep',
    HealthDataType.SLEEP_OUT_OF_BED: 'Sleep',
    HealthDataType.RESTING_HEART_RATE: 'Resting heart rate',
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD: 'Heart rate variability',
    HealthDataType.BLOOD_OXYGEN: 'Oxygen saturation',
    HealthDataType.RESPIRATORY_RATE: 'Respiratory rate',
    HealthDataType.STEPS: 'Steps',
    HealthDataType.NUTRITION: 'Nutrition',
    HealthDataType.WEIGHT: 'Weight',
  };

  static const _awakeTypes = <HealthDataType>{
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
    HealthDataType.SLEEP_OUT_OF_BED,
  };

  static const _metricOf = <HealthDataType, String>{
    HealthDataType.RESTING_HEART_RATE: 'rhr',
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD: 'hrv',
    HealthDataType.BLOOD_OXYGEN: 'spo2',
    HealthDataType.RESPIRATORY_RATE: 'breathing',
  };

  static const heartMetrics = ['rhr', 'hrv', 'spo2', 'breathing'];

  List<HealthDataAccess> get _read => types.map((_) => HealthDataAccess.READ).toList();

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthAvailability> availability() async {
    if (!Platform.isAndroid) return HealthAvailability.unsupported;
    try {
      await _configure();
      final s = await _health.getHealthConnectSdkStatus();
      if (s == HealthConnectSdkStatus.sdkAvailable) return HealthAvailability.ready;
      if (s == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) return HealthAvailability.needsInstall;
      return HealthAvailability.unsupported;
    } catch (_) {
      return HealthAvailability.unsupported;
    }
  }

  Future<void> installHealthConnect() async {
    await _configure();
    await _health.installHealthConnect();
  }

  Future<bool> hasAccess() async {
    try {
      await _configure();
      return (await _health.hasPermissions(types, permissions: _read)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Health Connect permission sheet. Returns true if access was granted.
  Future<bool> requestAccess() async {
    await _configure();
    bool granted;
    try {
      granted = await _health.requestAuthorization(types, permissions: _read);
    } catch (e) {
      throw HealthException('Health Connect could not open its permission screen ($e).');
    }
    // Health Connect only shares the last 30 days unless history access is granted too.
    try {
      if (!await _health.isHealthDataHistoryAuthorized()) {
        await _health.requestHealthDataHistoryAuthorization();
      }
    } catch (_) {}
    return granted;
  }

  /// Readable names of the data types Health Connect has NOT granted.
  Future<List<String>> missingPermissions() async {
    try {
      await _configure();
    } catch (_) {
      return const [];
    }
    final checks = await Future.wait(types.map((t) async {
      try {
        final ok = await _health.hasPermissions([t], permissions: const [HealthDataAccess.READ]);
        return ok == true ? null : t;
      } catch (_) {
        return t;
      }
    }));
    final out = <String>[];
    for (final t in checks) {
      if (t == null) continue;
      final label = typeLabels[t] ?? 'Health data';
      if (!out.contains(label)) out.add(label);
    }
    return out;
  }

  // ------------------------------------------------------------------ public reads

  Future<SyncResult> fetch({required int days, DateTime? now, SourcePrefs? prefs, SyncProgress? onProgress}) async {
    final watch = Stopwatch()..start();
    await _configure();
    final p = prefs ?? SourcePrefs();
    final end = now ?? DateTime.now();
    final firstDay = addDays(dayOnly(end), -(days - 1));
    final failed = <String>{};
    final an = await _collect(firstDay, days, end, failed, onProgress);
    final combined = await _combinedSteps(an, p, failed);
    final built = _build(an, p, combined);
    watch.stop();
    final used = <String, String>{};
    for (final cat in const ['sleep', 'steps', 'heart']) {
      final raw = built.used[cat];
      if (raw != null) used[cat == 'steps' ? 'activity' : cat] = prettySource(raw);
    }
    if (an.allSources['food'] != null) used['food'] = an.allSources['food']!.map(prettySource).join(', ');
    return SyncResult(
      records: built.records,
      weightKg: an.weightKg,
      sources: an.allSources.map((k, v) => MapEntry(k, v.map(prettySource).toSet())),
      used: used,
      latest: built.latest,
      failedTypes: failed,
      elapsed: watch.elapsed,
      days: days,
    );
  }

  /// One day, app by app, computed exactly the way a sync would.
  Future<DayAudit> audit(DateTime day, SourcePrefs prefs) async {
    await _configure();
    final now = DateTime.now();
    final d0 = dayOnly(day);
    final next = addDays(d0, 1);
    final end = next.isAfter(now) ? now : next;
    final failed = <String>{};
    final an = await _collect(d0, 1, end, failed, null);
    final combined = await _combinedSteps(an, prefs, failed, all: true);
    final built = _build(an, prefs, combined);
    final key = isoDate(d0);
    final rec = built.records.first;
    final sections = <AuditSection>[];

    // Steps
    final ds = an.steps[key] ?? const <String, double>{};
    final stepEntries = ds.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final usedSteps = built.used['steps'];
    final stepRows = <AuditRow>[
      for (final e in stepEntries)
        AuditRow(
          source: prettySource(e.key),
          raw: e.key,
          value: fmtInt(e.value),
          detail: '${an.stepCount[key]?[e.key] ?? 0} records${isWearableSource(e.key) ? ' · tracker' : ''}',
          used: usedSteps == e.key,
        ),
    ];
    final comb = combined[key];
    if (comb != null) {
      stepRows.add(AuditRow(
        source: prettySource('combined'),
        raw: 'combined',
        value: fmtInt(comb),
        detail: 'phone and tracker blended by Health Connect',
        used: usedSteps == 'combined' || (usedSteps == null && rec.steps != null),
      ));
    }
    sections.add(AuditSection(
      key: 'steps',
      title: 'Steps',
      pref: 'steps',
      rows: stepRows,
      note: 'Google Health counts only your tracker, so Almanac does too. Tap a row to use it instead.',
    ));

    // Sleep
    final sc = an.sleep[key] ?? const <String, _SleepCand>{};
    sections.add(AuditSection(
      key: 'sleep',
      title: 'Sleep (night ending this morning)',
      pref: 'sleep',
      rows: [
        for (final c in sc.values)
          AuditRow(
            source: prettySource(c.source),
            raw: c.source,
            value: fmtDur(c.total(prefs.countNaps)),
            detail: _sleepDetail(c, prefs.countNaps),
            used: built.used['sleep'] == c.source,
          ),
      ],
      note: 'Time asleep = time in bed minus time awake, like Google Health. Deep: ${rec.deep == null ? 'none' : fmtDur(rec.deep!)}.',
    ));

    // Heart
    const titles = {'rhr': 'Resting heart rate', 'hrv': 'Heart rate variability', 'spo2': 'Blood oxygen', 'breathing': 'Breathing rate'};
    for (final metric in heartMetrics) {
      final bySrc = an.heart[metric]?[key] ?? const <String, List<_Reading>>{};
      final rows = <AuditRow>[];
      bySrc.forEach((src, readings) {
        final list = [...readings]..sort((a, b) => a.at.compareTo(b.at));
        rows.add(AuditRow(
          source: prettySource(src),
          raw: src,
          value: _fmtHeart(metric, _heartValue(metric, list)),
          detail: list.length == 1
              ? 'one reading at ${fmtTime(list.first.at)}'
              : '${list.length} readings, ${fmtTime(list.first.at)} to ${fmtTime(list.last.at)}${metric == 'rhr' ? ', latest used' : ''}',
          used: built.used[metric] == src,
        ));
      });
      sections.add(AuditSection(
        key: metric,
        title: titles[metric]!,
        pref: 'heart',
        rows: rows,
        note: metric == 'rhr' ? '' : 'Overnight readings count toward the morning you woke up.',
      ));
    }

    // Meals
    final ms = an.mealStats[key] ?? const <String, _MealStat>{};
    sections.add(AuditSection(
      key: 'food',
      title: 'Meals',
      rows: [
        for (final e in ms.entries)
          AuditRow(
            source: prettySource(e.key),
            raw: e.key,
            value: '${e.value.n} logged',
            detail: '${fmtInt(e.value.kcal)} kcal · ${e.value.protein.round()} g protein',
            used: true,
          ),
      ],
      note: 'Every meal app is used; exact duplicates are dropped.',
    ));

    return DayAudit(date: key, sections: sections, createdAt: now, failed: failed);
  }

  // ------------------------------------------------------------------ collection

  Future<_Analysis> _collect(DateTime firstDay, int days, DateTime end, Set<String> failed, SyncProgress? onProgress) async {
    final keys = [for (var i = 0; i < days; i++) isoDate(addDays(firstDay, i))];
    final keySet = keys.toSet();
    final an = _Analysis(keys, end);
    // Noon the day before the window: catches the night that ends on the first morning.
    final start = addDays(firstDay, -1).add(const Duration(hours: 12));

    Future<List<HealthDataPoint>> read(HealthDataType t, DateTime from, DateTime to) async {
      try {
        return await _health.getHealthDataFromTypes(types: [t], startTime: from, endTime: to);
      } catch (_) {
        failed.add(typeLabels[t] ?? 'Health data');
        return const <HealthDataPoint>[];
      }
    }

    // Raw step records can be numerous: ten days per request, all requests in parallel.
    Future<List<HealthDataPoint>> chunked(HealthDataType t, DateTime from, DateTime to) async {
      final parts = <Future<List<HealthDataPoint>>>[];
      var a = from;
      while (a.isBefore(to)) {
        final next = addDays(dayOnly(a), 10);
        final b = next.isBefore(to) ? next : to;
        parts.add(read(t, a, b));
        a = b;
      }
      final res = await Future.wait(parts);
      return [for (final p in res) ...p];
    }

    Future<List<HealthDataPoint>> group(String cat, List<HealthDataType> ts, DateTime from) async {
      final parts = await Future.wait(ts.map((t) => read(t, from, end)));
      onProgress?.call(cat);
      return [for (final p in parts) ...p];
    }

    final results = await Future.wait<List<HealthDataPoint>>([
      group('sleep', sleepTypes, start),
      group('heart', heartTypes, start),
      group('food', const [HealthDataType.NUTRITION], firstDay),
      read(HealthDataType.WEIGHT, end.subtract(const Duration(days: 120)), end),
      chunked(HealthDataType.STEPS, firstDay, end).then((pts) {
        onProgress?.call('activity');
        return pts;
      }),
    ]);

    if (failed.length >= typeLabels.values.toSet().length) {
      throw HealthException("Health Connect refused every request. Open Health Connect › App permissions › Almanac and allow access.");
    }

    _foldSleep(_health.removeDuplicates(results[0]), an, keySet);
    _foldHeart(_health.removeDuplicates(results[1]), an, keySet);
    _foldFood(_health.removeDuplicates(results[2]), an, keySet);
    _foldSteps(_health.removeDuplicates(results[4]), an, keySet);

    final weights = results[3].where((p) => p.value is NumericHealthValue).toList()..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    if (weights.isNotEmpty) {
      final w = (weights.last.value as NumericHealthValue).numericValue.toDouble();
      if (w > 25 && w < 350) an.weightKg = w;
    }
    return an;
  }

  /// Health Connect's blended total, only for the days that need it.
  Future<Map<String, double>> _combinedSteps(_Analysis an, SourcePrefs p, Set<String> failed, {bool all = false}) async {
    final src = _stepSource(an, p);
    final need = <String>[
      for (final k in an.keys)
        if (all || src == null || src == 'combined' || (an.steps[k]?[src] ?? 0) <= 0) k,
    ];
    final out = <String, double>{};
    for (var c = 0; c < need.length; c += 10) {
      final chunk = need.sublist(c, math.min(c + 10, need.length));
      await Future.wait(chunk.map((k) async {
        final d = parseIso(k);
        final next = addDays(d, 1);
        final to = next.isAfter(an.end) ? an.end : next;
        try {
          final s = await _health.getTotalStepsInInterval(d, to);
          if (s != null && s > 0) out[k] = s.toDouble();
        } catch (_) {
          failed.add('Steps');
        }
      }));
    }
    return out;
  }

  // ------------------------------------------------------------------ choosing

  /// Highest score wins, but a wearable always beats the phone, and Fitbit beats other wearables.
  static String? _pick(Map<String, double> score, String pref) {
    if (score.isEmpty) return null;
    if (pref != 'auto' && score.containsKey(pref)) return pref;
    String? best;
    var bestScore = double.negativeInfinity;
    for (final e in score.entries) {
      final s = e.value + (isWearableSource(e.key) ? 1e12 : 0) + (e.key.toLowerCase().contains('fitbit') ? 1e11 : 0);
      if (s > bestScore) {
        best = e.key;
        bestScore = s;
      }
    }
    return best;
  }

  String? _stepSource(_Analysis an, SourcePrefs p) {
    if (p.steps == 'combined') return 'combined';
    final score = <String, double>{};
    for (final d in an.steps.values) {
      d.forEach((s, v) => score[s] = (score[s] ?? 0) + v);
    }
    return _pick(score, p.steps);
  }

  static double _heartValue(String metric, List<_Reading> list) {
    final sorted = [...list]..sort((a, b) => a.at.compareTo(b.at));
    // Trackers write one daily value (and may rewrite it); the latest one is what their app shows.
    final double v = (metric == 'rhr' || sorted.length <= 2)
        ? sorted.last.value
        : sorted.map((x) => x.value).reduce((a, b) => a + b) / sorted.length;
    return (metric == 'spo2' || metric == 'breathing') ? (v * 10).round() / 10 : v.roundToDouble();
  }

  static String _fmtHeart(String metric, double v) {
    switch (metric) {
      case 'rhr':
        return '${v.round()} bpm';
      case 'hrv':
        return '${v.round()} ms';
      case 'spo2':
        return '${v.toStringAsFixed(1)}%';
      default:
        return '${v.toStringAsFixed(1)} /min';
    }
  }

  static String _sleepDetail(_SleepCand c, bool countNaps) {
    final parts = <String>[];
    if (c.main.isNotEmpty) {
      final pieces = c.main.length > 1 ? ' in ${c.main.length} parts' : '';
      parts.add('${fmtTime(c.main.first.dateFrom)} to ${fmtTime(c.main.last.dateTo)}$pieces');
      parts.add('in bed ${fmtDur(c.mainInBed)}');
      if (c.staged) {
        parts.add('awake ${fmtDur(c.awake)}');
        parts.add('deep ${fmtDur(c.deep)}');
        parts.add('REM ${fmtDur(c.rem)}');
        parts.add('light ${fmtDur(c.light)}');
        parts.add('stages add up to ${fmtDur(c.stagedSum)}');
      } else {
        parts.add('no sleep stages');
      }
    }
    if (c.napAsleep > 0) parts.add('naps ${fmtDur(c.napAsleep)} (${countNaps ? 'counted' : 'not counted'})');
    return parts.join(' · ');
  }

  _Built _build(_Analysis an, SourcePrefs p, Map<String, double> combined) {
    final used = <String, String>{};
    final latest = <String, DateTime>{};
    void seen(String cat, DateTime? t) {
      if (t == null) return;
      final c = t.isAfter(an.end) ? an.end : t;
      final cur = latest[cat];
      if (cur == null || c.isAfter(cur)) latest[cat] = c;
    }

    final sleepScore = <String, double>{};
    for (final day in an.sleep.values) {
      day.forEach((src, c) {
        sleepScore[src] = (sleepScore[src] ?? 0) + (c.staged ? 1000 : 1) + c.mainAsleep / 10000;
      });
    }
    final sleepSrc = _pick(sleepScore, p.sleep);
    final stepSrc = _stepSource(an, p);
    final heartSrc = <String, String?>{};
    an.heart.forEach((metric, days) {
      final sc = <String, double>{};
      for (final d in days.values) {
        for (final s in d.keys) {
          sc[s] = (sc[s] ?? 0) + 1;
        }
      }
      heartSrc[metric] = _pick(sc, p.heart);
    });

    final today = isoDate(DateTime.now());
    final records = <DayRecord>[];
    for (final key in an.keys) {
      final r = DayRecord(date: key, partial: key == today);

      // Sleep: one app per night.
      final cands = an.sleep[key];
      if (cands != null && cands.isNotEmpty) {
        final src = (sleepSrc != null && cands.containsKey(sleepSrc))
            ? sleepSrc
            : _pick({for (final e in cands.entries) e.key: (e.value.staged ? 1000.0 : 0.0) + e.value.mainAsleep}, 'auto');
        final c = src == null ? null : cands[src];
        if (c != null) {
          final total = c.total(p.countNaps);
          if (total >= 10) {
            r.sleepMin = total.roundToDouble();
            if (c.napAsleep >= 1) r.napMin = c.napAsleep.roundToDouble();
            if (c.main.isNotEmpty) {
              r.deep = c.deep >= 1 ? c.deep.roundToDouble() : null;
              r.rem = c.rem >= 1 ? c.rem.roundToDouble() : null;
              r.light = c.light >= 1 ? c.light.roundToDouble() : null;
              r.awake = c.awake.roundToDouble();
              final prevMidnight = addDays(dayOnly(c.main.last.dateTo), -1);
              r.bedtime = c.main.first.dateFrom.difference(prevMidnight).inMinutes.toDouble();
              r.wake = c.main.last.dateTo.difference(prevMidnight).inMinutes.toDouble();
            }
            used['sleep'] = c.source;
            seen('sleep', c.lastEnd);
          }
        }
      }

      // Heart: one app per metric, its own daily value.
      for (final metric in heartMetrics) {
        final bySrc = an.heart[metric]?[key];
        if (bySrc == null || bySrc.isEmpty) continue;
        final gs = heartSrc[metric];
        final src = (gs != null && bySrc.containsKey(gs)) ? gs : _pick({for (final e in bySrc.entries) e.key: e.value.length.toDouble()}, 'auto');
        if (src == null) continue;
        final list = bySrc[src];
        if (list == null || list.isEmpty) continue;
        final v = _heartValue(metric, list);
        switch (metric) {
          case 'rhr':
            r.rhr = v;
          case 'hrv':
            r.hrv = v;
          case 'spo2':
            r.spo2 = v;
          case 'breathing':
            r.breathing = v;
        }
        used[metric] = src;
        used['heart'] = src;
        seen('heart', list.map((x) => x.at).reduce((a, b) => a.isAfter(b) ? a : b));
      }

      // Steps: the tracker's own count; Health Connect's blend only when the tracker has nothing.
      final ds = an.steps[key];
      if (stepSrc == 'combined') {
        final v = combined[key];
        if (v != null) {
          r.steps = v;
          used['steps'] = 'combined';
        }
      } else if (stepSrc != null && ds != null && (ds[stepSrc] ?? 0) > 0) {
        r.steps = ds[stepSrc]!.roundToDouble();
        used['steps'] = stepSrc;
        seen('activity', an.stepLatest[stepSrc]);
      } else {
        final v = combined[key];
        if (v != null) r.steps = v;
      }

      // Meals: every app, de-duplicated.
      final meals = an.meals[key];
      if (meals != null) {
        r.meals.addAll(meals);
        r.meals.sort((a, b) => a.minute.compareTo(b.minute));
      }
      records.add(r);
    }
    if (stepSrc == 'combined') {
      for (final t in an.stepLatest.values) {
        seen('activity', t);
      }
    }
    seen('food', an.foodLatest);
    return _Built(records, used, latest);
  }

  // ------------------------------------------------------------------ helpers

  double _mins(HealthDataPoint p) => p.dateTo.difference(p.dateFrom).inSeconds / 60.0;

  /// On Android the plugin reports the writing app's package as sourceName.
  String _src(HealthDataPoint p) => p.sourceName.trim().isNotEmpty ? p.sourceName.trim() : p.sourceId.trim();

  /// A daytime doze, not the night's sleep.
  bool _isNap(HealthDataPoint s) => s.dateFrom.hour >= 10 && s.dateFrom.hour < 18 && _mins(s) < 180;

  /// Overnight readings taken in the evening belong to the next morning's record.
  String _nightKey(DateTime t) => t.hour >= 16 ? isoDate(addDays(t, 1)) : isoDate(t);

  static double _overlapMin(DateTime a1, DateTime a2, DateTime b1, DateTime b2) {
    final from = a1.isAfter(b1) ? a1 : b1;
    final to = a2.isBefore(b2) ? a2 : b2;
    return to.isAfter(from) ? to.difference(from).inSeconds / 60.0 : 0.0;
  }

  static double _unionMin(List<(DateTime, DateTime)> spans) {
    if (spans.isEmpty) return 0.0;
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0.0;
    var curFrom = spans.first.$1;
    var curTo = spans.first.$2;
    for (final s in spans.skip(1)) {
      if (!s.$1.isAfter(curTo)) {
        if (s.$2.isAfter(curTo)) curTo = s.$2;
      } else {
        total += curTo.difference(curFrom).inSeconds / 60.0;
        curFrom = s.$1;
        curTo = s.$2;
      }
    }
    total += curTo.difference(curFrom).inSeconds / 60.0;
    return total;
  }

  bool _plausible(String metric, double v) {
    switch (metric) {
      case 'rhr':
        return v >= 30 && v <= 130;
      case 'hrv':
        return v >= 5 && v <= 250;
      case 'spo2':
        return v >= 70 && v <= 100;
      case 'breathing':
        return v >= 6 && v <= 40;
    }
    return true;
  }

  // ------------------------------------------------------------------ folding

  void _foldSleep(List<HealthDataPoint> pts, _Analysis an, Set<String> keys) {
    final sessions = pts.where((p) => p.type == HealthDataType.SLEEP_SESSION && _mins(p) >= 10).toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final stagesBySource = <String, List<HealthDataPoint>>{};
    for (final p in pts) {
      if (p.type == HealthDataType.SLEEP_SESSION) continue;
      stagesBySource.putIfAbsent(_src(p), () => <HealthDataPoint>[]).add(p);
    }
    final lastEnd = <String, DateTime>{};
    for (final s in sessions) {
      final src = _src(s);
      an.allSources.putIfAbsent('sleep', () => <String>{}).add(src);
      // Skip a session that mostly repeats one already counted from the same app.
      final prev = lastEnd[src];
      if (prev != null && prev.isAfter(s.dateFrom) && _overlapMin(s.dateFrom, s.dateTo, s.dateFrom, prev) > _mins(s) / 2) continue;
      if (prev == null || s.dateTo.isAfter(prev)) lastEnd[src] = s.dateTo;

      // Like Fitbit, a sleep belongs to the day it ends.
      final day = isoDate(s.dateTo);
      if (!keys.contains(day)) continue;
      final cand = an.sleep.putIfAbsent(day, () => <String, _SleepCand>{}).putIfAbsent(src, () => _SleepCand(src));
      final stages = stagesBySource[src] ?? stagesBySource[''] ?? const <HealthDataPoint>[];
      final awakeSpans = <(DateTime, DateTime)>[];
      var deep = 0.0, rem = 0.0, light = 0.0, sleeping = 0.0;
      var any = false;
      for (final p in stages) {
        if (!p.dateTo.isAfter(s.dateFrom) || !p.dateFrom.isBefore(s.dateTo)) continue;
        any = true;
        final from = p.dateFrom.isBefore(s.dateFrom) ? s.dateFrom : p.dateFrom;
        final to = p.dateTo.isAfter(s.dateTo) ? s.dateTo : p.dateTo;
        final m = to.difference(from).inSeconds / 60.0;
        if (_awakeTypes.contains(p.type)) {
          awakeSpans.add((from, to));
        } else if (p.type == HealthDataType.SLEEP_DEEP) {
          deep += m;
        } else if (p.type == HealthDataType.SLEEP_REM) {
          rem += m;
        } else if (p.type == HealthDataType.SLEEP_LIGHT) {
          light += m;
        } else if (p.type == HealthDataType.SLEEP_ASLEEP) {
          sleeping += m;
        }
      }
      final inBed = _mins(s);
      final awake = _unionMin(awakeSpans);
      // Fitbit's definition: time asleep = time in bed minus time awake.
      final asleep = math.max(0.0, inBed - awake);
      if (any) cand.staged = true;
      if (_isNap(s)) {
        cand.naps.add(s);
        cand.napAsleep += asleep;
      } else {
        cand.main.add(s);
        cand.mainAsleep += asleep;
        cand.mainInBed += inBed;
        cand.deep += deep;
        cand.rem += rem;
        cand.light += light;
        cand.sleeping += sleeping;
        cand.awake += awake;
      }
    }
  }

  void _foldHeart(List<HealthDataPoint> pts, _Analysis an, Set<String> keys) {
    for (final p in pts) {
      final metric = _metricOf[p.type];
      final raw = p.value;
      if (metric == null || raw is! NumericHealthValue) continue;
      var v = raw.numericValue.toDouble();
      if (metric == 'spo2' && v <= 1.0) v *= 100;
      if (!_plausible(metric, v)) continue;
      final day = metric == 'rhr' ? isoDate(p.dateFrom) : _nightKey(p.dateFrom);
      if (!keys.contains(day)) continue;
      final src = _src(p);
      an.allSources.putIfAbsent('heart', () => <String>{}).add(src);
      an.heart
          .putIfAbsent(metric, () => <String, Map<String, List<_Reading>>>{})
          .putIfAbsent(day, () => <String, List<_Reading>>{})
          .putIfAbsent(src, () => <_Reading>[])
          .add(_Reading(p.dateTo, v));
    }
  }

  void _addSteps(_Analysis an, String day, String src, double n, Set<String> keys) {
    if (!keys.contains(day) || n <= 0) return;
    final m = an.steps.putIfAbsent(day, () => <String, double>{});
    m[src] = (m[src] ?? 0) + n;
    final c = an.stepCount.putIfAbsent(day, () => <String, int>{});
    c[src] = (c[src] ?? 0) + 1;
  }

  void _foldSteps(List<HealthDataPoint> pts, _Analysis an, Set<String> keys) {
    for (final p in pts) {
      final raw = p.value;
      if (raw is! NumericHealthValue) continue;
      final n = raw.numericValue.toDouble();
      if (n <= 0) continue;
      final src = _src(p);
      an.allSources.putIfAbsent('activity', () => <String>{}).add(src);
      final cur = an.stepLatest[src];
      if (cur == null || p.dateTo.isAfter(cur)) an.stepLatest[src] = p.dateTo;
      final from = p.dateFrom;
      final to = p.dateTo;
      final total = to.difference(from).inSeconds;
      final lastInstant = to.subtract(const Duration(milliseconds: 1));
      if (total <= 0 || isoDate(from) == isoDate(lastInstant)) {
        _addSteps(an, isoDate(from), src, n, keys);
        continue;
      }
      // A record that crosses midnight is split by time.
      var cursor = from;
      while (cursor.isBefore(to)) {
        final next = addDays(dayOnly(cursor), 1);
        final segEnd = next.isBefore(to) ? next : to;
        _addSteps(an, isoDate(cursor), src, n * segEnd.difference(cursor).inSeconds / total, keys);
        cursor = segEnd;
      }
    }
  }

  void _foldFood(List<HealthDataPoint> pts, _Analysis an, Set<String> keys) {
    final seenMeals = <String>{};
    for (final p in pts) {
      final v = p.value;
      if (v is! NutritionHealthValue) continue;
      // Meals before 4 AM belong to the previous day (that 1 AM Maggi was yesterday's dinner).
      final t = p.dateFrom;
      final owner = t.hour < 4 ? addDays(dayOnly(t), -1) : dayOnly(t);
      final key = isoDate(owner);
      if (!keys.contains(key)) continue;
      final src = _src(p);
      an.allSources.putIfAbsent('food', () => <String>{}).add(src);
      final minute = t.difference(owner).inMinutes;
      final name = (v.name ?? v.mealType ?? '').trim();
      final kcal = (v.calories ?? 0).toDouble();
      final protein = (v.protein ?? 0).toDouble();
      final sig = '$key|$minute|${name.toLowerCase()}|${kcal.round()}';
      if (!seenMeals.add(sig)) continue; // same meal written twice
      an.meals.putIfAbsent(key, () => <Meal>[]).add(Meal(
            name: name,
            minute: minute,
            kcal: kcal,
            protein: protein,
            caffeine: (v.caffeine ?? 0).toDouble(),
          ));
      final st = an.mealStats.putIfAbsent(key, () => <String, _MealStat>{}).putIfAbsent(src, () => _MealStat());
      st.n += 1;
      st.kcal += kcal;
      st.protein += protein;
      final fl = an.foodLatest;
      if (fl == null || p.dateTo.isAfter(fl)) an.foodLatest = p.dateTo;
    }
  }
}
