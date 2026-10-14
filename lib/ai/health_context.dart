import '../domain/insights.dart';
import '../domain/metrics.dart';
import '../utils/format.dart';

/// What the person allows Almanac to send to Gemini. Defaults are the minimum needed for
/// useful answers; meal names and body weight are opt-in.
class SharingPrefs {
  SharingPrefs({
    this.sleep = true,
    this.heart = true,
    this.activity = true,
    this.food = true,
    this.mealNames = false,
    this.profile = false,
    this.days = 14,
  });

  bool sleep, heart, activity, food, mealNames, profile;
  int days;

  Map<String, dynamic> toJson() => {
        'sleep': sleep,
        'heart': heart,
        'activity': activity,
        'food': food,
        'mealNames': mealNames,
        'profile': profile,
        'days': days,
      };

  factory SharingPrefs.fromJson(Map<String, dynamic> j) => SharingPrefs(
        sleep: j['sleep'] != false,
        heart: j['heart'] != false,
        activity: j['activity'] != false,
        food: j['food'] != false,
        mealNames: j['mealNames'] == true,
        profile: j['profile'] == true,
        days: (j['days'] as num?)?.toInt() ?? 14,
      );

  List<String> get labels => [
        if (sleep) 'sleep',
        if (heart) 'heart',
        if (activity) 'steps',
        if (food) 'meal times & macros',
        if (food && mealNames) 'meal names',
        if (profile) 'body weight',
      ];

  bool get anything => sleep || heart || activity || food;
}

/// Builds the ONLY payload that ever leaves the phone: daily aggregates for the last N days,
/// the person's 30-day normal and a few computed patterns. No names, device IDs, raw
/// heart-rate streams, app names, location or exact timestamps of individual readings.
class HealthContext {
  static double? _r1(double? v) => v == null ? null : (v * 10).round() / 10;
  static int? _r0(double? v) => v?.round();

  static String daypart(DateTime t) {
    final h = t.hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    if (h < 21) return 'evening';
    return 'night';
  }

  static Map<String, dynamic> build(Insights ins, SharingPrefs p) {
    final recs = ins.records;
    final rows = recs.length > p.days ? recs.sublist(recs.length - p.days) : recs;
    final daily = <Map<String, dynamic>>[];
    for (final r in rows) {
      final m = <String, dynamic>{'date': r.date, 'weekday': weekdayShort(r.day)};
      if (r.partial) m['day_in_progress'] = true;
      if (p.sleep) {
        m['sleep_hours'] = _r1(r.sleepMin == null ? null : r.sleepMin! / 60);
        m['deep_min'] = _r0(r.deep);
        m['rem_min'] = _r0(r.rem);
        m['awake_min'] = _r0(r.awake);
        m['bedtime'] = r.bedtime == null ? null : fmtClock(r.bedtime!);
        m['wake_time'] = r.wake == null ? null : fmtClock(r.wake!);
      }
      if (p.heart) {
        m['hrv_rmssd_ms'] = _r0(r.hrv);
        m['resting_hr_bpm'] = _r0(r.rhr);
        m['spo2_pct'] = _r1(r.spo2);
        m['breaths_per_min'] = _r1(r.breathing);
      }
      if (p.activity) m['steps'] = _r0(r.steps);
      if (p.food && r.meals.isNotEmpty) {
        m['kcal_eaten'] = _r0(r.kcal);
        m['protein_g'] = _r0(r.protein);
        m['last_meal_time'] = r.lastMealMin == null ? null : fmtClock(r.lastMealMin!);
        m['caffeine_after_4pm'] = r.caffeineLate;
        m['meals_logged'] = r.meals.length;
        if (p.mealNames) {
          m['meals'] = r.meals.map((x) => '${fmtClock(x.minute.toDouble())} ${x.name}').toList();
        }
      }
      m.removeWhere((k, v) => v == null);
      daily.add(m);
    }

    final normal = <String, dynamic>{};
    void norm(String key, bool allowed) {
      if (!allowed) return;
      final b = ins.baseline(key);
      if (!b.ok) return;
      normal[key] = {'mean': _r1(b.mean), 'sd': _r1(b.sd), 'days': b.n, 'unit': metrics[key]?.unit ?? ''};
    }

    norm('sleepMin', p.sleep);
    norm('deep', p.sleep);
    norm('rem', p.sleep);
    norm('hrv', p.heart);
    norm('rhr', p.heart);
    norm('spo2', p.heart);
    norm('breathing', p.heart);
    norm('steps', p.activity);
    norm('protein', p.food);
    norm('kcal', p.food);

    final patterns = <String, dynamic>{};
    void split(String name, Split s, String unit) {
      if (!s.ok) return;
      patterns[name] = {'when_true': _r1(s.yes), 'when_false': _r1(s.no), 'nights_true': s.nYes, 'nights_false': s.nNo, 'unit': unit};
    }

    if (p.food && p.sleep) {
      split('deep_sleep_after_dinner_past_10pm', ins.lateDinnerDeep, 'min');
      split('sleep_after_caffeine_past_4pm', ins.chaiSleep, 'min');
    }
    if (p.food && p.heart) split('hrv_after_dinner_past_10pm', ins.lateDinnerHrv, 'ms');
    if (p.activity && p.sleep) split('sleep_after_9000_plus_step_day', ins.bigDaySleep, 'min');
    final jl = p.sleep ? ins.socialJetLagMin : null;
    if (jl != null) patterns['weekend_sleep_shift_min'] = jl.round();

    final score = (p.sleep || p.heart) ? ins.readiness() : null;
    final curve = (p.sleep || p.heart) ? ins.energyCurve() : null;
    final now = DateTime.now();
    return {
      'app': 'Almanac',
      'today': isoDate(now),
      'local_time': fmtTime(now),
      'part_of_day': daypart(now),
      'about_the_data': 'Daily aggregates from a consumer wearable and a meal-logging app via Health Connect. Estimates, not medical measurements. The last entry in days is today, still in progress.',
      if (score != null) 'readiness_score_0_to_100': score,
      if (score != null) 'readiness_label': ins.condition(score).label,
      if (curve != null)
        'energy_forecast_today': {
          'morning_peak': fmtClock(curve.peak.h * 60),
          'afternoon_dip': fmtClock(curve.dip.h * 60),
          'second_wind': fmtClock(curve.second.h * 60),
        },
      'shared_categories': p.labels,
      'days': daily,
      'personal_normal_30d': normal,
      'computed_patterns': patterns,
      if (p.profile && ins.weightKg != null) 'body_weight_kg': _r1(ins.weightKg),
      if (p.food) 'protein_target_g': ins.proteinTarget,
    };
  }
}
