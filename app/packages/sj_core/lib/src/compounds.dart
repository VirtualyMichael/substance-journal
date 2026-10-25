import 'reference.dart';

/// How much one person has used a substance (counts only that person's own history).
class UsageStat {
  const UsageStat({required this.count, required this.lastUsed});
  final int count;
  final DateTime lastUsed;
}

enum CompoundSort { mostUsed, recent, alphabetical }

/// Orders and filters the compound picker.
///
/// - [query] matches name, common names and key (case-insensitive); prefix matches rank
///   above substring matches.
/// - Favourites float to the top, then the chosen [sort]; compounds never used come last
///   (alphabetically) for the usage-based sorts.
/// - Compounds in [hidden] are left out unless [includeHidden] is true.
List<Substance> orderCompounds({
  required List<Substance> all,
  Map<String, UsageStat> usage = const {},
  String query = '',
  Set<String> hidden = const {},
  Set<String> favorites = const {},
  CompoundSort sort = CompoundSort.mostUsed,
  bool includeHidden = false,
}) {
  final q = query.trim().toLowerCase();

  // 0 = no match, 2 = name/alias starts with q, 1 = contains q.
  int matchScore(Substance s) {
    if (q.isEmpty) return 1;
    final names = [s.name, s.key, ...s.commonNames].map((n) => n.toLowerCase());
    if (names.any((n) => n.startsWith(q))) return 2;
    if (names.any((n) => n.contains(q))) return 1;
    return 0;
  }

  final candidates = [
    for (final s in all)
      if ((includeHidden || !hidden.contains(s.key)) && matchScore(s) > 0) s,
  ];

  int byName(Substance a, Substance b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());

  int usageOrder(Substance a, Substance b) {
    if (sort == CompoundSort.alphabetical) return byName(a, b);
    final ua = usage[a.key];
    final ub = usage[b.key];
    if (ua == null && ub == null) return byName(a, b);
    if (ua == null) return 1;
    if (ub == null) return -1;
    switch (sort) {
      case CompoundSort.mostUsed:
        final byCount = ub.count.compareTo(ua.count);
        if (byCount != 0) return byCount;
        final byRecent = ub.lastUsed.compareTo(ua.lastUsed);
        return byRecent != 0 ? byRecent : byName(a, b);
      case CompoundSort.recent:
        final byRecent = ub.lastUsed.compareTo(ua.lastUsed);
        if (byRecent != 0) return byRecent;
        final byCount = ub.count.compareTo(ua.count);
        return byCount != 0 ? byCount : byName(a, b);
      case CompoundSort.alphabetical:
        return byName(a, b); // handled above; kept so the switch stays exhaustive
    }
  }

  candidates.sort((a, b) {
    if (q.isNotEmpty) {
      final byScore = matchScore(b).compareTo(matchScore(a));
      if (byScore != 0) return byScore;
    }
    final favA = favorites.contains(a.key);
    final favB = favorites.contains(b.key);
    if (favA != favB) return favA ? -1 : 1;
    return usageOrder(a, b);
  });
  return candidates;
}
