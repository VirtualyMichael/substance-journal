import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:sj_core/sj_core.dart';

import 'data/database.dart';
import 'data/reference_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final reference = await ReferenceRepository.load();
  final file = await defaultDatabaseFile();
  await file.parent.create(recursive: true);
  final db = AppDatabase(NativeDatabase.createInBackground(file), deviceId: newId());
  runApp(SubstanceJournalApp(reference: reference, db: db));
}

class SubstanceJournalApp extends StatelessWidget {
  const SubstanceJournalApp({super.key, required this.reference, required this.db});

  final ReferenceRepository reference;
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Substance Journal',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F7CAC), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F7CAC),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: CompoundPickerPage(reference: reference),
    );
  }
}

/// Phase 1 smoke screen: proves bundled reference data loads and the compound ordering works.
class CompoundPickerPage extends StatefulWidget {
  const CompoundPickerPage({super.key, required this.reference, this.usage = const {}});

  final ReferenceRepository reference;
  final Map<String, UsageStat> usage;

  @override
  State<CompoundPickerPage> createState() => _CompoundPickerPageState();
}

class _CompoundPickerPageState extends State<CompoundPickerPage> {
  String _query = '';
  CompoundSort _sort = CompoundSort.mostUsed;

  @override
  Widget build(BuildContext context) {
    final compounds = orderCompounds(
      all: widget.reference.substances,
      usage: widget.usage,
      query: _query,
      sort: _sort,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Compounds')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search compounds',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<CompoundSort>(
                  value: _sort,
                  onChanged: (value) => setState(() => _sort = value ?? _sort),
                  items: const [
                    DropdownMenuItem(value: CompoundSort.mostUsed, child: Text('Most used')),
                    DropdownMenuItem(value: CompoundSort.recent, child: Text('Recent')),
                    DropdownMenuItem(value: CompoundSort.alphabetical, child: Text('A-Z')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final s in compounds)
                  ListTile(
                    title: Text(s.name),
                    subtitle: Text(s.category, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('${s.roas.length} routes'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
