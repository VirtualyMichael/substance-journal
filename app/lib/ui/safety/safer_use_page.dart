import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../providers.dart';
import '../design.dart';
import '../testing/testing_page.dart';
import 'research_page.dart';

/// Harm-reduction basics and a combination checker. The checker only repeats what the bundled
/// references (TripSit's combination chart and PsychonautWiki's interaction lists) say, and says
/// so: no entry never means safe.
class SaferUsePage extends ConsumerStatefulWidget {
  const SaferUsePage({super.key, this.initialA, this.initialB});

  /// Compounds to start with (for tests and deep links).
  final String? initialA;
  final String? initialB;

  @override
  ConsumerState<SaferUsePage> createState() => _SaferUsePageState();
}

class _SaferUsePageState extends ConsumerState<SaferUsePage> {
  Substance? _a, _b;
  bool _seeded = false;
  List<Substance> _all = const [];
  List<Substance>? _sortedFrom;

  @override
  Widget build(BuildContext context) {
    final reference = ref.watch(catalogProvider);
    final text = Theme.of(context).textTheme;
    if (!_seeded) {
      _seeded = true;
      _a = reference.byKey[widget.initialA];
      _b = reference.byKey[widget.initialB];
    }
    // Sorted once per catalog, not on every rebuild.
    if (!identical(_sortedFrom, reference.substances)) {
      _sortedFrom = reference.substances;
      _all = [...reference.substances]..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
    }

    Widget picker(String key, String label, Substance? value, void Function(Substance?) onChanged) => SizedBox(
          width: 280,
          child: InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final chosen = await showDialog<Substance>(context: context, builder: (_) => _CompoundSearchDialog(title: label, all: _all));
              if (chosen != null) setState(() => onChanged(chosen));
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.arrow_drop_down)),
              child: Text(value?.name ?? 'Choose...'),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Safer use')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text('Check a combination', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('Pick two compounds to see what the bundled references say about using them together.', style: text.bodySmall),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  picker('combo-a', 'First compound', _a, (s) => _a = s),
                  picker('combo-b', 'Second compound', _b, (s) => _b = s),
                ],
              ),
              const SizedBox(height: Gap.md),
              if (_a != null && _b != null) _ComboResult(a: _a!, b: _b!, pairs: reference.interactionPairs),
              const SizedBox(height: Gap.lg),
              Text('Basics that lower risk', style: text.titleMedium),
              const SizedBox(height: Gap.sm),
              for (final tip in _basics) _Tip(tip.$1, tip.$2),
              const SizedBox(height: Gap.lg),
              Text('If something goes wrong', style: text.titleMedium),
              const SizedBox(height: Gap.sm),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _emergency) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $line')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                key: const ValueKey('safer-use-testing'),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Drug checking log'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TestingPage())),
              ),
              const SizedBox(height: Gap.sm),
              OutlinedButton.icon(
                key: const ValueKey('safer-use-research'),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Research and resources'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResearchPage())),
              ),
              const SizedBox(height: Gap.md),
              Text(
                'General harm-reduction information, not medical advice. Everyone reacts differently, and no list covers every risk.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _basics = <(String, String)>[
  ('Start low, go slow', 'Use less than you think you need and wait for the full effect before more. Effects can take hours by mouth.'),
  ('Do not redose early', 'Taking more because nothing has happened yet is a common way to take too much.'),
  ('Avoid using alone', 'Have someone nearby who knows what you took and can get help.'),
  ('Be careful mixing', 'Combining depressants (alcohol, opioids, benzodiazepines, GHB) can stop breathing. Mixing stimulants strains the heart.'),
  ('Know what you have', 'Unknown powders and pills can contain something else or far more than expected. Testing kits help but are not proof.'),
  ('Do not drive or operate machinery', 'Not while affected, nor while coming down.'),
  ('Medication and conditions matter', 'Antidepressants, heart conditions and many prescriptions change risks sharply. Check with a pharmacist.'),
  ('Look after the basics', 'Sip water, do not overdo it, eat, rest and stay somewhere safe and cool.'),
];

const _emergency = <String>[
  'If someone is unresponsive, struggling to breathe, seizing, overheating or in severe distress, call your local emergency number straight away.',
  'Stay with them. If they are unconscious but breathing, lay them on their side so their airway stays clear.',
  'Tell responders what was taken, how much and when. Honest information helps; they are there to treat, not judge.',
  'In the US, Poison Help is 1-800-222-1222 and the crisis line is 988. Elsewhere use your country\'s poison or crisis service.',
];

class _Tip extends StatelessWidget {
  const _Tip(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(body),
          ],
        ),
      );
}

class _ComboResult extends StatelessWidget {
  const _ComboResult({required this.a, required this.b, required this.pairs});
  final Substance a;
  final Substance b;
  final List<TripSitPair> pairs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (a.key == b.key) {
      return const Card(child: Padding(padding: EdgeInsets.all(Gap.md), child: Text('Pick two different compounds.')));
    }
    final warnings = checkInteractions(incoming: a, active: [b], pairs: pairs);
    final recorded = pairs.where((p) => p.involves(a.key, b.key)).firstOrNull;
    final worst = warnings.isEmpty ? null : warnings.first;

    final (String label, Color color) = switch (worst?.severity) {
      InteractionSeverity.dangerous => ('Dangerous', scheme.errorContainer),
      InteractionSeverity.unsafe => ('Unsafe', scheme.errorContainer),
      InteractionSeverity.caution => ('Caution', scheme.tertiaryContainer),
      _ => (recorded == null ? 'No warning on record' : 'Low risk on record', scheme.surfaceContainerHighest),
    };

    return Card(
      key: const ValueKey('combo-result'),
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${a.name} + ${b.name}: $label', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Gap.sm),
            if (worst != null)
              for (final r in worst.reasons) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(r))
            else if (recorded?.note != null)
              Text(recorded!.note!),
            const SizedBox(height: Gap.sm),
            Text(
              worst == null
                  ? 'The references list no concern for this pair, but data is incomplete, so that does not mean it is safe. Doses, health and other substances all change the picture.'
                  : 'Treat this as a reason to avoid the combination or take much less, and do not use alone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick one compound from the whole catalog. The list is built only for what is on screen, so
/// opening it is instant even with hundreds of compounds.
class _CompoundSearchDialog extends StatefulWidget {
  const _CompoundSearchDialog({required this.title, required this.all});

  final String title;
  final List<Substance> all;

  @override
  State<_CompoundSearchDialog> createState() => _CompoundSearchDialogState();
}

class _CompoundSearchDialogState extends State<_CompoundSearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? widget.all : [for (final s in widget.all) if (s.name.toLowerCase().contains(q)) s];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('compound-search'),
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: Gap.sm),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Nothing matches.'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => ListTile(
                        key: ValueKey('compound-${shown[i].key}'),
                        dense: true,
                        title: Text(shown[i].name),
                        onTap: () => Navigator.of(context).pop(shown[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}
