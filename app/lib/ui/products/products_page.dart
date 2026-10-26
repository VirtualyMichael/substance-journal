import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cannabis_products.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';

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
                    for (final p in products) _ProductCard(product: p, usage: ProductUsage.of(p, ingestions)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product, required this.usage});
  final Product product;
  final ProductUsage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ProductDetails.of(product);
    final facts = [
      if (product.thcPercent != null) 'THC ${_n(product.thcPercent!)}%',
      if (d.thcMgPerUnit != null) 'THC ${_n(d.thcMgPerUnit!)} mg each',
      if (product.cbdPercent != null) 'CBD ${_n(product.cbdPercent!)}%',
      d.kind,
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
        subtitle: Text([facts.join(' · '), if (d.source.isNotEmpty) 'From ${d.source}', if (d.terpenes.isNotEmpty) d.terpenes, used].join('\n')),
        isThreeLine: true,
        onTap: () => showProductEditor(context, ref, existing: product),
        trailing: IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final db = ref.read(databaseProvider);
            await db.setProductDeleted(product.id, true);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
  late final TextEditingController _name, _thc, _cbd, _terpenes, _source, _cost, _labelMg, _notes;
  late String _kind;
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
    _terpenes = TextEditingController(text: d.terpenes);
    _source = TextEditingController(text: d.source);
    _cost = TextEditingController(text: num(d.costPerGram));
    _labelMg = TextEditingController(text: num(d.thcMgPerUnit));
    _notes = TextEditingController(text: d.notes);
    _kind = d.kind;
  }

  @override
  void dispose() {
    for (final c in [_name, _thc, _cbd, _terpenes, _source, _cost, _labelMg, _notes]) {
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
              Row(children: [
                Expanded(child: _field('product-thc', 'THC', _thc, suffix: '%', number: true)),
                const SizedBox(width: Gap.sm),
                Expanded(child: _field('product-cbd', 'CBD', _cbd, suffix: '%', number: true)),
              ]),
              if (edible) _field('product-label-mg', 'THC per piece or dose', _labelMg, suffix: 'mg', number: true),
              _field('product-terpenes', 'Terpenes (optional)', _terpenes),
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
