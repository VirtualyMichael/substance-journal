import 'dart:convert';

import 'database.dart';

/// What a saved cannabis product adds beyond its name and THC/CBD percent. Lives in the product's
/// details JSON so older copies of the app keep syncing it untouched.
class ProductDetails {
  const ProductDetails({this.kind = 'flower', this.terpenes = '', this.source = '', this.costPerGram, this.thcMgPerUnit, this.notes = ''});

  /// flower, concentrate, vape, edible, tincture or other.
  final String kind;
  final String terpenes;
  final String source;
  final double? costPerGram;

  /// For edibles and tinctures: THC on the label, per piece or dose.
  final double? thcMgPerUnit;
  final String notes;

  static const kinds = ['flower', 'concentrate', 'vape', 'edible', 'tincture', 'other'];

  Map<String, Object?> toJson() => {
        'kind': kind,
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
