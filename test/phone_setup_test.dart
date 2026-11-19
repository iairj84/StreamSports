import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/models/playlist_profile.dart';
import 'package:nox_iptv/models/surface_style.dart';
import 'package:nox_iptv/screens/setup_from_phone_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/app_update_service.dart';
import 'package:nox_iptv/services/catalog_database.dart';
import 'package:nox_iptv/services/epg_service.dart';
import 'package:nox_iptv/services/phone_pairing_service.dart';
import 'package:nox_iptv/services/playlist_manager.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';
import 'package:nox_iptv/widgets/phone_pair_panel.dart';

/// Only the parts of the playlist manager the setup path touches: saving,
/// the first load's success/failure, and the rollback that failure triggers.
class _Playlists extends PlaylistManager {
  _Playlists(StorageService storage) : super(storage, CatalogDatabase());

  final saved = <PlaylistProfile>[];
  final removed = <String>[];
  bool reject = false;
  String? _failure;

  @override
  List<PlaylistProfile> get profiles => saved;

  @override
  String? get error => _failure;

  @override
  Future<void> addPlaylist(PlaylistProfile profile) async => saved.add(profile);

  @override
  Future<void> loadPlaylist(String id) async {
    _failure = reject ? 'Provider rejected the account' : null;
  }

  @override
  Future<void> removePlaylist(String id) async {
    removed.add(id);
    saved.removeWhere((profile) => profile.id == id);
    _failure = null;
  }

  @override
  Set<String> knownChannelIdsFor(String playlistId) => const {};

  @override
  Set<String> knownChannelNamesFor(String playlistId) => const {};
}

/// The guide refreshes the setup starts are never fetched in a test; only the
/// fact that they were asked for is interesting.
class _Guide extends EpgService {
  _Guide(super.storage);

  final requested = <String>[];
  final headers = <Map<String, String>>[];

  @override
  Future<void> refresh(String url,
      {required Set<String> knownChannelIds,
      Set<String> knownChannelNames = const {},
      Map<String, String> headers = const {}}) async {
    requested.add(url);
    this.headers.add(headers);
  }

  @override
  Future<void> refreshPortal(String id) async => requested.add('portal:$id');
}

class _Harness {
  _Harness(this.storage, this.prefs, this.update, this.playlists, this.guide,
      this.navigatorKey);

  final StorageService storage;
  final AppPreferences prefs;
  final AppUpdateService update;
  final _Playlists playlists;
  final _Guide guide;
  final GlobalKey<NavigatorState> navigatorKey;
}

Future<_Harness> _pumpSetup(WidgetTester tester) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  final prefs = AppPreferences(storage);
  await prefs.init();
  prefs.isTelevision = true;
  final update = AppUpdateService(storage);
  final playlists = _Playlists(storage);
  final guide = _Guide(storage);
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<AppPreferences>.value(value: prefs),
        ChangeNotifierProvider<AppUpdateService>.value(value: update),
        ChangeNotifierProvider<PlaylistManager>.value(value: playlists),
        ChangeNotifierProvider<EpgService>.value(value: guide),
      ],
      child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('home')))));
  unawaited(navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SetupFromPhoneScreen())));
  await tester.pump();
  await tester.pump();
  return _Harness(storage, prefs, update, playlists, guide, navigatorKey);
}

/// The page's own callback, exactly as the QR session would invoke it: no
/// test-only entry into the screen's state.
///
/// Pumps frames rather than settling: the panel keeps a "waiting" spinner
/// running while it is on screen, so a settle only returns once the screen
/// has been left behind.
Future<void> _deliver(WidgetTester tester, PairingResult result) async {
  final panel = tester.widget<PhonePairPanel>(find.byType(PhonePairPanel));
  await tester.runAsync(() async {
    panel.onResult(result);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

PairingResult _setupPayload({Map<String, String>? settings}) =>
    PairingResult.fromJson({
      'mode': 'setup',
      'playlist': {
        'mode': 'xtream',
        'name': 'Living room',
        'server': 'http://host:8080',
        'username': 'someone',
        'password': 'secret',
        'epg': 'http://host/guide.xml',
      },
      'settings': settings ??
          const {
            // Every value differs from this build's default, so an
            // assertion here cannot pass by doing nothing.
            'palette': 'oled',
            'surface': 'stadium',
            'clock24': 'false',
            'scores': 'true',
            'update': 'early',
          },
    })!;

void main() {
  testWidgets('a setup payload applies every setting and adds the playlist',
      (tester) async {
    final harness = await _pumpSetup(tester);
    await _deliver(tester, _setupPayload());
    await tester.pumpAndSettle();

    // Every known settings key landed in the store the app reads at launch.
    expect(harness.storage.getPaletteId(), 'oled');
    expect(harness.storage.getSurfaceStyleId(), SurfaceStyle.stadium.name);
    expect(harness.storage.getTime24h(), isFalse);
    expect(harness.storage.getSportsHideScores(), isTrue);
    expect(harness.storage.getUpdateChannel(),
        AppConstants.updateChannelEarly);
    // ...and the live preference objects agree, so the current screen follows
    // without a relaunch.
    expect(harness.prefs.palette.id, 'oled');
    expect(harness.prefs.surfaceStyle, SurfaceStyle.stadium);

    // The playlist was added and kept, with the phone's credentials.
    expect(harness.playlists.saved, hasLength(1));
    final added = harness.playlists.saved.single;
    expect(added.mode, 'xtream');
    expect(added.name, 'Living room');
    expect(added.xtreamUsername, 'someone');
    expect(added.allEpgUrls, ['http://host/guide.xml']);
    expect(harness.playlists.removed, isEmpty);
    // Its guide started without blocking the screen.
    expect(harness.guide.requested, ['http://host/guide.xml']);

    // The setup screen is gone, back to the app underneath.
    expect(find.byType(SetupFromPhoneScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Setup complete. Your playlist is loading.'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    harness.prefs.dispose();
  });

  testWidgets('a settings key the phone page never offers changes nothing',
      (tester) async {
    final harness = await _pumpSetup(tester);
    final before = (
      palette: harness.storage.getPaletteId(),
      surface: harness.storage.getSurfaceStyleId(),
      clock24: harness.storage.getTime24h(),
      scores: harness.storage.getSportsHideScores(),
      update: harness.storage.getUpdateChannel(),
    );
    await _deliver(
        tester,
        const PairingResult(
            mode: 'm3u',
            name: 'One',
            m3uUrl: 'http://host/list.m3u',
            settings: {'alien': 'yes', 'surface2': 'stadium'},
            fromSetup: true));

    // Nothing a phone page never offers can be written; only the playlist is
    // added.
    expect(harness.storage.getPaletteId(), before.palette);
    expect(harness.storage.getSurfaceStyleId(), before.surface);
    expect(harness.storage.getTime24h(), before.clock24);
    expect(harness.storage.getSportsHideScores(), before.scores);
    expect(harness.storage.getUpdateChannel(), before.update);
    expect(harness.playlists.saved, hasLength(1));
    expect(harness.playlists.saved.single.mode, 'm3u');

    await tester.pumpWidget(const SizedBox());
    harness.prefs.dispose();
  });

  testWidgets('a failed first load rolls back and keeps the screen up',
      (tester) async {
    final harness = await _pumpSetup(tester);
    harness.playlists.reject = true;
    await _deliver(tester, _setupPayload());

    // The half-added profile is gone, so a retry cannot leave a duplicate.
    expect(harness.playlists.saved, isEmpty);
    expect(harness.playlists.removed, hasLength(1));
    // The screen stays up so the phone can be corrected and scanned again.
    expect(find.byType(SetupFromPhoneScreen), findsOneWidget);
    expect(
        find.text(
            'The playlist could not be added. Check its details on your phone and scan again.'),
        findsWidgets);
    // Settings were already applied before the add, and stay applied.
    expect(harness.storage.getPaletteId(), 'oled');
    // The QR panel is still there and offers another code, so correcting the
    // details on the phone costs one scan rather than a restart.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.byType(PhonePairPanel), findsOneWidget);
    expect(find.text('New code'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    harness.prefs.dispose();
  });

  testWidgets('a blank playlist on the setup page applies settings alone',
      (tester) async {
    final harness = await _pumpSetup(tester);
    // Exactly what the setup page sends when every playlist field is left
    // blank: a settings payload with no playlist in it.
    await _deliver(
        tester,
        PairingResult.fromJson({
          'mode': 'settings',
          'settings': const {
            'palette': 'oled',
            'surface': 'stadium',
            'clock24': 'false',
            'scores': 'true',
            'update': 'early',
          },
        })!);
    await tester.pumpAndSettle();

    expect(harness.storage.getPaletteId(), 'oled');
    expect(harness.storage.getSurfaceStyleId(), SurfaceStyle.stadium.name);
    expect(harness.storage.getTime24h(), isFalse);
    expect(harness.storage.getSportsHideScores(), isTrue);
    expect(harness.storage.getUpdateChannel(),
        AppConstants.updateChannelEarly);
    expect(harness.prefs.palette.id, 'oled');
    // No playlist was typed, so none is added and no guide starts.
    expect(harness.playlists.saved, isEmpty);
    expect(harness.playlists.removed, isEmpty);
    expect(harness.guide.requested, isEmpty);

    // Same landing as the settings screen: back underneath, settings saved.
    expect(find.byType(SetupFromPhoneScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Settings saved on your TV.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    harness.prefs.dispose();
  });

  test('a setup session accepts setup and settings-alone payloads', () {
    final setup = _setupPayload();
    final playlistOnly = PairingResult.fromJson({
      'mode': 'xtream',
      'name': 'Old code',
      'server': 'http://host:8080',
      'username': 'someone',
      'password': 'secret',
    })!;
    final settingsAlone = PairingResult.fromJson({
      'mode': 'settings',
      'settings': {'palette': 'oled'},
    })!;
    final setupSession = PhonePairingSession(kind: PairingKind.setup);
    expect(setupSession.acceptsResult(setup), isTrue);
    expect(setupSession.acceptsResult(settingsAlone), isTrue,
        reason:
            'a blank playlist on the setup page sends the settings alone');
    expect(setupSession.acceptsResult(playlistOnly), isFalse,
        reason: 'a playlist-only payload must not reach the settings writer');
    // The other direction: an old Add Playlist code cannot apply settings.
    final playlistSession = PhonePairingSession();
    expect(playlistSession.acceptsResult(playlistOnly), isTrue);
    expect(playlistSession.acceptsResult(setup), isFalse);
    expect(playlistSession.acceptsResult(settingsAlone), isFalse);
  });
}
