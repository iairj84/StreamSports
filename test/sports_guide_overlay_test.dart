import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/models/sports.dart';
import 'package:nox_iptv/services/sports_guide_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final league = sportsLeagueById('eng.1')!;

  SportsGame game({
    String id = '1',
    DateTime? start,
    DateTime? end,
    String home = 'Arsenal',
    String away = 'Chelsea',
  }) =>
      SportsGame(
          id: id,
          league: league,
          start: start ?? DateTime.now().add(const Duration(hours: 2)),
          end: end,
          state: GameState.pre,
          statusText: 'Scheduled',
          home: SportsTeam(
              id: 'h',
              name: home,
              shortName: home,
              abbreviation: 'HOM',
              score: '0'),
          away: SportsTeam(
              id: 'a',
              name: away,
              shortName: away,
              abbreviation: 'AWY',
              score: '0'));

  test('publishes a fixture under the normalized channel id', () {
    final overlay = SportsGuideOverlay();
    final fixture = game();

    overlay.publish([SportsGuideBinding(' ESPN4K.US ', fixture)]);

    final rows = overlay.programmesFor('espn4k.us')!;
    expect(rows, hasLength(1));
    expect(rows.single.channelId, 'espn4k.us');
    expect(rows.single.title, 'Arsenal vs Chelsea');
    expect(rows.single.description, league.name);
    expect(rows.single.start, fixture.start);
    expect(overlay.programmesFor('other.us'), isNull);
  });

  test('uses the scheduled end, otherwise a bounded default slot', () {
    final overlay = SportsGuideOverlay();
    final start = DateTime.now().add(const Duration(hours: 1));
    final end = start.add(const Duration(minutes: 150));

    overlay.publish([
      SportsGuideBinding('ended', game(id: 'ended', start: start, end: end)),
      SportsGuideBinding('open', game(id: 'open', start: start)),
    ]);

    expect(overlay.programmesFor('ended')!.single.stop, end);
    expect(overlay.programmesFor('open')!.single.stop,
        start.add(const Duration(hours: 3)));
  });

  test('omits fixtures beyond the horizon and already forgotten', () {
    final overlay = SportsGuideOverlay();
    final now = DateTime.now();

    overlay.publish([
      SportsGuideBinding(
          'later', game(id: 'later', start: now.add(const Duration(hours: 30)))),
      SportsGuideBinding(
          'gone',
          game(
              id: 'gone',
              start: now.subtract(const Duration(hours: 20)),
              end: now.subtract(const Duration(hours: 18)))),
    ]);

    expect(overlay.programmesFor('later'), isNull);
    expect(overlay.programmesFor('gone'), isNull);
    expect(overlay.isEmpty, isTrue);
  });

  test('a new scope drops the previous scope listings', () {
    final overlay = SportsGuideOverlay();
    overlay.publish([SportsGuideBinding('old', game())], scope: 'playlist-a');
    expect(overlay.programmesFor('old'), isNotNull);

    overlay.publish([SportsGuideBinding('new', game(id: '2'))],
        scope: 'playlist-b');

    expect(overlay.programmesFor('old'), isNull);
    expect(overlay.programmesFor('new'), isNotNull);
  });

  test('identical republishing does not notify the guide', () {
    final overlay = SportsGuideOverlay();
    var notifications = 0;
    overlay.addListener(() => notifications++);
    final bindings = [SportsGuideBinding('ch', game())];

    overlay.publish(bindings);
    final revision = overlay.revision;
    overlay.publish(bindings);

    expect(overlay.revision, revision);
    expect(notifications, 1);
  });

  test('keeps a channel to one bounded day of fixtures', () {
    final overlay = SportsGuideOverlay();
    final start = DateTime.now().add(const Duration(minutes: 30));

    overlay.publish([
      for (var i = 0; i < 14; i++)
        SportsGuideBinding(
            'ch',
            game(
                id: 'g$i',
                start: start.add(Duration(minutes: i * 60)),
                end: start.add(Duration(minutes: i * 60 + 45)))),
    ]);

    expect(overlay.programmesFor('ch'), hasLength(12));
  });

  test('finds the fixture that is on now', () {
    final overlay = SportsGuideOverlay();
    final now = DateTime.now();
    final fixture = game(
        start: now.subtract(const Duration(minutes: 30)),
        end: now.add(const Duration(minutes: 90)));

    overlay.publish([SportsGuideBinding('ch', fixture)]);

    expect(overlay.currentProgram('ch', now)?.title, 'Arsenal vs Chelsea');
    expect(overlay.nextProgram('ch', now), isNull);
  });
}
