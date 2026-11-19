import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/models/surface_style.dart';
import 'package:nox_iptv/screens/settings/settings_from_phone_screen.dart';
import 'package:nox_iptv/services/app_preferences.dart';
import 'package:nox_iptv/services/app_update_service.dart';
import 'package:nox_iptv/services/phone_pairing_service.dart';
import 'package:nox_iptv/services/phone_settings.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';
import 'package:nox_iptv/widgets/phone_pair_panel.dart';

/// Deliberately no [PlaylistManager]: the whole point of this screen is that a
/// settings change does not need a playlist to exist, and a provider that is
/// absent here fails loudly if that ever stops being true.
Future<(StorageService, AppPreferences)> _pump(WidgetTester tester) async {
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
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<AppPreferences>.value(value: prefs),
        ChangeNotifierProvider<AppUpdateService>.value(value: update),
      ],
      child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('home')))));
  unawaited(navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (_) => const SettingsFromPhoneScreen())));
  await tester.pump();
  await tester.pump();
  return (storage, prefs);
}

/// The page's own callback, exactly as the QR session invokes it.
Future<void> _deliver(WidgetTester tester, PairingResult result) async {
  final panel = tester.widget<PhonePairPanel>(find.byType(PhonePairPanel));
  await tester.runAsync(() async {
    panel.onResult(result);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

PairingResult _settingsPayload([Map<String, String> extra = const {}]) =>
    PairingResult.fromJson({
      'mode': 'settings',
      'settings': {
        // Every value differs from this build's default, so an assertion here
        // cannot pass by doing nothing.
        'palette': 'stadium_night',
        'surface': 'stadium',
        'clock24': 'false',
        'language': 'en',
        'buffer': 'balanced',
        'livebuffer': '4000',
        'startup': 'preview',
        'updateplaylists': 'true',
        'pip': 'true',
        'resumepill': 'false',
        'moviestab': 'false',
        'seriestab': 'true',
        'multiview': 'false',
        'scores': 'true',
        'update': 'early',
        ...extra,
      },
    })!;

void main() {
  testWidgets('a settings payload lands with no playlist anywhere in sight',
      (tester) async {
    final (storage, prefs) = await _pump(tester);
    await _deliver(tester, _settingsPayload());
    await tester.pumpAndSettle();

    expect(storage.getPaletteId(), 'stadium_night');
    expect(storage.getSurfaceStyleId(), SurfaceStyle.stadium.name);
    expect(storage.getTime24h(), isFalse);
    expect(storage.getPlaybackBuffer(), 'balanced');
    expect(storage.getLiveBufferMs(), 4000);
    expect(storage.getResumeLastChannelAtStartup(), isFalse);
    expect(storage.getResumeLastChannelInGuide(), isTrue);
    expect(storage.getUpdatePlaylistsAtStartup(), isTrue);
    expect(storage.getPictureInPictureOnHome(), isTrue);
    expect(storage.getShowResumePill(), isFalse);
    expect(storage.getHideMovies(), isTrue);
    expect(storage.getHideShows(), isFalse);
    expect(storage.getSportsHideScores(), isTrue);
    expect(storage.getUpdateChannel(), AppConstants.updateChannelEarly);

    // ...and the live objects follow, so the screens behind this one repaint.
    expect(prefs.palette.id, 'stadium_night');
    expect(prefs.surfaceStyle, SurfaceStyle.stadium);
    expect(prefs.use24h, isFalse);
    expect(prefs.language, 'en');
    expect(prefs.hideMultiview, isTrue);

    // The code is done and the app is back underneath.
    expect(find.byType(SettingsFromPhoneScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Settings saved on your TV.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    prefs.dispose();
  });

  testWidgets('values this build does not know are ignored, not fatal',
      (tester) async {
    final (storage, prefs) = await _pump(tester);
    final before = (
      palette: storage.getPaletteId(),
      surface: storage.getSurfaceStyleId(),
      clock24: storage.getTime24h(),
      buffer: storage.getPlaybackBuffer(),
      livebuffer: storage.getLiveBufferMs(),
      startup: storage.getResumeLastChannelAtStartup(),
      scores: storage.getSportsHideScores(),
    );
    // An older build meeting values added by a newer page: every key is one
    // it knows, no value is.
    await _deliver(
        tester,
        PairingResult.fromJson({
          'mode': 'settings',
          'settings': {
            'palette': 'neon',
            'surface': 'bubble',
            'clock24': 'maybe',
            'buffer': 'turbo',
            'livebuffer': '999',
            'startup': 'sometime',
          },
        })!);

    expect(storage.getPaletteId(), before.palette);
    expect(storage.getSurfaceStyleId(), before.surface);
    expect(storage.getTime24h(), before.clock24);
    expect(storage.getPlaybackBuffer(), before.buffer);
    expect(storage.getLiveBufferMs(), before.livebuffer);
    expect(storage.getResumeLastChannelAtStartup(), before.startup);
    expect(storage.getSportsHideScores(), before.scores);
    // The form was accepted and the code is spent, as it would be for any
    // payload the session accepts.
    expect(find.byType(SettingsFromPhoneScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    prefs.dispose();
  });

  test('the payload rules accept settings alone and nothing else', () {
    expect(_settingsPayload().mode, 'settings');
    expect(_settingsPayload().fromSetup, isFalse);
    // No playlist fields were invented for a settings payload.
    expect(_settingsPayload().name, isEmpty);
    expect(_settingsPayload().server, isEmpty);

    // Nothing to apply is not a result.
    expect(PairingResult.fromJson({'mode': 'settings'}), isNull);
    expect(
        PairingResult.fromJson({'mode': 'settings', 'settings': {}}), isNull);
    expect(
        PairingResult.fromJson({
          'mode': 'settings',
          'settings': {'alien': 'yes'}
        }),
        isNull);

    final settings = _settingsPayload();
    expect(PhonePairingSession(kind: PairingKind.settings)
        .acceptsResult(settings), isTrue);
    // A playlist code must not write preferences...
    expect(PhonePairingSession().acceptsResult(settings), isFalse);
    // ...and a settings code must not add a playlist.
    final setup = PairingResult.fromJson({
      'mode': 'setup',
      'playlist': {'mode': 'm3u', 'name': 'One', 'm3u': 'http://host/l.m3u'},
      'settings': {'palette': 'oled'},
    })!;
    expect(PhonePairingSession(kind: PairingKind.settings)
        .acceptsResult(setup), isFalse);
  });

  test('the phone is told what this device has now', () {
    final session = PhonePairingSession(
        kind: PairingKind.settings,
        palette: 'stadium_night',
        surface: 'stadium',
        settings: const {
          'palette': 'stadium_night',
          'surface': 'stadium',
          'clock24': '0',
          'buffer': 'balanced',
          'update': 'stable',
        });
    final query = session.lookQuery;
    expect(query, contains('p=stadium_night'));
    expect(query, contains('s=stadium'));
    expect(query, contains('clock24=0'));
    expect(query, contains('buffer=balanced'));
    // The look travels once, under the keys the page already reads.
    expect(query, isNot(contains('palette=')));
    expect(query, isNot(contains('surface=')));
  });

  test('a snapshot survives the payload rules unchanged', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final prefs = AppPreferences(storage);
    await prefs.init();

    final snapshot = phoneSettingsSnapshot(prefs: prefs, storage: storage);
    // Every offered key travels; a new one cannot be half-wired.
    expect(snapshot.keys.toSet(), phoneSettingKeys.toSet());
    final payload =
        PairingResult.fromJson({'mode': 'settings', 'settings': snapshot})!;
    expect(payload.settings, snapshot);

    prefs.dispose();
  });
}
