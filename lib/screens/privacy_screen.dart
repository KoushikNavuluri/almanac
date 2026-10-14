import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// What leaves the phone, what never does, and a live preview of the exact payload.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.sharing;
    final preview = app.contextPreview;
    final pretty = const JsonEncoder.withIndent('  ').convert(preview);
    final bytes = utf8.encode(jsonEncode(preview)).length;

    Widget toggle(String title, String sub, bool value, void Function(bool) set, {bool enabled = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: T.ui(15, weight: FontWeight.w800)),
                  Text(sub, style: T.ui(13, color: C.muted, weight: FontWeight.w500, height: 1.35)),
                ]),
              ),
              Switch(value: value && enabled, onChanged: enabled ? (v) => app.updateSharing((s) => set(v)) : null),
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const BackBar(title: 'Privacy & sharing'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('What leaves your phone.', style: T.display(48)),
                const SizedBox(height: 16),
                const _Fact(
                  icon: Icons.phone_android_rounded,
                  title: 'Stays here, always',
                  body: "Every raw reading, your meal history, chats, experiments and your API key. Kept in Almanac's private storage and excluded from cloud backups.",
                ),
                const _Fact(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Sent to Google Gemini, only when you use AI',
                  body: 'Daily summaries of the categories you allow below, your 30-day averages and a few computed patterns. No name, no account, no device IDs, no app names, no location.',
                ),
                const _Fact(
                  icon: Icons.block_rounded,
                  title: 'Never sent anywhere',
                  body: 'Raw heart-rate streams, individual readings with exact timestamps, which apps wrote your data, and anything you type in crisis-related messages.',
                ),
                const SizedBox(height: 18),
                const Kicker('You choose what Gemini sees', color: C.crimson),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.rule)),
                  child: Column(children: [
                    toggle('Sleep', 'Hours, stages, bed and wake times', p.sleep, (v) => p.sleep = v),
                    const Divider(height: 1),
                    toggle('Heart', 'HRV, resting heart rate, oxygen, breathing rate', p.heart, (v) => p.heart = v),
                    const Divider(height: 1),
                    toggle('Steps', 'Daily step totals', p.activity, (v) => p.activity = v),
                    const Divider(height: 1),
                    toggle('Meal times & macros', 'Calories, protein, last meal time, late caffeine yes/no', p.food, (v) => p.food = v),
                    const Divider(height: 1),
                    toggle('Meal names', 'e.g. "Chicken biryani". Off by default.', p.mealNames, (v) => p.mealNames = v, enabled: p.food),
                    const Divider(height: 1),
                    toggle('Body weight', 'Used for protein targets. Off by default.', p.profile, (v) => p.profile = v),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Text('Days included', style: T.ui(15, weight: FontWeight.w800))),
                  Segmented<int>(
                    value: p.days,
                    options: const {7: '7', 14: '14', 30: '30'},
                    onChanged: (v) => app.updateSharing((s) => s.days = v),
                    small: true,
                  ),
                ]),
                if (!p.anything) ...[
                  const SizedBox(height: 12),
                  const ErrorNote(message: 'With nothing shared, AI features stay off and everything is answered on this phone.'),
                ],
                const SizedBox(height: 26),
                Row(children: [
                  const Expanded(child: Kicker('Exactly what would be sent now', color: C.crimson)),
                  Text(bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB', style: T.ui(12, color: C.muted, weight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  width: double.infinity,
                  decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(18)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: SelectableText(pretty, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45, color: C.card)),
                  ),
                ),
                const SizedBox(height: 8),
                Press(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: pretty));
                    if (context.mounted) showToast(context, 'Payload copied');
                  },
                  child: Text('Copy payload', style: T.ui(14, color: C.crimson, weight: FontWeight.w800)),
                ),
                const SizedBox(height: 26),
                Row(children: [
                  const Expanded(child: Kicker('Recent AI requests')),
                  if (app.aiLog.isNotEmpty) Press(onTap: app.clearAiLog, child: Text('Clear', style: T.ui(13, color: C.crimson, weight: FontWeight.w800))),
                ]),
                const SizedBox(height: 8),
                if (app.aiLog.isEmpty)
                  Text('No requests yet. Nothing has been sent.', style: T.ui(14, color: C.muted))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.rule)),
                    child: Column(children: [
                      for (var i = 0; i < app.aiLog.length && i < 20; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            Icon(app.aiLog[i].ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 18, color: app.aiLog[i].ok ? C.teal : C.crimson),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${app.aiLog[i].purpose} · ${(app.aiLog[i].bytes / 1024).toStringAsFixed(1)} KB', style: T.ui(14, weight: FontWeight.w700)),
                                Text(
                                  '${fmtDate(isoDate(app.aiLog[i].time))}, ${fmtTime(app.aiLog[i].time)} · ${app.aiLog[i].model} · ${app.aiLog[i].categories.join(', ')}',
                                  style: T.ui(12, color: C.muted, weight: FontWeight.w500),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                const SizedBox(height: 22),
                const _Fact(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Health Connect access',
                  body: 'Almanac only reads. To change or revoke access, open Health Connect › App permissions › Almanac. Delete everything in Me removes Almanac\'s own copy.',
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: Color(0x12172767), shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: C.navy),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.ui(15, weight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(body, style: T.ui(14, color: C.ink, weight: FontWeight.w500, height: 1.45)),
          ]),
        ),
      ]),
    );
  }
}
