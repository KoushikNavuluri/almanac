import 'dart:math';

import '../models/day_record.dart';
import '../utils/format.dart';

/// A realistic, deterministic 60-day sample shaped like Fitbit + Cravin' records, with real
/// cause and effect baked in (late dinners hurt deep sleep and HRV, big walking days lengthen
/// sleep, late chai shortens it, weekends drift the body clock). Only used when the person
/// explicitly picks "Explore with sample data"; it is always labelled as sample data.
class SampleData {
  static const _light = [
    'Dal khichdi + curd', 'Pesarattu + ginger chutney', 'Paneer tikka + 2 rotis', 'Idli sambar',
    'Rajma chawal', 'Egg bhurji + 2 rotis', 'Curd rice + pickle', 'Grilled chicken + salad',
    'Vegetable upma', 'Dal tadka + jeera rice',
  ];
  static const _heavy = [
    'Chicken biryani (Paradise)', 'Mutton haleem (Pista House)', 'Butter chicken + garlic naan',
    'Hakka noodles + manchurian', 'Chicken 65 + bagara rice', 'Pizza (2 slices) + garlic bread',
  ];
  static const _breakfast = ['Poha', 'Idli + chutney', 'Upma', 'Egg dosa', 'Oats + banana', 'Pesarattu'];
  static const _lunch = ['Veg thali', 'Chicken curry + rice', 'Dal + 3 rotis + sabzi', 'Sambar rice + poriyal', 'Paneer wrap'];

  static List<DayRecord> generate(DateTime now, {int days = 60}) {
    final rnd = Random(14102026);
    double g() {
      var u = 0.0, v = 0.0;
      while (u == 0) {
        u = rnd.nextDouble();
      }
      while (v == 0) {
        v = rnd.nextDouble();
      }
      return sqrt(-2 * log(u)) * cos(2 * pi * v);
    }

    double c(double v, double a, double b) => v < a ? a : (v > b ? b : v);
    final today = dayOnly(now);
    final out = <DayRecord>[];
    var prevLate = false, prevChai = false;
    double prevSteps = 8200;

    for (var i = 0; i < days; i++) {
      final date = addDays(today, i - (days - 1));
      final weekend = date.weekday >= 6;
      final progress = i / (days - 1);

      final bedtime = (weekend ? 24 * 60 + 40 : 23 * 60 + 20) + g() * 25 + (prevLate ? 22 : 0);
      final sleep = c(425 + g() * 22 + (prevSteps > 9000 ? 24 : 0) - (prevChai ? 22 : 0) - (prevLate ? 16 : 0) + (weekend ? 28 : 0), 330, 520);
      final deep = c(sleep * 0.18 + g() * 7 - (prevLate ? 20 : 0) + (prevSteps > 9000 ? 7 : 0), 30, 110);
      final rem = c(sleep * 0.22 + g() * 9, 50, 130);
      final awake = c(34 + g() * 8 + (prevLate ? 12 : 0) + (prevChai ? 6 : 0), 12, 80);
      final hrv = 49 + progress * 6 + g() * 4 - (prevLate ? 7 : 0) - (sleep < 390 ? 4 : 0) + (prevSteps > 9000 ? 3 : 0);
      final rhr = 64 - progress * 2 + g() * 1.4 + (prevLate ? 3 : 0) + (sleep < 390 ? 1.5 : 0);
      final spo2 = c(96.6 + g() * 0.5, 94.6, 98.6);
      final breathing = 14.6 + g() * 0.4 + (prevLate ? 0.4 : 0);

      final lateDinner = rnd.nextDouble() < (weekend || date.weekday == 5 ? 0.5 : 0.22);
      final chaiLate = rnd.nextDouble() < 0.26;
      final steps = c((weekend ? (rnd.nextDouble() < 0.4 ? 12400 : 6200) : 8000) + progress * 900 + g() * 2100, 2400, 17500).roundToDouble();
      final dinnerMin = lateDinner ? 22 * 60 + rnd.nextDouble() * 50 : 20 * 60 + g() * 30;
      final dinner = lateDinner ? _heavy[rnd.nextInt(_heavy.length)] : _light[rnd.nextInt(_light.length)];
      final kcal = 1950 + g() * 200 + (lateDinner ? 260 : 0);
      final protein = c(60 + g() * 13 + (lateDinner ? 6 : 0), 32, 110);

      final meals = <Meal>[
        Meal(name: _breakfast[rnd.nextInt(_breakfast.length)], minute: (8 * 60 + 30 + g() * 20).round(), kcal: (kcal * 0.24).roundToDouble(), protein: (protein * 0.25).roundToDouble()),
        if (chaiLate)
          Meal(name: 'Irani chai', minute: (16 * 60 + 30 + g() * 20).round(), kcal: 90, protein: 2, caffeine: 0.05)
        else
          Meal(name: 'Masala chai', minute: 11 * 60, kcal: 90, protein: 2, caffeine: 0.05),
        Meal(name: _lunch[rnd.nextInt(_lunch.length)], minute: (13 * 60 + 30 + g() * 20).round(), kcal: (kcal * 0.33).roundToDouble(), protein: (protein * 0.33).roundToDouble()),
        Meal(name: dinner, minute: dinnerMin.round(), kcal: (kcal * 0.43 - 90).roundToDouble(), protein: (protein * 0.42 - 2).roundToDouble()),
      ];

      out.add(DayRecord(
        date: isoDate(date),
        sleepMin: sleep.roundToDouble(),
        deep: deep.roundToDouble(),
        rem: rem.roundToDouble(),
        light: (sleep - deep - rem).roundToDouble(),
        awake: awake.roundToDouble(),
        bedtime: bedtime.roundToDouble(),
        wake: (bedtime + sleep + awake).roundToDouble(),
        hrv: hrv.roundToDouble(),
        rhr: rhr.roundToDouble(),
        spo2: (spo2 * 10).round() / 10,
        breathing: (breathing * 10).round() / 10,
        steps: steps,
        meals: meals,
      ));
      prevLate = lateDinner;
      prevChai = chaiLate;
      prevSteps = steps;
    }

    // The story: yesterday was a 10:40 PM Paradise biryani after a 4:30 PM Irani chai.
    final y = out[days - 2];
    y.steps = 5130;
    y.meals = [
      Meal(name: 'Idli + chutney', minute: 8 * 60 + 35, kcal: 420, protein: 12),
      Meal(name: 'Veg thali', minute: 13 * 60 + 40, kcal: 690, protein: 21),
      Meal(name: 'Irani chai', minute: 16 * 60 + 30, kcal: 90, protein: 2, caffeine: 0.05),
      Meal(name: 'Chicken biryani (Paradise)', minute: 22 * 60 + 40, kcal: 1180, protein: 38),
    ];
    final t = out[days - 1];
    t
      ..bedtime = 24 * 60 + 25
      ..sleepMin = 381
      ..deep = 51
      ..rem = 82
      ..awake = 49
      ..light = 381 - 51 - 82
      ..wake = 24 * 60 + 25 + 381 + 49
      ..hrv = 44
      ..rhr = 67
      ..spo2 = 96.3
      ..breathing = 15.1
      ..partial = true;
    final minuteNow = now.hour * 60 + now.minute;
    final dayFrac = c((minuteNow - 7 * 60) / (15 * 60), 0.05, 1.0);
    t.steps = (7800 * dayFrac).roundToDouble();
    t.meals = [
      if (minuteNow > 8 * 60 + 40) Meal(name: 'Poha', minute: 8 * 60 + 40, kcal: 380, protein: 9),
      if (minuteNow > 11 * 60) Meal(name: 'Masala chai', minute: 11 * 60, kcal: 90, protein: 2, caffeine: 0.05),
      if (minuteNow > 13 * 60 + 20) Meal(name: 'Veg thali', minute: 13 * 60 + 20, kcal: 760, protein: 26),
    ];

    // A clean best night 17 days ago, worth remembering.
    out[days - 18]
      ..sleepMin = 484
      ..deep = 104
      ..rem = 118
      ..awake = 22
      ..light = 484 - 104 - 118
      ..hrv = 63
      ..rhr = 60;
    return out;
  }
}
