import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../design.dart';

/// The compound list: search, sort by your own history, favourites and hidden compounds.
///
/// History, favourites and hidden state all belong to [personId]; another person's use never
/// affects the order.
class CompoundPicker extends ConsumerStatefulWidget {
  const CompoundPicker({super.key, required this.personId, required this.onSelected, this.autofocusSearch = false});

  final String personId;
  final void Function(Substance substance) onSelected;
  final bool autofocusSearch;

  @override
  ConsumerState<CompoundPicker> createState() => _CompoundPickerState();
}

class _CompoundPickerState extends ConsumerState<CompoundPicker> {
  String _query = '';
  CompoundSort _sort = CompoundSort.mostUsed;
  bool _showHidden = false;
  String? _category;

  @override
  Widget build(BuildContext context) {
    final reference = ref.watch(catalogProvider);
    final usage = ref.watch(usageProvider(widget.personId)).value ?? const <String, UsageStat>{};
    final prefs = ref.watch(compoundPrefsProvider(widget.personId)).value ?? const CompoundPrefs();
    final now = ref.watch(clockProvider)();
    final db = ref.read(databaseProvider);

    final compounds = orderCompounds(
      all: reference.substances,
      usage: usage,
      query: _query,
      sort: _sort,
      hidden: prefs.hidden,
      favorites: prefs.favorites,
      includeHidden: _showHidden,
      category: _category,
    );
    final categories = compoundCategories(reference.substances);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
          child: TextField(
            autofocus: widget.autofocusSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search compounds',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Wrap(
            spacing: Gap.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (sort, label) in [
                (CompoundSort.mostUsed, 'Most used'),
                (CompoundSort.recent, 'Recent'),
                (CompoundSort.alphabetical, 'A-Z'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _sort == sort,
                  onSelected: (_) => setState(() => _sort = sort),
                ),
              if (prefs.hidden.isNotEmpty)
                FilterChip(
                  label: Text(_showHidden ? 'Hiding off' : 'Hidden (${prefs.hidden.length})'),
                  selected: _showHidden,
                  onSelected: (v) => setState(() => _showHidden = v),
                ),
            ],
          ),
        ),
        if (categories.length > 1)
          SizedBox(
            height: 48,
            child: ListView(
              key: const ValueKey('category-filter'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              children: [
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.sm),
                    child: FilterChip(
                      key: ValueKey('category-$c'),
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (v) => setState(() => _category = v ? c : null),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Gap.xs),
        Expanded(
          child: compounds.isEmpty
              ? const Center(child: Text('No compounds match'))
              : ListView.builder(
                  itemCount: compounds.length,
                  itemBuilder: (context, index) {
                    final s = compounds[index];
                    final stat = usage[s.key];
                    final isFavorite = prefs.favorites.contains(s.key);
                    final isHidden = prefs.hidden.contains(s.key);
                    return ListTile(
                      key: ValueKey('compound-${s.key}'),
                      leading: CircleAvatar(
                        backgroundColor: substanceColor(s.key),
                        radius: 14,
                        child: Text(s.name.characters.first, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      title: Text(s.name),
                      subtitle: Text(
                        stat == null
                            ? s.category
                            : 'Used ${stat.count}x, last ${relativeTime(stat.lastUsed, now)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.onSelected(s),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: isFavorite ? 'Remove favorite' : 'Favorite',
                            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                            onPressed: () => db.toggleFavorite(widget.personId, s.key),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            onSelected: (_) => db.setHidden(widget.personId, s.key, !isHidden),
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'hide', child: Text(isHidden ? 'Show in list' : 'Hide from list')),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
