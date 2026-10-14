import 'dart:io';

import 'package:health/health.dart';

import '../models/day_record.dart';
import '../utils/format.dart';

enum HealthAvailability { ready, needsInstall, unsupported }

class SyncResult {
  SyncResult(this.records, this.weightKg, this.sources);
  final List<DayRecord> records;
  final double? weightKg;

  /// Category -> app/device names that wrote it (e.g. sleep -> Fitbit).
  final Map<String, Set<String>> sources;
}

class HealthException implements Exception {
  HealthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads Fitbit (sleep, heart, steps) and Cravin' (nutrition) data from Health Connect and
/// folds it into one [DayRecord] per day. Read-only.
class HealthSource {
  final Health _health = Health();
  bool _configured = false;

  static const List<HealthDataType> types = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.STEPS,
    HealthDataType.NUTRITION,
    HealthDataType.WEIGHT,
  ];

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

  Future<SyncResult> fetch({int days = 60, DateTime? now}) async {
    await _configure();
    final end = now ?? DateTime.now();
    final firstDay = addDays(dayOnly(end), -(days - 1));
    final start = firstDay.subtract(const Duration(hours: 14)); // catch the first night

    final map = <String, DayRecord>{};
    for (var i = 0; i < days; i++) {
      final key = isoDate(addDays(firstDay, i));
      map[key] = DayRecord(date: key);
    }
    final sources = <String, Set<String>>{};
    void source(String cat, HealthDataPoint p) {
      final n = p.sourceName.trim();
      if (n.isNotEmpty) sources.putIfAbsent(cat, () => <String>{}).add(n);
    }

    // One type at a time, so a single denied permission doesn't sink the whole sync.
    var points = <HealthDataPoint>[];
    var failures = 0;
    for (final t in types) {
      if (t == HealthDataType.STEPS) continue; // aggregated below
      try {
        points.addAll(await _health.getHealthDataFromTypes(types: [t], startTime: start, endTime: end));
      } catch (_) {
        failures++;
      }
    }
    if (failures >= types.length - 1) {
      throw HealthException('Health Connect refused every request. Check Almanac\'s permissions in Health Connect.');
    }
    points = _health.removeDuplicates(points);

    _foldSleep(points, map, source);
    _foldAverages(points, map, source);
    _foldNutrition(points, map, source);

    // Steps: Health Connect's aggregate de-duplicates phone + watch counts.
    for (var i = 0; i < days; i++) {
      final d = addDays(firstDay, i);
      final dEnd = i == days - 1 ? end : addDays(d, 1);
      try {
        final s = await _health.getTotalStepsInInterval(d, dEnd);
        if (s != null && s > 0) map[isoDate(d)]!.steps = s.toDouble();
      } catch (_) {}
    }
    for (final p in points.where((p) => p.type == HealthDataType.STEPS)) {
      source('activity', p);
    }

    double? weight;
    final weights = points.where((p) => p.type == HealthDataType.WEIGHT && p.value is NumericHealthValue).toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    if (weights.isNotEmpty) {
      weight = (weights.last.value as NumericHealthValue).numericValue.toDouble();
    }

    final records = map.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    records.last.partial = true;
    return SyncResult(records, weight, sources);
  }

  double _mins(HealthDataPoint p) => p.dateTo.difference(p.dateFrom).inSeconds / 60.0;

  void _foldSleep(List<HealthDataPoint> pts, Map<String, DayRecord> map, void Function(String, HealthDataPoint) source) {
    final sessions = <String, HealthDataPoint>{};
    for (final p in pts.where((p) => p.type == HealthDataType.SLEEP_SESSION)) {
      final key = isoDate(p.dateTo);
      final cur = sessions[key];
      if (cur == null || _mins(p) > _mins(cur)) sessions[key] = p;
    }
    for (final entry in sessions.entries) {
      final r = map[entry.key];
      if (r == null) continue;
      final s = entry.value;
      source('sleep', s);
      final from = s.dateFrom.subtract(const Duration(minutes: 2));
      final to = s.dateTo.add(const Duration(minutes: 2));
      double deep = 0, rem = 0, light = 0, awake = 0, asleep = 0;
      for (final p in pts) {
        if (p.dateFrom.isBefore(from) || p.dateTo.isAfter(to)) continue;
        final m = _mins(p);
        switch (p.type) {
          case HealthDataType.SLEEP_DEEP:
            deep += m;
          case HealthDataType.SLEEP_REM:
            rem += m;
          case HealthDataType.SLEEP_LIGHT:
            light += m;
          case HealthDataType.SLEEP_AWAKE:
            awake += m;
          case HealthDataType.SLEEP_ASLEEP:
            asleep += m;
          default:
            break;
        }
      }
      final staged = deep + rem + light + asleep;
      final total = staged > 0 ? staged : _mins(s) - awake;
      if (total < 60) continue; // a nap or a glitch, not a night
      r.sleepMin = total.roundToDouble();
      if (deep > 0) r.deep = deep.roundToDouble();
      if (rem > 0) r.rem = rem.roundToDouble();
      if (light > 0) r.light = light.roundToDouble();
      r.awake = awake.roundToDouble();
      final prevMidnight = addDays(dayOnly(s.dateTo), -1);
      r.bedtime = s.dateFrom.difference(prevMidnight).inMinutes.toDouble();
      r.wake = s.dateTo.difference(prevMidnight).inMinutes.toDouble();
    }
  }

  /// Overnight readings taken in the evening belong to the next morning's record.
  String _nightKey(DateTime t) => t.hour >= 18 ? isoDate(addDays(t, 1)) : isoDate(t);

  void _foldAverages(List<HealthDataPoint> pts, Map<String, DayRecord> map, void Function(String, HealthDataPoint) source) {
    final buckets = <String, Map<String, List<double>>>{};
    void add(String metric, String key, double v) {
      buckets.putIfAbsent(metric, () => {}).putIfAbsent(key, () => []).add(v);
    }

    for (final p in pts) {
      if (p.value is! NumericHealthValue) continue;
      final v = (p.value as NumericHealthValue).numericValue.toDouble();
      switch (p.type) {
        case HealthDataType.RESTING_HEART_RATE:
          add('rhr', isoDate(p.dateFrom), v);
          source('heart', p);
        case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
          add('hrv', _nightKey(p.dateFrom), v);
          source('heart', p);
        case HealthDataType.BLOOD_OXYGEN:
          add('spo2', _nightKey(p.dateFrom), v <= 1.0 ? v * 100 : v);
          source('heart', p);
        case HealthDataType.RESPIRATORY_RATE:
          add('breathing', _nightKey(p.dateFrom), v);
          source('heart', p);
        default:
          break;
      }
    }
    buckets.forEach((metric, byDay) {
      byDay.forEach((day, vals) {
        final r = map[day];
        if (r == null || vals.isEmpty) return;
        final avg = vals.reduce((a, b) => a + b) / vals.length;
        switch (metric) {
          case 'rhr':
            r.rhr = avg.roundToDouble();
          case 'hrv':
            r.hrv = avg.roundToDouble();
          case 'spo2':
            r.spo2 = (avg * 10).round() / 10;
          case 'breathing':
            r.breathing = (avg * 10).round() / 10;
        }
      });
    });
  }

  void _foldNutrition(List<HealthDataPoint> pts, Map<String, DayRecord> map, void Function(String, HealthDataPoint) source) {
    for (final p in pts.where((p) => p.type == HealthDataType.NUTRITION)) {
      final v = p.value;
      if (v is! NutritionHealthValue) continue;
      source('food', p);
      // Meals before 4 AM belong to the previous day (that 1 AM Maggi was yesterday's dinner).
      final t = p.dateFrom;
      final owner = t.hour < 4 ? addDays(dayOnly(t), -1) : dayOnly(t);
      final r = map[isoDate(owner)];
      if (r == null) continue;
      final minute = t.difference(owner).inMinutes;
      r.meals.add(Meal(
        name: (v.name ?? v.mealType ?? '').toString(),
        minute: minute,
        kcal: (v.calories ?? 0).toDouble(),
        protein: (v.protein ?? 0).toDouble(),
        caffeine: (v.caffeine ?? 0).toDouble(),
      ));
    }
    for (final r in map.values) {
      r.meals.sort((a, b) => a.minute.compareTo(b.minute));
    }
  }
}
