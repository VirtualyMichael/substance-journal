import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/providers.dart';

void main() {
  testWidgets('now moves on after the timer and after the app resumes', (tester) async {
    var clock = DateTime(2026, 1, 1, 12);
    final container = ProviderContainer(overrides: [clockProvider.overrideWithValue(() => clock)]);
    final seen = <DateTime>[];
    container.listen(nowProvider, (_, n) => seen.add(n), fireImmediately: true);
    expect(seen.last, DateTime(2026, 1, 1, 12));

    clock = DateTime(2026, 1, 1, 12, 5);
    await tester.pump(const Duration(seconds: 31));
    expect(seen.last, DateTime(2026, 1, 1, 12, 5));

    clock = DateTime(2026, 1, 1, 18);
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(seen.last, DateTime(2026, 1, 1, 18));
    container.dispose();
  });
}
