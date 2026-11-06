import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/services/device_transfer_service.dart';
import 'package:nox_iptv/services/settings_bundle.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what a transfer carries', () {
    test('sports picks and lists travel for every viewer', () {
      expect(transferSectionOf(AppConstants.keySportsLeagues),
          TransferSection.sports);
      expect(
          transferSectionOf('${AppConstants.keySportsLeagues}'
              '${AppConstants.viewerKeySuffix}kid'),
          TransferSection.sports);
      expect(transferSectionOf(AppConstants.keyFavorites),
          TransferSection.lists);
      expect(transferSectionOf('${AppConstants.keyHiddenChannels}'
          '${AppConstants.viewerKeySuffix}kid'),
          TransferSection.lists);
    });

    test('playlists, including their logins, are their own section', () {
      expect(transferSectionOf(AppConstants.keyPlaylists),
          TransferSection.playlists);
      expect(transferSectionOf(AppConstants.keyXtreamPassword),
          TransferSection.playlists);
      expect(transferSectionOf(AppConstants.keyM3uUrl),
          TransferSection.playlists);
    });

    test('device state and caches never travel', () {
      for (final key in [
        AppConstants.keyLastChannelId,
        'nox_last_position_abc',
        'nox_last_duration_abc',
        'nox_last_full_sync_at_abc',
        AppConstants.keyCloudTransfer,
        AppConstants.keyActiveViewerId,
        AppConstants.keyLayoutMode,
        AppConstants.keyVideoFill,
        AppConstants.keyEpgCache,
        AppConstants.keySkippedUpdateVersion,
        AppConstants.keyWindowsBounds,
        'iptv_classic_layout_v1',
        'sports_coverage_v92',
      ]) {
        expect(transferSectionOf(key), isNull, reason: key);
      }
    });

    test('ordinary preferences are settings', () {
      expect(transferSectionOf(AppConstants.keyPaletteId),
          TransferSection.settings);
      expect(transferSectionOf(AppConstants.keyLanguage),
          TransferSection.settings);
      expect(transferSectionOf(AppConstants.keyViewerProfiles),
          TransferSection.settings);
    });
  });

  group('bundle', () {
    late StorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyPlaylists: '[{"id":"source"}]',
        AppConstants.keySportsLeagues: ['nba', 'eng.1'],
        AppConstants.keyLastChannelId: 'channel-9',
        AppConstants.keyPaletteId: 'classic_tv',
        // Skip the one-time coverage migration so the picks stay as seeded.
        'sports_coverage_v92': true,
      });
      storage = StorageService();
      await storage.init();
    });

    test('capture leaves device-only keys behind and encodes to JSON', () async {
      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      expect(bundle.values.containsKey(AppConstants.keyLastChannelId), isFalse);
      expect(bundle.values[AppConstants.keySportsLeagues],
          ['nba', 'eng.1']);
      expect(bundle.sections, contains(TransferSection.playlists));

      final decoded = SettingsBundle.fromJson(jsonDecode(bundle.encode()))!;
      expect(decoded.values[AppConstants.keyPlaylists], '[{"id":"source"}]');
      expect(decoded.sections, bundle.sections);
    });

    test('a newer or malformed format is refused', () {
      expect(SettingsBundle.fromJson({'format': 99, 'values': {}}), isNull);
      expect(SettingsBundle.fromJson({'format': 1, 'values': []}), isNull);
      expect(
          SettingsBundle.fromJson({
            'format': 1,
            'values': {'k': {'nested': 1}},
          }),
          isNull);
    });

    test('applying replaces the destination, keeps device state', () async {
      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      await storage.replaceRawPreferences({
        AppConstants.keyPlaylists: '[{"id":"destination"}]',
        AppConstants.keyPaletteId: 'light',
        'vesper_hide_archive': true,
      }, remove: []);

      final report = await bundle.applyTo(storage);
      final after = storage.rawPreferences();

      expect(after[AppConstants.keyPlaylists], '[{"id":"source"}]');
      expect(after[AppConstants.keyPaletteId], 'classic_tv');
      // Only on the destination, so the replacement clears it.
      expect(after.containsKey('vesper_hide_archive'), isFalse);
      // Belongs to this device, so the transfer leaves it alone.
      expect(after[AppConstants.keyLastChannelId], 'channel-9');
      expect(report.values, bundle.values.length);
      expect(report.sections, contains(TransferSection.playlists));
    });

    test('a section that was not sent is left alone', () async {
      final bundle = SettingsBundle.capture(storage,
          sections: {TransferSection.settings});
      await storage.replaceRawPreferences({
        AppConstants.keyPlaylists: '[{"id":"destination"}]',
      }, remove: []);
      await bundle.applyTo(storage);
      expect(storage.rawPreferences()[AppConstants.keyPlaylists],
          '[{"id":"destination"}]');
    });
  });

  group('crypto', () {
    test('both sides derive the same key and read the payload', () async {
      final a = TransferCipher(sessionId: 'session-1');
      final b = TransferCipher(sessionId: 'session-1');
      final aPublic = await a.ensureKeyPair();
      final bPublic = await b.ensureKeyPair();
      await a.derive(bPublic);
      await b.derive(aPublic);

      final sealed = await a.seal('{"values":{"nox_playlists":"x"}}');
      expect(await b.open(sealed), '{"values":{"nox_playlists":"x"}}');
    });

    test('tampering and a different session both fail closed', () async {
      final a = TransferCipher(sessionId: 'session-1');
      final b = TransferCipher(sessionId: 'session-1');
      final wrong = TransferCipher(sessionId: 'session-2');
      final aPublic = await a.ensureKeyPair();
      final bPublic = await b.ensureKeyPair();
      final wrongPublic = await wrong.ensureKeyPair();
      await a.derive(bPublic);
      await b.derive(aPublic);
      await wrong.derive(bPublic);

      final sealed = await a.seal('secret');
      final json = jsonDecode(sealed) as Map<String, dynamic>;
      final bytes = base64.decode(json['ct'] as String);
      bytes[0] ^= 0xff;
      json['ct'] = base64.encode(bytes);

      expect(await b.open(jsonEncode(json)), isNull);
      expect(await wrong.open(sealed), isNull);
      expect(await b.open('not json'), isNull);
      expect(wrongPublic.length, 32);
    });

    test('the confirmation code does not depend on who asks', () {
      final one = List<int>.filled(32, 7);
      final two = List<int>.filled(32, 9);
      expect(transferCode(one, two, 'abc'), transferCode(two, one, 'abc'));
      expect(transferCode(one, two, 'abc'),
          isNot(transferCode(one, two, 'abd')));
      expect(transferCode(one, two, 'abc'), matches(RegExp(r'^\d{3} \d{3}$')));
    });
  });

  test('a real transfer over loopback replaces the receiver', () async {
    // flutter_test replaces HttpClient with one that answers 400; this test
    // needs a real socket pair on loopback.
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    SharedPreferences.setMockInitialValues({
      'sports_coverage_v92': true,
      AppConstants.keyPlaylists: '[{"id":"source"}]',
      AppConstants.keySportsLeagues: ['nba'],
      AppConstants.keyLastChannelId: 'channel-9',
    });
    final storage = StorageService();
    await storage.init();

    final receiver = TransferReceiver(storage, deviceName: 'TV');
    await receiver.start(
        bindAddress: InternetAddress.loopbackIPv4, discovery: false);
    final approval =
        receiver.status.firstWhere((s) => s.phase == TransferPhase.approval);

    final peer = TransferPeer(
      id: receiver.sessionId,
      name: 'TV',
      address: '127.0.0.1',
      port: receiver.port!,
      token: receiver.token,
      publicKey: receiver.publicKey,
    );
    final sender = TransferSender(storage, deviceName: 'Phone');
    final request = sender.request(peer);

    await approval.timeout(const Duration(seconds: 10));
    await receiver.approve();
    final handshake = await request.timeout(const Duration(seconds: 10));
    expect(handshake.approved, isTrue);
    expect(handshake.code, matches(RegExp(r'^\d{3} \d{3}$')));

    final report = await sender.send(peer, handshake,
        sections: TransferSection.values.toSet());
    expect(report, isNotNull);
    expect(report!.values, greaterThan(0));
    expect(storage.rawPreferences()[AppConstants.keyLastChannelId],
        'channel-9');

    await receiver.stop();
    sender.dispose();
  });
}
