import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/sky.dart';
import 'ai_settings_screen.dart';
import 'connect_flow.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    final ok = await connectHealthFlow(context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _step = 1;
    });
  }

  void _sample() {
    AppScope.read(context).useSampleData();
    setState(() => _step = 1);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: C.navy,
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkyView(
            score: 70,
            condition: 'partly',
            height: 340 + top,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, top + 16, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('Almanac', style: T.display(26, color: C.card).copyWith(letterSpacing: 1.6)),
                const SizedBox(height: 8),
                Text(_step == 0 ? 'Your body\nhas weather.' : 'Want it in\nplain words?', style: T.display(64, color: C.card, height: 0.86)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _step == 0 ? _intro() : _aiStep(app),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _point(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: C.card.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: C.sun),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.ui(15, color: C.card, weight: FontWeight.w800)),
              Text(sub, style: T.ui(13, color: C.card.withValues(alpha: 0.75), weight: FontWeight.w500)),
            ]),
          ),
        ]),
      );

  Widget _intro() {
    return Column(key: const ValueKey('intro'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        "Almanac reads your tracker and meal-log data from Health Connect every morning and tells you what it means, in plain words.",
        style: T.serif(17, color: C.card.withValues(alpha: 0.92), height: 1.55),
      ),
      const SizedBox(height: 22),
      _point(Icons.phone_android_rounded, 'Stays on your phone', 'Readings are stored and analysed on-device'),
      _point(Icons.no_accounts_outlined, 'No account, no sign-up', 'Open it and go'),
      _point(Icons.auto_awesome, 'AI with your own Gemini key', 'Optional. You choose what it sees'),
      const SizedBox(height: 18),
      Pill(label: 'Connect Health Connect', icon: Icons.link_rounded, bg: C.crimson, expand: true, height: 56, busy: _busy, onTap: _connect),
      const SizedBox(height: 12),
      Center(
        child: Press(
          onTap: _busy ? null : _sample,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text('Explore with sample data first', style: T.ui(15, color: C.sun, weight: FontWeight.w800)),
          ),
        ),
      ),
    ]);
  }

  Widget _aiStep(AppController app) {
    return Column(key: const ValueKey('ai'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Add a Google Gemini API key and the forecaster writes your daily note, explains every metric and answers questions about your own data. Only the summaries you allow are sent.',
        style: T.serif(17, color: C.card.withValues(alpha: 0.92), height: 1.55),
      ),
      const SizedBox(height: 14),
      Text('Without a key, everything still works using on-device rules.', style: T.ui(14, color: C.card.withValues(alpha: 0.75), weight: FontWeight.w500)),
      const SizedBox(height: 24),
      Pill(
        label: app.hasKey ? 'Key added · continue' : 'Add my Gemini key',
        icon: app.hasKey ? Icons.check_rounded : Icons.key_rounded,
        bg: C.crimson,
        expand: true,
        height: 56,
        onTap: () async {
          if (!app.hasKey) {
            await Navigator.of(context).push(slideRoute(const AiSettingsScreen()));
          }
          if (!mounted) return;
          app.finishOnboarding();
        },
      ),
      const SizedBox(height: 12),
      Center(
        child: Press(
          onTap: app.finishOnboarding,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text('Maybe later', style: T.ui(15, color: C.sun, weight: FontWeight.w800)),
          ),
        ),
      ),
    ]);
  }
}
