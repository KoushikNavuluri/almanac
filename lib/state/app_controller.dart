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
import '../domain/metrics.dart';
import '../models/day_record.dart';
import '../utils/format.dart';

enum DataMode { none, healthConnect, sample }

enum ConnectOutcome { connected, needsInstall, unsupported, denied, error }

const _dayMetrics = {'steps', 'kcal', 'protein', 'lastMealMin'};

/// Bump when the way Health Connect data is folded changes: forces one full 60-day resync.
const _dataVersion = 3;

/// Single source of truth. Everything persists locally; the Gemini key lives in secure storage.
///
/// Sync: incremental (last 3 days) every 3 minutes while the app is open, on open/resume and on
/// pull-to-refresh; a 7-day repair sync once a day catches data your tracker uploads late; the full
/// 60-day backfill runs on first connect, on demand, or after you change which app to trust.
/// AI: a daily brief (forecast, tip, discoveries, one-liner per metric), a "right now" nudge that
/// follows the day, auto-explained metrics, an experiment coach, on-demand discoveries and a
/// streaming chat. All refresh themselves when the data they depend on changes.
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

  // ------------------------------------------------------------------ data state

  bool loaded = false;
  bool onboarded = false;
  DataMode mode = DataMode.none;
  List<DayRecord> _records = [];
  double? weightKg;
  Map<String, List<String>> sources = {};

  /// Category -> the app Almanac actually uses (friendly name).
  Map<String, String> usedSources = {};
  Map<String, DateTime> latestByCategory = {};
  List<String> missingPerms = [];
  List<String> failedReads = [];
  DateTime? lastSync;
  DateTime? lastFullSync;
  DateTime? lastDeepSync;
  Duration? lastSyncTook;
  int lastSyncDays = 0;
  bool syncing = false;
  int syncDays = 0;
  Set<String> syncDone = {};
  String? syncError;
  HealthAvailability? hcAvailability;

  /// Which app to trust per category (Me › Data check).
  SourcePrefs sourcePrefs = SourcePrefs();
  DayAudit? audit;
  bool auditing = false;
  String? auditError;
  DateTime? _auditDay;

  // ------------------------------------------------------------------ settings

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

  // ------------------------------------------------------------------ AI state

  DailyBrief? brief;
  bool briefLoading = false;
  String? briefError;
  DateTime? _briefErrorAt;
  Duration _briefRetry = const Duration(minutes: 2);

  LiveNudge? live;
  bool liveLoading = false;
  String? liveError;
  DateTime? _liveErrorAt;

  final Map<String, String> explanations = {};
  final Set<String> explaining = {};
  final Map<String, String> explainErrors = {};

  final Map<String, String> coach = {};
  final Set<String> coaching = {};
  final Map<String, String> coachErrors = {};

  List<AiDiscovery> extraDiscoveries = [];
  String extraDate = '';
  bool moreLoading = false;
  String? moreError;

  List<ChatMessage> chat = [];
  bool chatBusy = false;

  /// The answer being streamed right now (null when nothing is streaming).
  String? streaming;
  List<AiLogEntry> aiLog = [];

  Map<String, ExperimentRun> runs = {};
  Set<String> saved = {};

  Insights? _ins;
  Timer? _saveTimer;
  Timer? _ticker;
  Timer? _aiDebounce;

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
  bool get aiBusy => briefLoading || liveLoading || chatBusy || moreLoading || explaining.isNotEmpty || coaching.isNotEmpty;

  String get maskedKey {
    final k = _apiKey ?? '';
    if (k.length < 10) return '';
    return '${k.substring(0, 4)}••••••••${k.substring(k.length - 4)}';
  }

  String _sig(Object? o) => jsonEncode(o).hashCode.toRadixString(36);

  String get daypart => HealthContext.daypart(DateTime.now());

  /// Changes when last night's data or yesterday's food/steps change: the brief is about those.
  String get briefKey {
    final ins = insights;
    final t = ins.today;
    final y = t == null ? null : ins.prevOf(t);
    final ys = y?.steps;
    final night = t == null ? null : [t.sleepMin, t.napMin, t.deep, t.rem, t.awake, t.hrv, t.rhr, t.spo2, t.breathing];
    final yday = y == null ? null : [y.meals.length, y.lastMealMin, y.kcal?.round(), ys == null ? null : (ys / 500).round()];
    return [isoDate(DateTime.now()), _sig([night, yday, ins.nightsWithSleep]), _sig(sharing.toJson()), model].join('|');
  }

  /// Changes as the day moves: part of day, meals logged, steps walked.
  String get liveKey {
    final t = insights.today;
    final steps = t?.steps ?? 0;
    return [isoDate(DateTime.now()), daypart, t?.meals.length ?? 0, (steps / 1500).floor(), _sig(sharing.toJson()), model].join('|');
  }

  /// Kept for older call sites.
  String get dataKey => briefKey;

  DailyBrief? get todaysBrief {
    final b = brief;
    return b != null && b.isToday ? b : null;
  }

  LiveNudge? get todaysLive {
    final l = live;
    return l != null && l.isToday ? l : null;
  }

  bool get briefStale {
    final b = todaysBrief;
    return b != null && b.dataKey != briefKey;
  }

  String? metricLine(String key) {
    final b = todaysBrief;
    if (b == null) return null;
    final l = b.metricLines[key];
    return (l == null || l.trim().isEmpty) ? null : l;
  }

  List<AiDiscovery> get todaysExtra => extraDate == isoDate(DateTime.now()) ? extraDiscoveries : const [];

  Map<String, dynamic> get contextPreview => HealthContext.build(insights, sharing);

  List<String> get _fallbacks {
    final out = <String>[];
    for (final m in [...models, ...GeminiClient.preferredModels]) {
      if (m == model || out.contains(m) || !m.contains('flash')) continue;
      if (models.isNotEmpty && !models.contains(m)) continue;
      out.add(m);
      if (out.length >= 2) break;
    }
    return out;
  }

  String get aiStatusLine {
    if (!hasKey) return 'AI off · add your Gemini key';
    if (!aiEnabled) return 'AI paused';
    if (!sharing.anything) return 'AI off · nothing shared';
    if (!keyVerified) return 'Key needs attention';
    if (aiBusy) return 'Gemini is thinking…';
    if (briefError != null) return 'Gemini hit a snag · retrying soon';
    final times = <DateTime>[
      if (todaysBrief != null) todaysBrief!.createdAt,
      if (todaysLive != null) todaysLive!.createdAt,
    ]..sort();
    if (times.isNotEmpty) return 'Gemini live · updated ${fmtTime(times.last)} · $model';
    return 'Gemini ready · $model';
  }

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
    if (mode == DataMode.healthConnect) _merge(const <DayRecord>[], DateTime.now());
    _ins = null;
    loaded = true;
    notifyListeners();
    _startTicker();
    if (mode == DataMode.healthConnect) unawaited(sync());
    _scheduleAi();
  }

  void onResume() {
    _ins = null;
    _startTicker();
    if (mode == DataMode.healthConnect) {
      _rollWindow();
      unawaited(sync());
    }
    _scheduleAi();
    notifyListeners();
  }

  void onPause() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 3), (_) => _tick());
  }

  void _tick() {
    _ins = null; // re-evaluate "now", the energy curve and the day boundary
    if (mode == DataMode.healthConnect) {
      _rollWindow();
      unawaited(sync());
    }
    _scheduleAi();
    notifyListeners();
  }

  void _rollWindow() {
    if (_records.isEmpty || _records.last.date != isoDate(DateTime.now())) _merge(const <DayRecord>[], DateTime.now());
  }

  /// Debounced so a burst of changes (sync + settings) costs one round of AI calls.
  void _scheduleAi({Duration delay = const Duration(milliseconds: 700)}) {
    _aiDebounce?.cancel();
    _aiDebounce = Timer(delay, () {
      if (!aiReady) return;
      unawaited(refreshBrief());
      unawaited(refreshLive());
    });
  }

  void finishOnboarding() {
    onboarded = true;
    tab = 0;
    _persist();
    notifyListeners();
    _scheduleAi();
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
    usedSources = {};
    latestByCategory = {};
    lastFullSync = null;
    lastDeepSync = null;
    _ins = null;
    _persist();
    await sync(full: true);
    return syncError == null ? ConnectOutcome.connected : ConnectOutcome.error;
  }

  /// Re-opens the Health Connect permission sheet, then backfills everything.
  Future<void> fixPermissions() async {
    try {
      await health.requestAccess();
    } on HealthException catch (e) {
      syncError = e.message;
      notifyListeners();
    }
    await _resyncAll();
  }

  /// [deep] = last 7 days, [full] = all 60 days. Plain calls sync the last 3 days and are
  /// throttled to once every 90 seconds unless [force] is set.
  Future<void> sync({bool force = false, bool deep = false, bool full = false}) async {
    if (mode != DataMode.healthConnect || syncing) return;
    final now = DateTime.now();
    final ls = lastSync;
    if (!force && !deep && !full && ls != null && now.difference(ls) < const Duration(seconds: 90)) return;
    final lf = lastFullSync, ld = lastDeepSync;
    final int days = (full || lf == null) ? 60 : ((deep || ld == null || isoDate(ld) != isoDate(now)) ? 7 : 3);
    syncing = true;
    syncDays = days;
    syncDone = {};
    syncError = null;
    notifyListeners();
    try {
      final res = await health.fetch(
        days: days,
        now: now,
        prefs: sourcePrefs,
        onProgress: (c) {
          syncDone = {...syncDone, c};
          notifyListeners();
        },
      );
      _merge(res.records, now);
      if (res.weightKg != null) weightKg = res.weightKg;
      final merged = <String, Set<String>>{};
      if (days < 60) sources.forEach((k, v) => merged.putIfAbsent(k, () => <String>{}).addAll(v));
      res.sources.forEach((k, v) => merged.putIfAbsent(k, () => <String>{}).addAll(v));
      merged.forEach((k, v) => v.remove('Sample data'));
      sources = merged.map((k, v) => MapEntry(k, v.toList()..sort()));
      if (days == 60) {
        usedSources = Map<String, String>.of(res.used);
        latestByCategory = {};
      } else {
        usedSources = {...usedSources, ...res.used};
      }
      res.latest.forEach((k, v) {
        final cur = latestByCategory[k];
        if (cur == null || v.isAfter(cur)) latestByCategory[k] = v;
      });
      failedReads = res.failedTypes.toList()..sort();
      lastSync = now;
      lastSyncTook = res.elapsed;
      lastSyncDays = days;
      if (days == 60) lastFullSync = now;
      if (days >= 7) {
        lastDeepSync = now;
        missingPerms = await health.missingPermissions();
      }
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
      syncDone = {};
      _persist();
      notifyListeners();
      _scheduleAi();
    }
  }

  /// Full 60-day resync, waiting for a sync that's already running.
  Future<void> _resyncAll() async {
    var guard = 0;
    while (syncing && guard < 200) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      guard++;
    }
    await sync(full: true);
  }

  /// Replaces the synced days and keeps exactly 60 days ending today.
  void _merge(List<DayRecord> fresh, DateTime now) {
    final byDate = {for (final r in _records) r.date: r};
    for (final r in fresh) {
      byDate[r.date] = r;
    }
    final today = dayOnly(now);
    final out = <DayRecord>[];
    for (var i = 59; i >= 0; i--) {
      final key = isoDate(addDays(today, -i));
      final r = byDate[key] ?? DayRecord(date: key);
      r.partial = i == 0;
      out.add(r);
    }
    _records = out;
    _ins = null;
  }

  // ------------------------------------------------------------------ data check

  /// Reads one day straight from Health Connect, app by app.
  Future<void> runAudit(DateTime day) async {
    if (mode != DataMode.healthConnect) return;
    _auditDay = day;
    auditing = true;
    auditError = null;
    notifyListeners();
    try {
      audit = await health.audit(day, sourcePrefs);
    } on HealthException catch (e) {
      auditError = e.message;
    } catch (e) {
      auditError = 'Could not read Health Connect ($e).';
    } finally {
      auditing = false;
      notifyListeners();
    }
  }

  /// [category] is 'sleep', 'steps' or 'heart'; [value] is 'auto', 'combined' (steps) or an app's package.
  Future<void> setSourcePref(String category, String value) async {
    sourcePrefs.set(category, value);
    _persist();
    notifyListeners();
    await _resyncAll();
    final d = _auditDay;
    if (d != null) await runAudit(d);
  }

  Future<void> setCountNaps(bool v) async {
    sourcePrefs.countNaps = v;
    _persist();
    notifyListeners();
    await _resyncAll();
    final d = _auditDay;
    if (d != null) await runAudit(d);
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
    usedSources = {};
    latestByCategory = {};
    missingPerms = [];
    syncError = null;
    audit = null;
    _clearAiCache();
    _ins = null;
    _persist();
    notifyListeners();
    _scheduleAi();
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
    _scheduleAi(delay: const Duration(seconds: 2));
  }

  void setAiEnabled(bool v) {
    aiEnabled = v;
    _persist();
    notifyListeners();
    _scheduleAi();
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
      _scheduleAi(delay: const Duration(milliseconds: 200));
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
      liveError = null;
      _persist();
      notifyListeners();
      _scheduleAi();
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
    _scheduleAi();
  }

  void _clearAiCache() {
    brief = null;
    briefError = null;
    live = null;
    liveError = null;
    explanations.clear();
    explainErrors.clear();
    coach.clear();
    coachErrors.clear();
    extraDiscoveries = [];
    moreError = null;
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
    if (aiLog.length > 60) aiLog = aiLog.sublist(0, 60);
  }

  void _keyFailed(GeminiException e) {
    if (e.keyProblem) keyVerified = false;
  }

  // ------------------------------------------------------------------ AI: brief & live

  Future<void> refreshBrief({bool force = false}) async {
    final key = _apiKey;
    if (!aiReady || key == null || briefLoading || insights.isEmpty) return;
    final bk = briefKey;
    final cur = brief;
    if (!force && cur != null && cur.dataKey == bk) return;
    final errAt = _briefErrorAt;
    if (!force && briefError != null && errAt != null && DateTime.now().difference(errAt) < _briefRetry) return;
    briefLoading = true;
    briefError = null;
    notifyListeners();
    final ctx = contextPreview;
    try {
      brief = await ai.dailyBrief(key: key, model: model, fallbacks: _fallbacks, context: ctx, dataKey: bk);
      _log('Daily forecast', ctx, true);
    } on GeminiException catch (e) {
      briefError = e.message;
      _briefErrorAt = DateTime.now();
      _briefRetry = e.keyProblem ? const Duration(hours: 6) : const Duration(minutes: 2);
      _keyFailed(e);
      _log('Daily forecast', ctx, false);
    } catch (e) {
      briefError = 'Something went wrong: $e';
      _briefErrorAt = DateTime.now();
    } finally {
      briefLoading = false;
      _persist();
      notifyListeners();
    }
  }

  Future<void> refreshLive({bool force = false}) async {
    final key = _apiKey;
    if (!aiReady || key == null || liveLoading || insights.isEmpty) return;
    final lk = liveKey;
    final cur = live;
    if (!force && cur != null && cur.isToday) {
      if (cur.key == lk) return;
      final samePart = cur.key.split('|').take(2).join('|') == lk.split('|').take(2).join('|');
      if (samePart && DateTime.now().difference(cur.createdAt) < const Duration(minutes: 15)) return;
    }
    final errAt = _liveErrorAt;
    if (!force && liveError != null && errAt != null && DateTime.now().difference(errAt) < const Duration(minutes: 3)) return;
    liveLoading = true;
    liveError = null;
    notifyListeners();
    final ctx = contextPreview;
    try {
      live = await ai.liveNudge(key: key, model: model, fallbacks: _fallbacks, context: ctx, liveKey: lk, daypart: daypart);
      _log('Right now', ctx, true);
    } on GeminiException catch (e) {
      liveError = e.message;
      _liveErrorAt = DateTime.now();
      _keyFailed(e);
      _log('Right now', ctx, false);
    } catch (e) {
      liveError = 'Something went wrong: $e';
      _liveErrorAt = DateTime.now();
    } finally {
      liveLoading = false;
      _persist();
      notifyListeners();
    }
  }

  void retryAi() {
    briefError = null;
    liveError = null;
    unawaited(refreshBrief(force: true));
    unawaited(refreshLive(force: true));
  }

  // ------------------------------------------------------------------ AI: metrics

  String _explainKey(String metric) => '$metric|$depth|${_dayMetrics.contains(metric) ? liveKey : briefKey}';
  String? explanationFor(String metric) => explanations[_explainKey(metric)];
  String? explainErrorFor(String metric) => explainErrors[_explainKey(metric)];
  bool isExplaining(String metric) => explaining.contains(metric);

  Future<void> explainMetric(String metric, {bool force = false}) async {
    final key = _apiKey;
    if (!aiReady || key == null || explaining.contains(metric)) return;
    final ck = _explainKey(metric);
    if (!force && (explanations.containsKey(ck) || explainErrors.containsKey(ck))) return;
    explaining.add(metric);
    explainErrors.remove(ck);
    notifyListeners();
    final ctx = contextPreview;
    try {
      final text = await ai.explainMetric(key: key, model: model, fallbacks: _fallbacks, context: ctx, metric: metric, depth: depth);
      explanations[ck] = text;
      while (explanations.length > 60) {
        explanations.remove(explanations.keys.first);
      }
      _log('Explain ${metrics[metric]?.name ?? metric}', ctx, true);
    } on GeminiException catch (e) {
      explainErrors[ck] = e.message;
      _keyFailed(e);
      _log('Explain ${metrics[metric]?.name ?? metric}', ctx, false);
    } catch (e) {
      explainErrors[ck] = 'Something went wrong: $e';
    } finally {
      explaining.remove(metric);
      _persist();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ AI: experiment coach

  String coachKey(String id) {
    final run = runs[id];
    String state;
    if (run == null) {
      state = 'idle';
    } else {
      final p = insights.progress(run);
      state = p.done ? 'done${p.kept}' : 'd${p.todayIndex}c${run.checkins.length}k${p.kept}';
    }
    return '$id|$state|${isoDate(DateTime.now())}|$model|$depth';
  }

  String? coachFor(String id) => coach[coachKey(id)];
  String? coachErrorFor(String id) => coachErrors[coachKey(id)];
  bool isCoaching(String id) => coaching.contains(id);

  Future<void> loadCoach(String id, {bool force = false}) async {
    final key = _apiKey;
    final info = experiments[id];
    if (!aiReady || key == null || info == null || coaching.contains(id)) return;
    final ck = coachKey(id);
    if (!force && (coach.containsKey(ck) || coachErrors.containsKey(ck))) return;
    coaching.add(id);
    coachErrors.remove(ck);
    notifyListeners();
    final run = runs[id];
    final p = run == null ? null : insights.progress(run);
    final imp = insights.experimentImpact(id);
    final exp = <String, dynamic>{
      'id': id,
      'title': info.title,
      'daily_question': info.question,
      'tracked_metric': info.metric,
      'state': p == null ? 'not_started' : (p.done ? 'finished' : 'running'),
      if (imp != null) 'predicted_from_history': '+${imp.delta} ${imp.unit}',
      if (p != null) 'day': p.todayIndex + 1,
      if (p != null) 'days_kept': p.kept,
      if (p != null) 'days_answered': p.answered,
      if (p != null && p.measured != null) 'measured_after_kept_days': (p.measured! * 10).round() / 10,
      if (p != null && p.baseline != null) 'baseline_30_days_before': (p.baseline! * 10).round() / 10,
      if (p != null) 'nights_measured': p.nights,
    };
    final ctx = contextPreview;
    try {
      final text = await ai.experimentCoach(key: key, model: model, fallbacks: _fallbacks, context: ctx, experiment: exp, depth: depth);
      coach[ck] = text;
      while (coach.length > 30) {
        coach.remove(coach.keys.first);
      }
      _log('Experiment coach', ctx, true);
    } on GeminiException catch (e) {
      coachErrors[ck] = e.message;
      _keyFailed(e);
      _log('Experiment coach', ctx, false);
    } catch (e) {
      coachErrors[ck] = 'Something went wrong: $e';
    } finally {
      coaching.remove(id);
      _persist();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ AI: discover more

  Future<void> discoverMore() async {
    final key = _apiKey;
    if (!aiReady || key == null || moreLoading) return;
    moreLoading = true;
    moreError = null;
    notifyListeners();
    final ctx = contextPreview;
    final exclude = <String>[
      ...?todaysBrief?.discoveries.map((d) => d.head),
      ...todaysExtra.map((d) => d.head),
      ...insights.discoveries().map((d) => d.head),
    ];
    try {
      final list = await ai.moreDiscoveries(key: key, model: model, fallbacks: _fallbacks, context: ctx, exclude: exclude);
      final today = isoDate(DateTime.now());
      final keep = extraDate == today ? extraDiscoveries : <AiDiscovery>[];
      extraDate = today;
      extraDiscoveries = [...list, ...keep].take(12).toList();
      _log('Find new patterns', ctx, true);
    } on GeminiException catch (e) {
      moreError = e.message;
      _keyFailed(e);
      _log('Find new patterns', ctx, false);
    } catch (e) {
      moreError = 'Something went wrong: $e';
    } finally {
      moreLoading = false;
      _persist();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ AI: chat

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
      final buf = StringBuffer();
      streaming = '';
      notifyListeners();
      try {
        await for (final piece in ai.chatStream(
          key: key,
          model: model,
          fallbacks: _fallbacks,
          context: ctx,
          history: history,
          question: q,
          depth: depth,
        )) {
          buf.write(piece);
          final v = AiService.visible(buf.toString());
          if (v != streaming) {
            streaming = v;
            notifyListeners();
          }
        }
        reply = AiService.finishChat(buf.toString());
        _log('Ask', ctx, true);
      } on GeminiException catch (e) {
        final partial = AiService.visible(buf.toString());
        if (partial.length > 40) {
          reply = ChatMessage(
            id: ChatMessage.newId(),
            role: 'ai',
            text: partial,
            source: 'gemini',
            error: 'the connection dropped, so this answer may be cut short',
          );
        } else {
          reply = LocalBrain.respond(q, insights, depth).withError(e.message);
        }
        _keyFailed(e);
        _log('Ask', ctx, false);
      } catch (e) {
        reply = LocalBrain.respond(q, insights, depth).withError('$e');
      }
      streaming = null;
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
  String exportWeekly() => exporter.weeklyEdition(insights, brief: todaysBrief);

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
    usedSources = {};
    latestByCategory = {};
    missingPerms = [];
    failedReads = [];
    lastSync = null;
    lastFullSync = null;
    lastDeepSync = null;
    lastSyncTook = null;
    syncError = null;
    sourcePrefs = SourcePrefs();
    audit = null;
    auditError = null;
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

  static String? _iso(DateTime? t) => t?.toIso8601String();
  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

  Map<String, dynamic> _toJson() {
    final b = brief;
    final l = live;
    final took = lastSyncTook;
    return {
      'v': 2,
      'dataVersion': _dataVersion,
      'onboarded': onboarded,
      'mode': mode.name,
      if (weightKg != null) 'weightKg': weightKg,
      'sources': sources,
      'usedSources': usedSources,
      'sourcePrefs': sourcePrefs.toJson(),
      'latest': latestByCategory.map((k, v) => MapEntry(k, v.toIso8601String())),
      'missingPerms': missingPerms,
      'failedReads': failedReads,
      'lastSync': _iso(lastSync),
      'lastFullSync': _iso(lastFullSync),
      'lastDeepSync': _iso(lastDeepSync),
      if (took != null) 'lastSyncTookMs': took.inMilliseconds,
      'lastSyncDays': lastSyncDays,
      'depth': depth,
      'reduceMotion': reduceMotion,
      'sharing': sharing.toJson(),
      'aiEnabled': aiEnabled,
      'model': model,
      'models': models,
      'keyVerified': keyVerified,
      'keyVerifiedAt': _iso(keyVerifiedAt),
      if (b != null) 'brief': b.toJson(),
      if (l != null) 'live': l.toJson(),
      'explanations': explanations,
      'coach': coach,
      'extraDate': extraDate,
      'extraDiscoveries': extraDiscoveries.map((d) => d.toJson()).toList(),
      'chat': chat.map((m) => m.toJson()).toList(),
      'aiLog': aiLog.map((e) => e.toJson()).toList(),
      'runs': runs.map((k, v) => MapEntry(k, v.toJson())),
      'saved': saved.toList(),
    };
  }

  void _fromJson(Map<String, dynamic> j) {
    List<String> strings(dynamic v) => ((v as List?) ?? const []).map((e) => e.toString()).toList();
    Map<String, String> stringMap(dynamic v) => ((v as Map?) ?? const {}).map((k, val) => MapEntry(k.toString(), val.toString()));

    onboarded = j['onboarded'] == true;
    mode = DataMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => DataMode.none);
    weightKg = (j['weightKg'] as num?)?.toDouble();
    sources = ((j['sources'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), strings(v)));
    usedSources = stringMap(j['usedSources']);
    if (j['sourcePrefs'] is Map) sourcePrefs = SourcePrefs.fromJson(Map<String, dynamic>.from(j['sourcePrefs'] as Map));
    latestByCategory = {};
    ((j['latest'] as Map?) ?? const {}).forEach((k, v) {
      final t = _date(v);
      if (t != null) latestByCategory[k.toString()] = t;
    });
    missingPerms = strings(j['missingPerms']);
    failedReads = strings(j['failedReads']);
    lastSync = _date(j['lastSync']);
    lastFullSync = _date(j['lastFullSync']);
    lastDeepSync = _date(j['lastDeepSync']);
    final tookMs = (j['lastSyncTookMs'] as num?)?.toInt();
    lastSyncTook = tookMs == null ? null : Duration(milliseconds: tookMs);
    lastSyncDays = (j['lastSyncDays'] as num?)?.toInt() ?? 0;
    depth = j['depth'] == 'nerdy' ? 'nerdy' : 'simple';
    reduceMotion = j['reduceMotion'] == true;
    if (j['sharing'] is Map) sharing = SharingPrefs.fromJson(Map<String, dynamic>.from(j['sharing'] as Map));
    aiEnabled = j['aiEnabled'] != false;
    model = (j['model'] ?? GeminiClient.defaultModel).toString();
    models = strings(j['models']);
    keyVerified = j['keyVerified'] == true;
    keyVerifiedAt = _date(j['keyVerifiedAt']);
    if (j['brief'] is Map) {
      try {
        brief = DailyBrief.fromJson(Map<String, dynamic>.from(j['brief'] as Map));
      } catch (_) {}
    }
    if (j['live'] is Map) {
      try {
        live = LiveNudge.fromJson(Map<String, dynamic>.from(j['live'] as Map));
      } catch (_) {}
    }
    explanations
      ..clear()
      ..addAll(stringMap(j['explanations']));
    coach
      ..clear()
      ..addAll(stringMap(j['coach']));
    extraDate = (j['extraDate'] ?? '').toString();
    extraDiscoveries = ((j['extraDiscoveries'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => AiDiscovery.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    chat = ((j['chat'] as List?) ?? const []).whereType<Map>().map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m))).toList();
    aiLog = ((j['aiLog'] as List?) ?? const []).whereType<Map>().map((m) => AiLogEntry.fromJson(Map<String, dynamic>.from(m))).toList();
    runs = ((j['runs'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), ExperimentRun.fromJson(Map<String, dynamic>.from(v as Map))),
    );
    saved = strings(j['saved']).toSet();

    // Data folded by an older version: re-read all 60 days and let Gemini rewrite with the new numbers.
    final version = (j['dataVersion'] as num?)?.toInt() ?? 0;
    if (version < _dataVersion) {
      lastFullSync = null;
      lastDeepSync = null;
      usedSources = {};
      brief = null;
      live = null;
      explanations.clear();
      coach.clear();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _ticker?.cancel();
    _aiDebounce?.cancel();
    super.dispose();
  }
}

/// Makes the controller available to every widget and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
