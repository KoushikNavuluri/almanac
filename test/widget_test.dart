import 'package:almanac/ai/health_context.dart';
import 'package:almanac/ai/local_brain.dart';
import 'package:almanac/data/sample_data.dart';
import 'package:almanac/domain/insights.dart';
import 'package:almanac/domain/export.dart';
import 'package:almanac/models/day_record.dart';
import 'package:almanac/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 14, 19, 30);
  final records = SampleData.generate(now);
  final ins = Insights(records, now: now);

  test('sample data covers 60 days ending today', () {
    expect(records.length, 60);
    expect(records.last.date, isoDate(now));
    expect(ins.today, isNotNull);
  });

  test('forecast, energy curve and note are computed', () {
    final score = ins.readiness();
    expect(score, isNotNull);
    expect(score! >= 18 && score <= 98, isTrue);
    final c = ins.energyCurve();
    expect(c.dip.h, greaterThan(12));
    expect(ins.forecasterNote('simple'), isNotEmpty);
    expect(ins.forecasterNote('nerdy'), contains('TST'));
  });

  test('late dinners show up as a deep-sleep pattern', () {
    final s = ins.lateDinnerDeep;
    expect(s.ok, isTrue);
    expect(s.diff, lessThan(0));
    expect(ins.discoveries().map((d) => d.id), contains('late-dinner'));
  });

  test('privacy payload respects sharing choices', () {
    final off = HealthContext.build(ins, SharingPrefs(food: true, mealNames: false));
    final days = off['days'] as List;
    expect(days.any((d) => (d as Map).containsKey('meals')), isFalse);
    final on = HealthContext.build(ins, SharingPrefs(food: true, mealNames: true));
    expect((on['days'] as List).any((d) => (d as Map).containsKey('meals')), isTrue);
    final noHeart = HealthContext.build(ins, SharingPrefs(heart: false));
    expect((noHeart['days'] as List).any((d) => (d as Map).containsKey('hrv_rmssd_ms')), isFalse);
  });

  test('crisis language is handled locally', () {
    final r = LocalBrain.safety('I want to hurt myself');
    expect(r, isNotNull);
    expect(r!.help, 'crisis');
    expect(LocalBrain.safety('how did I sleep?'), isNull);
  });

  test('records survive a JSON round trip', () {
    final r = records.last;
    final back = DayRecord.fromJson(r.toJson());
    expect(back.sleepMin, r.sleepMin);
    expect(back.meals.length, r.meals.length);
  });

  test('exports are produced', () {
    expect(recordsCsv(records).split('\n').length, 61);
    expect(weeklyEdition(ins), contains('Weekly edition'));
  });

  test('Indian digit grouping', () {
    expect(fmtInt(1234567), '12,34,567');
    expect(fmtInt(950), '950');
  });
}
