import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/reagent_tests.dart';
import '../../providers.dart';
import '../design.dart';
import '../link_tile.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// Chart pages to compare colours against. Charts differ by brand and change over time, so the app
/// points to current ones instead of baking colours in.
const chartLinks = [
  ('DanceSafe: testing kit instructions', 'How to test, what each reagent is for and how to read the colours.', 'https://dancesafe.org/testing-kit-instructions/'),
  ('NUAA: colour charts and chemistry', 'Reaction charts and the chemistry behind them.', 'https://testkits.nuaa.org.au/pages/charts'),
  ('Wikipedia: reagent testing colour charts', 'A list of published charts to compare.', 'https://en.wikipedia.org/wiki/List_of_reagent_testing_color_charts'),
];

/// The drug-checking log: samples, the reagent and strip tests done on them, and what they showed.
/// It records what you saw and concluded. It never says a sample is safe.
class TestingPage extends ConsumerWidget {
  const TestingPage({super.key, this.substanceKey});

  /// Compound to start a new test with.
  final String? substanceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samples = ref.watch(samplesProvider).value ?? const <Product>[];
    final tests = ref.watch(reagentTestsProvider).value ?? const <ReagentTest>[];
    final catalog = ref.watch(catalogProvider);
    final text = Theme.of(context).textTheme;
    // Strains of cannabis are products too; only show them here once they have a test.
    final withTests = {for (final t in tests) t.productId};
    final shown = [for (final p in samples) if (p.substanceKey != 'cannabis' || withTests.contains(p.id)) p];

    return Scaffold(
      appBar: AppBar(title: const Text('Drug checking log')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-test'),
        icon: const Icon(Icons.science_outlined),
        label: const Text('Test a sample'),
        onPressed: () => openTestEditor(context, substanceKey: substanceKey),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 96),
            children: [
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What testing can and cannot tell you', style: text.titleSmall),
                      const SizedBox(height: 4),
                      const Text(
                        'Reagents and strips are quick screens. They can show some expected or unexpected substances, but not purity, dose '
                        'or everything else a sample could contain, and colours are read by eye. A clean result is never proof of safety. '
                        'A test strip only looks for one thing.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.sm),
              Text('Compare your result with a current chart', style: text.titleSmall),
              for (final (title, description, url) in chartLinks) LinkTile(url, label: title, description: description),
              const SizedBox(height: Gap.md),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.lg),
                  child: Text(
                    'No samples yet. Tap Test a sample to log a reagent or strip result. It will then show up when you log that sample.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                )
              else
                for (final p in shown) _SampleCard(sample: p, tests: tests, compound: catalog.byKey[p.substanceKey]?.name ?? p.substanceKey),
            ],
          ),
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, SampleStatus s) {
  final scheme = Theme.of(context).colorScheme;
  return switch (s) {
    SampleStatus.flagged => scheme.errorContainer,
    SampleStatus.checked => scheme.secondaryContainer,
    SampleStatus.untested => scheme.surfaceContainerHighest,
  };
}

class _SampleCard extends ConsumerWidget {
  const _SampleCard({required this.sample, required this.tests, required this.compound});

  final Product sample;
  final List<ReagentTest> tests;
  final String compound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = SampleSummary.of(tests, sample.id);
    final text = Theme.of(context).textTheme;
    return Card(
      key: ValueKey('sample-${sample.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(sample.name, style: text.titleMedium)),
                Text(compound, style: text.labelMedium),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Container(
              key: ValueKey('status-${sample.id}'),
              padding: const EdgeInsets.all(Gap.sm),
              decoration: BoxDecoration(color: _statusColor(context, summary.status), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary.headline, style: text.titleSmall),
                  Text(summary.caution, style: text.bodySmall),
                ],
              ),
            ),
            for (final t in summary.tests)
              ListTile(
                key: ValueKey('test-${t.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(describeTest(t)),
                subtitle: Text([_date(t.testedAt), if (t.notes.isNotEmpty) t.notes].join(' · ')),
                trailing: IconButton(
                  tooltip: 'Remove this test',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final db = ref.read(databaseProvider);
                    await db.setReagentTestDeleted(t.id, true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Test removed'),
                        action: SnackBarAction(label: 'Undo', onPressed: () => db.setReagentTestDeleted(t.id, false)),
                      ));
                    }
                  },
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('add-test-${sample.id}'),
                icon: const Icon(Icons.add),
                label: const Text('Add a test'),
                onPressed: () => openTestEditor(context, sample: sample),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openTestEditor(BuildContext context, {Product? sample, String? substanceKey}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => TestEditorPage(sample: sample, substanceKey: substanceKey)));

/// Adds one test to an existing sample, or starts a new sample with its first test.
class TestEditorPage extends ConsumerStatefulWidget {
  const TestEditorPage({super.key, this.sample, this.substanceKey});

  final Product? sample;
  final String? substanceKey;

  @override
  ConsumerState<TestEditorPage> createState() => _TestEditorPageState();
}

class _TestEditorPageState extends ConsumerState<TestEditorPage> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  String? _compound;
  String _reagent = reagentNames.first;
  String? _initial, _final;
  TestOutcome? _outcome;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _compound = widget.sample?.substanceKey ?? widget.substanceKey;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _strip => isStrip(_reagent);

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final existing = widget.sample;
    final compound = _compound;
    if (existing == null && _name.text.trim().isEmpty) return setState(() => _error = 'Give the sample a name, such as "pink pill" or "Saturday powder".');
    if (compound == null) return setState(() => _error = 'Choose what it is supposed to be.');
    final outcome = _outcome;
    if (outcome == null) return setState(() => _error = _strip ? 'Choose what the strip showed.' : 'Choose how it compared with the chart.');
    setState(() => _saving = true);
    final sample = existing ?? await db.addProduct(substanceKey: compound, name: _name.text);
    await db.addReagentTest(
      productId: sample.id,
      substanceKey: sample.substanceKey,
      testedAt: ref.read(clockProvider)(),
      kind: _strip ? 'strip' : 'reagent',
      reagent: _reagent,
      initialColor: _strip ? '' : (_initial ?? ''),
      finalColor: _strip ? '' : (_final ?? ''),
      outcome: outcome.key,
      notes: _notes.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _chips(String keyPrefix, List<String> options, String? selected, void Function(String?) onSelect) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final o in options)
            ChoiceChip(
              key: ValueKey('$keyPrefix-$o'),
              label: Text(o),
              selected: selected == o,
              onSelected: (v) => setState(() => onSelect(v ? o : null)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final text = Theme.of(context).textTheme;
    final compoundName = _compound == null ? null : catalog.byKey[_compound]?.name;
    final suggestions = _compound == null ? const <String>[] : suggestedTests(_compound!);
    final outcomes = _strip ? const [TestOutcome.positive, TestOutcome.negative, TestOutcome.invalid] : const [TestOutcome.matched, TestOutcome.unmatched, TestOutcome.unclear];
    final all = [...catalog.substances]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: Text(widget.sample == null ? 'Test a sample' : 'Add a test to ${widget.sample!.name}')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              if (widget.sample == null) ...[
                TextField(
                  key: const ValueKey('sample-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Sample name', helperText: 'Something that tells this sample apart from the next one'),
                ),
                const SizedBox(height: Gap.md),
                DropdownMenu<String>(
                  key: const ValueKey('sample-compound'),
                  width: 320,
                  label: const Text('It is supposed to be'),
                  enableFilter: true,
                  requestFocusOnTap: true,
                  initialSelection: _compound,
                  dropdownMenuEntries: [for (final s in all) DropdownMenuEntry(value: s.key, label: s.name)],
                  onSelected: (v) => setState(() => _compound = v),
                ),
                const SizedBox(height: Gap.md),
              ],
              DropdownButtonFormField<String>(
                key: const ValueKey('test-reagent'),
                initialValue: _reagent,
                decoration: const InputDecoration(labelText: 'Test'),
                items: [
                  for (final r in [...reagentNames, ...stripNames]) DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) => setState(() {
                  _reagent = v ?? _reagent;
                  _outcome = null;
                }),
              ),
              if (suggestions.isNotEmpty && compoundName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Often used for $compoundName: ${suggestions.join(', ')}. Use more than one test where you can, and check a current chart.',
                    key: const ValueKey('suggested-tests'),
                    style: text.bodySmall,
                  ),
                ),
              const SizedBox(height: Gap.md),
              if (!_strip) ...[
                Text('Colour straight away', style: text.titleSmall),
                const SizedBox(height: 4),
                _chips('initial', reagentColors, _initial, (v) => _initial = v),
                const SizedBox(height: Gap.md),
                Text('Colour after about a minute (if it changed)', style: text.titleSmall),
                const SizedBox(height: 4),
                _chips('final', reagentColors, _final, (v) => _final = v),
                const SizedBox(height: Gap.md),
              ],
              Text(_strip ? 'What the strip showed' : 'Compared with a current chart for this compound', style: text.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final o in outcomes)
                    ChoiceChip(
                      key: ValueKey('outcome-${o.key}'),
                      label: Text(o.label),
                      selected: _outcome == o,
                      onSelected: (v) => setState(() => _outcome = v ? o : null),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _strip
                    ? 'A positive means that substance was detected. A negative only means this strip did not detect it.'
                    : 'Colour charts differ by brand and change over time. If you are not sure it matched, choose Unclear.',
                style: text.bodySmall,
              ),
              const SizedBox(height: Gap.md),
              TextField(
                key: const ValueKey('test-notes'),
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)', helperText: 'Brand of kit, how much you used, anything odd'),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: Gap.sm), child: Text(_error!, key: const ValueKey('test-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: Gap.md),
              FilledButton(key: const ValueKey('test-save'), onPressed: _saving ? null : _save, child: const Text('Save test')),
            ],
          ),
        ),
      ),
    );
  }
}
