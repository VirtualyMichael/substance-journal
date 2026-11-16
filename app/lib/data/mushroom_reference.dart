import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sj_core/sj_core.dart';

/// The built-in strain reference (assets/data/mushroom_strains.json): published analyses only.
/// Read-only reference data, never synced. Empty if the file is missing or unreadable.
final strainReferenceProvider = FutureProvider<StrainReference>((ref) async {
  try {
    return StrainReference.parse(await rootBundle.loadString('assets/data/mushroom_strains.json'));
  } on Object {
    return StrainReference.empty;
  }
});

/// One potency-testing service, as checked on its own website on [verified].
class TestingService {
  const TestingService({
    required this.name,
    required this.url,
    required this.kind,
    required this.tests,
    required this.eligibility,
    required this.verified,
  });
  final String name;
  final String url;
  final String kind;
  final String tests;
  final String eligibility;
  final String verified;
}

class CheckedService {
  const CheckedService(this.name, this.url, this.reason);
  final String name;
  final String url;
  final String reason;
}

/// assets/data/potency_testing.json: kept as data so it can be corrected without a code change.
class PotencyTestingInfo {
  const PotencyTestingInfo({
    this.verified = '',
    this.legal = '',
    this.whatATestTells = const [],
    this.readingACertificate = const [],
    this.services = const [],
    this.checkedNotListed = const [],
  });

  final String verified;
  final String legal;
  final List<String> whatATestTells;
  final List<String> readingACertificate;
  final List<TestingService> services;
  final List<CheckedService> checkedNotListed;

  static const empty = PotencyTestingInfo();

  static PotencyTestingInfo parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    List<String> strings(Object? v) => (v as List?)?.whereType<String>().toList() ?? const [];
    String s(Map<String, dynamic> m, String k) => m[k] as String? ?? '';
    return PotencyTestingInfo(
      verified: j['verified'] as String? ?? '',
      legal: j['legal'] as String? ?? '',
      whatATestTells: strings(j['what_a_test_tells']),
      readingACertificate: strings(j['reading_a_certificate']),
      services: [
        for (final m in (j['services'] as List? ?? const []).cast<Map<String, dynamic>>())
          TestingService(
            name: s(m, 'name'),
            url: s(m, 'url'),
            kind: s(m, 'kind'),
            tests: s(m, 'tests'),
            eligibility: s(m, 'eligibility'),
            verified: s(m, 'verified'),
          ),
      ],
      checkedNotListed: [
        for (final m in (j['checked_not_listed'] as List? ?? const []).cast<Map<String, dynamic>>())
          CheckedService(s(m, 'name'), s(m, 'url'), s(m, 'reason')),
      ],
    );
  }
}

final potencyTestingProvider = FutureProvider<PotencyTestingInfo>((ref) async {
  try {
    return PotencyTestingInfo.parse(await rootBundle.loadString('assets/data/potency_testing.json'));
  } on Object {
    return PotencyTestingInfo.empty;
  }
});
