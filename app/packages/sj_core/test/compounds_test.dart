import 'package:sj_core/sj_core.dart';
import 'package:test/test.dart';

Substance _s(String key, String name, {List<String> aka = const []}) => Substance(
      key: key,
      name: name,
      category: '',
      summary: '',
      hasTolerance: true,
      commonNames: aka,
    );

void main() {
  final all = [
    _s('alcohol', 'Alcohol', aka: ['Booze', 'Ethanol']),
    _s('cannabis', 'Cannabis', aka: ['Weed', 'Marijuana', 'THC']),
    _s('lsd', 'LSD', aka: ['Acid']),
    _s('mdma', 'MDMA', aka: ['Ecstasy', 'Molly']),
    _s('ketamine', 'Ketamine', aka: ['K']),
  ];
  keys(List<Substance> l) => l.map((s) => s.key).toList();

  final usage = {
    'cannabis': UsageStat(count: 30, lastUsed: DateTime(2026, 10, 1)),
    'alcohol': UsageStat(count: 30, lastUsed: DateTime(2026, 10, 20)),
    'lsd': UsageStat(count: 2, lastUsed: DateTime(2026, 10, 24)),
  };

  test('most used: count, then recency, then never-used alphabetically', () {
    expect(keys(orderCompounds(all: all, usage: usage)), ['alcohol', 'cannabis', 'lsd', 'ketamine', 'mdma']);
  });

  test('recent sort puts the latest use first', () {
    expect(keys(orderCompounds(all: all, usage: usage, sort: CompoundSort.recent)),
        ['lsd', 'alcohol', 'cannabis', 'ketamine', 'mdma']);
  });

  test('alphabetical ignores usage', () {
    expect(keys(orderCompounds(all: all, usage: usage, sort: CompoundSort.alphabetical)),
        ['alcohol', 'cannabis', 'ketamine', 'lsd', 'mdma']);
  });

  test('favourites float above heavier use', () {
    expect(keys(orderCompounds(all: all, usage: usage, favorites: {'mdma'})).first, 'mdma');
  });

  test('hidden compounds are removed unless requested', () {
    expect(keys(orderCompounds(all: all, usage: usage, hidden: {'lsd'})), isNot(contains('lsd')));
    expect(keys(orderCompounds(all: all, usage: usage, hidden: {'lsd'}, includeHidden: true)), contains('lsd'));
  });

  test('search matches names and aliases case-insensitively', () {
    expect(keys(orderCompounds(all: all, query: 'weed')), ['cannabis']);
    expect(keys(orderCompounds(all: all, query: 'ECSTA')), ['mdma']);
    expect(keys(orderCompounds(all: all, query: 'zzz')), isEmpty);
  });

  test('prefix matches outrank substring matches, then usage breaks ties', () {
    // "a" prefixes Alcohol and Acid(LSD); it is only a substring of Cannabis/Ketamine/MDMA aliases.
    final result = keys(orderCompounds(all: all, usage: usage, query: 'a'));
    expect(result.indexOf('alcohol'), lessThan(result.indexOf('cannabis')));
    expect(result.indexOf('lsd'), lessThan(result.indexOf('ketamine')));
    expect(result.first, 'alcohol');
  });

  test('search still respects hidden compounds', () {
    expect(keys(orderCompounds(all: all, query: 'weed', hidden: {'cannabis'})), isEmpty);
  });
}
