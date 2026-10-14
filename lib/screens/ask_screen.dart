import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/chat_models.dart';
import '../ai/local_brain.dart';
import '../domain/metrics.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'ai_settings_screen.dart';
import 'metric_screen.dart';
import 'privacy_screen.dart';

class AskScreen extends StatefulWidget {
  const AskScreen({super.key});
  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;
  bool _lastBusy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(AppController app, [String? q]) {
    final text = (q ?? _input.text).trim();
    if (text.isEmpty || app.chatBusy) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    app.sendChat(text);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (motionOff(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.chat.length != _lastCount || app.chatBusy != _lastBusy) {
      _lastCount = app.chat.length;
      _lastBusy = app.chatBusy;
      _scrollToEnd();
    }
    final ins = app.insights;
    final top = MediaQuery.of(context).padding.top;
    ChatMessage? lastAi;
    for (final m in app.chat.reversed) {
      if (!m.isMe) {
        lastAi = m;
        break;
      }
    }
    final chips = app.chatBusy ? const <String>[] : (lastAi != null && lastAi.chips.isNotEmpty ? lastAi.chips : LocalBrain.starterChips);
    final score = ins.readiness();

    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(20, top + 20, 20, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Kicker('Ask', color: C.crimson),
              const SizedBox(height: 4),
              Text('The forecaster is in.', style: T.display(38)),
            ]),
          ),
          if (app.chat.isNotEmpty)
            Press(
              semantics: 'Clear conversation',
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Clear the conversation?'),
                    content: const Text('This deletes the chat history on this phone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
                    ],
                  ),
                );
                if (ok == true) app.clearChat();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.card, shape: BoxShape.circle, border: Border.all(color: C.rule)),
                child: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ),
        ]),
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          children: [
            _Bubble(
              text: "${_greeting()}. Today's ${ins.condition(score).label.toLowerCase()}. I've read ${app.records.length} days of your ${app.isSample ? 'sample ' : ''}data. Ask me anything, in plain words.",
            ),
            if (!app.aiReady) ...[
              const SizedBox(height: 10),
              PaperCard(
                color: const Color(0x14172767),
                border: false,
                padding: const EdgeInsets.all(14),
                onTap: () => Navigator.of(context).push(slideRoute(const AiSettingsScreen())),
                child: Row(children: [
                  const Icon(Icons.key_rounded, size: 18, color: C.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      app.hasKey ? 'AI answers are switched off. Turn them on in AI & your key.' : 'Answering from rules on this phone. Add your Gemini key for real AI answers.',
                      style: T.ui(14, color: C.navy, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ],
            for (final m in app.chat) ...[
              const SizedBox(height: 14),
              if (m.isMe) _MyBubble(m.text) else _AiMessage(m),
            ],
            if (app.chatBusy) ...[
              const SizedBox(height: 14),
              _Thinking(gemini: app.aiReady),
            ],
          ],
        ),
      ),
      Container(
        decoration: const BoxDecoration(color: C.paper, border: Border(top: BorderSide(color: C.rule))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (chips.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Press(
                        onTap: () => _send(app, c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.rule)),
                          child: Text(c, style: T.ui(14, color: C.navy, weight: FontWeight.w700)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(app),
                style: T.ui(16, weight: FontWeight.w500),
                decoration: const InputDecoration(hintText: 'Ask about sleep, heart, food…'),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (_, v, __) {
                final can = v.text.trim().isNotEmpty && !app.chatBusy;
                return Press(
                  semantics: 'Send',
                  onTap: can ? () => _send(app) : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: C.crimson, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_upward_rounded, color: C.card),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 8),
          Press(
            onTap: () => Navigator.of(context).push(slideRoute(const PrivacyScreen())),
            child: Text(
              app.aiReady
                  ? 'Gemini sees only what you share (${app.sharing.labels.join(', ')}). Not medical advice.'
                  : 'On-device answers. Nothing is sent anywhere. Not medical advice.',
              textAlign: TextAlign.center,
              style: T.ui(12, color: C.muted, weight: FontWeight.w500),
            ),
          ),
        ]),
      ),
    ]);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.card,
          border: Border.all(color: C.rule),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
        ),
        child: SelectableText(text, style: T.serif(16, height: 1.6)),
      );
}

class _MyBubble extends StatelessWidget {
  const _MyBubble(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: C.navy,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6)),
            ),
            child: Text(text, style: T.ui(15, color: C.card, weight: FontWeight.w700)),
          ),
        ),
      );
}

class _AiMessage extends StatelessWidget {
  const _AiMessage(this.m);
  final ChatMessage m;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Bubble(text: m.text),
      const SizedBox(height: 6),
      SourceBadge(gemini: m.source == 'gemini'),
      if (m.error != null) ...[
        const SizedBox(height: 8),
        ErrorNote(message: 'Gemini could not answer (${m.error}) This reply came from the phone instead.'),
      ],
      if (m.help != null) ...[
        const SizedBox(height: 10),
        HelpCard(emergency: m.help == 'emergency'),
      ],
      if (m.metric != null && metrics.containsKey(m.metric)) ...[
        const SizedBox(height: 10),
        _MetricMini(metric: m.metric!, app: app),
      ],
      if (m.experiment != null && experiments.containsKey(m.experiment)) ...[
        const SizedBox(height: 10),
        ExperimentCard(id: m.experiment!),
      ],
    ]);
  }
}

class _MetricMini extends StatelessWidget {
  const _MetricMini({required this.metric, required this.app});
  final String metric;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final info = metrics[metric]!;
    final ins = app.insights;
    final r = ins.reading(metric);
    final vals = app.records.length > 30 ? app.records.sublist(app.records.length - 30) : app.records;
    return PaperCard(
      onTap: () => Navigator.of(context).push(slideRoute(MetricScreen(metricKey: metric))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Kicker(info.name),
            const SizedBox(height: 4),
            Text('${fmtValue(metric, r?.value)}${info.unit.isNotEmpty ? ' ${info.unit}' : ''}', style: T.display(34)),
            const SizedBox(height: 4),
            StatusChip(ins.status(metric)),
          ]),
        ),
        Sparkline(values: vals.map((d) => d.value(metric)).toList(), color: C.group(info.group)),
      ]),
    );
  }
}

class _Thinking extends StatefulWidget {
  const _Thinking({required this.gemini});
  final bool gemini;
  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  int _at = 0;
  Timer? _t;

  List<String> get _steps => widget.gemini
      ? const ['Picking only what you share', 'Asking Gemini about your data', 'Writing it plainly']
      : const ['Reading your data on this phone', 'Comparing with your normal', 'Writing it plainly'];

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted && _at < _steps.length - 1) setState(() => _at++);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      child: Column(children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Opacity(
              opacity: i > _at ? 0.35 : 1,
              child: Row(children: [
                if (i < _at)
                  const Icon(Icons.check_rounded, size: 16, color: C.teal)
                else
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.crimson)),
                const SizedBox(width: 10),
                Expanded(child: Text(_steps[i], style: T.ui(14, color: i == _at ? C.crimson : C.ink, weight: FontWeight.w700))),
              ]),
            ),
          ),
      ]),
    );
  }
}
