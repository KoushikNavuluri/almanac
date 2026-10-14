import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../ai/ai_service.dart';
import '../ai/chat_models.dart';
import '../ai/gemini_client.dart';
import '../ai/health_context.dart';
import '../ai/local_brain.dart';
import '../data/health_source.dart';
import '../data/local_store.dart';
import '../data/sample_data.dart';
import '../domain/export.dart' as exporter;
import '../domain/insights.dart';
import '../models/day_record.dart';
import '../utils/format.dart';

enum DataMode { none, healthConnect, sample }

enum ConnectOutcome { connected, needsInstall, unsupported, denied, error }

/// Single source of truth for the app. Everything persists locally; the Gemini key lives in
/// secure storage only.
class AppController extends ChangeNotifier {
  AppController({LocalStore? store, KeyVault? vault, HealthSource? health, GeminiClient? gemini})
      : store = store ?? LocalStore(),
        vault = vault ?? KeyVault(),
        health = health ?? HealthSource(),
        gemini = gemini ?? GeminiClient() {
    ai = AiService(this.gemini);
  }

  final LocalStore store;
  final KeyVault vault;
  final HealthSource health;
  final GeminiClient gemini;
  late final AiService ai;

  bool loaded = false;
  bool onboarded = false;
  DataMode mode = DataMode.none;
  List<DayRecord> _records = [];
  double? weightKg;
  Map<String, List<String>> sources = {};
  DateTime? lastSync;
  bool syncing = false;
  String? syncError;
  HealthAvailability? hcAvailability;

  String depth = 'simple';
  bool reduceMotion = false;
  int tab = 0;

  SharingPrefs sharing = SharingPrefs();
  bool aiEnabled = true;
  String model = GeminiClient.defaultModel;
  List<String> models = [];
  String? _apiKey;
  bool keyVerified = false;
  DateTime? keyVerifiedAt;

  DailyBrief? brief;
  bool briefLoading = false;
  String? briefError;
  final Map<String, String> explanations = {};
  final Set<String> explaining = {};
  final Map<String, String> explainErrors = {};

  List<ChatMessage> chat = [];
  bool chatBusy = false;
  List<AiLogEntry> aiLog = [];

  Map<String, ExperimentRun> runs = {};
  Set<String> saved = {};

  Insights? _ins;
  Timer? _saveTimer;

  // ------------------------------------------------------------------ derived

  List<DayRecord> get records => _records;

  Insights get insights {
    final cur = _ins;
    if (cur != null && isoDate(cur.now) == isoDate(DateTime.now())) return cur;
    if (mode == DataMode.sample && cur != null) _records = SampleData.generate(DateTime.now());
    final fresh = Insights(_records, weightKg: weightKg);
    _ins = fresh;
    return fresh;
  }

  bool get hasKey => (_apiKey ?? '').isNotEmpty;
  bool get aiReady => hasKey && aiEnabled && sharing.anything;
  bool get isSample => mode == DataMode.sample;

  String get maskedKey {
    final k = _apiKey ?? '';
    if (k.length < 10) return '';
    return '${k.substring(0, 4)}••••••••${k.substring(k.length - 4)}';
  }

  String get dataKey {
    final last = _records.length > 2 ? _records.sublist(_records.length - 2) : _records;
    final sig = jsonEncode(last.map((r) => r.toJson()).toList()).hashCode;
    return '${isoDate(DateTime.now())}|$sig|${jsonEncode(sharing.toJson()).hashCode}|$model';
  }

  Map<String, dynamic> get contextPreview => HealthContext.build(insights, sharing);

  // ------------------------------------------------------------------ lifecycle

  Future<void> init() async {
    try {
      final s = await store.readState();
      if (s != null) _fromJson(s);
      _apiKey = await vault.read();
      if (mode == DataMode.sample) {
        _records = SampleData.generate(DateTime.now());
      } else {
        _records = await store.readRecords();
      }
    } catch (e) {
      debugPrint('Almanac: init failed ($e)');
    }
    _ins = null;
    loaded = true;
    notifyListeners();
    if (mode == DataMode.healthConnect) unawaited(sync());
  }

  void onResume() {
    _ins = null;
    notifyListeners();
    if (mode == DataMode.healthConnect) unawaited(sync());
  }

  void finishOnboarding() {
    onboarded = true;
    tab = 0;
    _persist();
    notifyListeners();
  }

  void setTab(int i) {
    if (tab == i) return;
    tab = i;
    notifyListeners();
  }

  // ------------------------------------------------------------------ data sources

  Future<HealthAvailability> checkHealth() async {
    final av = await health.availability();
    hcAvailability = av;
    notifyListeners();
    return av;
  }

  Future<void> installHealthConnect() => health.installHealthConnect();

  Future<ConnectOutcome> connectHealth() async {
    final av = await checkHealth();
    if (av == HealthAvailability.needsInstall) return ConnectOutcome.needsInstall;
    if (av == HealthAvailability.unsupported) return ConnectOutcome.unsupported;
    try {
      final ok = await health.requestAccess();
      if (!ok) return ConnectOutcome.denied;
    } on HealthException catch (e) {
      syncError = e.message;
      notifyListeners();
      return ConnectOutcome.error;
    }
    mode = DataMode.healthConnect;
    _clearAiCache();
    _records = [];
    sources = {};
    _ins = null;
    _persist();
    await sync(force: true);
    return syncError == null ? ConnectOutcome.connected : ConnectOutcome.error;
  }

  Future<void> sync({bool force = false}) async {
    if (mode != DataMode.healthConnect || syncing) return;
    final ls = lastSync;
    if (!force && ls != null && DateTime.now().difference(ls) < const Duration(minutes: 10)) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      final res = await health.fetch(days: 60);
      _records = res.records;
      weightKg = res.weightKg ?? weightKg;
      sources = res.sources.map((k, v) => MapEntry(k, v.toList()..sort()));
      lastSync = DateTime.now();
      _ins = null;
      await store.writeRecords(_records);
      if (insights.isEmpty) {
        syncError = 'Connected, but Health Connect has no sleep, heart, step or meal data for the last 60 days. Make sure your tracker and meal app are set to sync with Health Connect.';
      }
    } on HealthException catch (e) {
      syncError = e.message;
    } catch (e) {
      syncError = 'Sync failed: $e';
    } finally {
      syncing = false;
      _persist();
      notifyListeners();
    }
  }

  void useSampleData() {
    mode = DataMode.sample;
    _records = SampleData.generate(DateTime.now());
    sources = {
      'sleep': ['Sample data'],
      'heart': ['Sample data'],
      'activity': ['Sample data'],
      'food': ['Sample data'],
    };
    syncError = null;
    _clearAiCache();
    _ins = null;
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------------------------ settings

  void setDepth(String d) {
    depth = d;
    _persist();
    notifyListeners();
  }

  void setReduceMotion(bool v) {
    reduceMotion = v;
    _persist();
    notifyListeners();
  }

  void updateSharing(void Function(SharingPrefs p) change) {
    change(sharing);
    _clearAiCache();
    _persist();
    notifyListeners();
  }

  void setAiEnabled(bool v) {
    aiEnabled = v;
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------------------------ BYOK

  /// Validates the key with Google, then stores it in secure storage. Returns an error or null.
  Future<String?> saveKey(String raw) async {
    final key = raw.trim().replaceAll(RegExp(r'\s'), '');
    if (key.length < 20) {
      return "That doesn't look like a Gemini API key. Keys from Google AI Studio are about 39 characters and usually start with AIza.";
    }
    try {
      final list = await gemini.listModels(key);
      if (list.isEmpty) return 'That key works, but no Gemini text models are available to it.';
      models = list;
      if (!list.contains(model)) model = GeminiClient.pickDefault(list);
      await vault.write(key);
      _apiKey = key;
      keyVerified = true;
      keyVerifiedAt = DateTime.now();
      _clearAiCache();
      _persist();
      notifyListeners();
      return null;
    } on GeminiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not save the key ($e).';
    }
  }

  Future<String?> recheckKey() async {
    final k = _apiKey;
    if (k == null) return 'No key saved.';
    try {
      final list = await gemini.listModels(k);
      models = list;
      if (list.isNotEmpty && !list.contains(model)) model = GeminiClient.pickDefault(list);
      keyVerified = true;
      keyVerifiedAt = DateTime.now();
      briefError = null;
      _persist();
      notifyListeners();
      return null;
    } on GeminiException catch (e) {
      if (e.keyProblem) keyVerified = false;
      notifyListeners();
      return e.message;
    }
  }

  Future<void> removeKey() async {
    await vault.delete();
    _apiKey = null;
    keyVerified = false;
    keyVerifiedAt = null;
    models = [];
    _clearAiCache();
    _persist();
    notifyListeners();
  }

  void setModel(String m) {
    model = m;
    _clearAiCache();
    _persist();
    notifyListeners();
  }

  void _clearAiCache() {
    brief = null;
    briefError = null;
    explanations.clear();
    explainErrors.clear();
  }

  void _log(String purpose, Map<String, dynamic> ctx, bool ok) {
    aiLog.insert(
      0,
      AiLogEntry(
        time: DateTime.now(),
        purpose: purpose,
        bytes: utf8.encode(jsonEncode(ctx)).length,
        model: model,
        ok: ok,
        categories: sharing.labels,
      ),
    );
    if (aiLog.length > 50) aiLog = aiLog.sublist(0, 50);
  }

  // ------------------------------------------------------------------ AI features

  Future<void> refreshBrief({bool force = false}) async {
    final key = _apiKey;
    if (!aiReady || key == null || briefLoading || insights.today == null) return;
    final dk = dataKey;
    final cur = brief;
    if (!force && cur != null && cur.dataKey == dk) return;
    if (!force && briefError != null) return; // don't hammer a failing key; the user retries
    briefLoading = true;
    briefError = null;
    notifyListeners();
    final ctx = contextPreview;
    try {
      brief = await ai.dailyBrief(key: key, model: model, context: ctx, dataKey: dk);
      _log('Daily forecast', ctx, true);
    } on GeminiException catch (e) {
      briefError = e.message;
      if (e.keyProblem) keyVerified = false;
      _log('Daily forecast', ctx, false);
    } catch (e) {
      briefError = 'Something went wrong: $e';
    } finally {
      briefLoading = false;
      _persist();
      notifyListeners();
    }
  }

  String? explanationFor(String metric) => explanations['$metric|$depth|$dataKey'];
  bool isExplaining(String metric) => explaining.contains(metric);

  Future<void> explainMetric(String metric) async {
    final key = _apiKey;
    if (!aiReady || key == null || explaining.contains(metric)) return;
    explaining.add(metric);
    explainErrors.remove(metric);
    notifyListeners();
    final ctx = contextPreview;
    final cacheKey = '$metric|$depth|$dataKey';
    try {
      final text = await ai.explainMetric(key: key, model: model, context: ctx, metric: metric, depth: depth);
      explanations[cacheKey] = text;
      _log('Explain a metric', ctx, true);
    } on GeminiException catch (e) {
      explainErrors[metric] = e.message;
      _log('Explain a metric', ctx, false);
    } catch (e) {
      explainErrors[metric] = 'Something went wrong: $e';
    } finally {
      explaining.remove(metric);
      _persist();
      notifyListeners();
    }
  }

  Future<void> sendChat(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || chatBusy) return;
    final history = List<ChatMessage>.of(chat);
    chat.add(ChatMessage.me(q));
    chatBusy = true;
    notifyListeners();
    ChatMessage reply;
    final safety = LocalBrain.safety(q);
    final key = _apiKey;
    if (safety != null) {
      reply = safety;
    } else if (!aiReady || key == null) {
      reply = LocalBrain.respond(q, insights, depth);
    } else {
      final ctx = contextPreview;
      try {
        reply = await ai.chat(key: key, model: model, context: ctx, history: history, question: q, depth: depth);
        _log('Ask', ctx, true);
      } on GeminiException catch (e) {
        reply = LocalBrain.respond(q, insights, depth).withError(e.message);
        if (e.keyProblem) keyVerified = false;
        _log('Ask', ctx, false);
      } catch (e) {
        reply = LocalBrain.respond(q, insights, depth).withError('$e');
      }
    }
    chat.add(reply);
    if (chat.length > 120) chat = chat.sublist(chat.length - 120);
    chatBusy = false;
    _persist();
    notifyListeners();
  }

  void ask(String q) {
    tab = 2;
    notifyListeners();
    unawaited(sendChat(q));
  }

  void clearChat() {
    chat = [];
    _persist();
    notifyListeners();
  }

  void clearAiLog() {
    aiLog = [];
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------------------------ experiments & saves

  void startExperiment(String id) {
    runs[id] = ExperimentRun(id: id, start: isoDate(DateTime.now()));
    _persist();
    notifyListeners();
  }

  void checkIn(String id, String date, bool kept) {
    final r = runs[id];
    if (r == null) return;
    r.checkins[date] = kept;
    _persist();
    notifyListeners();
  }

  void stopExperiment(String id) {
    runs.remove(id);
    _persist();
    notifyListeners();
  }

  bool isSaved(String id) => saved.contains(id);

  void toggleSave(String id) {
    if (!saved.remove(id)) saved.add(id);
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------------------------ export & wipe

  String exportCsv() => exporter.recordsCsv(_records);
  String exportWeekly() => exporter.weeklyEdition(insights, brief: brief);

  Future<void> wipeEverything() async {
    _saveTimer?.cancel();
    await store.wipe();
    await vault.delete();
    _apiKey = null;
    onboarded = false;
    mode = DataMode.none;
    _records = [];
    weightKg = null;
    sources = {};
    lastSync = null;
    syncError = null;
    depth = 'simple';
    reduceMotion = false;
    tab = 0;
    sharing = SharingPrefs();
    aiEnabled = true;
    model = GeminiClient.defaultModel;
    models = [];
    keyVerified = false;
    keyVerifiedAt = null;
    _clearAiCache();
    chat = [];
    aiLog = [];
    runs = {};
    saved = {};
    _ins = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ persistence

  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      store.writeState(_toJson()).catchError((Object e) {
        debugPrint('Almanac: save failed ($e)');
      });
    });
  }

  Map<String, dynamic> _toJson() {
    final ex = explanations.entries.toList();
    final keep = ex.length > 40 ? ex.sublist(ex.length - 40) : ex;
    final b = brief;
    final ls = lastSync;
    final kv = keyVerifiedAt;
    return {
      'v': 1,
      'onboarded': onboarded,
      'mode': mode.name,
      if (weightKg != null) 'weightKg': weightKg,
      'sources': sources,
      if (ls != null) 'lastSync': ls.toIso8601String(),
      'depth': depth,
      'reduceMotion': reduceMotion,
      'sharing': sharing.toJson(),
      'aiEnabled': aiEnabled,
      'model': model,
      'models': models,
      'keyVerified': keyVerified,
      if (kv != null) 'keyVerifiedAt': kv.toIso8601String(),
      if (b != null) 'brief': b.toJson(),
      'explanations': {for (final e in keep) e.key: e.value},
      'chat': chat.map((m) => m.toJson()).toList(),
      'aiLog': aiLog.map((e) => e.toJson()).toList(),
      'runs': runs.map((k, v) => MapEntry(k, v.toJson())),
      'saved': saved.toList(),
    };
  }

  void _fromJson(Map<String, dynamic> j) {
    onboarded = j['onboarded'] == true;
    mode = DataMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => DataMode.none);
    weightKg = (j['weightKg'] as num?)?.toDouble();
    sources = ((j['sources'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), ((v as List?) ?? const []).map((e) => e.toString()).toList()),
    );
    lastSync = DateTime.tryParse((j['lastSync'] ?? '').toString());
    depth = j['depth'] == 'nerdy' ? 'nerdy' : 'simple';
    reduceMotion = j['reduceMotion'] == true;
    if (j['sharing'] is Map) sharing = SharingPrefs.fromJson(Map<String, dynamic>.from(j['sharing'] as Map));
    aiEnabled = j['aiEnabled'] != false;
    model = (j['model'] ?? GeminiClient.defaultModel).toString();
    models = ((j['models'] as List?) ?? const []).map((e) => e.toString()).toList();
    keyVerified = j['keyVerified'] == true;
    keyVerifiedAt = DateTime.tryParse((j['keyVerifiedAt'] ?? '').toString());
    if (j['brief'] is Map) brief = DailyBrief.fromJson(Map<String, dynamic>.from(j['brief'] as Map));
    explanations
      ..clear()
      ..addAll(((j['explanations'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())));
    chat = ((j['chat'] as List?) ?? const []).whereType<Map>().map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m))).toList();
    aiLog = ((j['aiLog'] as List?) ?? const []).whereType<Map>().map((m) => AiLogEntry.fromJson(Map<String, dynamic>.from(m))).toList();
    runs = ((j['runs'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), ExperimentRun.fromJson(Map<String, dynamic>.from(v as Map))),
    );
    saved = ((j['saved'] as List?) ?? const []).map((e) => e.toString()).toSet();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// Makes the controller available to every widget and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
