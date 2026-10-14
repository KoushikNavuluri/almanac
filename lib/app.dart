import 'package:flutter/material.dart';

import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'state/app_controller.dart';
import 'theme/tokens.dart';

class AlmanacApp extends StatelessWidget {
  const AlmanacApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Almanac',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget child;
    if (!app.loaded) {
      child = const _Splash();
    } else if (!app.onboarded) {
      child = const OnboardingScreen();
    } else {
      child = const Shell();
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child));
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.navy,
        body: Center(child: Text('Almanac', style: T.display(56, color: C.card).copyWith(letterSpacing: 2))),
      );
}
