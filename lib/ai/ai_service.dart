import 'dart:convert';

import '../domain/metrics.dart';
import 'chat_models.dart';
import 'gemini_client.dart';

const _system = '''
You are "the forecaster" inside Almanac, a personal health companion app. You read ONE person's own
wearable and meal-log data (given to you as JSON) and explain it like a warm, witty weather presenter:
plain words, short sentences, specific numbers from THEIR data, no jargon unless they ask for the nerdy level.

Rules:
- Only use numbers that appear in the data or follow directly from it. If something is missing, say so. Never invent readings.
- Compare the person with their own normal (personal_normal_30d) first; population norms only as context.
- Write numbers the way the app shows them: durations as hours and minutes like 5h 36m (use the "asleep" and
  "typical" strings when present; never write "336 minutes" or decimal hours), clock times like 11:40 PM, and whole
  numbers for steps, bpm, ms and minutes of a sleep stage. No decimals except SpO2 and breathing rate.
- Be practical: one concrete action beats five vague ones. Indian food and daily-life context is welcome.
- Respect the time of day (local_time, part_of_day): don't suggest a morning walk at 10 PM.
- You are not a doctor. Never diagnose, never say a disease is likely, never suggest starting, stopping or changing medication.
  If something looks medically worrying (very low oxygen, chest pain, fainting, a sustained large jump in resting heart rate
  or breathing rate), calmly say it is worth checking with a doctor.
- If the person mentions self-harm, an eating disorder or a crisis, respond with care, no numbers, and point them to
  Tele-MANAS 14416 (India, free, 24x7) or emergency services (112).
- Wearable numbers are estimates; trends over weeks matter more than one night.
- When asked for JSON, answer with valid JSON only, exactly in the shape requested. No markdown, no code fences.
''';

final _metricKeys = metricOrder.join(', ');
const _kinds = ['Pattern', 'Trend', 'Fun fact', 'Milestone'];

const Map<String, dynamic> _str = {'type': 'STRING'};

Map<String, dynamic> _obj(Map<String, dynamic> props, [List<String> required = const []]) => {
      'type': 'OBJECT',
      'properties': props,
      if (required.isNotEmpty) 'required': required,
    };

Map<String, dynamic> _arr(Map<String, dynamic> items) => {'type': 'ARRAY', 'items': items};

final _discoverySchema = _obj({'kind': _str, 'head': _str, 'body': _str, 'metric': _str}, const ['kind', 'head', 'body', 'metric']);

final _briefSchema = _obj({
  'headline': _str,
  'note_simple': _str,
  'note_nerdy': _str,
  'tip': _obj({'title': _str, 'body': _str}, const ['title', 'body']),
  'discoveries': _arr(_discoverySchema),
  'fun_fact': _str,
  'metric_lines': _obj({for (final k in metricOrder) k: _str}),
}, const ['headline', 'note_simple', 'note_nerdy', 'tip', 'discoveries', 'fun_fact', 'metric_lines']);

final _liveSchema = _obj({'title': _str, 'body': _str, 'metric': _str, 'experiment': _str}, const ['title', 'body']);
final _textSchema = _obj({'text': _str}, const ['text']);
final _moreSchema = _obj({'discoveries': _arr(_discoverySchema)}, const ['discoveries']);

String _clean(dynamic v, [String fallback = '']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty || s == 'null' ? fallback : s;
}

String _metric(dynamic v) {
  final s = _clean(v);
  return metrics.containsKey(s) ? s : 'sleepMin';
}

String? _optMetric(dynamic v) {
  final s = _clean(v);
  return metrics.containsKey(s) ? s : null;
}

String? _optExp(dynamic v) {
  final s = _clean(v);
  return experiments.containsKey(s) ? s : null;
}

List<AiDiscovery> _discoveries(dynamic list) {
  if (list is! List) return const [];
  final out = <AiDiscovery>[];
  for (final m in list.whereType<Map>()) {
    final kind = _clean(m['kind'], 'Pattern');
    final head = _clean(m['head']);
    if (head.isEmpty) continue;
    out.add(AiDiscovery(
      kind: _kinds.contains(kind) ? kind : 'Pattern',
      head: head,
      body: _clean(m['body']),
      metric: _metric(m['metric']),
    ));
  }
  return out;
}

/// All Gemini prompts live here. Every call receives only the privacy-filtered context JSON.
class AiService {
  AiService(this.client);
  final GeminiClient client;

  String _data(Map<String, dynamic> context) => 'Here is my health data as JSON:\n${jsonEncode(context)}';

  Future<DailyBrief> dailyBrief({
    required String key,
    required String model,
    List<String> fallbacks = const [],
    required Map<String, dynamic> context,
    required String dataKey,
  }) async {
    final prompt = '''
${_data(context)}

Write today's forecast for me. JSON fields:
- headline: max 8 words, the story of my day
- note_simple: 2-3 sentences, max 55 words, plain words: how last night went, the likely reason, what today will feel like
- note_nerdy: 2-3 sentences, max 60 words, real terms (TST, N3, RMSSD, RHR) with my numbers vs my normal
- tip: {title: max 6 words, an action for the rest of today; body: max 30 words, why it helps me specifically}
- discoveries: exactly 3 items {kind: Pattern | Trend | Fun fact | Milestone, head: max 10 words, a statement, body: max 35 words, metric: one of $_metricKeys}
- fun_fact: max 30 words, a surprising true fact about my body using my numbers
- metric_lines: for each metric key ($_metricKeys) that has data, one plain line (max 14 words) on my latest value vs my typical value, durations written like 5h 36m. Leave out keys with no data.
''';
    final text = await client.generate(
      key: key,
      model: model,
      fallbacks: fallbacks,
      system: _system,
      contents: [GeminiClient.userTurn(prompt)],
      schema: _briefSchema,
    );
    final j = GeminiClient.parseJson(text);
    final tip = j['tip'] is Map ? Map<String, dynamic>.from(j['tip'] as Map) : const <String, dynamic>{};
    final simple = _clean(j['note_simple']);
    if (simple.isEmpty) throw GeminiException('Gemini sent back an empty forecast.', retryable: true);
    final lines = <String, String>{};
    final ml = j['metric_lines'];
    if (ml is Map) {
      ml.forEach((k, v) {
        final ks = k.toString();
        final vs = _clean(v);
        if (metrics.containsKey(ks) && vs.isNotEmpty) lines[ks] = vs;
      });
    }
    return DailyBrief(
      headline: _clean(j['headline']),
      noteSimple: simple,
      noteNerdy: _clean(j['note_nerdy'], simple),
      tipTitle: _clean(tip['title'], 'One thing for today'),
      tipBody: _clean(tip['body']),
      discoveries: _discoveries(j['discoveries']).take(4).toList(),
      funFact: _clean(j['fun_fact']),
      metricLines: lines,
      model: model,
      createdAt: DateTime.now(),
      dataKey: dataKey,
    );
  }

  Future<LiveNudge> liveNudge({
    required String key,
    required String model,
    List<String> fallbacks = const [],
    required Map<String, dynamic> context,
    required String liveKey,
    required String daypart,
  }) async {
    final prompt = '''
${_data(context)}

It is ${context['local_time']} ($daypart). Give me a "right now" update: what is going on in my body at this moment and the single
most useful thing to do in the next couple of hours, based on last night, today's steps and meals so far, and the energy forecast.
Return JSON: {"title": "max 7 words", "body": "max 40 words, specific to my numbers and this time of day",
"metric": "most relevant key from: $_metricKeys", "experiment": "kitchen, walk, chai, weekend, or empty string"}
''';
    final text = await client.generate(
      key: key,
      model: model,
      fallbacks: fallbacks,
      system: _system,
      contents: [GeminiClient.userTurn(prompt)],
      schema: _liveSchema,
      temperature: 0.8,
    );
    final j = GeminiClient.parseJson(text);
    final body = _clean(j['body']);
    if (body.isEmpty) throw GeminiException('Gemini sent back an empty update.', retryable: true);
    return LiveNudge(
      title: _clean(j['title'], 'Right now'),
      body: body,
      metric: _optMetric(j['metric']),
      experiment: _optExp(j['experiment']),
      key: liveKey,
      model: model,
      createdAt: DateTime.now(),
    );
  }

  Future<String> explainMetric({
    required String key,
    required String model,
    List<String> fallbacks = const [],
    required Map<String, dynamic> context,
    required String metric,
    required String depth,
  }) async {
    final info = metrics[metric]!;
    final prompt = '''
${_data(context)}

Explain my "${info.name}" (data key: $metric)${depth == 'nerdy' ? ' at a nerdy level, using real terms' : ' in plain words'}.
Cover what my recent numbers say compared with my own normal, whether it is trending, and one specific thing that moves it for me.
Return JSON: {"text": "max 75 words"}
''';
    final text = await client.generate(key: key, model: model, fallbacks: fallbacks, system: _system, contents: [GeminiClient.userTurn(prompt)], schema: _textSchema);
    final out = _clean(GeminiClient.parseJson(text)['text']);
    if (out.isEmpty) throw GeminiException('Gemini sent back an empty answer.', retryable: true);
    return out;
  }

  Future<String> experimentCoach({
    required String key,
    required String model,
    List<String> fallbacks = const [],
    required Map<String, dynamic> context,
    required Map<String, dynamic> experiment,
    required String depth,
  }) async {
    final prompt = '''
${_data(context)}

I'm looking at this 7-day experiment in the app:
${jsonEncode(experiment)}
Coach me in max 60 words${depth == 'nerdy' ? ', nerdy level' : ', plain words'}:
- not_started: why it is worth trying for me specifically, using my numbers.
- running: one practical tip for today's check-in and how I'm doing so far.
- finished: an honest verdict on the result (measured vs baseline when present; say so if the sample is too small) and what to do next.
Return JSON: {"text": "..."}
''';
    final text = await client.generate(key: key, model: model, fallbacks: fallbacks, system: _system, contents: [GeminiClient.userTurn(prompt)], schema: _textSchema);
    final out = _clean(GeminiClient.parseJson(text)['text']);
    if (out.isEmpty) throw GeminiException('Gemini sent back an empty answer.', retryable: true);
    return out;
  }

  Future<List<AiDiscovery>> moreDiscoveries({
    required String key,
    required String model,
    List<String> fallbacks = const [],
    required Map<String, dynamic> context,
    required List<String> exclude,
  }) async {
    final prompt = '''
${_data(context)}

Find 3 NEW, specific patterns, trends or surprising facts in my data. Do not repeat any of these: ${jsonEncode(exclude)}.
Each must cite numbers from the data and be something I can act on or find genuinely interesting.
Return JSON: {"discoveries": [{"kind": "Pattern | Trend | Fun fact | Milestone", "head": "max 10 words", "body": "max 35 words", "metric": "one of: $_metricKeys"}]}
''';
    final text = await client.generate(
      key: key,
      model: model,
      fallbacks: fallbacks,
      system: _system,
      contents: [GeminiClient.userTurn(prompt)],
      schema: _moreSchema,
      temperature: 0.9,
    );
    final list = _discoveries(GeminiClient.parseJson(text)['discoveries']).take(3).toList();
    if (list.isEmpty) throw GeminiException('Gemini found nothing new this time. Try again later.');
    return list;
  }

  static void _push(List<Map<String, dynamic>> contents, String role, String text) {
    if (contents.isNotEmpty && contents.last['role'] == role) {
      (contents.last['parts'] as List).add({'text': text});
    } else {
      contents.add({
        'role': role,
        'parts': [
          {'text': text}
        ],
      });
    }
  }

  List<Map<String, dynamic>> _chatContents(Map<String, dynamic> context, List<ChatMessage> history, String question, String depth) {
    final contents = <Map<String, dynamic>>[];
    _push(contents, 'user', 'My health data as JSON. Use it to answer my questions:\n${jsonEncode(context)}');
    _push(contents, 'model', 'Got it. Ask me anything about your sleep, heart, steps or food.');
    final recent = history.length > 12 ? history.sublist(history.length - 12) : history;
    for (final m in recent) {
      if (m.help != null) continue;
      _push(contents, m.isMe ? 'user' : 'model', m.text);
    }
    _push(contents, 'user', '''
$question

Answer in plain text, no markdown, no bullet symbols, max 110 words${depth == 'nerdy' ? ', nerdy level with real terms' : ', plain words'}.
Then on a new line write exactly ### and after it one line of JSON:
{"chips": ["2-3 short follow-up questions I might ask next"], "metric": "most relevant key from $_metricKeys, or empty", "experiment": "kitchen, walk, chai, weekend, or empty"}
''');
    return contents;
  }

  /// Streams the chat answer. Falls back to another model if the first fails before writing anything.
  Stream<String> chatStream({
    required String key,
    required String model,
    List<String> fallbacks = const [],
    required Map<String, dynamic> context,
    required List<ChatMessage> history,
    required String question,
    required String depth,
  }) async* {
    final contents = _chatContents(context, history, question, depth);
    final tryModels = [model, ...fallbacks.where((m) => m != model)];
    for (var i = 0; i < tryModels.length; i++) {
      var gotAny = false;
      try {
        await for (final piece in client.stream(key: key, model: tryModels[i], system: _system, contents: contents)) {
          gotAny = true;
          yield piece;
        }
        return;
      } on GeminiException catch (e) {
        final canFallBack = (e.retryable || e.modelProblem) && !e.keyProblem;
        if (gotAny || i == tryModels.length - 1 || !canFallBack) rethrow;
      }
    }
  }

  /// The part of a streamed answer that should be on screen (everything before the ### metadata).
  static String visible(String raw) {
    final i = raw.indexOf('###');
    var s = i >= 0 ? raw.substring(0, i) : raw;
    s = s.replaceAll('**', '').replaceAll(RegExp(r'#+\s*$'), '');
    return s.trim();
  }

  static ChatMessage finishChat(String raw) {
    final text = visible(raw);
    if (text.isEmpty) throw GeminiException('Gemini sent back an empty answer.', retryable: true);
    var chips = <String>[];
    String? metric, experiment;
    final i = raw.indexOf('###');
    if (i >= 0) {
      try {
        final j = GeminiClient.parseJson(raw.substring(i + 3));
        chips = ((j['chips'] as List?) ?? const []).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).take(3).toList();
        metric = _optMetric(j['metric']);
        experiment = _optExp(j['experiment']);
      } catch (_) {}
    }
    return ChatMessage(
      id: ChatMessage.newId(),
      role: 'ai',
      text: text,
      chips: chips,
      metric: metric,
      experiment: experiment,
      source: 'gemini',
    );
  }
}
