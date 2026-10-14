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
- Be practical: one concrete action beats five vague ones. Indian food and daily-life context is welcome.
- You are not a doctor. Never diagnose, never say a disease is likely, never suggest starting, stopping or changing medication.
  If something looks medically worrying (very low oxygen, chest pain, fainting, a sustained large jump in resting heart rate
  or breathing rate), calmly say it is worth checking with a doctor.
- If the person mentions self-harm, an eating disorder or a crisis, respond with care, no numbers, and point them to
  Tele-MANAS 14416 (India, free, 24x7) or emergency services (112).
- Wearable numbers are estimates; trends over weeks matter more than one night.
- Answer with valid JSON only, exactly in the shape requested. No markdown, no code fences.
''';

final _metricKeys = metricOrder.join(', ');
const _kinds = ['Pattern', 'Trend', 'Fun fact', 'Milestone'];

String _clean(dynamic v, [String fallback = '']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

String _metric(dynamic v) {
  final s = _clean(v);
  return metrics.containsKey(s) ? s : 'sleepMin';
}

/// All Gemini prompts live here. Every call receives only the privacy-filtered context JSON.
class AiService {
  AiService(this.client);
  final GeminiClient client;

  Future<DailyBrief> dailyBrief({
    required String key,
    required String model,
    required Map<String, dynamic> context,
    required String dataKey,
  }) async {
    final prompt = '''
Here is my health data as JSON:
${jsonEncode(context)}

Write today's forecast for me. Return JSON in exactly this shape:
{
  "note_simple": "2-3 sentences, max 55 words, plain words: how last night went, the likely reason, what today will feel like",
  "note_nerdy": "2-3 sentences, max 60 words, with real terms (TST, N3, RMSSD, RHR) and my numbers vs my normal",
  "tip": {"title": "max 6 words, an action for today", "body": "max 30 words, why it helps me specifically, citing my data"},
  "discoveries": [
    {"kind": "one of: Pattern, Trend, Fun fact, Milestone", "head": "max 10 words, a statement", "body": "max 35 words", "metric": "one of: $_metricKeys"}
  ],
  "fun_fact": "max 30 words, a surprising true fact about my body that uses my numbers"
}
Give exactly 3 discoveries, each about something different, each grounded in the data.
''';
    final text = await client.generate(
      key: key,
      model: model,
      system: _system,
      contents: [GeminiClient.userTurn(prompt)],
    );
    final j = GeminiClient.parseJson(text);
    final tip = j['tip'] is Map ? Map<String, dynamic>.from(j['tip'] as Map) : const <String, dynamic>{};
    final discs = ((j['discoveries'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) {
          final kind = _clean(m['kind'], 'Pattern');
          return AiDiscovery(
            kind: _kinds.contains(kind) ? kind : 'Pattern',
            head: _clean(m['head']),
            body: _clean(m['body']),
            metric: _metric(m['metric']),
          );
        })
        .where((d) => d.head.isNotEmpty)
        .take(4)
        .toList();
    final simple = _clean(j['note_simple']);
    if (simple.isEmpty) throw GeminiException('Gemini sent back an empty forecast. Try again.');
    return DailyBrief(
      noteSimple: simple,
      noteNerdy: _clean(j['note_nerdy'], simple),
      tipTitle: _clean(tip['title'], 'One thing for today'),
      tipBody: _clean(tip['body']),
      discoveries: discs,
      funFact: _clean(j['fun_fact']),
      model: model,
      createdAt: DateTime.now(),
      dataKey: dataKey,
    );
  }

  Future<String> explainMetric({
    required String key,
    required String model,
    required Map<String, dynamic> context,
    required String metric,
    required String depth,
  }) async {
    final info = metrics[metric]!;
    final prompt = '''
Here is my health data as JSON:
${jsonEncode(context)}

Explain my "${info.name}" (data key: $metric) for me${depth == 'nerdy' ? ' at a nerdy level, using real terms' : ' in plain words'}.
Cover: what my recent numbers say compared with my own normal, whether it is trending, and one specific thing that moves it for me.
Return JSON: {"text": "max 75 words"}
''';
    final text = await client.generate(key: key, model: model, system: _system, contents: [GeminiClient.userTurn(prompt)]);
    final out = _clean(GeminiClient.parseJson(text)['text']);
    if (out.isEmpty) throw GeminiException('Gemini sent back an empty answer. Try again.');
    return out;
  }

  Future<ChatMessage> chat({
    required String key,
    required String model,
    required Map<String, dynamic> context,
    required List<ChatMessage> history,
    required String question,
    required String depth,
  }) async {
    final contents = <Map<String, dynamic>>[
      GeminiClient.userTurn('My health data as JSON (use it to answer my questions):\n${jsonEncode(context)}'),
      GeminiClient.modelTurn('{"text": "Got it. Ask me anything about your sleep, heart, steps or food."}'),
    ];
    final recent = history.length > 12 ? history.sublist(history.length - 12) : history;
    for (final m in recent) {
      if (m.help != null) continue;
      contents.add(m.isMe ? GeminiClient.userTurn(m.text) : GeminiClient.modelTurn(jsonEncode({'text': m.text})));
    }
    contents.add(GeminiClient.userTurn('''
$question

Reply as JSON:
{"text": "your answer, max 90 words${depth == 'nerdy' ? ', nerdy level with real terms' : ', plain words'}",
 "chips": ["2 or 3 short follow-up questions I might ask next"],
 "metric": "the single most relevant data key from: $_metricKeys, or null",
 "experiment": "one of kitchen (dinner by 8:30), walk (10 min after lunch), chai (no caffeine after 3 PM), weekend (same wake time on weekends) if it genuinely fits, else null"}
'''));
    final text = await client.generate(key: key, model: model, system: _system, contents: contents);
    final j = GeminiClient.parseJson(text);
    final metric = _clean(j['metric']);
    final exp = _clean(j['experiment']);
    final reply = _clean(j['text']);
    if (reply.isEmpty) throw GeminiException('Gemini sent back an empty answer. Try again.');
    return ChatMessage(
      id: ChatMessage.newId(),
      role: 'ai',
      text: reply,
      chips: ((j['chips'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).take(3).toList(),
      metric: metrics.containsKey(metric) ? metric : null,
      experiment: experiments.containsKey(exp) ? exp : null,
      source: 'gemini',
    );
  }
}
