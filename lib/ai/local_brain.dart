import '../domain/insights.dart';
import '../utils/format.dart';
import 'chat_models.dart';

bool _has(String t, List<String> words) => words.any(t.contains);

/// On-device answers. Used for safety (always, before anything is sent anywhere), and as the
/// fallback when no Gemini key is set or Gemini is unreachable. Every number comes from [Insights].
class LocalBrain {
  static const starterChips = [
    'Why am I tired today?',
    "What's HRV, simply?",
    'Does late dinner hurt my sleep?',
    'Give me one tip for today',
    'Tell me a fun fact about my body',
  ];

  static ChatMessage _ai(String text, {List<String> chips = const [], String? metric, String? experiment, String? help}) =>
      ChatMessage(id: ChatMessage.newId(), role: 'ai', text: text, chips: chips, metric: metric, experiment: experiment, help: help, source: 'local');

  /// Crisis and emergency language never goes to the network.
  static ChatMessage? safety(String raw) {
    final t = raw.toLowerCase();
    if (_has(t, ['kill myself', 'suicid', 'self harm', 'self-harm', 'hurt myself', 'end it all', 'want to die', 'starve myself', 'purge', 'throw up after', 'stop eating', 'hate my body'])) {
      return _ai(
        "I'm really glad you said something. This is bigger than a sleep score, and you deserve a real person to talk to. In India you can call Tele-MANAS on 14416, free and confidential, any time. If you're in danger right now, call 112.",
        chips: const ['Can we talk about sleep instead?'],
        help: 'crisis',
      );
    }
    if (_has(t, ['chest pain', 'heart attack', 'fainted', 'fainting', 'passed out', 'can\'t breathe', 'cannot breathe', 'stroke'])) {
      return _ai(
        "That's not a wearable question. Call 112 or get to a hospital now, and tell them exactly what you feel.",
        help: 'emergency',
      );
    }
    return null;
  }

  static ChatMessage respond(String raw, Insights ins, String depth) {
    final t = raw.toLowerCase().trim();
    final today = ins.today;
    final nerdy = depth == 'nerdy';

    if (_has(t, ['diagnos', 'disease', 'afib', 'arrhythm', 'medicine', 'medication', 'tablet', 'blood pressure', 'diabet', 'fever', 'dizzy', 'palpitation', 'apnea', 'apnoea'])) {
      final br = ins.reading('breathing'), sp = ins.reading('spo2');
      return _ai(
        "That's one for a doctor, not a wristband. Tracker numbers are estimates and can't diagnose anything.${br != null ? ' For context: your latest breathing rate is ${br.value.toStringAsFixed(1)}/min' : ''}${sp != null ? ' and oxygen ${sp.value.toStringAsFixed(1)}%' : ''}. You can export your data from Me to show them.",
        metric: 'breathing',
        chips: const ['Why am I tired today?'],
      );
    }

    if (_has(t, ['tired', 'exhaust', 'sleepy', 'low energy', 'groggy', 'foggy', 'drained', 'why do i feel'])) {
      return _ai(ins.forecasterNote(depth), metric: 'deep', experiment: ins.experimentImpact('kitchen') != null ? 'kitchen' : null, chips: const ['Does late dinner hurt my sleep?', 'How do I beat the afternoon dip?']);
    }

    if (_has(t, ['hrv', 'calm reserve', 'variability'])) {
      final b = ins.baseline('hrv');
      final r = ins.reading('hrv');
      if (r == null) return _ai("I don't have HRV readings yet. If your tracker records it, check that it syncs HRV to Health Connect.", chips: starterChips);
      final tr = ins.hrvTrend;
      return _ai(
        nerdy
            ? 'RMSSD during sleep: ${r.value.round()} ms${b.ok ? ', 30-day mean ${b.mean.round()} ± ${b.sd.round()}' : ''}. Higher values mean stronger rest-and-digest tone.${tr != null ? ' ${tr.pct >= 0 ? 'Up' : 'Down'} ${tr.pct.abs().round()}% over 8 weeks.' : ''}'
            : "Your heart doesn't tick like a clock. The gaps between beats wobble a little, and more wobble means your body feels safe enough to rest. Latest: ${r.value.round()} ms${b.ok ? ', your usual is ${b.mean.round()}' : ''}.${tr != null && tr.pct > 3 ? ' Good news: it is up ${tr.pct.round()}% over 8 weeks.' : ''}",
        metric: 'hrv',
        chips: const ['How do I raise it?', 'Why am I tired today?'],
      );
    }

    if (_has(t, ['protein'])) {
      final b = ins.baseline('protein');
      return _ai(
        b.ok
            ? 'You average ${b.mean.round()} g a day in your meal logs. A good target is about ${ins.proteinTarget.round()} g (0.83 g per kg, ICMR-NIN). Easy wins: eggs, curd, paneer, chana or a second katori of dal.'
            : 'I need a few more days of meal logs to judge protein. A good target is about 0.83 g per kg of body weight a day.',
        metric: 'protein',
        chips: const ['Does late dinner hurt my sleep?'],
      );
    }

    if (_has(t, ['dinner', 'late meal', 'eat late', 'biryani', 'food', 'meal', 'eating', 'raise it'])) {
      final s = ins.lateDinnerDeep;
      if (!s.ok) return _ai('Not enough nights with logged dinner times yet to tell. Keep logging meals for a couple of weeks and I will show you.', chips: starterChips);
      return _ai(
        'After the ${s.nYes} dinners you logged past 10 PM, you averaged ${s.yes.round()} min of deep sleep. After earlier dinners: ${s.no.round()} min.${ins.lateDinnerRhr.ok ? ' Your resting heart also runs ${ins.lateDinnerRhr.diff.toStringAsFixed(1)} bpm higher.' : ''} The food isn\'t the villain, the clock is.',
        metric: 'deep',
        experiment: 'kitchen',
        chips: const ['Is my evening chai a problem?', 'Am I eating enough protein?'],
      );
    }

    if (_has(t, ['chai', 'coffee', 'caffeine']) || RegExp(r'\btea\b').hasMatch(t)) {
      final s = ins.chaiSleep;
      if (!s.ok) return _ai("I can't see enough late-caffeine days in your logs to judge. As a rule, caffeine is still half-working 5 to 6 hours later.", experiment: 'chai');
      return _ai(
        'On ${s.nYes} days with caffeine after 4 PM you slept ${fmtDur(s.yes)} on average, vs ${fmtDur(s.no)} without. Keep the chai, move it before 3.',
        metric: 'sleepMin',
        experiment: 'chai',
        chips: const ['Why am I tired today?'],
      );
    }

    if (_has(t, ['dip', 'afternoon', 'slump', 'after lunch'])) {
      final c = ins.energyCurve();
      return _ai(
        'Your dip lands near ${fmtClock(c.dip.h * 60)}. Everyone has one. Make it smaller: lighter lunch, a 10-minute walk right after, daylight on your face, and save hard thinking for ${fmtClock(c.peak.h * 60)} or ${fmtClock(c.second.h * 60)}.',
        experiment: 'walk',
        chips: const ['How much should I walk?'],
      );
    }

    if (_has(t, ['monday', 'weekend', 'jet lag', 'body clock'])) {
      final j = ins.socialJetLagMin;
      if (j == null) return _ai('I need a few more weekends of sleep data to measure your weekend drift.');
      return _ai(
        'On weekends your sleep slides about ${j.round()} min later, like a weekly trip to ${ins.jetLagPlace(j)}. Wake within 45 min of your weekday alarm, even on Saturday, and Mondays get easier.',
        experiment: 'weekend',
        metric: 'rem',
      );
    }

    if (_has(t, ['walk', 'step', 'move', 'exercise', 'workout', 'active'])) {
      final s = ins.bigDaySleep;
      final r = ins.reading('steps');
      return _ai(
        '${s.ok && s.diff > 0 ? 'On 9,000+ step days you sleep ${s.diff.round()} min longer that night. ' : ''}Research puts the sweet spot at 8,000–10,000 a day for adults under 60.${r != null && r.isToday ? ' You are at ${fmtInt(r.value)} today.' : ''}',
        metric: 'steps',
        experiment: 'walk',
      );
    }

    if (_has(t, ['sleep', 'night', 'bed', 'rem', 'dream'])) {
      final b = ins.baseline('sleepMin');
      if (!b.ok) return _ai('I need about a week of nights to know your normal. Keep wearing your tracker to bed.');
      return _ai(
        '${b.mean >= 420 ? 'Mostly, yes.' : 'Not quite.'} You average ${fmtDur(b.mean)} a night; adults do best on 7h+. Your longest run of 7h+ nights is ${ins.best7hStreak}.${today?.sleepMin != null ? ' Last night: ${fmtDur(today!.sleepMin!)}.' : ''}',
        metric: 'sleepMin',
        chips: const ['Why are my Mondays rough?'],
      );
    }

    if (_has(t, ['heart', 'rhr', 'pulse'])) {
      final b = ins.baseline('rhr');
      if (!b.ok) return _ai('No resting heart rate readings yet. Check that your tracker syncs heart data to Health Connect.');
      return _ai(
        'Your resting heart usually sits around ${b.mean.round()} bpm (60–100 is the normal adult range). Late meals, short sleep, heat and stress nudge it up; it drops back as you recover.',
        metric: 'rhr',
      );
    }

    if (_has(t, ['fun', 'fact', 'cool', 'surprise', 'another'])) {
      final d = ins.discoveries().where((d) => d.kind == 'Fun fact' || d.kind == 'Milestone').toList();
      if (d.isEmpty) return _ai('Once I have a couple of weeks of data I will have plenty of these.');
      final pick = d[DateTime.now().second % d.length];
      return _ai('${pick.head}. ${pick.body}', metric: pick.metric, chips: const ['Another one', 'Why am I tired today?']);
    }

    if (_has(t, ['tip', 'what should i do', 'advice', 'plan', 'suggest'])) {
      final imp = ins.experimentImpact('kitchen');
      if (imp != null) {
        return _ai('One thing: finish dinner by 8:30 tonight. In your data it is worth about ${imp.delta} min of deep sleep.', experiment: 'kitchen');
      }
      return _ai('Get daylight within an hour of waking and take a 10-minute walk after lunch. Small, boring, and it works.', experiment: 'walk');
    }

    return _ai(
      "I'm best at sleep, heart, steps and food. Add your Gemini key in Me to let me answer anything in your own words; for now, try one of these:",
      chips: starterChips,
    );
  }
}
