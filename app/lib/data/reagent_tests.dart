import 'database.dart';

/// Colour (reagent) tests the log offers. The order is the order shown.
const reagentNames = ['Marquis', 'Mecke', 'Mandelin', "Simon's", 'Ehrlich', 'Liebermann', 'Morris', 'Froehde', 'Scott', 'Zimmermann', 'Other reagent'];

/// Immunoassay strips: they look for one drug (or class), not a colour.
const stripNames = ['Fentanyl strip', 'Benzodiazepine strip', 'Xylazine strip', 'Other strip'];

/// Colours seen on a reagent. "No reaction" and "Other" are real answers too.
const reagentColors = ['No reaction', 'Yellow', 'Orange', 'Red', 'Pink', 'Purple', 'Blue', 'Green', 'Brown', 'Black', 'Grey', 'Other'];

enum TestOutcome {
  matched('matched', 'Matched the chart'),
  unmatched('unmatched', 'Did not match'),
  unclear('unclear', 'Unclear'),
  positive('positive', 'Positive'),
  negative('negative', 'Negative'),
  invalid('invalid', 'Invalid strip');

  const TestOutcome(this.key, this.label);
  final String key;
  final String label;

  static TestOutcome? parse(String key) => values.where((o) => o.key == key).firstOrNull;

  /// Results that should make someone stop and think before taking the sample.
  bool get isWarning => this == unmatched || this == positive;

  /// Results that fit expectations. They still prove nothing about purity or dose.
  bool get isReassuring => this == matched || this == negative;
}

bool isStrip(String reagent) => stripNames.contains(reagent);

/// Reagents people commonly use for a compound, for the "which test?" hint. Deliberately short and
/// cautious: colour charts change and differ by brand, so this says what to try, never what to expect.
/// Anything not listed gets the general advice.
List<String> suggestedTests(String substanceKey) => switch (substanceKey) {
      'mdma' => ['Marquis', 'Mecke', "Simon's", 'Fentanyl strip'],
      'lsd' => ['Ehrlich'],
      'dmt' => ['Ehrlich'],
      'ketamine' => ['Morris', 'Mandelin'],
      'alcohol' || 'nicotine' || 'cannabis' || 'psilocybin_mushrooms' => const [],
      _ => const ['Marquis', 'Fentanyl strip'],
    };

/// What the log says about a sample, never "safe".
enum SampleStatus { untested, flagged, checked }

class SampleSummary {
  const SampleSummary(this.status, this.tests);
  final SampleStatus status;
  final List<ReagentTest> tests;

  String get headline => switch (status) {
        SampleStatus.flagged => 'A test did not match or was positive',
        SampleStatus.checked => 'Tested, nothing unexpected seen',
        SampleStatus.untested => 'Not tested',
      };

  String get caution => switch (status) {
        SampleStatus.flagged => 'Do not take it unless you know why. Colour tests cannot say what is in it, so consider lab drug checking.',
        SampleStatus.checked =>
          'Tests are presumptive only. They cannot show purity, dose or everything else that could be in a sample, and a strip only looks for one thing.',
        SampleStatus.untested => 'Nothing tested yet. Unknown samples can contain something else or far more than expected.',
      };

  static SampleSummary of(Iterable<ReagentTest> all, String productId) {
    final tests = [for (final t in all) if (t.productId == productId && !t.deleted) t]..sort((a, b) => b.testedAt.compareTo(a.testedAt));
    final outcomes = [for (final t in tests) TestOutcome.parse(t.outcome)];
    if (outcomes.any((o) => o?.isWarning ?? false)) return SampleSummary(SampleStatus.flagged, tests);
    if (outcomes.any((o) => o?.isReassuring ?? false)) return SampleSummary(SampleStatus.checked, tests);
    return SampleSummary(SampleStatus.untested, tests);
  }
}

/// A short line for one test: "Marquis: yellow, then purple (matched the chart)".
String describeTest(ReagentTest t) {
  final outcome = TestOutcome.parse(t.outcome)?.label.toLowerCase() ?? t.outcome;
  if (isStrip(t.reagent) || t.kind == 'strip') return '${t.reagent}: $outcome';
  final colours = [
    if (t.initialColor.isNotEmpty) t.initialColor.toLowerCase(),
    if (t.finalColor.isNotEmpty && t.finalColor != t.initialColor) t.finalColor.toLowerCase(),
  ];
  return '${t.reagent}${colours.isEmpty ? '' : ': ${colours.join(', then ')}'} ($outcome)';
}
