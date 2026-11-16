import 'dart:math';

/// A substance-specific tolerance model read from the reference data (`tolerance_profile` in
/// substances.json), for substances where human studies measured how much weaker a repeat dose
/// feels and for how long. Substances without one keep the generic score in tolerance.dart.
///
/// Every number carries its sources. Where the studies leave a range, [low] is the reading that
/// gives the least tolerance and [high] the most, so the app can draw a band instead of one line.

/// One figure with its plausible range and where it came from.
class ProfileValue {
  const ProfileValue(this.expected, {double? low, double? high, this.sources = const [], this.note = ''})
      : low = low ?? expected,
        high = high ?? expected;

  final double expected;

  /// The value that gives the least tolerance (for example the fastest recovery).
  final double low;

  /// The value that gives the most tolerance.
  final double high;
  final List<String> sources;
  final String note;

  double pick(ToleranceBand band) => switch (band) {
        ToleranceBand.low => low,
        ToleranceBand.expected => expected,
        ToleranceBand.high => high,
      };

  static ProfileValue? fromJson(Object? json) {
    if (json is num) return ProfileValue(json.toDouble());
    if (json is! Map<String, dynamic>) return null;
    final e = (json['expected'] as num?)?.toDouble();
    if (e == null) return null;
    return ProfileValue(
      e,
      low: (json['low'] as num?)?.toDouble(),
      high: (json['high'] as num?)?.toDouble(),
      sources: _strings(json['sources']),
      note: json['note'] as String? ?? '',
    );
  }
}

/// Which edge of the uncertainty band to compute.
enum ToleranceBand { low, expected, high }

/// How strongly use of another substance counts toward this one's tolerance (1.0 = like a dose of
/// this substance of the same strength band).
class CrossTolerance {
  const CrossTolerance(this.substanceKey, this.factor, {this.sources = const [], this.note = ''});
  final String substanceKey;
  final double factor;
  final List<String> sources;
  final String note;
}

class ToleranceProfile {
  const ToleranceProfile({
    required this.riseStartHours,
    required this.peakHours,
    required this.singleDoseLoss,
    required this.maxLoss,
    required this.recoveryDays,
    required this.doseExponent,
    this.crossTolerance = const [],
    this.summary = '',
    this.limits = '',
    this.sources = const [],
  });

  /// Hours after a dose before its tolerance starts to show (rises linearly from here).
  final ProfileValue riseStartHours;

  /// Hours after a dose when its tolerance is largest.
  final ProfileValue peakHours;

  /// Loss of effect (0-1) for a same-size dose taken at [peakHours] after one typical dose.
  final ProfileValue singleDoseLoss;

  /// The largest loss (0-1) the studies measured with repeated dosing; estimates never pass it.
  final ProfileValue maxLoss;

  /// Days from a dose until its tolerance has gone (fades linearly from the peak).
  final ProfileValue recoveryDays;

  /// How a dose's size scales its tolerance: (dose / common dose) ^ exponent, at most 1.
  /// 0 = size does not matter, 0.5 = square root, 1 = in proportion.
  final ProfileValue doseExponent;
  final List<CrossTolerance> crossTolerance;

  /// Plain-language summary of what the profile says and where it comes from.
  final String summary;

  /// What the evidence cannot tell (shown with the estimate).
  final String limits;
  final List<String> sources;

  /// Every source the profile cites, without duplicates.
  List<String> get allSources => {
        ...sources,
        for (final v in [riseStartHours, peakHours, singleDoseLoss, maxLoss, recoveryDays, doseExponent]) ...v.sources,
        for (final c in crossTolerance) ...c.sources,
      }.toList();

  CrossTolerance? crossWith(String substanceKey) {
    for (final c in crossTolerance) {
      if (c.substanceKey == substanceKey) return c;
    }
    return null;
  }

  /// How much tolerance one dose of [weight] (1.0 = a common dose) leaves [hours] after it was
  /// taken, as a loss of effect from 0 to 1, before combining with other doses.
  double contribution(double hours, double weight, ToleranceBand band) {
    if (hours < 0 || weight <= 0) return 0;
    final start = riseStartHours.pick(band);
    final peak = max(peakHours.pick(band), start + 0.01);
    final end = max(recoveryDays.pick(band) * 24, peak + 0.01);
    final double shape;
    if (hours <= start) {
      shape = 0;
    } else if (hours < peak) {
      shape = (hours - start) / (peak - start);
    } else if (hours < end) {
      shape = 1 - (hours - peak) / (end - peak);
    } else {
      shape = 0;
    }
    final exponent = doseExponent.pick(band);
    final scale = min(1.0, pow(weight, exponent).toDouble());
    return singleDoseLoss.pick(band) * scale * shape;
  }

  static ToleranceProfile? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final rise = ProfileValue.fromJson(json['rise_start_hours']);
    final peak = ProfileValue.fromJson(json['peak_hours']);
    final single = ProfileValue.fromJson(json['single_dose_loss']);
    final recovery = ProfileValue.fromJson(json['recovery_days']);
    if (rise == null || peak == null || single == null || recovery == null) return null;
    return ToleranceProfile(
      riseStartHours: rise,
      peakHours: peak,
      singleDoseLoss: single,
      maxLoss: ProfileValue.fromJson(json['max_loss']) ?? const ProfileValue(1.0),
      recoveryDays: recovery,
      doseExponent: ProfileValue.fromJson(json['dose_exponent']) ?? const ProfileValue(0.5),
      crossTolerance: [
        for (final c in (json['cross_tolerance'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[])
          if (c['substance'] is String && c['factor'] is num)
            CrossTolerance(c['substance'] as String, (c['factor'] as num).toDouble(),
                sources: _strings(c['sources']), note: c['note'] as String? ?? ''),
      ],
      summary: json['summary'] as String? ?? '',
      limits: json['limits'] as String? ?? '',
      sources: _strings(json['sources']),
    );
  }
}

List<String> _strings(Object? json) => (json as List?)?.whereType<String>().toList() ?? const [];

/// Estimated loss of effect from a same-size dose, with its uncertainty band (all 0 to 1).
class EffectLoss {
  const EffectLoss(this.expected, this.low, this.high);
  final double expected;
  final double low;
  final double high;

  static const none = EffectLoss(0, 0, 0);

  int get percent => (expected * 100).round();
  int get lowPercent => (low * 100).round();
  int get highPercent => (high * 100).round();
}

/// One dose as the profile model sees it: when, how big (1.0 = a common dose), and which
/// profile and cross-tolerance factor it counts with.
class ProfileDose {
  const ProfileDose(this.at, this.weight, this.profile, this.factor);
  final DateTime at;
  final double weight;
  final ToleranceProfile profile;
  final double factor;
}

/// Combines doses: each dose leaves a fraction of the effect, and the fractions multiply, so
/// tolerance builds with repeated use but levels off below the profile's largest measured loss.
double combinedLoss(List<ProfileDose> doses, DateTime at, ToleranceBand band, {DateTime? upTo}) {
  final limit = upTo == null || upTo.isAfter(at) ? at : upTo;
  var remaining = 1.0;
  var cap = 1.0;
  for (final d in doses) {
    if (d.at.isAfter(limit)) continue;
    final hours = at.difference(d.at).inMicroseconds / Duration.microsecondsPerHour;
    final c = (d.profile.contribution(hours, d.weight, band) * d.factor).clamp(0.0, 1.0);
    remaining *= 1 - c;
    cap = min(cap, d.profile.maxLoss.pick(band));
  }
  return min(1 - remaining, cap);
}
