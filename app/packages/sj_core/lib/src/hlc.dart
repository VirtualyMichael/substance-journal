/// Hybrid logical clock used to order edits across devices without trusting wall clocks.
///
/// Text form `<15-digit ms>-<4-hex counter>-<node id>` sorts lexicographically in the
/// same order as [compareTo], so it can be stored in SQLite and compared as a string.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.wallMillis, this.counter, this.nodeId);

  final int wallMillis;
  final int counter;
  final String nodeId;

  static const int _maxCounter = 0xffff;

  /// Remote clocks further ahead than this are rejected instead of dragging ours forward.
  static const int maxDriftMillis = 24 * 60 * 60 * 1000;

  factory Hlc.zero(String nodeId) => Hlc(0, 0, nodeId);

  factory Hlc.parse(String text) {
    final parts = text.split('-');
    if (parts.length < 3) throw FormatException('Not an HLC: $text');
    return Hlc(int.parse(parts[0]), int.parse(parts[1], radix: 16), parts.sublist(2).join('-'));
  }

  /// Next clock value for a local event (an edit made on this device).
  Hlc send(int nowMillis) {
    if (nowMillis > wallMillis) return Hlc(nowMillis, 0, nodeId);
    if (counter >= _maxCounter) throw StateError('HLC counter overflow');
    return Hlc(wallMillis, counter + 1, nodeId);
  }

  /// Clock value after seeing [remote], so later local edits sort after it.
  Hlc receive(Hlc remote, int nowMillis) {
    if (remote.wallMillis - nowMillis > maxDriftMillis) {
      throw StateError('Remote clock is too far ahead (${remote.wallMillis - nowMillis} ms)');
    }
    final wall = [wallMillis, remote.wallMillis, nowMillis].reduce((a, b) => a > b ? a : b);
    int next;
    if (wall == wallMillis && wall == remote.wallMillis) {
      next = (counter > remote.counter ? counter : remote.counter) + 1;
    } else if (wall == wallMillis) {
      next = counter + 1;
    } else if (wall == remote.wallMillis) {
      next = remote.counter + 1;
    } else {
      next = 0;
    }
    if (next > _maxCounter) throw StateError('HLC counter overflow');
    return Hlc(wall, next, nodeId);
  }

  @override
  int compareTo(Hlc other) {
    final byWall = wallMillis.compareTo(other.wallMillis);
    if (byWall != 0) return byWall;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc && wallMillis == other.wallMillis && counter == other.counter && nodeId == other.nodeId;

  @override
  int get hashCode => Object.hash(wallMillis, counter, nodeId);

  @override
  String toString() =>
      '${wallMillis.toString().padLeft(15, '0')}-${counter.toRadixString(16).padLeft(4, '0')}-$nodeId';
}
