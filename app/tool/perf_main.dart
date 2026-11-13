// Frame-time probe: a throwaway in-memory journal with a long history, the flow background on,
// and the live session page opened. Run:  flutter run -d windows --profile -t tool/perf_main.dart
import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:substance_journal_app/app.dart';
import 'package:substance_journal_app/data/background_config.dart';
import 'package:substance_journal_app/data/database.dart';
import 'package:substance_journal_app/data/reference_repository.dart';
import 'package:substance_journal_app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final reference = await ReferenceRepository.load();
  final db = AppDatabase.memory();
  final me = await db.ensureDefaultPerson();
  final now = DateTime.now();
  for (var d = 1; d <= 150; d++) {
    final day = now.subtract(Duration(days: d * 2 + 1));
    final e = await db.addExperience(personId: me.id, sortDate: day, title: 'Night $d');
    for (var k = 0; k < 5; k++) {
      await db.addIngestion(experience: e, substanceKey: 'alcohol', route: 'oral', time: day.add(Duration(minutes: 25 * k)), dose: 14, unit: 'g');
      await db.addIngestion(experience: e, substanceKey: 'cannabis', route: 'smoked', time: day.add(Duration(minutes: 25 * k)), dose: 5, unit: 'mg');
    }
  }
  final live = await db.addExperience(personId: me.id, sortDate: now.subtract(const Duration(hours: 4)), title: 'Live session');
  for (var k = 0; k < 6; k++) {
    await db.addIngestion(experience: live, substanceKey: 'alcohol', route: 'oral', time: now.subtract(Duration(minutes: 200 - 25 * k)), dose: 14, unit: 'g');
    await db.addIngestion(experience: live, substanceKey: 'cannabis', route: 'smoked', time: now.subtract(Duration(minutes: 190 - 30 * k)), dose: 5, unit: 'mg');
  }
  await db.setSetting('background', const BackgroundConfig(mode: BackgroundMode.flow).encode());

  final build = <double>[];
  final raster = <double>[];
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> t) {
    for (final f in t) {
      build.add(f.buildDuration.inMicroseconds / 1000);
      raster.add(f.rasterDuration.inMicroseconds / 1000);
    }
  });
  String stats(List<double> v) {
    if (v.isEmpty) return '-';
    final s = [...v]..sort();
    return 'avg ${(v.reduce((a, b) => a + b) / v.length).toStringAsFixed(1)} p95 ${s[(s.length * .95).floor().clamp(0, s.length - 1)].toStringAsFixed(1)} max ${s.last.toStringAsFixed(1)}';
  }

  var phase = 'journal list';
  Timer.periodic(const Duration(seconds: 4), (_) {
    // ignore: avoid_print
    print('PERF [$phase] frames=${build.length} build(ms) ${stats(build)} | raster(ms) ${stats(raster)}');
    build.clear();
    raster.clear();
  });
  Timer(const Duration(seconds: 9), () {
    phase = 'session page';
    void visit(Element e) {
      if (e.widget is Text && (e.widget as Text).data == 'Live session') {
        e.visitAncestorElements((a) {
          final w = a.widget;
          if (w is ListTile && w.onTap != null) {
            w.onTap!();
            return false;
          }
          if (w is InkWell && w.onTap != null) {
            w.onTap!();
            return false;
          }
          return true;
        });
        return;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  });

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      referenceProvider.overrideWithValue(reference),
      interactionPairsProvider.overrideWithValue(reference.interactionPairs),
    ],
    child: const SubstanceJournalApp(),
  ));
}
