import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/sync.dart';

void main() {
  test('only private and Tailscale addresses are accepted from a peer', () {
    for (final ok in ['10.0.0.2', '192.168.1.5', '172.16.0.1', '172.31.255.1', '100.64.0.1', '100.126.148.55', '100.127.0.1']) {
      expect(isReachablePeerAddress(ok), isTrue, reason: ok);
    }
    for (final bad in ['8.8.8.8', '172.32.0.1', '100.128.0.1', '100.63.0.1', '127.0.0.1', '10.0.0', '10.0.0.256', 'abc', '10.0.0.1.5', '']) {
      expect(isReachablePeerAddress(bad), isFalse, reason: bad);
    }
  });
}
