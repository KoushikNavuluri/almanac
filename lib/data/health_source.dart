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

/// What one sync produced. [records] covers exactly the requested window, rebuilt from scratch.
class SyncResult {
  SyncResult({
    required this.records,
    required this.weightKg,
    required this.sources,
    required this.latest,
    required this.failedTypes,
    required this.elapsed,
    required this.days,
  });
  final List<DayRecord> records;
  final double? weightKg;

  /// Category -> friendly names of the apps/devices that wrote it (e.g. sleep -> Fitbit).
  final Map<String, Set<String>> sources;

  /// Category -> end time of the newest record seen.
  final Map<String, DateTime> latest;

  /// Readable names of data types whose read failed (usually a missing permission).
  final Set<String> failedTypes;
  final Duration elapsed;
  final int days;
}

typedef SyncProgress = void Function(String category);

/// "com.fitbit.FitbitMobile" -> "Fitbit".
String prettySource(String raw) {
  final s = raw.trim();
  final l = s.toLowerCase();
  if (l.contains('fitbit')) return 'Fitbit';
  if (l.contains('cravin')) return "Cravin'";
  if (l.contains('apps.fitness')) return 'Google Fit';
  if (l.contains('shealth') || l.contains('samsung')) return 'Samsung Health';
  if (l.contains('apps.healthdata')) return 'Health Connect';
  if (l.contains('garmin')) return 'Garmin';
  if (l.contains('whoop')) return 'WHOOP';
  if (l.contains('oura')) return 'Oura';
  if (!s.contains('.')) return s;
  final last = s.split('.').last;
  return last.isEmpty ? s : last[0].toUpperCase() + last.substring(1);
}

class _Sink {
  _Sink(this.now);
  final DateTime now;
  final sources = <String, Set<String>>{};
  final latest = <String, DateTime>{};

  void add(String cat, HealthDataPoint p) {
    final raw = p.sourceName.trim().isNotEmpty ? p.sourceName : p.sourceId;
    if (raw.trim().isNotEmpty) sources.putIfAbsent(cat, () => <String>{}).add(prettySource(raw));
    final t = p.dateTo.isAfter(now) ? now : p.dateTo;
    final cur = latest[cat];
    if (cur == null || t.isAfter(cur)) latest[cat] = t;
  }
}

/// Reads Fitbit (sleep, heart, steps) and Cravin' (nutrition) data from Health Connect and
/// folds it into one [DayRecord] per day. Read-only.
///
/// Speed: every data type is read in parallel, and the app only asks for the last few days
/// on routine syncs (the controller merges them into the stored 60-day history).
/// Accuracy: nights split into several sessions are merged, one device wins per night and per
/// metric (so a phone and a watch never double count), naps are excluded, glitchy readings are
/// dropped, and medians are used where a single bad sample could skew the day.
class HealthSource {
  final Health _health = Health();
  bool _configured = false;

  static const sleepTypes = <HealthDataType>[
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_ASLEEP,
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
    HealthDataType.SLEEP_AWAKE: 'Sleep',
    HealthDataType.SLEEP_ASLEEP: 'Sleep',
    HealthDataType.RESTING_HEART_RATE: 'Resting heart rate',
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD: 'Heart rate variability',
    HealthDataType.BLOOD_OXYGEN: 'Oxygen saturation',
    HealthDataType.RESPIRATORY_RATE: 'Respiratory rate',
    HealthDataType.STEPS: 'Steps',
    HealthDataType.NUTRITION: 'Nutrition',
    HealthDataType.WEIGHT: 'Weight',
  };

  static const _stageTypes = <HealthDataType>{
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_ASLEEP,
  };

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

  Future<SyncResult> fetch({required int days, DateTime? now, SyncProgress? onProgress}) async {
    final watch = Stopwatch()..start();
    await _configure();
    final end = now ?? DateTime.now();
    final firstDay = addDays(dayOnly(end), -(days - 1));
    // Noon the day before the window: catches the night that ends on the first morning.
    final start = addDays(firstDay, -1).add(const Duration(hours: 12));

    final map = <String, DayRecord>{};
    for (var i = 0; i < days; i++) {
      final key = isoDate(addDays(firstDay, i));
      map[key] = DayRecord(date: key);
    }
    final failed = <String>{};
    final sink = _Sink(end);

    Future<List<HealthDataPoint>> read(HealthDataType t, DateTime from) async {
      try {
        return await _health.getHealthDataFromTypes(types: [t], startTime: from, endTime: end);
      } catch (_) {
        failed.add(typeLabels[t] ?? 'Health data');
        return const <HealthDataPoint>[];
      }
    }

    Future<List<HealthDataPoint>> group(String cat, List<HealthDataType> ts) async {
      final parts = await Future.wait(ts.map((t) => read(t, start)));
      onProgress?.call(cat);
      return [for (final p in parts) ...p];
    }

    final results = await Future.wait<List<HealthDataPoint>>([
      group('sleep', sleepTypes),
      group('heart', heartTypes),
      group('food', const [HealthDataType.NUTRITION]),
      read(HealthDataType.WEIGHT, end.subtract(const Duration(days: 120))),
      _steps(firstDay, days, end, map, failed).then((_) => read(HealthDataType.STEPS, dayOnly(end))).then((pts) {
        onProgress?.call('activity');
        return pts;
      }),
    ]);

    if (failed.length >= typeLabels.values.toSet().length) {
      throw HealthException("Health Connect refused every request. Open Health Connect › App permissions › Almanac and allow access.");
    }

    _foldSleep(_health.removeDuplicates(results[0]), map, sink);
    _foldHeart(_health.removeDuplicates(results[1]), map, sink);
    _foldFood(_health.removeDuplicates(results[2]), map, sink);
    for (final p in results[4]) {
      sink.add('activity', p);
    }

    double? weight;
    final weights = results[3].where((p) => p.value is NumericHealthValue).toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    if (weights.isNotEmpty) {
      final w = (weights.last.value as NumericHealthValue).numericValue.toDouble();
      if (w > 25 && w < 350) weight = w;
    }

    final records = map.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    records.last.partial = true;
    watch.stop();
    return SyncResult(
      records: records,
      weightKg: weight,
      sources: sink.sources,
      latest: sink.latest,
      failedTypes: failed,
      elapsed: watch.elapsed,
      days: days,
    );
  }

  // ------------------------------------------------------------------ steps

  /// Health Connect's aggregate de-duplicates phone + watch counts. Ten days at a time, in parallel.
  Future<void> _steps(DateTime firstDay, int days, DateTime end, Map<String, DayRecord> map, Set<String> failed) async {
    for (var c = 0; c < days; c += 10) {
      final upto = math.min(c + 10, days);
      await Future.wait([
        for (var i = c; i < upto; i++) _stepsFor(addDays(firstDay, i), i == days - 1 ? end : addDays(firstDay, i + 1), map, failed),
      ]);
    }
  }

  Future<void> _stepsFor(DateTime from, DateTime to, Map<String, DayRecord> map, Set<String> failed) async {
    try {
      final s = await _health.getTotalStepsInInterval(from, to);
      if (s != null && s > 0) map[isoDate(from)]?.steps = s.toDouble();
    } catch (_) {
      failed.add('Steps');
    }
  }

  // ------------------------------------------------------------------ helpers

  double _mins(HealthDataPoint p) => p.dateTo.difference(p.dateFrom).inSeconds / 60.0;

  String _src(HealthDataPoint p) => p.sourceId.isNotEmpty ? p.sourceId : p.sourceName;

  /// A daytime doze, not the night's sleep.
  bool _isNap(HealthDataPoint s) => s.dateFrom.hour >= 10 && s.dateFrom.hour < 18 && _mins(s) < 180;

  /// Overnight readings taken in the evening belong to the next morning's record.
  String _nightKey(DateTime t) => t.hour >= 16 ? isoDate(addDays(t, 1)) : isoDate(t);

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

  // ------------------------------------------------------------------ sleep

  void _foldSleep(List<HealthDataPoint> pts, Map<String, DayRecord> map, _Sink sink) {
    final nights = <String, List<HealthDataPoint>>{};
    for (final s in pts) {
      if (s.type != HealthDataType.SLEEP_SESSION || _mins(s) < 20 || _isNap(s)) continue;
      nights.putIfAbsent(isoDate(s.dateTo), () => <HealthDataPoint>[]).add(s);
    }
    final stages = pts.where((p) => _stageTypes.contains(p.type)).toList();

    nights.forEach((key, list) {
      final r = map[key];
      if (r == null) return;
      // One device per night: whichever recorded the most sleep wins.
      final bySource = <String, double>{};
      for (final s in list) {
        bySource[_src(s)] = (bySource[_src(s)] ?? 0) + _mins(s);
      }
      final winner = bySource.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      // Fitbit often splits one night into several sessions when you wake up. Merge them.
      final mine = list.where((s) => _src(s) == winner).toList()..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

      bool inside(HealthDataPoint p) {
        final mid = p.dateFrom.add(p.dateTo.difference(p.dateFrom) ~/ 2);
        for (final s in mine) {
          final from = s.dateFrom.subtract(const Duration(minutes: 2));
          final to = s.dateTo.add(const Duration(minutes: 2));
          if (!mid.isBefore(from) && !mid.isAfter(to)) return true;
        }
        return false;
      }

      Map<HealthDataType, double> sum(bool sameSource) {
        final out = <HealthDataType, double>{};
        for (final p in stages) {
          if (sameSource && _src(p) != winner) continue;
          if (!inside(p)) continue;
          out[p.type] = (out[p.type] ?? 0) + _mins(p);
        }
        return out;
      }

      var st = sum(true);
      if (st.isEmpty) st = sum(false);
      final deep = st[HealthDataType.SLEEP_DEEP] ?? 0;
      final rem = st[HealthDataType.SLEEP_REM] ?? 0;
      final light = st[HealthDataType.SLEEP_LIGHT] ?? 0;
      final awake = st[HealthDataType.SLEEP_AWAKE] ?? 0;
      final asleep = st[HealthDataType.SLEEP_ASLEEP] ?? 0;
      final sessionMin = mine.fold<double>(0, (a, s) => a + _mins(s));
      final staged = deep + rem + light + asleep;
      final total = staged > 0 ? staged : sessionMin - awake;
      if (total < 60) return; // a glitch, not a night

      r.sleepMin = total.roundToDouble();
      r.deep = deep > 0 ? deep.roundToDouble() : null;
      r.rem = rem > 0 ? rem.roundToDouble() : null;
      r.light = light > 0 ? light.roundToDouble() : null;
      r.awake = awake.roundToDouble();
      final prevMidnight = addDays(dayOnly(mine.last.dateTo), -1);
      r.bedtime = mine.first.dateFrom.difference(prevMidnight).inMinutes.toDouble();
      r.wake = mine.last.dateTo.difference(prevMidnight).inMinutes.toDouble();
      sink.add('sleep', mine.last);
    });
  }

  // ------------------------------------------------------------------ heart

  void _foldHeart(List<HealthDataPoint> pts, Map<String, DayRecord> map, _Sink sink) {
    const metricOf = <HealthDataType, String>{
      HealthDataType.RESTING_HEART_RATE: 'rhr',
      HealthDataType.HEART_RATE_VARIABILITY_RMSSD: 'hrv',
      HealthDataType.BLOOD_OXYGEN: 'spo2',
      HealthDataType.RESPIRATORY_RATE: 'breathing',
    };
    final byMetric = <String, List<HealthDataPoint>>{};
    for (final p in pts) {
      final m = metricOf[p.type];
      if (m == null || p.value is! NumericHealthValue) continue;
      byMetric.putIfAbsent(m, () => <HealthDataPoint>[]).add(p);
    }

    byMetric.forEach((metric, list) {
      // One device per metric (ties go to Fitbit), so a phone estimate never mixes in.
      final score = <String, double>{};
      for (final p in list) {
        final bonus = p.sourceName.toLowerCase().contains('fitbit') || p.sourceId.toLowerCase().contains('fitbit') ? 0.5 : 0.0;
        score[_src(p)] = (score[_src(p)] ?? bonus) + 1;
      }
      final winner = score.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      final buckets = <String, List<double>>{};
      for (final p in list) {
        if (_src(p) != winner) continue;
        var v = (p.value as NumericHealthValue).numericValue.toDouble();
        if (metric == 'spo2' && v <= 1.0) v *= 100;
        if (!_plausible(metric, v)) continue;
        final day = metric == 'rhr' ? isoDate(p.dateFrom) : _nightKey(p.dateFrom);
        buckets.putIfAbsent(day, () => <double>[]).add(v);
        sink.add('heart', p);
      }
      buckets.forEach((day, vals) {
        final r = map[day];
        if (r == null || vals.isEmpty) return;
        vals.sort();
        final median = vals[vals.length ~/ 2];
        final mean = vals.reduce((a, b) => a + b) / vals.length;
        switch (metric) {
          case 'rhr':
            r.rhr = median.roundToDouble();
          case 'hrv':
            r.hrv = median.roundToDouble();
          case 'spo2':
            r.spo2 = (mean * 10).round() / 10;
          case 'breathing':
            r.breathing = (mean * 10).round() / 10;
        }
      });
    });
  }

  // ------------------------------------------------------------------ food

  void _foldFood(List<HealthDataPoint> pts, Map<String, DayRecord> map, _Sink sink) {
    final seen = <String>{};
    for (final p in pts) {
      final v = p.value;
      if (v is! NutritionHealthValue) continue;
      // Meals before 4 AM belong to the previous day (that 1 AM Maggi was yesterday's dinner).
      final t = p.dateFrom;
      final owner = t.hour < 4 ? addDays(dayOnly(t), -1) : dayOnly(t);
      final r = map[isoDate(owner)];
      if (r == null) continue;
      final minute = t.difference(owner).inMinutes;
      final name = (v.name ?? v.mealType ?? '').trim();
      final kcal = (v.calories ?? 0).toDouble();
      final sig = '${isoDate(owner)}|$minute|${name.toLowerCase()}|${kcal.round()}';
      if (!seen.add(sig)) continue; // same meal written twice
      r.meals.add(Meal(
        name: name,
        minute: minute,
        kcal: kcal,
        protein: (v.protein ?? 0).toDouble(),
        caffeine: (v.caffeine ?? 0).toDouble(),
      ));
      sink.add('food', p);
    }
    for (final r in map.values) {
      r.meals.sort((a, b) => a.minute.compareTo(b.minute));
    }
  }
}
