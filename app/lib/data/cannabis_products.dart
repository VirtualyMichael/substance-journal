import 'dart:convert';

import 'database.dart';

/// What a saved cannabis product adds beyond its name and THC/CBD percent. Lives in the product's
/// details JSON so older copies of the app keep syncing it untouched.
class ProductDetails {
  const ProductDetails({this.kind = 'flower', this.strainType = '', this.batch = '', this.terpenes = '', this.source = '', this.costPerGram, this.thcMgPerUnit, this.notes = ''});

  /// flower, concentrate, vape, edible, tincture or other.
  final String kind;

  /// indica, sativa or hybrid, or empty when unknown. A market label that says little about the
  /// effect on its own, kept so you can see whether it matches what you rate.
  final String strainType;

  /// Batch or lot number, for comparing one purchase with the next.
  final String batch;
  final String terpenes;
  final String source;
  final double? costPerGram;

  /// For edibles and tinctures: THC on the label, per piece or dose.
  final double? thcMgPerUnit;
  final String notes;

  static const kinds = ['flower', 'concentrate', 'vape', 'edible', 'tincture', 'other'];
  static const strainTypes = ['indica', 'sativa', 'hybrid'];
  static const commonTerpenes = ['Myrcene', 'Limonene', 'Caryophyllene', 'Pinene', 'Linalool', 'Humulene', 'Terpinolene', 'Ocimene'];

  Map<String, Object?> toJson() => {
        'kind': kind,
        if (strainType.isNotEmpty) 'strainType': strainType,
        if (batch.isNotEmpty) 'batch': batch,
        if (terpenes.isNotEmpty) 'terpenes': terpenes,
        if (source.isNotEmpty) 'source': source,
        'costPerGram': ?costPerGram,
        'thcMgPerUnit': ?thcMgPerUnit,
        if (notes.isNotEmpty) 'notes': notes,
      };

  static ProductDetails of(Product p) {
    try {
      final j = jsonDecode(p.detailsJson) as Map<String, dynamic>;
      final kind = j['kind'];
      return ProductDetails(
        kind: kind is String && kinds.contains(kind) ? kind : 'flower',
        strainType: strainTypes.contains(j['strainType']) ? j['strainType'] as String : '',
        batch: '${j['batch'] ?? ''}',
        terpenes: '${j['terpenes'] ?? ''}',
        source: '${j['source'] ?? ''}',
        costPerGram: (j['costPerGram'] as num?)?.toDouble(),
        thcMgPerUnit: (j['thcMgPerUnit'] as num?)?.toDouble(),
        notes: '${j['notes'] ?? ''}',
      );
    } on Object {
      return const ProductDetails();
    }
  }
}

/// How one person has used one product.
class ProductUsage {
  const ProductUsage({required this.doses, required this.grams, required this.last, required this.spend});
  final int doses;

  /// Flower or concentrate actually consumed (amount times the share used), where it was entered by weight.
  final double grams;
  final DateTime? last;

  /// Grams times the cost per gram, or null when no cost is saved.
  final double? spend;

  static ProductUsage of(Product product, Iterable<Ingestion> ingestions) {
    var doses = 0;
    var grams = 0.0;
    DateTime? last;
    for (final i in ingestions) {
      if (i.productId != product.id || i.deleted) continue;
      doses++;
      if (last == null || i.time.isAfter(last)) last = i.time;
      try {
        final d = jsonDecode(i.detailsJson) as Map<String, dynamic>;
        final g = d['grams'];
        if (g is num) grams += g * ((d['fractionUsed'] as num?) ?? 1);
      } on Object {
        // Details written by another version; the dose still counts.
      }
    }
    final cost = ProductDetails.of(product).costPerGram;
    return ProductUsage(doses: doses, grams: grams, last: last, spend: cost == null || grams == 0 ? null : grams * cost);
  }
}

/// How the experiences that included a product were rated. Each experience counts once however many
/// doses it had, and the numbers are about the whole session (other substances included), so they
/// hint rather than prove.
class ProductOutcomes {
  const ProductOutcomes({required this.experiences, required this.rated, required this.withOthers, required this.averages, required this.counts});

  /// Experiences containing a dose of the product.
  final int experiences;

  /// Of those, the ones with any rating.
  final int rated;

  /// Experiences that also had another substance, which blurs the picture.
  final int withOthers;

  /// Mean 0 to 10 score per field (mood, pain, ...), and how many ratings fed each.
  final Map<String, double> averages;
  final Map<String, int> counts;

  static ProductOutcomes of(Product product, Iterable<Ingestion> ingestions, Iterable<Rating> ratings) {
    final live = [for (final i in ingestions) if (!i.deleted) i];
    final ids = {for (final i in live) if (i.productId == product.id) i.experienceId};
    final withOthers = ids.where((e) => live.any((i) => i.experienceId == e && i.substanceKey != product.substanceKey)).length;
    final sums = <String, double>{};
    final counts = <String, int>{};
    final ratedExperiences = <String>{};
    for (final r in ratings) {
      if (r.deleted || !ids.contains(r.experienceId)) continue;
      ratedExperiences.add(r.experienceId);
      try {
        final scores = jsonDecode(r.scoresJson) as Map<String, dynamic>;
        scores.forEach((k, v) {
          if (v is num) {
            sums[k] = (sums[k] ?? 0) + v;
            counts[k] = (counts[k] ?? 0) + 1;
          }
        });
      } on Object {
        // A rating written by another version; it still counts as rated.
      }
    }
    return ProductOutcomes(
      experiences: ids.length,
      rated: ratedExperiences.length,
      withOthers: withOthers,
      averages: {for (final k in sums.keys) k: sums[k]! / counts[k]!},
      counts: counts,
    );
  }
}

/// Scores where a lower number is the better outcome.
const lowerIsBetter = {'pain', 'anxiety'};

/// The product with the best average for [field], needing at least [minRatings] ratings behind it.
({Product product, double average, int count})? bestFor(String field, Map<Product, ProductOutcomes> outcomes, {int minRatings = 3}) {
  ({Product product, double average, int count})? best;
  outcomes.forEach((p, o) {
    final avg = o.averages[field];
    final n = o.counts[field] ?? 0;
    if (avg == null || n < minRatings) return;
    final better = best == null || (lowerIsBetter.contains(field) ? avg < best!.average : avg > best!.average);
    if (better) best = (product: p, average: avg, count: n);
  });
  return best;
}

/// Average scores for one strain type across every rated product of that type.
class TypeOutcomes {
  const TypeOutcomes({required this.type, required this.products, required this.averages, required this.counts});
  final String type;
  final int products;
  final Map<String, double> averages;
  final Map<String, int> counts;
}

/// Groups product outcomes by indica, sativa or hybrid. A product's average counts as many times
/// as it has ratings, so a type is not swung by one product with a single rating.
List<TypeOutcomes> outcomesByType(Map<Product, ProductOutcomes> outcomes) {
  final out = <TypeOutcomes>[];
  for (final type in ProductDetails.strainTypes) {
    final sums = <String, double>{};
    final counts = <String, int>{};
    var products = 0;
    outcomes.forEach((p, o) {
      if (ProductDetails.of(p).strainType != type || o.rated == 0) return;
      products++;
      o.averages.forEach((k, avg) {
        final n = o.counts[k] ?? 0;
        sums[k] = (sums[k] ?? 0) + avg * n;
        counts[k] = (counts[k] ?? 0) + n;
      });
    });
    if (products == 0) continue;
    out.add(TypeOutcomes(type: type, products: products, averages: {for (final k in sums.keys) k: sums[k]! / counts[k]!}, counts: counts));
  }
  return out;
}
