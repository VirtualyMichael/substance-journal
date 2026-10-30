import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/ui/toast.dart';

void main() {
  testWidgets('messages fade on their own even with an Undo, can be closed, and only important ones are logged', (tester) async {
    final logged = <String>[];
    activitySink = logged.add;
    addTearDown(() => activitySink = null);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }))));
    final messenger = ScaffoldMessenger.of(ctx);

    messenger.showToast(SnackBar(content: const Text('Logged Ketamine'), action: SnackBarAction(label: 'Undo', onPressed: () {})));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Logged Ketamine'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget); // can be closed by hand
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('Logged Ketamine'), findsNothing); // an Undo no longer keeps it on screen for ever

    messenger.showToast(const SnackBar(content: Text('Could not save the backup: disk full')));
    await tester.pump();
    messenger.showToast(const SnackBar(content: Text('Link copied')));
    await tester.pump();
    expect(logged, ['Could not save the backup: disk full']);
    expect(find.text('Could not save the backup: disk full'), findsNothing); // replaced, not stacked

  });
}
