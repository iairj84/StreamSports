import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/sports_channel_matcher.dart';

void main() {
  test('scopeGuideIds covers every stored form of each guide id', () {
    final scope = SportsChannelMatcher.scopeGuideIds([
      'ESPN.us',
      '  Sky Sports Main Event  ',
      '',
      'espn.us', // duplicate of the first once normalized
      'BBC One',
    ]);
    // The superset property the scorer relies on: the normalized form that
    // matching itself uses is always in scope, so no usable row is excluded.
    for (final id in [
      'ESPN.us',
      '  Sky Sports Main Event  ',
      'BBC One',
      'espn.us',
    ]) {
      expect(scope, contains(normalizeEpgId(id)));
    }
    // Raw and trimmed forms survive too, so provider casing never excludes
    // a row the normalized lookup would have accepted.
    expect(scope, contains('ESPN.us'));
    expect(scope, contains('Sky Sports Main Event'));
    // Empties contribute nothing.
    expect(scope.any((id) => id.isEmpty), isFalse);
    // Deduplicated.
    expect(scope.length, scope.toSet().length);
  });
}
