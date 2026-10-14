import 'package:flutter/material.dart';

import '../domain/metrics.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'metric_screen.dart';

/// Every number, in plain words.
class AlmanacScreen extends StatefulWidget {
  const AlmanacScreen({super.key});
  @override
  State<AlmanacScreen> createState() => _AlmanacScreenState();
}

class _AlmanacScreenState extends State<AlmanacScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ins = app.insights;
    final needle = _q.text.trim().toLowerCase();
    final keys = metricOrder.where((k) {
      if (needle.isEmpty) return true;
      final m = metrics[k]!;
      return '${m.name} ${m.tag} ${m.simple} ${m.group}'.toLowerCase().contains(needle);
    }).toList();
    final recent = app.records.length > 30 ? app.records.sublist(app.records.length - 30) : app.records;
    final top = MediaQuery.of(context).padding.top;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, top + 20, 20, 32),
      children: [
        const Kicker('The almanac', color: C.crimson),
        const SizedBox(height: 4),
        Text('Every number, in plain words.', style: T.display(46)),
        const SizedBox(height: 16),
        TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          style: T.ui(16, weight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Search: HRV, deep sleep, protein…',
            prefixIcon: const Icon(Icons.search_rounded, color: C.muted),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _q.clear()),
                  ),
          ),
        ),
        if (keys.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: C.rule, width: 2)),
              child: Column(children: [
                Text('Nothing by that name.', style: T.display(28)),
                const SizedBox(height: 4),
                Text('Try "sleep", "heart" or "meals".', style: T.ui(14, color: C.muted)),
              ]),
            ),
          ),
        for (final g in metricGroups)
          if (keys.any((k) => metrics[k]!.group == g)) ...[
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.group(g), width: 2))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Text(g, style: T.display(30, color: C.group(g)))),
                Text(metricGroupNotes[g] ?? '', style: T.ui(12, color: C.muted)),
              ]),
            ),
            for (final k in keys.where((k) => metrics[k]!.group == g))
              Press(
                onTap: () => Navigator.of(context).push(slideRoute(MetricScreen(metricKey: k))),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                          Flexible(child: Text(metrics[k]!.name, style: T.ui(16, weight: FontWeight.w800))),
                          const SizedBox(width: 8),
                          Text(metrics[k]!.tag.toUpperCase(), style: T.kicker(size: 11)),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          app.depth == 'nerdy' ? metrics[k]!.nerdy : metrics[k]!.simple,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.ui(14, color: C.muted, weight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        StatusChip(ins.status(k)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(
                        '${fmtValue(k, ins.reading(k)?.value)}${metrics[k]!.unit.isEmpty ? '' : ' ${metrics[k]!.unit}'}',
                        style: T.display(26),
                      ),
                      const SizedBox(height: 4),
                      Sparkline(values: recent.map((r) => r.value(k)).toList(), width: 72, height: 22, color: C.group(g)),
                    ]),
                  ]),
                ),
              ),
          ],
      ],
    );
  }
}
