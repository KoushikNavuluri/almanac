import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'almanac_screen.dart';
import 'ask_screen.dart';
import 'discover_screen.dart';
import 'me_screen.dart';
import 'today_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppScope.read(context).onResume();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final style = app.tab == 0
        ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Scaffold(
        backgroundColor: C.paper,
        body: IndexedStack(
          index: app.tab,
          children: const [TodayScreen(), DiscoverScreen(), AskScreen(), AlmanacScreen(), MeScreen()],
        ),
        bottomNavigationBar: const _NavBar(),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar();

  static const _items = [
    (Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Today'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Discover'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Ask'),
    (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Almanac'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      decoration: const BoxDecoration(color: C.paper, border: Border(top: BorderSide(color: C.rule))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: Press(
                  semantics: _items[i].$3,
                  onTap: () => app.setTab(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: 56,
                      height: 32,
                      decoration: BoxDecoration(
                        color: app.tab == i ? C.crimson.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(app.tab == i ? _items[i].$2 : _items[i].$1, size: 22, color: app.tab == i ? C.crimson : C.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(_items[i].$3, style: T.ui(12, color: app.tab == i ? C.crimson : C.muted, weight: FontWeight.w800)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
