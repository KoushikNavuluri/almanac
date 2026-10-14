import 'package:flutter/material.dart';

import '../domain/metrics.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'metric_screen.dart';

class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({super.key, required this.id});
  final String id;
  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  int _confetti = 0;
  bool? _wasDone;

  Future<void> _askDay(AppController app, String date, String question) async {
    final kept = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: C.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Kicker(fmtDate(date, weekday: true)),
            const SizedBox(height: 6),
            Text(question, style: T.display(30)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Pill(label: 'Yes, done', bg: C.teal, expand: true, onTap: () => Navigator.pop(c, true))),
              const SizedBox(width: 10),
              Expanded(child: Pill(label: 'Not that day', bg: const Color(0x14172767), fg: C.navy, expand: true, onTap: () => Navigator.pop(c, false))),
            ]),
          ]),
        ),
      ),
    );
    if (kept == null) return;
    app.checkIn(widget.id, date, kept);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ins = app.insights;
    final info = experiments[widget.id]!;
    final run = app.runs[widget.id];
    final prog = run == null ? null : ins.progress(run);
    final impact = ins.experimentImpact(widget.id);
    final done = prog?.done ?? false;

    final was = _wasDone;
    _wasDone = done;
    if (was == false && done && prog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _confetti++);
        showToast(context, 'Experiment complete: kept ${prog.kept} of ${info.days} days', good: true);
      });
    }

    final metricInfo = metrics[info.metric]!;
    return Scaffold(
      backgroundColor: C.paper,
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const BackBar(title: '7-day experiment'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.science_outlined, size: 18, color: C.crimson),
                    const SizedBox(width: 6),
                    Kicker(done ? 'Finished' : run != null ? 'Running' : 'Ready when you are', color: C.crimson),
                  ]),
                  const SizedBox(height: 8),
                  Text(info.title, style: T.display(58, height: 0.88)),
                  const SizedBox(height: 12),
                  Text(info.why, style: T.serif(17, height: 1.6)),
                  const SizedBox(height: 18),
                  PaperCard(
                    color: C.navy,
                    border: false,
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Kicker('What your data predicts', color: C.sun),
                      const SizedBox(height: 6),
                      if (impact != null)
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('+${impact.delta}', style: T.display(64, color: C.card, height: 0.85)),
                          const SizedBox(width: 10),
                          Expanded(child: Text('${impact.unit}\non nights you stick to it', style: T.ui(15, color: C.card, weight: FontWeight.w800))),
                        ])
                      else
                        Text('Not enough history to predict yet. Run it anyway and the week will tell you.', style: T.ui(15, color: C.card, height: 1.4)),
                      const SizedBox(height: 8),
                      Text('From your own past days. Tracked metric: ${metricInfo.name}.', style: T.ui(13, color: C.card.withValues(alpha: 0.8), weight: FontWeight.w500)),
                    ]),
                  ),
                  if (run == null) ...[
                    const SizedBox(height: 22),
                    Pill(
                      label: 'Start the 7 days',
                      bg: C.crimson,
                      height: 56,
                      expand: true,
                      onTap: () {
                        app.startExperiment(widget.id);
                        showToast(context, 'Experiment started: ${info.title}', good: true);
                      },
                    ),
                  ],
                  if (run != null && prog != null) ...[
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(child: Text('The week', style: T.display(30))),
                      Text('${prog.kept} of ${prog.answered} kept', style: T.ui(13, color: C.muted, weight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < prog.dates.length; i++)
                          _DayDot(
                            index: i,
                            value: run.checkins[prog.dates[i]],
                            isToday: i == prog.todayIndex && !done,
                            future: i > prog.todayIndex,
                            onTap: i <= prog.todayIndex ? () => _askDay(app, prog.dates[i], info.question) : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (!done && prog.todayIndex < prog.dates.length)
                      _TodayCheckIn(
                        date: prog.dates[prog.todayIndex],
                        day: prog.todayIndex + 1,
                        answer: run.checkins[prog.dates[prog.todayIndex]],
                        question: info.question,
                        onAnswer: (v) {
                          app.checkIn(widget.id, prog.dates[prog.todayIndex], v);
                          showToast(context, v ? 'Day ${prog.todayIndex + 1} kept. Tomorrow\'s forecast will show it.' : 'Logged. Tomorrow is a fresh day.', good: v);
                        },
                      ),
                    if (done)
                      PaperCard(
                        color: C.sun,
                        border: false,
                        padding: const EdgeInsets.all(20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Kicker('Result', color: C.navy),
                          const SizedBox(height: 6),
                          Text('You kept it ${prog.kept} of ${info.days} days.', style: T.display(40, height: 0.92)),
                          const SizedBox(height: 10),
                          if (prog.measured != null && prog.baseline != null) ...[
                            Builder(builder: (_) {
                              final d = prog.measured! - prog.baseline!;
                              final better = metricInfo.lowerIsBetter ? d < 0 : d > 0;
                              final amount = info.metric == 'sleepMin' ? '${d.abs().round()} min' : '${d.abs().round()} ${metricInfo.unit}';
                              return Text(
                                '${better ? '+' : '−'}$amount ${metricInfo.name.toLowerCase()} on the nights after kept days, vs the 30 days before you started (${prog.nights} nights measured).',
                                style: T.ui(15, weight: FontWeight.w700, height: 1.45),
                              );
                            }),
                          ] else
                            Text('Sync a few more nights and the effect on your ${metricInfo.name.toLowerCase()} shows up here.', style: T.ui(15, weight: FontWeight.w600, height: 1.45)),
                          const SizedBox(height: 14),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            Pill(
                              label: 'See ${metricInfo.name.toLowerCase()}',
                              onTap: () => Navigator.of(context).push(slideRoute(MetricScreen(metricKey: info.metric))),
                            ),
                            Pill(
                              label: 'Run it again',
                              bg: C.card,
                              fg: C.navy,
                              onTap: () {
                                app.stopExperiment(widget.id);
                                app.startExperiment(widget.id);
                                _wasDone = false;
                                showToast(context, 'New week started', good: true);
                              },
                            ),
                          ]),
                        ]),
                      ),
                    const SizedBox(height: 22),
                    Center(
                      child: Press(
                        onTap: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: Text(done ? 'Clear this experiment?' : 'Stop this experiment?'),
                              content: const Text('Your check-ins for this week will be removed.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
                                TextButton(onPressed: () => Navigator.pop(c, true), child: Text(done ? 'Clear' : 'Stop')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          app.stopExperiment(widget.id);
                          if (context.mounted) Navigator.of(context).maybePop();
                        },
                        child: Text(
                          done ? 'Clear and run it again later' : 'Stop this experiment',
                          style: T.ui(14, color: C.muted, weight: FontWeight.w700).copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ],
          ),
        ),
        Positioned.fill(child: ConfettiBurst(trigger: _confetti)),
      ]),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.index, required this.value, required this.isToday, required this.future, this.onTap});
  final int index;
  final bool? value;
  final bool isToday, future;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.transparent;
    Color fg = C.muted;
    BoxBorder? border;
    Widget child = Text('${index + 1}', style: T.ui(14, color: fg, weight: FontWeight.w800));
    if (value == true) {
      bg = C.teal;
      child = const Icon(Icons.check_rounded, size: 20, color: C.card);
    } else if (value == false) {
      bg = C.coral.withValues(alpha: 0.2);
      child = const Icon(Icons.close_rounded, size: 18, color: C.crimson);
    } else if (isToday) {
      bg = C.card;
      border = Border.all(color: C.crimson, width: 2);
      child = Text('${index + 1}', style: T.ui(14, color: C.crimson, weight: FontWeight.w800));
    } else if (!future) {
      border = Border.all(color: C.amber, width: 2);
      child = Text('?', style: T.ui(14, color: C.amberInk, weight: FontWeight.w800));
    } else {
      border = Border.all(color: C.rule, width: 2);
    }
    final label = value == true ? 'kept' : value == false ? 'missed' : isToday ? 'today' : future ? 'upcoming' : 'not answered, tap to log';
    return Press(
      semantics: 'Day ${index + 1}: $label',
      onTap: onTap,
      child: Column(children: [
        Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: border), child: child),
        const SizedBox(height: 6),
        Text('D${index + 1}', style: T.ui(12, color: C.muted)),
      ]),
    );
  }
}

class _TodayCheckIn extends StatelessWidget {
  const _TodayCheckIn({required this.date, required this.day, required this.answer, required this.question, required this.onAnswer});
  final String date;
  final int day;
  final bool? answer;
  final String question;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Kicker('Check in · day $day'),
        const SizedBox(height: 6),
        if (answer == null) ...[
          Text(question, style: T.display(30, height: 0.95)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Pill(label: 'Yes, done', bg: C.teal, expand: true, onTap: () => onAnswer(true))),
            const SizedBox(width: 10),
            Expanded(child: Pill(label: 'Not today', bg: const Color(0x14172767), fg: C.navy, expand: true, onTap: () => onAnswer(false))),
          ]),
          const SizedBox(height: 10),
          Text('Best answered in the evening. Tap any earlier day above to fill it in.', style: T.ui(13, color: C.muted)),
        ] else ...[
          Text(answer! ? 'Kept today. Nice.' : 'Logged as missed.', style: T.display(30, height: 0.95)),
          const SizedBox(height: 8),
          Text('Come back tomorrow for day ${day + 1}. Changed your mind?', style: T.ui(14, color: C.muted)),
          const SizedBox(height: 8),
          Press(
            onTap: () => onAnswer(!answer!),
            child: Text(answer! ? 'Mark today as missed' : 'Mark today as kept', style: T.ui(14, color: C.crimson, weight: FontWeight.w800)),
          ),
        ],
      ]),
    );
  }
}
