import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cannabis_products.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';
import '../journal/dialogs.dart' show scoreFields;
import '../toast.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Saved cannabis strains and batches, with how much of each the current person has used.
class ProductsPage extends ConsumerWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(cannabisProductsProvider).value ?? const <Product>[];
    final person = ref.watch(currentPersonProvider);
    final ingestions = person == null ? const <Ingestion>[] : (ref.watch(personIngestionsProvider(person.id)).value ?? const <Ingestion>[]);
    final ratings = person == null ? const <Rating>[] : (ref.watch(personRatingsProvider(person.id)).value ?? const <Rating>[]);
    final outcomes = {for (final p in products) p: ProductOutcomes.of(p, ingestions, ratings)};
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cannabis products')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-product'),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
        onPressed: () => showProductEditor(context, ref),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: products.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Gap.lg),
                  child: Center(
                    child: Text(
                      'Save a strain or batch once, with its THC and CBD, and pick it when you log. '
                      'You will see how much of each you have used.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 96),
                  children: [
                    _BestCard(outcomes: outcomes),
                    _TypeCard(outcomes: outcomes),
                    for (final p in products) _ProductCard(product: p, usage: ProductUsage.of(p, ingestions), outcomes: outcomes[p]!),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product, required this.usage, required this.outcomes});
  final Product product;
  final ProductUsage usage;
  final ProductOutcomes outcomes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ProductDetails.of(product);
    final facts = [
      if (product.thcPercent != null) 'THC ${_n(product.thcPercent!)}%',
      if (d.thcMgPerUnit != null) 'THC ${_n(d.thcMgPerUnit!)} mg each',
      if (product.cbdPercent != null) 'CBD ${_n(product.cbdPercent!)}%',
      d.strainType.isEmpty ? d.kind : '${d.strainType} ${d.kind}',
      if (d.batch.isNotEmpty) 'batch ${d.batch}',
    ];
    final used = usage.doses == 0
        ? 'Not used yet'
        : [
            '${usage.doses} ${usage.doses == 1 ? 'dose' : 'doses'}',
            if (usage.grams > 0) '${_n(double.parse(usage.grams.toStringAsFixed(2)))} g',
            if (usage.spend != null) '\$${usage.spend!.toStringAsFixed(2)}',
            'last ${_months[usage.last!.month - 1]} ${usage.last!.day}}',
          ].join(' · ');
    return Card(
      key: ValueKey('product-${product.id}'),
      child: ListTile(
        title: Text(product.name),
        subtitle: Text([facts.join(' · '), if (d.source.isNotEmpty) 'From ${d.source}', if (d.terpenes.isNotEmpty) d.terpenes, used, if (_rated(outcomes) != null) _rated(outcomes)!].join('\n')),
        onTap: () => showProductEditor(context, ref, existing: product),
        trailing: IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final db = ref.read(databaseProvider);
            await db.setProductDeleted(product.id, true);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showToast(SnackBar(
                content: Text('${product.name} removed. Past doses keep their record.'),
                action: SnackBarAction(label: 'Undo', onPressed: () => db.setProductDeleted(product.id, false)),
              ));
            }
          },
        ),
      ),
    );
  }
}

String? _rated(ProductOutcomes o) {
  if (o.rated == 0) return null;
  final scores = [
    for (final (key, label) in scoreFields)
      if (o.averages[key] != null) '${label.toLowerCase()} ${_n(double.parse(o.averages[key]!.toStringAsFixed(1)))}',
  ];
  return 'Rated in ${o.rated} of ${o.experiences} sessions${scores.isEmpty ? '' : ': ${scores.join(', ')}'}';
}

/// The best product so far for each feeling, once there are enough ratings to say anything.
class _BestCard extends StatelessWidget {
  const _BestCard({required this.outcomes});
  final Map<Product, ProductOutcomes> outcomes;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final (key, label) in scoreFields)
        if (bestFor(key, outcomes) case final best?)
          '${lowerIsBetter.contains(key) ? 'Lowest ${label.toLowerCase()}' : 'Best ${label.toLowerCase()}'}: ${best.product.name} '
              '(${_n(double.parse(best.average.toStringAsFixed(1)))} over ${best.count} ratings)',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const ValueKey('best-products'),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What seems to work for you', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final l in lines) Text(l),
            const SizedBox(height: 4),
            Text(
              'Based on your own ratings of whole sessions, so other substances and your mood that day also play a part. A hint, not proof.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// How the strain types you have saved compare, once at least two have ratings behind them.
class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.outcomes});
  final Map<Product, ProductOutcomes> outcomes;

  @override
  Widget build(BuildContext context) {
    final types = outcomesByType(outcomes);
    if (types.length < 2) return const SizedBox.shrink();
    return Card(
      key: const ValueKey('type-outcomes'),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('By strain type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final t in types)
              Text([
                '${t.type[0].toUpperCase()}${t.type.substring(1)}: ',
                [
                  for (final (key, label) in scoreFields)
                    if (t.averages[key] != null) '${label.toLowerCase()} ${_n(double.parse(t.averages[key]!.toStringAsFixed(1)))}',
                ].join(', '),
                ' (${t.products} ${t.products == 1 ? 'product' : 'products'})',
              ].join()),
            const SizedBox(height: 4),
            Text(
              "Indica, sativa and hybrid are market labels and often do not match a strain's chemistry, so treat this as a curiosity. "
              'Whole-session ratings, other substances included.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the add/edit sheet. Returns the saved product, or null if cancelled.
Future<Product?> showProductEditor(BuildContext context, WidgetRef ref, {Product? existing}) {
  return showDialog<Product>(context: context, builder: (_) => _ProductEditor(existing: existing));
}

class _ProductEditor extends ConsumerStatefulWidget {
  const _ProductEditor({this.existing});
  final Product? existing;

  @override
  ConsumerState<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<_ProductEditor> {
  late final TextEditingController _name, _thc, _cbd, _batch, _terpenes, _source, _cost, _labelMg, _notes;
  late String _kind;
  late String _strainType;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    final d = p == null ? const ProductDetails() : ProductDetails.of(p);
    String num(double? v) => v == null ? '' : _n(v);
    _name = TextEditingController(text: p?.name ?? '');
    _thc = TextEditingController(text: num(p?.thcPercent));
    _cbd = TextEditingController(text: num(p?.cbdPercent));
    _batch = TextEditingController(text: d.batch);
    _terpenes = TextEditingController(text: d.terpenes);
    _source = TextEditingController(text: d.source);
    _cost = TextEditingController(text: num(d.costPerGram));
    _labelMg = TextEditingController(text: num(d.thcMgPerUnit));
    _notes = TextEditingController(text: d.notes);
    _kind = d.kind;
    _strainType = d.strainType;
  }

  @override
  void dispose() {
    for (final c in [_name, _thc, _cbd, _batch, _terpenes, _source, _cost, _labelMg, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Give it a name.');
    final thc = _parse(_thc), cbd = _parse(_cbd);
    if ((thc != null && (thc < 0 || thc > 100)) || (cbd != null && (cbd < 0 || cbd > 100))) {
      return setState(() => _error = 'THC and CBD percent must be between 0 and 100.');
    }
    final details = ProductDetails(
      kind: _kind,
      strainType: _strainType,
      batch: _batch.text.trim(),
      terpenes: _terpenes.text.trim(),
      source: _source.text.trim(),
      costPerGram: _parse(_cost),
      thcMgPerUnit: _parse(_labelMg),
      notes: _notes.text.trim(),
    ).toJson();
    final db = ref.read(databaseProvider);
    final existing = widget.existing;
    Product saved;
    if (existing == null) {
      saved = await db.addProduct(substanceKey: 'cannabis', name: name, thcPercent: thc, cbdPercent: cbd, details: details);
    } else {
      await db.updateProduct(existing.id, name: name, thcPercent: thc, cbdPercent: cbd, details: details);
      saved = await (db.select(db.products)..where((t) => t.id.equals(existing.id))).getSingle();
    }
    if (mounted) Navigator.of(context).pop(saved);
  }

  Widget _field(String key, String label, TextEditingController c, {String? suffix, bool number = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: TextField(
          key: ValueKey(key),
          controller: c,
          maxLines: lines,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label, suffixText: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final edible = _kind == 'edible' || _kind == 'tincture';
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add product' : 'Edit product'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('product-name', 'Name or strain', _name),
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('product-kind'),
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [for (final k in ProductDetails.kinds) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => setState(() => _kind = v ?? _kind),
                ),
              ),
              if (_kind == 'flower' || _kind == 'concentrate' || _kind == 'vape')
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('product-strain-type'),
                    initialValue: _strainType,
                    decoration: const InputDecoration(labelText: 'Strain type (optional)'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Not sure')),
                      for (final t in ProductDetails.strainTypes) DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => _strainType = v ?? ''),
                  ),
                ),
              Row(children: [
                Expanded(child: _field('product-thc', 'THC', _thc, suffix: '%', number: true)),
                const SizedBox(width: Gap.sm),
                Expanded(child: _field('product-cbd', 'CBD', _cbd, suffix: '%', number: true)),
              ]),
              if (edible) _field('product-label-mg', 'THC per piece or dose', _labelMg, suffix: 'mg', number: true),
              _field('product-terpenes', 'Terpenes (optional)', _terpenes),
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, children: [
                    for (final t in ProductDetails.commonTerpenes)
                      ActionChip(
                        key: ValueKey('terpene-${t.toLowerCase()}'),
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          if (_terpenes.text.toLowerCase().contains(t.toLowerCase())) return;
                          setState(() => _terpenes.text = _terpenes.text.trim().isEmpty ? t : '${_terpenes.text.trim()}, $t');
                        },
                      ),
                  ]),
                ),
              ),
              _field('product-batch', 'Batch or lot (optional)', _batch),
              _field('product-source', 'Where from (optional)', _source),
              _field('product-cost', 'Cost per gram (optional)', _cost, suffix: '\$', number: true),
              _field('product-notes', 'Notes', _notes, lines: 2),
              if (_error != null) Text(_error!, key: const ValueKey('product-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('product-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
