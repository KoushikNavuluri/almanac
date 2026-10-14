import 'package:flutter/material.dart';

import '../domain/metrics.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'ai_settings_screen.dart';
import 'connect_flow.dart';
import 'discover_screen.dart';
import 'experiment_screen.dart';
import 'metric_screen.dart';
import 'privacy_screen.dart';

/// "just now", "4 min ago", "3 h ago", "yesterday, 11:40 PM", "Mon, 12 Oct, 7:05 AM".
String _ago(DateTime t) {
  final now = DateTime.now();
  final d = now.difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  final days = daysBetween(t, now);
  if (days == 0) return '${d.inHours} h ago';
  if (days == 1) return 'yesterday, ${fmtTime(t)}';
  return '${fmtDay(t)}, ${fmtTime(t)}';
}

String _secs(Duration d) {
  final s = d.inMilliseconds / 1000;
  return s < 10 ? '${s.toStringAsFixed(1)} s' : '${s.round()} s';
}

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final top = MediaQuery.of(context).padding.top;
    final ls = app.lastSync;
    final modeLine = switch (app.mode) {
      DataMode.healthConnect => app.syncing
          ? 'Health Connect · syncing…'
          : ls == null
              ? 'Health Connect · not synced yet'
              : 'Health Connect · synced ${_ago(ls)}',
      DataMode.sample => 'Exploring sample data',
      DataMode.none => 'No data source yet',
    };
    final discoveries = allDiscoveries(app).where((d) => app.saved.contains(d.id)).toList();
    final missingSaved = app.saved.length - discoveries.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, top + 20, 20, 40),
      children: [
        Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: C.crimson, shape: BoxShape.circle),
            child: const Icon(Icons.wb_sunny_rounded, color: C.sun, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your almanac', style: T.display(40)),
              Text(modeLine, style: T.ui(14, color: C.muted)),
            ]),
          ),
        ]),
        const _Section('Your data'),
        const _SourceCard(),
        const _Section('AI'),
        _Group(children: [
          _Row(
            icon: Icons.key_rounded,
            title: 'AI & your key',
            sub: app.hasKey ? app.aiStatusLine : 'Add your own Gemini API key',
            onTap: () => Navigator.of(context).push(slideRoute(const AiSettingsScreen())),
          ),
          _Row(
            icon: Icons.auto_awesome,
            title: app.aiBusy ? 'Gemini is writing…' : 'Refresh AI insights',
            sub: app.aiReady ? "Rewrite today's forecast and the Right now card from your latest data" : 'Needs a Gemini key, AI on, and at least one category shared',
            onTap: app.aiReady && !app.aiBusy
                ? () {
                    app.retryAi();
                    showToast(context, 'Gemini is rewriting today with your latest data', good: true);
                  }
                : null,
          ),
          _Row(
            icon: Icons.shield_outlined,
            title: 'Privacy & sharing',
            sub: app.sharing.anything ? 'Gemini sees: ${app.sharing.labels.join(', ')}' : 'Nothing is shared with AI',
            onTap: () => Navigator.of(context).push(slideRoute(const PrivacyScreen())),
          ),
        ]),
        const _Section('Experiments'),
        _Group(children: [
          if (app.runs.isEmpty)
            _Row(icon: Icons.science_outlined, title: 'Nothing running yet', sub: 'Start one from Today or Discover', onTap: () => app.setTab(0)),
          for (final run in app.runs.values)
            Builder(builder: (context) {
              final p = app.insights.progress(run);
              final info = experiments[run.id]!;
              return _Row(
                icon: Icons.science_outlined,
                title: info.title,
                sub: p.done ? 'Done · kept ${p.kept} of ${info.days}' : 'Day ${p.todayIndex + 1} of ${info.days} · ${p.kept} kept',
                onTap: () => Navigator.of(context).push(slideRoute(ExperimentScreen(id: run.id))),
              );
            }),
        ]),
        const _Section('Saved discoveries'),
        _Group(children: [
          if (discoveries.isEmpty)
            _Row(
              icon: Icons.bookmark_border_rounded,
              title: missingSaved > 0 ? 'Saved cards are refreshing' : 'No clippings yet',
              sub: missingSaved > 0 ? 'They reappear when the data that made them is back' : 'Tap Save on any card in Discover',
              onTap: () => app.setTab(1),
            ),
          for (final d in discoveries)
            _Row(
              icon: Icons.bookmark_rounded,
              title: d.head,
              sub: d.kind,
              onTap: () => Navigator.of(context).push(slideRoute(MetricScreen(metricKey: d.metric))),
            ),
        ]),
        const _Section('How it talks'),
        _Group(children: [
          _Row(
            title: 'Explain level',
            sub: app.depth == 'simple' ? 'Plain words, no jargon' : 'Real terms, real numbers',
            trailing: Segmented<String>(value: app.depth, options: const {'simple': 'Simple', 'nerdy': 'Nerdy'}, onChanged: app.setDepth, small: true),
          ),
          _Row(
            title: 'Reduce motion',
            sub: 'Still sky, no confetti, no count-ups',
            trailing: Switch(value: app.reduceMotion, onChanged: app.setReduceMotion),
          ),
        ]),
        const _Section('Take it with you'),
        _Group(children: [
          _Row(
            icon: Icons.article_outlined,
            title: "This week's edition",
            sub: 'A one-page recap (Markdown)',
            onTap: () => shareTextFile(context, fileName: 'almanac-weekly-edition.md', text: app.exportWeekly(), mime: 'text/markdown'),
          ),
          _Row(
            icon: Icons.table_chart_outlined,
            title: 'All ${app.records.length} days, raw',
            sub: 'For your doctor or a spreadsheet (CSV)',
            onTap: app.records.isEmpty ? null : () => shareTextFile(context, fileName: 'almanac-days.csv', text: app.exportCsv(), mime: 'text/csv'),
          ),
        ]),
        const _Section('Danger zone'),
        _Group(children: [
          _Row(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Clear the conversation',
            sub: '${app.chat.length} messages on this phone',
            onTap: app.chat.isEmpty
                ? null
                : () {
                    app.clearChat();
                    showToast(context, 'Conversation cleared');
                  },
          ),
          _Row(
            icon: Icons.delete_forever_outlined,
            title: 'Delete everything',
            sub: 'Data, chat, experiments, settings and your key',
            danger: true,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete everything?'),
                  content: const Text('This removes every reading, chat, experiment, setting and your Gemini key from this phone. Health Connect keeps its own copy of your data.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) await app.wipeEverything();
            },
          ),
        ]),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0x0F172767), borderRadius: BorderRadius.circular(18)),
          child: Text(
            'Almanac · No account, no servers. Your health data stays on this phone; AI features talk directly to Google Gemini with your own key and only the summaries you allow. Not a medical device and not medical advice.',
            style: T.ui(13, color: C.muted, weight: FontWeight.w500, height: 1.55),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 6),
        child: Text(title, style: T.display(30)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.rule)),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: C.rule),
          children[i],
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.sub, this.icon, this.trailing, this.onTap, this.danger = false});
  final String title;
  final String? sub;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: danger ? const Color(0x1AE74B47) : const Color(0x12172767), shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: danger ? C.crimson : C.navy),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.ui(15, color: danger ? C.crimson : C.ink, weight: FontWeight.w800)),
            if (sub != null) Text(sub!, style: T.ui(13, color: C.muted, weight: FontWeight.w500, height: 1.35)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!] else if (onTap != null) const Icon(Icons.chevron_right_rounded, color: C.muted),
      ]),
    );
    if (trailing != null) return row;
    return Press(onTap: onTap, child: row);
  }
}

/// Where the data comes from, how fresh it is, and what Almanac can't read yet.
class _SourceCard extends StatefulWidget {
  const _SourceCard();
  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  static const _catNames = {'sleep': 'Sleep', 'heart': 'Heart', 'activity': 'Steps', 'food': 'Meals'};
  static const _order = ['sleep', 'heart', 'activity', 'food'];

  bool _connecting = false;
  bool _fixing = false;

  Future<void> _connect() async {
    setState(() => _connecting = true);
    await connectHealthFlow(context);
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _fix(AppController app) async {
    setState(() => _fixing = true);
    await app.fixPermissions();
    if (!mounted) return;
    setState(() => _fixing = false);
    final missing = app.missingPerms;
    showToast(
      context,
      missing.isEmpty ? 'All set. Almanac can read everything it needs.' : 'Still missing: ${missing.join(', ')}',
      good: missing.isEmpty,
    );
  }

  Future<void> _syncNow(AppController app, {bool full = false}) async {
    if (full) {
      await app.sync(full: true);
    } else {
      await app.sync(deep: true);
    }
    if (!mounted) return;
    final took = app.lastSyncTook;
    if (app.syncError == null) {
      showToast(context, 'Up to date · read ${app.lastSyncDays} days${took != null ? ' in ${_secs(took)}' : ''}', good: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final hc = app.mode == DataMode.healthConnect;
    final now = DateTime.now();
    final cats = <String>[
      for (final c in _order)
        if (app.sources.containsKey(c) || app.latestByCategory.containsKey(c)) c,
      for (final c in app.sources.keys)
        if (!_order.contains(c)) c,
    ];

    // Trackers only hand data to Health Connect after their own app syncs.
    final staleNames = <String>[];
    DateTime? oldest;
    if (hc) {
      for (final c in const ['sleep', 'heart', 'activity']) {
        final t = app.latestByCategory[c];
        if (t == null || now.difference(t) < const Duration(hours: 26)) continue;
        staleNames.add(_catNames[c] ?? c);
        if (oldest == null || t.isBefore(oldest)) oldest = t;
      }
    }

    String? syncLine;
    if (hc) {
      final ls = app.lastSync;
      final took = app.lastSyncTook;
      if (app.syncing) {
        syncLine = 'Reading the last ${app.syncDays} days · ${app.syncDone.length} of 4 done';
      } else if (ls != null) {
        final span = app.lastSyncDays > 0 ? ' · last ${app.lastSyncDays} days' : '';
        final speed = took != null ? ' in ${_secs(took)}' : '';
        syncLine = 'Synced ${_ago(ls)}$span$speed';
      } else {
        syncLine = 'Not synced yet';
      }
    }

    final missing = app.missingPerms;
    final failed = app.failedReads.where((f) => !missing.contains(f)).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.rule)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Color(0x12172767), shape: BoxShape.circle),
            child: Icon(hc ? Icons.favorite_border_rounded : Icons.science_outlined, size: 19, color: C.navy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hc ? 'Health Connect' : app.isSample ? 'Sample data' : 'Not connected', style: T.ui(15, weight: FontWeight.w800)),
              Text(
                hc
                    ? '${app.insights.nightsWithSleep} nights · ${app.records.length} days on this phone'
                    : app.isSample
                        ? '60 made-up days, for exploring'
                        : 'Connect to read your tracker and meal app',
                style: T.ui(13, color: C.muted, weight: FontWeight.w500),
              ),
            ]),
          ),
          if (hc)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: missing.isEmpty ? C.teal : C.amber, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(missing.isEmpty ? 'Connected' : 'Partial', style: T.ui(12, color: missing.isEmpty ? C.teal : C.amberInk, weight: FontWeight.w800)),
            ]),
        ]),
        if (syncLine != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(app.syncing ? Icons.sync_rounded : Icons.check_circle_outline_rounded, size: 16, color: C.teal),
            const SizedBox(width: 6),
            Expanded(child: Text(syncLine, style: T.ui(13, color: C.ink, weight: FontWeight.w700))),
          ]),
          if (app.syncing) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: app.syncDone.isEmpty ? null : app.syncDone.length / 4,
                minHeight: 4,
                backgroundColor: C.rule,
                color: C.teal,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Syncs on open, every 3 min while open and on pull-down. A 7-day repair runs daily to catch late uploads.',
            style: T.ui(12, color: C.muted, weight: FontWeight.w500, height: 1.4),
          ),
        ],
        if (cats.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 56, child: Text(_catNames[c] ?? c, style: T.ui(13, weight: FontWeight.w800))),
                Expanded(
                  child: Text(
                    [
                      if ((app.sources[c] ?? const <String>[]).isNotEmpty) app.sources[c]!.join(', '),
                      if (app.latestByCategory[c] != null) 'newest ${_ago(app.latestByCategory[c]!)}',
                    ].join(' · '),
                    style: T.ui(13, color: C.muted, weight: FontWeight.w600, height: 1.35),
                  ),
                ),
                if (app.syncing)
                  app.syncDone.contains(c)
                      ? const Icon(Icons.check_rounded, size: 16, color: C.teal)
                      : const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: C.teal)),
              ]),
            ),
        ],
        if (staleNames.isNotEmpty && oldest != null && !app.syncing) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.sun.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
            child: Text(
              'Nothing new for ${staleNames.join(', ').toLowerCase()} since ${_ago(oldest)}. Open your tracker app once: it only hands new data to Health Connect after it syncs itself.',
              style: T.ui(13, color: C.ink, weight: FontWeight.w600, height: 1.4),
            ),
          ),
        ],
        if (hc && missing.isNotEmpty) ...[
          const SizedBox(height: 10),
          ErrorNote(
            message: _fixing ? 'Opening Health Connect…' : "Almanac can't read: ${missing.join(', ')}. Those cards stay empty until you allow them.",
            onRetry: _fixing ? null : () => _fix(app),
            actionLabel: 'Grant access',
          ),
        ],
        if (hc && failed.isNotEmpty && app.syncError == null) ...[
          const SizedBox(height: 8),
          Text("Last sync couldn't read: ${failed.join(', ')}.", style: T.ui(12, color: C.muted, weight: FontWeight.w600)),
        ],
        if (app.syncError != null) ...[
          const SizedBox(height: 10),
          ErrorNote(message: app.syncError!, onRetry: hc && !app.syncing ? () => app.sync(force: true) : null),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (hc) ...[
            Pill(
              label: app.syncing ? 'Syncing…' : 'Sync now',
              icon: Icons.sync_rounded,
              busy: app.syncing,
              height: 42,
              onTap: () => _syncNow(app),
            ),
            Pill(
              label: 'Full resync (60 days)',
              icon: Icons.history_rounded,
              bg: const Color(0x14172767),
              fg: C.navy,
              height: 42,
              onTap: app.syncing ? null : () => _syncNow(app, full: true),
            ),
          ] else
            Pill(label: 'Connect Health Connect', icon: Icons.link_rounded, bg: C.crimson, busy: _connecting, height: 42, onTap: _connect),
          if (!app.isSample)
            Pill(
              label: 'Use sample data',
              bg: const Color(0x14172767),
              fg: C.navy,
              height: 42,
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Switch to sample data?'),
                    content: const Text('Almanac will show 60 made-up days instead of yours. Reconnect Health Connect any time.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Switch')),
                    ],
                  ),
                );
                if (ok == true) app.useSampleData();
              },
            ),
        ]),
      ]),
    );
  }
}
