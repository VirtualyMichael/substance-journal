import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'ui/design.dart';
import 'ui/lock/lock_gate.dart';
import 'ui/shell.dart';

class SubstanceJournalApp extends ConsumerStatefulWidget {
  const SubstanceJournalApp({super.key});

  @override
  ConsumerState<SubstanceJournalApp> createState() => _SubstanceJournalAppState();
}

class _SubstanceJournalAppState extends ConsumerState<SubstanceJournalApp> {
  Timer? _timer;
  double _hue = 210;

  /// The rainbow accent steps slowly and the theme fades between steps, so it costs a
  /// repaint every few seconds rather than a constant animation.
  static const _step = Duration(seconds: 3);

  void _syncTimer(bool rainbow) {
    if (rainbow && _timer == null) {
      _timer = Timer.periodic(_step, (_) => setState(() => _hue = (_hue + 14) % 360));
    } else if (!rainbow && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final rainbow = ref.watch(rainbowAccentProvider).value ?? false;
    final accent = ref.watch(accentColorProvider).value;
    _syncTimer(rainbow);
    final seed = rainbow ? HSLColor.fromAHSL(1, _hue, 0.65, 0.5).toColor() : (accent ?? const Color(0xFF4F7CAC));
    return MaterialApp(
      title: 'Substance Journal',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, seed: seed),
      darkTheme: buildTheme(Brightness.dark, seed: seed),
      themeMode: themeMode,
      themeAnimationDuration: rainbow ? _step : kThemeAnimationDuration,
      builder: (context, child) => LockGate(child: child ?? const SizedBox.shrink()),
      home: const AppShell(),
    );
  }
}
