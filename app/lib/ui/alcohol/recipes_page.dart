import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';

final recipesProvider = StreamProvider<List<RecipeRow>>((ref) => ref.watch(databaseProvider).watchRecipes());

Recipe? recipeOf(RecipeRow row) {
  try {
    return Recipe.fromPayload(jsonDecode(row.payload));
  } on Object {
    return null;
  }
}

/// The recipe library: search, read, copy, edit, add, share and import.
class RecipesPage extends ConsumerStatefulWidget {
  const RecipesPage({super.key});

  @override
  ConsumerState<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends ConsumerState<RecipesPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Fills the library the first time; later calls do nothing.
    ref.read(databaseProvider).ensureBuiltInRecipes();
  }

  Future<void> _import() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _ImportRecipesDialog());
    if (text == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (added, skipped) = await ref.read(databaseProvider).importRecipes(parseRecipes(text));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$added recipes added${skipped > 0 ? ', $skipped already here' : ''}.')));
    } on RecipeFormatException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _shareAll() async {
    final rows = ref.read(recipesProvider).value ?? const <RecipeRow>[];
    final recipes = [for (final r in rows) ?recipeOf(r)];
    final text = const JsonEncoder.withIndent('  ').convert(recipeDocument(recipes));
    await ref.read(packageSharerProvider)('alcohol-recipes.json', text);
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(recipesProvider).value ?? const <RecipeRow>[];
    final text = Theme.of(context).textTheme;
    final shown = <(RecipeRow, Recipe)>[
      for (final row in rows)
        if (recipeOf(row) case final Recipe r when recipeMatches(r, _query)) (row, r),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-recipe'),
        heroTag: null,
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipeEditorPage())),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.sm),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('recipe-search'),
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search recipes, ingredients or a liquor'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  IconButton(key: const ValueKey('import-recipes'), tooltip: 'Import recipes', icon: const Icon(Icons.download_outlined), onPressed: _import),
                  IconButton(key: const ValueKey('share-recipes'), tooltip: 'Share all recipes', icon: const Icon(Icons.ios_share), onPressed: _shareAll),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${shown.length} of ${rows.length} recipes', key: const ValueKey('recipe-count'), style: text.bodySmall),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('No recipes match'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 96),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final (row, recipe) = shown[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: Gap.sm),
                            child: ListTile(
                              key: ValueKey('recipe-${row.id}'),
                              leading: const CircleAvatar(child: Icon(Icons.local_bar_outlined)),
                              title: Text(recipe.name),
                              subtitle: Text([
                                recipe.yieldText,
                                if (recipe.abvPercent != null) '${recipe.abvPercent! == recipe.abvPercent!.roundToDouble() ? recipe.abvPercent!.toStringAsFixed(0) : recipe.abvPercent}% ABV',
                                if (recipe.tags.isNotEmpty) recipe.tags.take(3).join(', '),
                              ].join('  |  ')),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeDetailPage(rowId: row.id))),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportRecipesDialog extends ConsumerStatefulWidget {
  const _ImportRecipesDialog();

  @override
  ConsumerState<_ImportRecipesDialog> createState() => _ImportRecipesDialogState();
}

class _ImportRecipesDialogState extends ConsumerState<_ImportRecipesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import recipes'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Paste a recipe share code (from this app or Alcohol Tracker), or choose a file.'),
          const SizedBox(height: Gap.sm),
          TextField(key: const ValueKey('recipe-import-field'), controller: _controller, minLines: 4, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder())),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) _controller.text = data!.text!;
          },
          child: const Text('Paste'),
        ),
        TextButton(
          onPressed: () async {
            final text = await ref.read(packageFilePickerProvider)();
            if (text != null && context.mounted) Navigator.pop(context, text);
          },
          child: const Text('File...'),
        ),
        FilledButton(key: const ValueKey('recipe-import-ok'), onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Import')),
      ],
    );
  }
}

class RecipeDetailPage extends ConsumerWidget {
  const RecipeDetailPage({super.key, required this.rowId});

  final String rowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = (ref.watch(recipesProvider).value ?? const <RecipeRow>[]).where((r) => r.id == rowId).firstOrNull;
    final recipe = row == null ? null : recipeOf(row);
    if (row == null || recipe == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This recipe no longer exists.')));
    final db = ref.read(databaseProvider);
    final text = Theme.of(context).textTheme;
    final messenger = ScaffoldMessenger.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(recipe.name), actions: [
        IconButton(
          key: const ValueKey('edit-recipe'),
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecipeEditorPage(rowId: row.id, recipe: recipe))),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('recipe-menu'),
          onSelected: (v) async {
            switch (v) {
              case 'copy':
                final copy = recipe.copyWith(name: '${recipe.name} (copy)');
                await db.addRecipe(copy);
                messenger.showSnackBar(const SnackBar(content: Text('Copied. Find "(copy)" in the list to edit it.')));
              case 'share':
                await Clipboard.setData(ClipboardData(text: recipe.shareText));
                messenger.showSnackBar(const SnackBar(content: Text('Share code copied. Paste it anywhere; Import reads it back.')));
              case 'delete':
                final nav = Navigator.of(context);
                await db.setRecipeDeleted(row.id, true);
                nav.pop();
                messenger.showSnackBar(SnackBar(
                  content: Text('${recipe.name} deleted'),
                  action: SnackBarAction(label: 'Undo', onPressed: () => db.setRecipeDeleted(row.id, false)),
                ));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('Make a copy')),
            PopupMenuItem(value: 'share', child: Text('Copy share code')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ]),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text(
                [
                  recipe.yieldText,
                  if (recipe.abvPercent != null) '~${recipe.abvPercent! == recipe.abvPercent!.roundToDouble() ? recipe.abvPercent!.toStringAsFixed(0) : recipe.abvPercent}% ABV',
                ].join('  |  '),
                style: text.labelLarge,
              ),
              if (recipe.tags.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Wrap(spacing: Gap.sm, children: [for (final t in recipe.tags) Chip(label: Text(t))]),
              ],
              const SizedBox(height: Gap.md),
              Text('Ingredients', style: text.titleMedium),
              for (final i in recipe.ingredients)
                ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.circle, size: 8), title: Text('${i.quantity} ${i.name}'.trim())),
              const SizedBox(height: Gap.md),
              Text('Instructions', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(recipe.instructions),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create or edit a recipe.
class RecipeEditorPage extends ConsumerStatefulWidget {
  const RecipeEditorPage({super.key, this.rowId, this.recipe});

  final String? rowId;
  final Recipe? recipe;

  @override
  ConsumerState<RecipeEditorPage> createState() => _RecipeEditorPageState();
}

class _RecipeEditorPageState extends ConsumerState<RecipeEditorPage> {
  late final _name = TextEditingController(text: widget.recipe?.name ?? '');
  late final _yield = TextEditingController(text: widget.recipe?.yieldText ?? '1 cocktail');
  late final _abv = TextEditingController(text: widget.recipe?.abvPercent == null ? '' : '${widget.recipe!.abvPercent}');
  late final _tags = TextEditingController(text: (widget.recipe?.tags ?? const []).join(', '));
  late final _instructions = TextEditingController(text: widget.recipe?.instructions ?? '');
  late final List<(TextEditingController, TextEditingController)> _ingredients = [
    for (final i in widget.recipe?.ingredients ?? const <RecipeIngredient>[]) (TextEditingController(text: i.quantity), TextEditingController(text: i.name)),
    if ((widget.recipe?.ingredients ?? const []).isEmpty) (TextEditingController(), TextEditingController()),
  ];
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _yield, _abv, _tags, _instructions]) {
      c.dispose();
    }
    for (final (q, n) in _ingredients) {
      q.dispose();
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Give the recipe a name.');
    final abvText = _abv.text.trim().replaceAll(',', '.');
    final abv = abvText.isEmpty ? null : double.tryParse(abvText);
    if (abvText.isNotEmpty && (abv == null || abv < 0 || abv > 100)) return setState(() => _error = 'ABV must be between 0 and 100.');
    final recipe = Recipe(
      name: name,
      ingredients: [
        for (final (q, n) in _ingredients)
          if (n.text.trim().isNotEmpty || q.text.trim().isNotEmpty) RecipeIngredient(q.text.trim(), n.text.trim()),
      ],
      instructions: _instructions.text.trim(),
      yieldText: _yield.text.trim().isEmpty ? '1 serving' : _yield.text.trim(),
      tags: [for (final t in _tags.text.split(',')) if (t.trim().isNotEmpty) t.trim()],
      abvPercent: abv,
    );
    final db = ref.read(databaseProvider);
    if (widget.rowId == null) {
      if (!await db.addRecipe(recipe)) return setState(() => _error = 'You already have an identical recipe.');
    } else {
      await db.updateRecipe(widget.rowId!, recipe);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.rowId == null ? 'New recipe' : 'Edit recipe'), actions: [
        TextButton(key: const ValueKey('recipe-save'), onPressed: _save, child: const Text('Save')),
      ]),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              TextField(key: const ValueKey('recipe-name'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: Gap.sm),
              Row(children: [
                Expanded(child: TextField(key: const ValueKey('recipe-yield'), controller: _yield, decoration: const InputDecoration(labelText: 'Makes'))),
                const SizedBox(width: Gap.sm),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const ValueKey('recipe-abv'),
                    controller: _abv,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'ABV', suffixText: '%'),
                  ),
                ),
              ]),
              const SizedBox(height: Gap.sm),
              TextField(key: const ValueKey('recipe-tags'), controller: _tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
              const SizedBox(height: Gap.md),
              Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
              for (var i = 0; i < _ingredients.length; i++)
                Row(children: [
                  SizedBox(width: 96, child: TextField(key: ValueKey('ingredient-qty-$i'), controller: _ingredients[i].$1, decoration: const InputDecoration(labelText: 'Amount'))),
                  const SizedBox(width: Gap.sm),
                  Expanded(child: TextField(key: ValueKey('ingredient-name-$i'), controller: _ingredients[i].$2, decoration: const InputDecoration(labelText: 'Ingredient'))),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _ingredients.length == 1 ? null : () => setState(() => _ingredients.removeAt(i)),
                  ),
                ]),
              TextButton.icon(
                key: const ValueKey('add-ingredient'),
                icon: const Icon(Icons.add),
                label: const Text('Add ingredient'),
                onPressed: () => setState(() => _ingredients.add((TextEditingController(), TextEditingController()))),
              ),
              const SizedBox(height: Gap.sm),
              TextField(key: const ValueKey('recipe-instructions'), controller: _instructions, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Instructions', alignLabelWithHint: true)),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: Gap.sm), child: Text(_error!, key: const ValueKey('recipe-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 96),
            ],
          ),
        ),
      ),
    );
  }
}
