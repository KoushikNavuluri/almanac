import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/health_source.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Every app's number for a day, straight from Health Connect, and which one Almanac uses.
/// Tap a row to make Almanac use that app for the category; Almanac re-reads 60 days.
class DataCheckScreen extends StatefulWidget {
  const DataCheckScreen({super.key});
  @override
  State<DataCheckScreen> createState() => _DataCheckScreenState();
}

class _DataCheckScreenState extends State<DataCheckScreen> {
  int _back = 0;

  DateTime get _day => addDays(dayOnly(DateTime.now()), -_back);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).runAudit(_day);
    });
  }

  void _pickDay(int back) {
    setState(() => _back = back);
    AppScope.read(context).runAudit(_day);
  }

  static String _catLabel(String cat) => cat == 'heart' ? 'heart metrics' : cat;

  Future<void> _use(AppController app, AuditSection s, AuditRow r) async {
    final cat = s.pref;
    if (cat == null || r.used) return;
    showToast(context, 'Using ${r.source} for ${_catLabel(cat)}. Re-reading 60 days…', good: true);
    await app.setSourcePref(cat, r.raw);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = app.audit;
    final key = isoDate(_day);
    final busy = app.auditing || app.syncing;
    final twoAgo = addDays(dayOnly(DateTime.now()), -2);
    final hc = app.mode == DataMode.healthConnect;

    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const BackBar(title: 'Data check'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Does it match your tracker?', style: T.display(46, height: 0.92)),
                const SizedBox(height: 10),
                Text(
                  "Every app that wrote to Health Connect for this day, and the one Almanac uses. Google Health keeps its own copy: if it shows a newer number than the row marked USED, it just hasn't handed that data to Health Connect yet.",
                  style: T.serif(15.5, height: 1.55),
                ),
                const SizedBox(height: 16),
                if (!hc)
                  const ErrorNote(message: 'Connect Health Connect in Me to compare your real data with your tracker.')
                else ...[
                  Row(children: [
                    Segmented<int>(
                      value: _back,
                      options: {0: 'Today', 1: 'Yesterday', 2: weekdayShort(twoAgo)},
                      onChanged: _pickDay,
                      small: true,
                    ),
                    const Spacer(),
                    if (busy)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.crimson))
                    else
                      Press(
                        semantics: 'Check again',
                        onTap: () => app.runAudit(_day),
                        child: const Icon(Icons.refresh_rounded, color: C.navy),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    app.syncing ? 'Re-reading Health Connect with your choice…' : 'Sleep is filed under the morning you woke up, like Google Health does.',
                    style: T.ui(12.5, color: C.muted, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  if (app.auditError != null) ...[
                    ErrorNote(message: app.auditError!, onRetry: () => app.runAudit(_day)),
                    const SizedBox(height: 14),
                  ],
                  if (a != null && a.date == key) ...[
                    for (final s in a.sections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _SectionCard(
                          section: s,
                          pref: s.pref == null ? null : app.sourcePrefs.of(s.pref!),
                          enabled: !busy,
                          onUse: (r) => _use(app, s, r),
                          onAuto: () => app.setSourcePref(s.pref!, 'auto'),
                        ),
                      ),
                    PaperCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Count naps in total sleep', style: T.ui(15, weight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('Google Health adds naps to the day. Turn off to count only the night.', style: T.ui(13, color: C.muted, height: 1.35)),
                          ]),
                        ),
                        Switch(value: app.sourcePrefs.countNaps, onChanged: busy ? null : (v) => app.setCountNaps(v)),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Pill(
                      label: 'Copy report',
                      icon: Icons.copy_rounded,
                      expand: true,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: a.toText()));
                        if (context.mounted) showToast(context, 'Report copied. Paste it anywhere.', good: true);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Checked at ${fmtTime(a.createdAt)}${a.failed.isEmpty ? '' : '. Could not read: ${a.failed.join(', ')}'}.',
                      style: T.ui(12, color: C.muted, weight: FontWeight.w500),
                    ),
                  ] else if (app.auditing)
                    PaperCard(
                      child: Row(children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.crimson)),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Reading Health Connect for ${fmtDate(key, weekday: true)}…', style: T.ui(14, color: C.muted))),
                      ]),
                    ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.pref, required this.enabled, required this.onUse, required this.onAuto});
  final AuditSection section;
  final String? pref;
  final bool enabled;
  final ValueChanged<AuditRow> onUse;
  final VoidCallback onAuto;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final p = pref;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.title, style: T.display(26))),
          if (p != null) Text(p == 'auto' ? 'AUTO' : 'YOUR PICK', style: T.kicker(size: 11, color: p == 'auto' ? C.muted : C.crimson)),
        ]),
        const SizedBox(height: 4),
        if (s.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('Nothing in Health Connect for this day.', style: T.ui(14, color: C.muted)),
          )
        else
          for (var i = 0; i < s.rows.length; i++)
            _RowTile(
              row: s.rows[i],
              first: i == 0,
              tappable: s.pref != null && enabled,
              onTap: () => onUse(s.rows[i]),
            ),
        if (s.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(s.note, style: T.ui(12, color: C.muted, weight: FontWeight.w600, height: 1.4)),
          ),
        if (p != null && p != 'auto')
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Press(
              onTap: enabled ? onAuto : null,
              child: Text('Back to automatic', style: T.ui(13, color: C.crimson, weight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.first, required this.tappable, required this.onTap});
  final AuditRow row;
  final bool first, tappable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: C.rule))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(r.source, style: T.ui(15, weight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
              if (r.used) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(999)),
                  child: Text('USED', style: T.ui(11, color: C.card, weight: FontWeight.w800)),
                ),
              ],
            ]),
            if (r.detail.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(r.detail, style: T.ui(13, color: C.muted, weight: FontWeight.w500, height: 1.4)),
            ],
            if (tappable && !r.used) ...[
              const SizedBox(height: 4),
              Text('Tap to use this one', style: T.ui(12, color: C.crimson, weight: FontWeight.w800)),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Text(r.value, style: T.display(26, color: r.used ? C.ink : C.muted)),
      ]),
    );
    if (!tappable || r.used) return body;
    return Press(semantics: 'Use ${r.source}', onTap: onTap, child: body);
  }
}
