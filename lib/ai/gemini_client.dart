import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GeminiException implements Exception {
  GeminiException(this.message, {this.keyProblem = false, this.retryable = false, this.modelProblem = false, this.detail = ''});
  final String message;

  /// The key itself is the problem (invalid, revoked, no API access).
  final bool keyProblem;

  /// Worth retrying (rate limit, overload, timeout).
  final bool retryable;

  /// The chosen model isn't available; another model may work.
  final bool modelProblem;
  final String detail;

  @override
  String toString() => message;
}

/// REST client for the Gemini API. The key is sent only as the x-goog-api-key header, straight
/// from this phone to Google. Retries transient failures, falls back to another model when one
/// is overloaded or missing, streams chat answers, and asks for structured JSON where it helps.
class GeminiClient {
  GeminiClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';
  static const defaultModel = 'gemini-3.8-flash';
  static const preferredModels = [
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
    'gemini-3-flash-preview',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
  ];

  static const _skip = ['tts', 'image', 'live', 'embedding', 'transcribe', 'audio', 'banana', 'veo', 'robotics', 'computer-use'];

  final Set<String> _noThinking = {};
  bool _noSchema = false;

  Map<String, String> _headers(String key) => {'x-goog-api-key': key, 'Content-Type': 'application/json'};

  GeminiException _errorFor(int status, String body) {
    var detail = '';
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) detail = (j['error']['message'] ?? '').toString();
    } catch (_) {}
    final lower = detail.toLowerCase();
    if (status == 400 && (lower.contains('api key') || lower.contains('api_key'))) {
      return GeminiException("That API key isn't valid. Check it in Me › AI & your key.", keyProblem: true, detail: detail);
    }
    if (status == 401 || status == 403) {
      return GeminiException(
        'This key does not have access to the Gemini API. Create a key in Google AI Studio or enable the Generative Language API for it.',
        keyProblem: true,
        detail: detail,
      );
    }
    if (status == 404) {
      return GeminiException('That model is not available for your key. Pick another in Me › AI & your key.', modelProblem: true, detail: detail);
    }
    if (status == 429) {
      return GeminiException('Rate limit or quota reached on your key. Give it a minute, or check your quota in Google AI Studio.', retryable: true, detail: detail);
    }
    if (status >= 500) {
      return GeminiException('Gemini is busy right now ($status). Retrying usually works.', retryable: true, detail: detail);
    }
    return GeminiException(detail.isNotEmpty ? 'Gemini said: $detail' : 'Gemini request failed ($status).', detail: detail);
  }

  Future<http.Response> _send(Future<http.Response> Function() call, {Duration timeout = const Duration(seconds: 45)}) async {
    try {
      return await call().timeout(timeout);
    } on SocketException {
      throw GeminiException('No internet connection. Your data is still here; AI needs a connection.');
    } on TimeoutException {
      throw GeminiException('Gemini took too long to answer.', retryable: true);
    } on HandshakeException {
      throw GeminiException('Secure connection to Gemini failed. Check your network.', retryable: true);
    } on http.ClientException catch (e) {
      throw GeminiException('Could not reach Gemini (${e.message}).', retryable: true);
    }
  }

  /// Lists text models this key can call. Doubles as key validation.
  Future<List<String>> listModels(String key) async {
    final res = await _send(() => _http.get(Uri.parse('$_base/models?pageSize=200'), headers: {'x-goog-api-key': key}), timeout: const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) throw _errorFor(res.statusCode, res.body);
    final j = jsonDecode(res.body);
    final list = (j is Map ? j['models'] as List? : null) ?? const [];
    final names = <String>[];
    for (final m in list.whereType<Map>()) {
      final methods = (m['supportedGenerationMethods'] as List?) ?? const [];
      if (!methods.contains('generateContent')) continue;
      final name = (m['name'] ?? '').toString().replaceFirst('models/', '');
      if (!name.startsWith('gemini')) continue;
      if (_skip.any(name.contains)) continue;
      names.add(name);
    }
    names.sort((a, b) {
      final ia = preferredModels.indexOf(a), ib = preferredModels.indexOf(b);
      if (ia != -1 || ib != -1) return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
      return b.compareTo(a);
    });
    return names;
  }

  static String pickDefault(List<String> available) {
    for (final m in preferredModels) {
      if (available.contains(m)) return m;
    }
    return available.firstWhere((m) => m.contains('flash'), orElse: () => available.isEmpty ? defaultModel : available.first);
  }

  /// Fast answers: flash models think as little as possible. Pro models keep their defaults.
  Map<String, dynamic>? _thinkingFor(String model) {
    if (_noThinking.contains(model) || model.contains('pro')) return null;
    if (model.startsWith('gemini-2.5')) return {'thinkingBudget': 0};
    if (model.startsWith('gemini-')) return {'thinkingLevel': 'low'};
    return null;
  }

  Map<String, dynamic> _body(
    String model,
    String system,
    List<Map<String, dynamic>> contents, {
    Map<String, dynamic>? schema,
    bool json = true,
    double temperature = 0.7,
    int maxTokens = 8192,
  }) {
    final gen = <String, dynamic>{'temperature': temperature, 'maxOutputTokens': maxTokens};
    if (json) gen['responseMimeType'] = 'application/json';
    if (json && schema != null && !_noSchema) gen['responseSchema'] = schema;
    final thinking = _thinkingFor(model);
    if (thinking != null) gen['thinkingConfig'] = thinking;
    return {
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': contents,
      'generationConfig': gen,
    };
  }

  /// Learns from a 400 about an unsupported option. Returns true when a retry makes sense.
  bool _adapt(String model, String detail) {
    final l = detail.toLowerCase();
    if (l.contains('thinking') && !_noThinking.contains(model)) {
      _noThinking.add(model);
      return true;
    }
    if ((l.contains('schema') || l.contains('response_schema')) && !_noSchema) {
      _noSchema = true;
      return true;
    }
    return false;
  }

  static String _textOf(dynamic j) {
    if (j is! Map) return '';
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty) return '';
    final first = cands.first;
    if (first is! Map) return '';
    final content = first['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List) return '';
    final b = StringBuffer();
    for (final p in parts) {
      if (p is Map && p['thought'] != true && p['text'] != null) b.write(p['text']);
    }
    return b.toString();
  }

  Future<String> _once(String key, String model, String system, List<Map<String, dynamic>> contents, Map<String, dynamic>? schema, bool json, double temperature) async {
    final res = await _send(() => _http.post(
          Uri.parse('$_base/models/$model:generateContent'),
          headers: _headers(key),
          body: jsonEncode(_body(model, system, contents, schema: schema, json: json, temperature: temperature)),
        ));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final e = _errorFor(res.statusCode, res.body);
      if (res.statusCode == 400 && _adapt(model, e.detail)) {
        return _once(key, model, system, contents, schema, json, temperature);
      }
      throw e;
    }
    final j = jsonDecode(res.body);
    final text = _textOf(j);
    if (text.trim().isNotEmpty) return text;
    String? reason;
    if (j is Map) {
      final pf = j['promptFeedback'];
      if (pf is Map && pf['blockReason'] != null) reason = pf['blockReason'].toString();
      final c = j['candidates'];
      if (reason == null && c is List && c.isNotEmpty && c.first is Map) reason = (c.first as Map)['finishReason']?.toString();
    }
    if (reason == 'SAFETY' || reason == 'PROHIBITED_CONTENT' || reason == 'BLOCKLIST') {
      throw GeminiException('Gemini held this answer back for safety reasons.');
    }
    throw GeminiException('Gemini sent back an empty answer.', retryable: true);
  }

  /// One answer, with up to two tries per model and automatic fallback to [fallbacks].
  Future<String> generate({
    required String key,
    required String model,
    List<String> fallbacks = const [],
    required String system,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? schema,
    bool json = true,
    double temperature = 0.7,
  }) async {
    final models = [model, ...fallbacks.where((m) => m != model)];
    GeminiException? last;
    for (final m in models) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await _once(key, m, system, contents, schema, json, temperature);
        } on GeminiException catch (e) {
          last = e;
          if (e.keyProblem) rethrow;
          if (e.modelProblem) break;
          if (!e.retryable) rethrow;
          if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }
    }
    throw last ?? GeminiException('Gemini request failed.');
  }

  /// Streams the answer as it is written (server-sent events).
  Stream<String> stream({
    required String key,
    required String model,
    required String system,
    required List<Map<String, dynamic>> contents,
    double temperature = 0.7,
  }) async* {
    final req = http.Request('POST', Uri.parse('$_base/models/$model:streamGenerateContent?alt=sse'));
    req.headers.addAll(_headers(key));
    req.body = jsonEncode(_body(model, system, contents, json: false, temperature: temperature, maxTokens: 4096));
    http.StreamedResponse res;
    try {
      res = await _http.send(req).timeout(const Duration(seconds: 30));
    } on SocketException {
      throw GeminiException('No internet connection. Your data is still here; AI needs a connection.');
    } on TimeoutException {
      throw GeminiException('Gemini took too long to start answering.', retryable: true);
    } on http.ClientException catch (e) {
      throw GeminiException('Could not reach Gemini (${e.message}).', retryable: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = await res.stream.bytesToString();
      final e = _errorFor(res.statusCode, body);
      if (res.statusCode == 400 && _adapt(model, e.detail)) {
        yield* stream(key: key, model: model, system: system, contents: contents, temperature: temperature);
        return;
      }
      throw e;
    }
    final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(const Duration(seconds: 40));
    try {
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        dynamic j;
        try {
          j = jsonDecode(payload);
        } catch (_) {
          continue;
        }
        if (j is Map && j['error'] is Map) {
          throw GeminiException('Gemini stopped: ${j['error']['message']}', retryable: true);
        }
        final t = _textOf(j);
        if (t.isNotEmpty) yield t;
      }
    } on TimeoutException {
      throw GeminiException('The answer stalled. Try again.', retryable: true);
    } on SocketException {
      throw GeminiException('The connection dropped mid-answer.', retryable: true);
    } on http.ClientException catch (e) {
      throw GeminiException('The connection dropped mid-answer (${e.message}).', retryable: true);
    }
  }

  static Map<String, dynamic> userTurn(String text) => {
        'role': 'user',
        'parts': [
          {'text': text}
        ],
      };

  static Map<String, dynamic> modelTurn(String text) => {
        'role': 'model',
        'parts': [
          {'text': text}
        ],
      };

  /// Tolerant JSON extraction (handles code fences or stray prose around the object).
  static Map<String, dynamic> parseJson(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '');
      final end = t.lastIndexOf('```');
      if (end >= 0) t = t.substring(0, end);
    }
    final a = t.indexOf('{'), b = t.lastIndexOf('}');
    if (a < 0 || b <= a) throw GeminiException('Gemini answered in an unexpected format.', retryable: true);
    try {
      final v = jsonDecode(t.substring(a, b + 1));
      if (v is Map<String, dynamic>) return v;
    } on FormatException {
      // fall through
    }
    throw GeminiException('Gemini answered in an unexpected format.', retryable: true);
  }
}
