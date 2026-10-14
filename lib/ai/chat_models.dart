import '../utils/format.dart';

/// A message in the Ask conversation. Stored only on this phone.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.chips = const [],
    this.metric,
    this.experiment,
    this.help,
    this.source = 'local',
    this.error,
  });

  final String id;

  /// 'me' or 'ai'.
  final String role;
  final String text;
  final List<String> chips;
  final String? metric;
  final String? experiment;

  /// 'crisis' or 'emergency' shows a helpline card.
  final String? help;

  /// 'gemini' or 'local'.
  final String source;

  /// Set when Gemini failed (or was cut off).
  final String? error;

  bool get isMe => role == 'me';

  static String newId() => '${DateTime.now().microsecondsSinceEpoch}';

  factory ChatMessage.me(String text) => ChatMessage(id: newId(), role: 'me', text: text);

  ChatMessage withError(String e) => ChatMessage(
        id: id,
        role: role,
        text: text,
        chips: chips,
        metric: metric,
        experiment: experiment,
        help: help,
        source: source,
        error: e,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        if (chips.isNotEmpty) 'chips': chips,
        if (metric != null) 'metric': metric,
        if (experiment != null) 'experiment': experiment,
        if (help != null) 'help': help,
        'source': source,
        if (error != null) 'error': error,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] ?? newId()).toString(),
        role: (j['role'] ?? 'ai').toString(),
        text: (j['text'] ?? '').toString(),
        chips: ((j['chips'] as List?) ?? const []).map((e) => e.toString()).toList(),
        metric: j['metric'] as String?,
        experiment: j['experiment'] as String?,
        help: j['help'] as String?,
        source: (j['source'] ?? 'local').toString(),
        error: j['error'] as String?,
      );
}

class AiDiscovery {
  const AiDiscovery({required this.kind, required this.head, required this.body, required this.metric});
  final String kind, head, body, metric;

  Map<String, dynamic> toJson() => {'kind': kind, 'head': head, 'body': body, 'metric': metric};

  factory AiDiscovery.fromJson(Map<String, dynamic> j) => AiDiscovery(
        kind: (j['kind'] ?? 'Pattern').toString(),
        head: (j['head'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        metric: (j['metric'] ?? 'sleepMin').toString(),
      );
}

/// Gemini's written forecast for the day, plus a one-liner per metric.
class DailyBrief {
  DailyBrief({
    required this.headline,
    required this.noteSimple,
    required this.noteNerdy,
    required this.tipTitle,
    required this.tipBody,
    required this.discoveries,
    required this.funFact,
    required this.metricLines,
    required this.model,
    required this.createdAt,
    required this.dataKey,
  });

  final String headline, noteSimple, noteNerdy, tipTitle, tipBody, funFact, model, dataKey;
  final List<AiDiscovery> discoveries;
  final Map<String, String> metricLines;
  final DateTime createdAt;

  bool get isToday => isoDate(createdAt) == isoDate(DateTime.now());

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'noteSimple': noteSimple,
        'noteNerdy': noteNerdy,
        'tipTitle': tipTitle,
        'tipBody': tipBody,
        'discoveries': discoveries.map((d) => d.toJson()).toList(),
        'funFact': funFact,
        'metricLines': metricLines,
        'model': model,
        'createdAt': createdAt.toIso8601String(),
        'dataKey': dataKey,
      };

  factory DailyBrief.fromJson(Map<String, dynamic> j) => DailyBrief(
        headline: (j['headline'] ?? '').toString(),
        noteSimple: (j['noteSimple'] ?? '').toString(),
        noteNerdy: (j['noteNerdy'] ?? '').toString(),
        tipTitle: (j['tipTitle'] ?? '').toString(),
        tipBody: (j['tipBody'] ?? '').toString(),
        discoveries: ((j['discoveries'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => AiDiscovery.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        funFact: (j['funFact'] ?? '').toString(),
        metricLines: ((j['metricLines'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        model: (j['model'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
        dataKey: (j['dataKey'] ?? '').toString(),
      );
}

/// A short "right now" note that follows the day: refreshed as meals, steps and time move on.
class LiveNudge {
  LiveNudge({
    required this.title,
    required this.body,
    this.metric,
    this.experiment,
    required this.key,
    required this.model,
    required this.createdAt,
  });

  final String title, body, key, model;
  final String? metric, experiment;
  final DateTime createdAt;

  bool get isToday => isoDate(createdAt) == isoDate(DateTime.now());

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        if (metric != null) 'metric': metric,
        if (experiment != null) 'experiment': experiment,
        'key': key,
        'model': model,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LiveNudge.fromJson(Map<String, dynamic> j) => LiveNudge(
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        metric: j['metric'] as String?,
        experiment: j['experiment'] as String?,
        key: (j['key'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
      );
}

class AiLogEntry {
  AiLogEntry({required this.time, required this.purpose, required this.bytes, required this.model, required this.ok, required this.categories});
  final DateTime time;
  final String purpose, model;
  final int bytes;
  final bool ok;
  final List<String> categories;

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'purpose': purpose,
        'bytes': bytes,
        'model': model,
        'ok': ok,
        'categories': categories,
      };

  factory AiLogEntry.fromJson(Map<String, dynamic> j) => AiLogEntry(
        time: DateTime.tryParse((j['time'] ?? '').toString()) ?? DateTime.now(),
        purpose: (j['purpose'] ?? '').toString(),
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        model: (j['model'] ?? '').toString(),
        ok: j['ok'] == true,
        categories: ((j['categories'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}
