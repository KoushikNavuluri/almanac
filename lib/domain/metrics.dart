/// The metric dictionary: plain words, nerdy words, adult norms with sources, fun facts.
class MetricInfo {
  const MetricInfo({
    required this.key,
    required this.name,
    required this.tag,
    required this.group,
    required this.unit,
    required this.simple,
    required this.nerdy,
    required this.norm,
    required this.source,
    required this.fact,
    this.lowerIsBetter = false,
    this.experiment,
  });

  final String key, name, tag, group, unit, simple, nerdy, norm, source, fact;
  final bool lowerIsBetter;
  final String? experiment;
}

const metricGroups = ['Overnight', 'Heart', 'Day', 'Fuel'];

const metricGroupNotes = {
  'Overnight': 'From your tracker, while you slept',
  'Heart': 'From your tracker, overnight',
  'Day': 'Steps, all day',
  'Fuel': 'From your meal logs',
};

const metricOrder = ['sleepMin', 'deep', 'rem', 'hrv', 'rhr', 'spo2', 'breathing', 'steps', 'protein', 'kcal', 'lastMealMin'];

const metrics = <String, MetricInfo>{
  'sleepMin': MetricInfo(
    key: 'sleepMin', name: 'Sleep time', tag: 'Asleep', group: 'Overnight', unit: '',
    simple: 'How long you were actually asleep, not just lying in bed.',
    nerdy: 'Total sleep time (TST): light + deep + REM, awake minutes removed. Trackers estimate stages from movement and heart-rate variability.',
    norm: 'Adults do best on 7 hours or more.', source: 'AASM & Sleep Research Society consensus, Watson et al., 2015',
    fact: 'Losing even one hour a night for a week can blunt reaction time like a few drinks would.',
    experiment: 'kitchen',
  ),
  'deep': MetricInfo(
    key: 'deep', name: 'Deep sleep', tag: 'Repairs', group: 'Overnight', unit: 'min',
    simple: "Your body's repair shift: muscles rebuild, memories get filed, hormones reset.",
    nerdy: 'Slow-wave sleep (N3). Dominated by delta waves; growth hormone release peaks here. Front-loaded in the first half of the night.',
    norm: 'Usually 13–23% of sleep for adults.', source: 'Ohayon et al., Sleep, 2004 (meta-analysis)',
    fact: "Most deep sleep happens in the first 3 hours. That's why a late bedtime eats it first.",
    experiment: 'kitchen',
  ),
  'rem': MetricInfo(
    key: 'rem', name: 'Dream sleep', tag: 'REM', group: 'Overnight', unit: 'min',
    simple: 'The vivid-dream stage. Your brain replays the day and sorts what to keep.',
    nerdy: 'Rapid-eye-movement sleep. Near-waking brain activity with muscle atonia; linked to emotional processing and memory consolidation.',
    norm: 'Usually 20–25% of sleep for adults.', source: 'Ohayon et al., Sleep, 2004',
    fact: "During REM your body is briefly paralysed so you don't act out your dreams.",
    experiment: 'weekend',
  ),
  'hrv': MetricInfo(
    key: 'hrv', name: 'Calm reserve', tag: 'HRV', group: 'Heart', unit: 'ms',
    simple: 'Tiny gaps between heartbeats. Bigger, more varied gaps mean your body feels relaxed and recovered.',
    nerdy: 'Heart rate variability (RMSSD) during sleep. Higher values reflect stronger parasympathetic, rest-and-digest tone.',
    norm: 'Very personal. Compare with your own normal, not anyone else.', source: 'Shaffer & Ginsberg, Frontiers in Public Health, 2017',
    fact: 'A healthy heart is not a metronome. The irregularity is the good part.',
    experiment: 'kitchen',
  ),
  'rhr': MetricInfo(
    key: 'rhr', name: 'Resting heart', tag: 'RHR', group: 'Heart', unit: 'bpm', lowerIsBetter: true,
    simple: 'How hard your heart works when you are doing nothing. Lower usually means fitter and calmer.',
    nerdy: 'Resting heart rate from your lowest stable periods. Rises with stress, illness, alcohol, heat and late meals.',
    norm: '60–100 bpm for most adults; fitter people often sit lower.', source: 'American Heart Association',
    fact: 'A 1 bpm drop saves your heart about 1,440 beats a day.',
    experiment: 'walk',
  ),
  'spo2': MetricInfo(
    key: 'spo2', name: 'Oxygen', tag: 'SpO₂', group: 'Heart', unit: '%',
    simple: 'How full of oxygen your blood is while you sleep.',
    nerdy: 'Peripheral oxygen saturation, estimated with red and infrared light at the wrist, averaged across the night.',
    norm: '95–100% is typical near sea level.', source: 'Cleveland Clinic',
    fact: 'Your blood makes about 1,000 trips around your body every day carrying that oxygen.',
  ),
  'breathing': MetricInfo(
    key: 'breathing', name: 'Breathing rate', tag: 'Breaths/min', group: 'Heart', unit: '/min', lowerIsBetter: true,
    simple: 'Breaths per minute while asleep. Steady is what matters; a jump can flag a cold coming.',
    nerdy: 'Average respiratory rate during sleep, derived from heart-rate oscillations (respiratory sinus arrhythmia).',
    norm: '12–20 breaths a minute for adults at rest.', source: 'Cleveland Clinic',
    fact: 'Your breathing rate often creeps up a day or two before you notice you are getting sick.',
  ),
  'steps': MetricInfo(
    key: 'steps', name: 'Steps', tag: 'Moving', group: 'Day', unit: '',
    simple: 'How much you moved. It feeds better sleep and a calmer heart.',
    nerdy: 'Accelerometer step count, de-duplicated across phone and watch by Health Connect. Benefits plateau around 8,000–10,000 for adults under 60.',
    norm: '8,000–10,000 a day is the sweet spot for adults under 60.', source: 'Paluch et al., Lancet Public Health, 2022',
    fact: 'Every 1,000 steps is roughly 760 m for an average stride.',
    experiment: 'walk',
  ),
  'protein': MetricInfo(
    key: 'protein', name: 'Protein', tag: 'Meals', group: 'Fuel', unit: 'g',
    simple: 'Building blocks for muscle and repair, added up from your meal logs.',
    nerdy: 'Daily protein from logged meals. ICMR-NIN RDA for Indian adults is 0.83 g per kg body weight per day.',
    norm: 'About 0.83 g per kg of body weight a day.', source: 'ICMR-NIN Dietary Guidelines for Indians, 2024',
    fact: 'Two eggs plus a bowl of dal gets most adults about a third of the way.',
  ),
  'kcal': MetricInfo(
    key: 'kcal', name: 'Energy eaten', tag: 'kcal', group: 'Fuel', unit: 'kcal',
    simple: 'Calories from everything you logged today.',
    nerdy: 'Sum of energy across logged nutrition records. Accuracy depends on the logging app and portion estimates.',
    norm: 'Needs vary with size and activity; most adults land between 1,800 and 2,600 kcal.', source: 'ICMR-NIN Dietary Guidelines for Indians, 2024',
    fact: 'Your brain alone burns about a fifth of those calories.',
  ),
  'lastMealMin': MetricInfo(
    key: 'lastMealMin', name: 'Kitchen closed', tag: 'Meals', group: 'Fuel', unit: '', lowerIsBetter: true,
    simple: 'When you finished eating. Digesting a big meal keeps your body busy when it wants to rest.',
    nerdy: 'Time of the last logged meal (150 kcal+). Late, heavy meals raise core temperature and heart rate in early sleep.',
    norm: 'Finishing 2–3 hours before bed is the common advice.', source: 'Your own data below says how much it matters for you',
    fact: 'Your body cools by about 1°C to fall asleep. Digestion fights that.',
    experiment: 'kitchen',
  ),
};

class ExperimentInfo {
  const ExperimentInfo({
    required this.id,
    required this.title,
    required this.why,
    required this.metric,
    required this.question,
    this.days = 7,
  });
  final String id, title, why, metric, question;
  final int days;
}

const experiments = <String, ExperimentInfo>{
  'kitchen': ExperimentInfo(
    id: 'kitchen', title: 'Kitchen closes at 8:30', metric: 'deep',
    why: 'Nights after late dinners tend to carry less deep sleep and a lower calm reserve.',
    question: 'Did dinner wrap up by 8:30?',
  ),
  'walk': ExperimentInfo(
    id: 'walk', title: '10 after lunch', metric: 'sleepMin',
    why: 'A short walk softens the 2 PM dip, and bigger step days usually come with longer sleep.',
    question: 'Did you walk 10 minutes after lunch?',
  ),
  'chai': ExperimentInfo(
    id: 'chai', title: 'Last chai by 3', metric: 'sleepMin',
    why: 'Caffeine is still half-working 5–6 hours later. Late-chai nights tend to run short.',
    question: 'Was your last chai or coffee before 3 PM?',
  ),
  'weekend': ExperimentInfo(
    id: 'weekend', title: 'Same alarm, Saturday too', metric: 'rem',
    why: 'Weekends shift your body clock like a short flight east, and Monday pays for it.',
    question: 'Up within 45 min of your weekday alarm?',
  ),
};
