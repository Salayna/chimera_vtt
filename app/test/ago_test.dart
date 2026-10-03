import 'package:chimera_vtt/campaigns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('when a campaign was played, in words', () {
    final now = DateTime(2026, 10, 3, 18);
    String at(Duration d) => ago(now.subtract(d), now);
    expect(at(const Duration(seconds: 20)), 'just now');
    expect(at(const Duration(minutes: 5)), '5 min ago');
    expect(at(const Duration(hours: 3)), '3 h ago');
    expect(at(const Duration(hours: 30)), 'yesterday');
    expect(at(const Duration(days: 4)), '4 days ago');
    expect(ago(DateTime(2026, 9, 1), now), 'on 1 September');
    expect(ago(DateTime(2025, 9, 1), now), 'on 1 September 2025');
  });
}
