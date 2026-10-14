import 'package:flutter/material.dart';

import '../domain/insights.dart';
import '../domain/metrics.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'experiment_screen.dart';
import 'metric_screen.dart';

const _kindColor = {'Pattern': C.crimson, 'Fun fact': C.tealInk, 'Trend': C.navy, 'Milestone': C.amberInk};
const _kindBg = {'Pattern': C.card, 'Fun fact': C.sun, 'Trend': C.card, 'Milestone': Color(0xFFF6C48C)};
const _filters = ['All', 'Pattern', 'Fun fact', 'Trend', 'Milestone'];

/// Local discoveries plus Gemini's (when a fresh brief exists).
List<Discovery> allDiscoveries(AppController app) {
  final out = <Discovery>[];
  final b = app.brief;
  if (b != null && b.dataKey == app.dataKey) {
    for (final d in b.discoveries) {
      out.add(Discovery(
        id: 'ai-${d.head.hashCode}',
        kind: d.kind,
        head: d.head,
        body: d.body,
        metric: d.metric,
        basis: 'Written by Gemini from your last ${app.sharing.days} days',
        ask: 'Tell me more: ${d.head}',
        viz: SparkViz(d.metric),
        ai: true,
      ));
    }
  }
  out.addAll(app.insights.discoveries());
  return out;
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _pc = PageController();
  String _filter = 'All';
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int delta, int count) {
    if (count == 0 || !_pc.hasClients) return;
    var next = (_page + delta) % count;
    if (next < 0) next += count;
    if (motionOff(context)) {
      _pc.jumpToPage(next);
    } else {
      _pc.animateToPage(next, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = allDiscoveries(app);
    final list = _filter == 'All' ? all : all.where((d) => d.kind == _filter).toList();
    final int idx = list.isEmpty ? 0 : (_page >= list.length ? list.length - 1 : _page);
    final Discovery? card = list.isEmpty ? null : list[idx];
    final top = MediaQuery.of(context).padding.top;

    return ListView(
      padding: EdgeInsets.fromLTRB(0, top + 20, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Kicker('Discover', color: C.crimson),
            const SizedBox(height: 4),
            Text('Things your body told us.', style: T.display(40)),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Press(
                    onTap: () {
                      setState(() {
                        _filter = f;
                        _page = 0;
                      });
                      if (_pc.hasClients) _pc.jumpToPage(0);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _filter == f ? C.navy : C.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _filter == f ? C.navy : C.rule),
                      ),
                      child: Text(f == 'All' ? 'All' : '${f}s', style: T.ui(14, color: _filter == f ? C.card : C.navy, weight: FontWeight.w800)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (card == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: C.rule, width: 2)),
              child: Column(children: [
                Text(all.isEmpty ? 'Still gathering clues.' : 'Nothing in this drawer yet.', style: T.display(28), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  all.isEmpty ? 'Discoveries appear after about a week of synced nights and meals.' : 'Try another filter.',
                  style: T.ui(14, color: C.muted),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          )
        else ...[
          SizedBox(
            height: 452,
            child: PageView.builder(
              controller: _pc,
              itemCount: list.length,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: _pc,
                builder: (context, child) {
                  double delta = 0;
                  if (_pc.hasClients && _pc.position.haveDimensions) {
                    delta = (_pc.page ?? 0.0) - i;
                  }
                  return Transform.rotate(
                    angle: -delta * 0.08,
                    child: Transform.scale(scale: 1 - delta.abs() * 0.06, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: _ClippingCard(d: list[i], index: i, total: list.length),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _Round(icon: Icons.chevron_left_rounded, label: 'Previous discovery', onTap: () => _go(-1, list.length)),
              const Spacer(),
              Pill(
                label: app.isSaved(card.id) ? 'Saved' : 'Save',
                icon: app.isSaved(card.id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                bg: C.card,
                fg: C.navy,
                onTap: () {
                  final was = app.isSaved(card.id);
                  app.toggleSave(card.id);
                  showToast(context, was ? 'Removed from saved' : 'Saved to your almanac');
                },
              ),
              const SizedBox(width: 8),
              _ActionPill(card: card, app: app),
              const Spacer(),
              _Round(icon: Icons.chevron_right_rounded, label: 'Next discovery', dark: true, onTap: () => _go(1, list.length)),
            ]),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              app.records.isEmpty ? 'Swipe the card.' : 'Swipe the card. ${app.records.length} days, ${fmtDate(app.records.first.date)} to today.',
              style: T.ui(12, color: C.muted, weight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.card, required this.app});
  final Discovery card;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final exp = card.experiment;
    if (exp != null) {
      return Pill(
        label: 'Try it',
        icon: Icons.science_outlined,
        bg: C.crimson,
        onTap: () => Navigator.of(context).push(slideRoute(ExperimentScreen(id: exp))),
      );
    }
    return Pill(
      label: 'Ask',
      icon: Icons.chat_bubble_outline_rounded,
      onTap: () => app.ask(card.ask ?? 'Tell me more about ${card.head}'),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.label, required this.onTap, this.dark = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dark;
  @override
  Widget build(BuildContext context) => Press(
        semantics: label,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: dark ? C.navy : C.card, shape: BoxShape.circle, border: dark ? null : Border.all(color: C.rule)),
          child: Icon(icon, color: dark ? C.card : C.ink),
        ),
      );
}

class _ClippingCard extends StatelessWidget {
  const _ClippingCard({required this.d, required this.index, required this.total});
  final Discovery d;
  final int index, total;

  @override
  Widget build(BuildContext context) {
    final kindColor = _kindColor[d.kind] ?? C.crimson;
    final viz = d.viz;
    final basis = d.basis.isEmpty ? 'your data' : d.basis[0].toLowerCase() + d.basis.substring(1);
    return Press(
      onTap: () => Navigator.of(context).push(slideRoute(MetricScreen(metricKey: d.metric))),
      child: Container(
        decoration: BoxDecoration(
          color: _kindBg[d.kind] ?? C.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: C.rule),
          boxShadow: const [BoxShadow(color: Color(0x33121838), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -16)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              Kicker(d.kind, color: kindColor),
              if (d.ai) ...[
                const SizedBox(width: 8),
                const Icon(Icons.auto_awesome, size: 14, color: C.muted),
              ],
              const Spacer(),
              Text('${index + 1} of $total', style: T.ui(12, color: C.muted, weight: FontWeight.w700)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(d.head, style: T.display(38, height: 0.92), maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(d.body, style: T.serif(16), maxLines: 5, overflow: TextOverflow.ellipsis),
          ),
          const Spacer(),
          if (viz != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: VizView(viz: viz)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x40172767)))),
            child: Text('Based on $basis', style: T.ui(12, color: C.muted, weight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class VizView extends StatelessWidget {
  const VizView({super.key, required this.viz});
  final Viz viz;

  Widget _bar(double frac, Color c, int delayMs) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: frac.clamp(0.0, 1.0).toDouble()),
        duration: Duration(milliseconds: 900 + delayMs),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: v,
          child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999))),
        ),
      );

  Widget _lane(String label, double offset, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 70, child: Text(label, style: T.ui(13, weight: FontWeight.w800))),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) => Container(
                height: 24,
                decoration: BoxDecoration(color: const Color(0x1A172767), borderRadius: BorderRadius.circular(999)),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: offset),
                  duration: const Duration(milliseconds: 1100),
                  curve: Curves.easeOutCubic,
                  builder: (_, o, __) => Stack(children: [
                    Positioned(
                      left: box.maxWidth * o,
                      top: 0,
                      bottom: 0,
                      width: box.maxWidth * 0.55,
                      child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999))),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final v = viz;
    if (v is BarsViz) {
      final double mx = (v.a > v.b ? v.a : v.b) * 1.08;
      String f(double x) => v.decimals > 0 ? x.toStringAsFixed(v.decimals) : x.round().toString();
      final rows = [(v.aLabel, v.a, C.coral, 0), (v.bLabel, v.b, C.teal, 120)];
      return Column(children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(row.$1, style: T.ui(13, weight: FontWeight.w800))),
                Text('${f(row.$2)} ${v.unit}', style: T.ui(13, weight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Container(
                height: 16,
                decoration: BoxDecoration(color: const Color(0x1A172767), borderRadius: BorderRadius.circular(999)),
                child: _bar(mx == 0 ? 0.0 : row.$2 / mx, row.$3, row.$4),
              ),
            ]),
          ),
      ]);
    }
    if (v is BigViz) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v.value, style: T.display(64, height: 1))),
        Text(v.label.toUpperCase(), style: T.kicker()),
      ]);
    }
    if (v is SparkViz) {
      final app = AppScope.of(context);
      final vals = app.records.map((r) => r.value(v.metric)).toList();
      final color = C.group(metrics[v.metric]?.group ?? 'Overnight');
      return LayoutBuilder(builder: (_, box) => Sparkline(values: vals, width: box.maxWidth, height: 84, stroke: 2.5, color: color));
    }
    if (v is ClockViz) {
      final double shift = (v.minutes / 240).clamp(0.0, 0.4).toDouble();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lane('Tue–Fri', 0, C.navy),
        _lane('Weekend', shift, C.crimson),
        Padding(
          padding: const EdgeInsets.only(left: 70),
          child: Row(children: [
            Text('Asleep → awake', style: T.ui(12, color: C.muted, weight: FontWeight.w700)),
            const Spacer(),
            Text('+${v.minutes.round()} min', style: T.ui(12, color: C.muted, weight: FontWeight.w700)),
          ]),
        ),
      ]);
    }
    if (v is RouteViz) {
      final double total = v.nextKm ?? v.km;
      final double frac = total == 0 ? 1.0 : (v.km / total).clamp(0.0, 1.0).toDouble();
      final next = v.next;
      return Column(children: [
        LayoutBuilder(builder: (_, box) {
          return SizedBox(
            height: 24,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: frac),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, f, __) => Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
                Container(height: 12, decoration: BoxDecoration(color: const Color(0x1A172767), borderRadius: BorderRadius.circular(999))),
                Container(width: box.maxWidth * f, height: 12, decoration: BoxDecoration(color: C.amber, borderRadius: BorderRadius.circular(999))),
                Positioned(
                  left: (box.maxWidth * f - 12).clamp(0.0, box.maxWidth - 24).toDouble(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: C.crimson, shape: BoxShape.circle, border: Border.all(color: C.card, width: 4)),
                  ),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 10),
        Row(children: [
          Text('Home', style: T.ui(12, color: C.muted, weight: FontWeight.w700)),
          const Spacer(),
          Flexible(child: Text('${v.reached} ✓', style: T.ui(12, color: C.muted, weight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          if (next != null) ...[
            const Spacer(),
            Flexible(child: Text(next, style: T.ui(12, color: C.muted, weight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          ],
        ]),
      ]);
    }
    return const SizedBox.shrink();
  }
}
