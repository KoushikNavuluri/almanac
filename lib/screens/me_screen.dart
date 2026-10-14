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

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final top = MediaQuery.of(context).padding.top;
    final ls = app.lastSync;
    final modeLine = switch (app.mode) {
      DataMode.healthConnect => ls == null ? 'Health Connect · not synced yet' : 'Health Connect · synced ${fmtTime(ls)}',
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
            sub: app.hasKey ? '${app.keyVerified ? 'Gemini connected' : 'Key needs attention'} · ${app.model}${app.aiEnabled ? '' : ' · off'}' : 'Add your own Gemini API key',
            onTap: () => Navigator.of(context).push(slideRoute(const AiSettingsScreen())),
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
            'Almanac 1.0 · No account, no servers. Your health data stays on this phone; AI features talk directly to Google Gemini with your own key and only the summaries you allow. Not a medical device and not medical advice.',
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

class _SourceCard extends StatefulWidget {
  const _SourceCard();
  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _connecting = false;

  Future<void> _connect() async {
    setState(() => _connecting = true);
    await connectHealthFlow(context);
    if (mounted) setState(() => _connecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    const catNames = {'sleep': 'Sleep', 'heart': 'Heart', 'activity': 'Steps', 'food': 'Meals'};
    final hc = app.mode == DataMode.healthConnect;
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
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: C.teal, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Connected', style: T.ui(12, color: C.teal, weight: FontWeight.w800)),
            ]),
        ]),
        if (app.sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final e in app.sources.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${catNames[e.key] ?? e.key}: ${e.value.join(', ')}', style: T.ui(13, color: C.ink, weight: FontWeight.w600)),
            ),
        ],
        if (app.syncError != null) ...[
          const SizedBox(height: 10),
          ErrorNote(message: app.syncError!),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (hc)
            Pill(label: app.syncing ? 'Syncing…' : 'Sync now', icon: Icons.sync_rounded, busy: app.syncing, height: 42, onTap: () => app.sync(force: true))
          else
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
