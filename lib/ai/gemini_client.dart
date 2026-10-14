import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GeminiException implements Exception {
  GeminiException(this.message, {this.keyProblem = false});
  final String message;

  /// True when the key itself is the problem (invalid, revoked, no API access).
  final bool keyProblem;

  @override
  String toString() => message;
}

/// Minimal REST client for the Gemini API. The key is sent only as the x-goog-api-key header,
/// straight from this phone to Google. No proxy, no Almanac server.
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

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 60));
    } on SocketException {
      throw GeminiException('No internet connection. Your data is still here; AI insights need a connection.');
    } on TimeoutException {
      throw GeminiException('Gemini took too long to answer. Try again.');
    } on http.ClientException catch (e) {
      throw GeminiException('Could not reach Gemini (${e.message}).');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;

    var detail = '';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['error'] is Map) detail = (j['error']['message'] ?? '').toString();
    } catch (_) {}
    final lower = detail.toLowerCase();
    if (res.statusCode == 400 && (lower.contains('api key') || lower.contains('api_key'))) {
      throw GeminiException("That API key isn't valid. Check it in Me › AI & your key.", keyProblem: true);
    }
    switch (res.statusCode) {
      case 401:
      case 403:
        throw GeminiException(
          'This key does not have access to the Gemini API. Create a key in Google AI Studio or enable the Generative Language API for it.',
          keyProblem: true,
        );
      case 404:
        throw GeminiException('That model is not available for your key. Pick another model in Me › AI & your key.');
      case 429:
        throw GeminiException('Rate limit or quota reached on your key. Wait a minute, or check your quota in Google AI Studio.');
    }
    if (res.statusCode >= 500) {
      throw GeminiException('Gemini is having trouble right now (${res.statusCode}). Try again shortly.');
    }
    throw GeminiException(detail.isNotEmpty ? 'Gemini said: $detail' : 'Gemini request failed (${res.statusCode}).');
  }

  /// Lists text models this key can call. Doubles as key validation.
  Future<List<String>> listModels(String key) async {
    final res = await _send(() => _http.get(Uri.parse('$_base/models?pageSize=200'), headers: {'x-goog-api-key': key}));
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

  Future<String> generate({
    required String key,
    required String model,
    required String system,
    required List<Map<String, dynamic>> contents,
    bool json = true,
    double temperature = 0.7,
  }) async {
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': 8192,
        if (json) 'responseMimeType': 'application/json',
      },
    };
    final res = await _send(() => _http.post(
          Uri.parse('$_base/models/$model:generateContent'),
          headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
    final j = jsonDecode(res.body);
    final cands = j is Map ? j['candidates'] as List? : null;
    if (cands == null || cands.isEmpty) {
      final block = j is Map && j['promptFeedback'] is Map ? j['promptFeedback']['blockReason'] : null;
      throw GeminiException(block != null ? 'Gemini declined to answer this one ($block).' : 'Gemini sent back an empty answer. Try again.');
    }
    final first = cands.first;
    final content = first is Map ? first['content'] : null;
    final parts = content is Map ? (content['parts'] as List?) ?? const [] : const [];
    final text = parts.whereType<Map>().where((p) => p['thought'] != true).map((p) => (p['text'] ?? '').toString()).join();
    if (text.trim().isEmpty) {
      final reason = first is Map ? first['finishReason'] : null;
      throw GeminiException(reason == 'SAFETY' ? 'Gemini held this answer back for safety reasons.' : 'Gemini sent back an empty answer. Try again.');
    }
    return text;
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
    if (a < 0 || b <= a) throw GeminiException('Gemini answered in an unexpected format. Try again.');
    try {
      final v = jsonDecode(t.substring(a, b + 1));
      if (v is Map<String, dynamic>) return v;
    } on FormatException {
      // fall through
    }
    throw GeminiException('Gemini answered in an unexpected format. Try again.');
  }
}
