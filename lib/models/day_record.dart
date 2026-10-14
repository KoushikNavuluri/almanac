import '../utils/format.dart';

final _caffeineWords = RegExp(
  r'\b(chai|coffee|tea|espresso|latte|cappuccino|americano|cold brew|mocha|energy drink|red bull|cola|coke)\b',
  caseSensitive: false,
);

/// One logged meal (from Cravin' via Health Connect nutrition records).
class Meal {
  const Meal({required this.name, required this.minute, this.kcal = 0, this.protein = 0, this.caffeine = 0});

  final String name;

  /// Minutes after the day's midnight. Can exceed 1440 for after-midnight snacks.
  final int minute;
  final double kcal;
  final double protein;

  /// Grams of caffeine, if the logging app recorded it.
  final double caffeine;

  bool get isCaffeinated => caffeine > 0 || _caffeineWords.hasMatch(name);

  /// Drinks and small snacks don't count as "the last meal".
  bool get isMeal => kcal >= 150;

  Map<String, dynamic> toJson() => {'n': name, 'm': minute, 'k': kcal, 'p': protein, 'c': caffeine};

  factory Meal.fromJson(Map<String, dynamic> j) => Meal(
        name: (j['n'] as String?) ?? '',
        minute: (j['m'] as num?)?.toInt() ?? 0,
        kcal: (j['k'] as num?)?.toDouble() ?? 0,
        protein: (j['p'] as num?)?.toDouble() ?? 0,
        caffeine: (j['c'] as num?)?.toDouble() ?? 0,
      );
}

/// Everything Almanac knows about one calendar day.
/// Overnight fields describe the night that ENDED on this morning.
class DayRecord {
  DayRecord({
    required this.date,
    this.sleepMin,
    this.napMin,
    this.deep,
    this.rem,
    this.light,
    this.awake,
    this.bedtime,
    this.wake,
    this.hrv,
    this.rhr,
    this.spo2,
    this.breathing,
    this.steps,
    List<Meal>? meals,
    this.partial = false,
  }) : meals = meals ?? <Meal>[];

  final String date;

  /// Total time asleep for the day, the way Google Health counts it (naps included unless
  /// switched off in Data check).
  double? sleepMin;

  /// Minutes of daytime naps that ended on this day (already inside [sleepMin] when counted).
  double? napMin;
  double? deep;
  double? rem;
  double? light;
  double? awake;

  /// Minutes after the PREVIOUS day's midnight (23:30 = 1410, 00:40 = 1480).
  double? bedtime;

  /// Same reference as [bedtime] (07:35 = 1895).
  double? wake;
  double? hrv;
  double? rhr;
  double? spo2;
  double? breathing;
  double? steps;
  List<Meal> meals;

  /// True for today while the day is still accumulating.
  bool partial;

  DateTime get day => parseIso(date);
  int get weekday => day.weekday;

  double? get kcal => meals.isEmpty ? null : meals.fold<double>(0, (s, m) => s + m.kcal);
  double? get protein => meals.isEmpty ? null : meals.fold<double>(0, (s, m) => s + m.protein);

  List<Meal> get realMeals {
    final list = meals.where((m) => m.isMeal).toList()..sort((a, b) => a.minute.compareTo(b.minute));
    return list;
  }

  double? get lastMealMin {
    final list = realMeals;
    return list.isEmpty ? null : list.last.minute.toDouble();
  }

  String? get dinnerName {
    final list = realMeals;
    if (list.isEmpty || list.last.name.trim().isEmpty) return null;
    return list.last.name.trim();
  }

  bool get lateDinner => (lastMealMin ?? 0) >= 22 * 60;
  bool get caffeineLate => meals.any((m) => m.isCaffeinated && m.minute >= 16 * 60);

  double? value(String key) {
    switch (key) {
      case 'sleepMin':
        return sleepMin;
      case 'deep':
        return deep;
      case 'rem':
        return rem;
      case 'light':
        return light;
      case 'awake':
        return awake;
      case 'hrv':
        return hrv;
      case 'rhr':
        return rhr;
      case 'spo2':
        return spo2;
      case 'breathing':
        return breathing;
      case 'steps':
        return steps;
      case 'kcal':
        return kcal;
      case 'protein':
        return protein;
      case 'lastMealMin':
        return lastMealMin;
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        if (sleepMin != null) 'sleepMin': sleepMin,
        if (napMin != null) 'napMin': napMin,
        if (deep != null) 'deep': deep,
        if (rem != null) 'rem': rem,
        if (light != null) 'light': light,
        if (awake != null) 'awake': awake,
        if (bedtime != null) 'bedtime': bedtime,
        if (wake != null) 'wake': wake,
        if (hrv != null) 'hrv': hrv,
        if (rhr != null) 'rhr': rhr,
        if (spo2 != null) 'spo2': spo2,
        if (breathing != null) 'breathing': breathing,
        if (steps != null) 'steps': steps,
        'meals': meals.map((m) => m.toJson()).toList(),
        if (partial) 'partial': true,
      };

  factory DayRecord.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return DayRecord(
      date: j['date'] as String,
      sleepMin: d('sleepMin'),
      napMin: d('napMin'),
      deep: d('deep'),
      rem: d('rem'),
      light: d('light'),
      awake: d('awake'),
      bedtime: d('bedtime'),
      wake: d('wake'),
      hrv: d('hrv'),
      rhr: d('rhr'),
      spo2: d('spo2'),
      breathing: d('breathing'),
      steps: d('steps'),
      meals: ((j['meals'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Meal.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      partial: j['partial'] == true,
    );
  }
}
