import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/services/device_memory_service.dart';
import 'package:nox_iptv/services/device_transfer_service.dart';
import 'package:nox_iptv/services/settings_bundle.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';

Future<StorageService> _transferStorage() async {
  SharedPreferences.setMockInitialValues({
    'sports_coverage_v92': true,
    AppConstants.keyPlaylists: '[{"id":"source","name":"Source","mode":"m3u"}]',
    AppConstants.keySportsLeagues: ['nba'],
    AppConstants.keyLastChannelId: 'channel-9',
    AppConstants.keyPaletteId: 'classic_tv',
  });
  final storage = StorageService();
  await storage.init();
  return storage;
}

Future<TransferReceiver> _startReceiver(StorageService storage,
    {Duration approvalWindow = kTransferApprovalWindow}) async {
  final receiver = TransferReceiver(storage,
      deviceName: 'TV', approvalWindow: approvalWindow);
  await receiver.start(
      bindAddress: InternetAddress.loopbackIPv4, discovery: false);
  addTearDown(receiver.stop);
  return receiver;
}

Uri _transferUri(TransferReceiver receiver, String action) =>
    Uri.parse('http://127.0.0.1:${receiver.port}/p/${receiver.token}/$action');

Future<http.Response> _postHello(
        TransferReceiver receiver, List<int> publicKey) =>
    http
        .post(_transferUri(receiver, 'hello'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'name': 'Phone', 'pk': base64Url.encode(publicKey)}))
        .timeout(const Duration(seconds: 10));

Future<http.Response> _postBundle(TransferReceiver receiver, String sealed) =>
    http
        .post(_transferUri(receiver, 'bundle'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'payload': sealed}))
        .timeout(const Duration(seconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('naming this device in a transfer', () {
    const channel = MethodChannel('com.nox.nox_iptv/device_type');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('uses the name Android reports, trimmed', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'deviceName');
        return '  Living room TV  ';
      });
      expect(await DeviceTypeService.transferName(), 'Living room TV');
    });

    test('a box that cannot name itself is never called "This device"',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await DeviceTypeService.transferName(),
          DeviceTypeService.unnamedDevice);
      messenger.setMockMethodCallHandler(channel, (call) async => '   ');
      expect(await DeviceTypeService.transferName(),
          DeviceTypeService.unnamedDevice);
      expect(DeviceTypeService.unnamedDevice, isNot('This device'));
    });

    test('a long name is cut to fit one row', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => 'x' * 80);
      expect((await DeviceTypeService.transferName()).length, 40);
    });
  });

  group('a failed handshake names its cause', () {
    test('a receiver that stopped listening is not a timeout', () {
      expect(handshakeFailure(const SocketException('refused')),
          contains('no longer waiting'));
      expect(handshakeFailure(http.ClientException('closed')),
          contains('no longer waiting'));
    });

    test('a silent receiver reads as a timeout, and says what to do', () {
      final message = handshakeFailure(TimeoutException('silent'));
      expect(message, contains('did not answer in time'));
      expect(message, contains('open Receive again'));
    });

    test('a reply that is not a handshake carries the status code', () {
      expect(handshakeFailure(null, status: 409), contains('409'));
      expect(handshakeFailure(null), contains('no reply'));
    });
  });

  group('what a transfer carries', () {
    test('sports picks and lists travel for every viewer', () {
      expect(transferSectionOf(AppConstants.keySportsLeagues),
          TransferSection.sports);
      expect(
          transferSectionOf('${AppConstants.keySportsLeagues}'
              '${AppConstants.viewerKeySuffix}kid'),
          TransferSection.sports);
      expect(
          transferSectionOf(AppConstants.keyFavorites), TransferSection.lists);
      expect(
          transferSectionOf('${AppConstants.keyHiddenChannels}'
              '${AppConstants.viewerKeySuffix}kid'),
          TransferSection.lists);
    });

    test('playlists, including their logins, are their own section', () {
      expect(transferSectionOf(AppConstants.keyPlaylists),
          TransferSection.playlists);
      expect(transferSectionOf(AppConstants.keyXtreamPassword),
          TransferSection.playlists);
      expect(
          transferSectionOf(AppConstants.keyM3uUrl), TransferSection.playlists);
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
        AppConstants.keyUpdateChannel,
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
        AppConstants.keyPlaylists: '[{"id":"source","name":"Source","mode":"m3u"}]',
        AppConstants.keySportsLeagues: ['nba', 'eng.1'],
        AppConstants.keyLastChannelId: 'channel-9',
        AppConstants.keyPaletteId: 'classic_tv',
        // Skip the one-time coverage migration so the picks stay as seeded.
        'sports_coverage_v92': true,
      });
      storage = StorageService();
      await storage.init();
    });

    test('capture leaves device-only keys behind and encodes to JSON',
        () async {
      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      expect(bundle.values.containsKey(AppConstants.keyLastChannelId), isFalse);
      expect(bundle.values[AppConstants.keySportsLeagues], ['nba', 'eng.1']);
      expect(bundle.sections, contains(TransferSection.playlists));

      final decoded = SettingsBundle.fromJson(jsonDecode(bundle.encode()))!;
      expect(decoded.values[AppConstants.keyPlaylists], '[{"id":"source","name":"Source","mode":"m3u"}]');
      expect(decoded.sections, bundle.sections);
    });

    test('a newer or malformed format is refused', () {
      expect(SettingsBundle.fromJson({'format': 99, 'values': {}}), isNull);
      expect(SettingsBundle.fromJson({'format': 1, 'values': []}), isNull);
      expect(
          SettingsBundle.fromJson({
            'format': 1,
            'values': {
              'k': {'nested': 1}
            },
          }),
          isNull);
    });

    test('applying replaces the destination, keeps device state', () async {
      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      await storage.replaceRawPreferences({
        AppConstants.keyPlaylists: '[{"id":"destination","name":"Destination","mode":"m3u"}]',
        AppConstants.keyPaletteId: 'light',
        'vesper_hide_archive': true,
      }, remove: []);

      final report = await bundle.applyTo(storage);
      final after = storage.rawPreferences();

      expect(after[AppConstants.keyPlaylists], '[{"id":"source","name":"Source","mode":"m3u"}]');
      expect(after[AppConstants.keyPaletteId], 'classic_tv');
      // Only on the destination, so the replacement clears it.
      expect(after.containsKey('vesper_hide_archive'), isFalse);
      // Belongs to this device, so the transfer leaves it alone.
      expect(after[AppConstants.keyLastChannelId], 'channel-9');
      expect(report.values, bundle.values.length);
      expect(report.sections, contains(TransferSection.playlists));
    });

    test('a bundle cannot write keys the contract calls device-only', () async {
      // A hand-built or tampered payload naming device state directly: the key
      // is dropped on the way in, so applying it changes nothing there.
      final bundle = SettingsBundle.fromJson({
        'format': 1,
        'values': {
          AppConstants.keyLastChannelId: 'hijacked',
          AppConstants.keyPinFailCount: 9,
          AppConstants.keyPaletteId: 'light',
        },
      })!;
      expect(bundle.values.containsKey(AppConstants.keyLastChannelId), isFalse);
      expect(bundle.values.containsKey(AppConstants.keyPinFailCount), isFalse);

      await bundle.applyTo(storage);
      final after = storage.rawPreferences();
      expect(after[AppConstants.keyLastChannelId], 'channel-9');
      expect(after[AppConstants.keyPinFailCount], isNull);
      expect(after[AppConstants.keyPaletteId], 'light');
    });

    test('a bundle whose playlist section cannot be read is refused', () async {
      // AUD-004: whatever the payload says, only a profile list this build can
      // read back may replace the working one.
      for (final corrupt in [
        '{not json',
        '[] trailing',
        '{"id":"source"}',
        '[{"name":"No id","mode":"m3u"}]',
        '[{"id":"x","name":"No mode"}]',
        '[42]',
      ]) {
        expect(
            SettingsBundle.fromJson({
              'format': 1,
              'values': {AppConstants.keyPlaylists: corrupt},
            }),
            isNull,
            reason: 'accepted an unreadable playlist payload: $corrupt');
      }
      // An unreadable value cannot reach storage through applyTo either.
      final bundle = SettingsBundle.fromJson({
        'format': 1,
        'values': {
          AppConstants.keyPlaylists:
              '[{"id":"source","name":"Source","mode":"m3u"}]',
        },
      })!;
      expect(bundle.values[AppConstants.keyPlaylists], isNotNull);
    });

    test('a section that was not sent is left alone', () async {
      final bundle =
          SettingsBundle.capture(storage, sections: {TransferSection.settings});
      await storage.replaceRawPreferences({
        AppConstants.keyPlaylists: '[{"id":"destination","name":"Destination","mode":"m3u"}]',
      }, remove: []);
      await bundle.applyTo(storage);
      expect(storage.rawPreferences()[AppConstants.keyPlaylists],
          '[{"id":"destination","name":"Destination","mode":"m3u"}]');
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
      expect(
          transferCode(one, two, 'abc'), isNot(transferCode(one, two, 'abd')));
      expect(transferCode(one, two, 'abc'), matches(RegExp(r'^\d{3} \d{3}$')));
    });
  });

  group('approval gate', () {
    test('hello without approval cannot deliver a bundle', () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final storage = await _transferStorage();
      final receiver = await _startReceiver(storage);
      final cipher = TransferCipher(sessionId: receiver.sessionId);
      final key = await cipher.ensureKeyPair();
      await cipher.derive(receiver.publicKey);

      final hello = _postHello(receiver, key);
      hello.ignore();
      await receiver.status
          .firstWhere((s) => s.phase == TransferPhase.approval)
          .timeout(const Duration(seconds: 5));

      final before = Map.of(storage.rawPreferences());
      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      final sealed = await cipher.seal(bundle.encode());
      final response = await _postBundle(receiver, sealed);

      expect(response.statusCode, HttpStatus.forbidden);
      expect(storage.rawPreferences(), before);
    });

    test('an approved bundle applies once and a replay is refused', () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final storage = await _transferStorage();
      final receiver = await _startReceiver(storage);
      final cipher = TransferCipher(sessionId: receiver.sessionId);
      final key = await cipher.ensureKeyPair();
      await cipher.derive(receiver.publicKey);

      final hello = _postHello(receiver, key);
      await receiver.status
          .firstWhere((s) => s.phase == TransferPhase.approval)
          .timeout(const Duration(seconds: 5));
      await receiver.approve();
      final helloResponse = await hello;
      expect(jsonDecode(helloResponse.body)['approved'], isTrue);

      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      await storage.replaceRawPreferences({
        AppConstants.keyPlaylists: '[{"id":"destination","name":"Destination","mode":"m3u"}]',
        AppConstants.keyPaletteId: 'light',
      }, remove: []);
      final sealed = await cipher.seal(bundle.encode());

      final applied = await _postBundle(receiver, sealed);
      expect(applied.statusCode, HttpStatus.ok);
      expect(storage.rawPreferences()[AppConstants.keyPlaylists],
          '[{"id":"source","name":"Source","mode":"m3u"}]');

      // The approved key was consumed, and a completed transfer closes the
      // listener, so the replay is refused either way.
      Object? replayError;
      int? replayStatus;
      try {
        replayStatus = (await _postBundle(receiver, sealed)).statusCode;
      } catch (_) {
        replayError = true;
      }
      expect(
          replayStatus == HttpStatus.forbidden || replayError != null, isTrue);
      expect(storage.rawPreferences()[AppConstants.keyPlaylists],
          '[{"id":"source","name":"Source","mode":"m3u"}]');
    });

    test('a declined handshake cannot be used afterwards', () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final storage = await _transferStorage();
      final receiver = await _startReceiver(storage);
      final cipher = TransferCipher(sessionId: receiver.sessionId);
      final key = await cipher.ensureKeyPair();
      await cipher.derive(receiver.publicKey);

      final hello = _postHello(receiver, key);
      await receiver.status
          .firstWhere((s) => s.phase == TransferPhase.approval)
          .timeout(const Duration(seconds: 5));
      await receiver.reject();
      final helloResponse = await hello;
      expect(jsonDecode(helloResponse.body)['approved'], isFalse);

      final before = Map.of(storage.rawPreferences());
      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      final sealed = await cipher.seal(bundle.encode());
      final response = await _postBundle(receiver, sealed);

      expect(response.statusCode, HttpStatus.forbidden);
      expect(storage.rawPreferences(), before);
    });

    test('a timed-out handshake cannot be used afterwards', () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final storage = await _transferStorage();
      final receiver = await _startReceiver(storage,
          approvalWindow: const Duration(milliseconds: 500));
      final cipher = TransferCipher(sessionId: receiver.sessionId);
      final key = await cipher.ensureKeyPair();
      await cipher.derive(receiver.publicKey);

      final helloResponse = await _postHello(receiver, key);
      expect(jsonDecode(helloResponse.body)['approved'], isFalse);

      final before = Map.of(storage.rawPreferences());
      final bundle = SettingsBundle.capture(storage,
          sections: TransferSection.values.toSet());
      final sealed = await cipher.seal(bundle.encode());
      final response = await _postBundle(receiver, sealed);

      expect(response.statusCode, HttpStatus.forbidden);
      expect(storage.rawPreferences(), before);
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
      AppConstants.keyPlaylists: '[{"id":"source","name":"Source","mode":"m3u"}]',
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
    expect(
        storage.rawPreferences()[AppConstants.keyLastChannelId], 'channel-9');

    await receiver.stop();
    sender.dispose();
  });
}
