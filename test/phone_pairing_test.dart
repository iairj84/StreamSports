import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/services/phone_pairing_service.dart';

void main() {
  test('a names payload keeps usable channel renames', () {
    final result = PairingResult.fromJson({
      'v': 1,
      'mode': 'names',
      'renames': [
        {'id': 'fixture::one', 'name': ' ESPN2 '},
        {'id': 'fixture::two', 'name': ''},
        {'id': '', 'name': 'No id is useless'},
        {'name': 'No id at all'},
        {'id': 'fixture::three', 'name': 'x' * 81},
      ],
    });
    expect(result, isNotNull);
    expect(result!.mode, 'names');
    expect(result.renames, [
      (id: 'fixture::one', name: 'ESPN2'),
      (id: 'fixture::two', name: ''),
    ]);
  });

  test('a backup payload carries the file name and its base64 data', () {
    final result = PairingResult.fromJson({
      'mode': 'backup',
      'name': 'streamsports-backup-20261109-073512-482.json',
      'data': 'eyJ2IjoxfQ==',
    });
    expect(result, isNotNull);
    expect(result!.mode, 'backup');
    expect(result.backupName, 'streamsports-backup-20261109-073512-482.json');
    expect(result.backupData, 'eyJ2IjoxfQ==');
    // The file name is cosmetic: the TV writes its own, so data alone is enough.
    final unnamed = PairingResult.fromJson(
        {'mode': 'backup', 'data': 'eyJ2IjoxfQ=='});
    expect(unnamed, isNotNull);
    expect(unnamed!.backupName, '');
    expect(PairingResult.fromJson({'mode': 'backup', 'name': 'x'}), isNull);
    expect(
        PairingResult.fromJson({'mode': 'backup', 'data': '   '}), isNull);
  });

  test('a setup payload carries the playlist and the chosen settings', () {
    final result = PairingResult.fromJson({
      'mode': 'setup',
      'playlist': {
        'mode': 'xtream',
        'name': 'Living room',
        'server': 'http://host:8080',
        'username': 'someone',
        'password': 'secret',
        'movies': 'false',
      },
      'settings': {
        'palette': 'oled',
        'surface': 'stadium',
        'clock24': 'true',
        'scores': 'true',
        'update': 'early',
      },
    });
    expect(result, isNotNull);
    expect(result!.fromSetup, isTrue);
    expect(result.mode, 'xtream');
    expect(result.name, 'Living room');
    expect(result.server, 'http://host:8080');
    // An omitted content choice keeps the Add Playlist default.
    expect(result.includeLive, isTrue);
    expect(result.includeMovies, isFalse);
    expect(result.settings['surface'], 'stadium');
    expect(result.settings['update'], 'early');
  });

  test('a setup payload only keeps settings the TV can apply', () {
    final result = PairingResult.fromJson({
      'mode': 'setup',
      'playlist': {'mode': 'm3u', 'name': 'One', 'm3u': 'http://host/list.m3u'},
      'settings': {'palette': ' OLED ', 'alien': 'yes', 'surface': ''},
    });
    expect(result, isNotNull);
    expect(result!.settings, {'palette': 'oled'});
  });

  test('a setup payload needs a playlist it can actually save', () {
    // No nested playlist at all.
    expect(PairingResult.fromJson({'mode': 'setup'}), isNull);
    expect(PairingResult.fromJson({'mode': 'setup', 'playlist': 'nope'}), isNull);
    // Xtream still needs all three credentials.
    expect(
        PairingResult.fromJson({
          'mode': 'setup',
          'playlist': {'mode': 'xtream', 'server': 'http://host:8080'},
        }),
        isNull);
    // Stalker needs both the portal and the MAC the provider registered.
    expect(
        PairingResult.fromJson({
          'mode': 'setup',
          'playlist': {'mode': 'stalker', 'portalUrl': 'http://portal/c/'},
        }),
        isNull);
    // A setup payload cannot nest another one.
    expect(
        PairingResult.fromJson({
          'mode': 'setup',
          'playlist': {'mode': 'setup', 'playlist': {}},
        }),
        isNull);
  });

  test('a setup payload carries a stalker login', () {
    final result = PairingResult.fromJson({
      'mode': 'setup',
      'playlist': {
        'mode': 'stalker',
        'name': 'Portal',
        'portalUrl': 'http://portal.example.com/c/',
        'portalMac': '00:1A:79:12:34:56',
        'portalUsername': 'user',
      },
      'settings': {},
    });
    expect(result, isNotNull);
    expect(result!.fromSetup, isTrue);
    expect(result.mode, 'stalker');
    expect(result.portalMac, '00:1A:79:12:34:56');
    expect(result.portalUsername, 'user');
  });

  test('a settings payload needs no playlist and keeps known keys only', () {
    final result = PairingResult.fromJson({
      'mode': 'settings',
      'settings': {
        'palette': ' OLED ',
        'buffer': 'balanced',
        'livebuffer': '4000',
        'startup': 'full',
        'moviestab': 'false',
        'alien': 'yes',
      },
    });
    expect(result, isNotNull);
    expect(result!.mode, 'settings');
    expect(result.fromSetup, isFalse);
    expect(result.settings, {
      'palette': 'oled',
      'buffer': 'balanced',
      'livebuffer': '4000',
      'startup': 'full',
      'moviestab': 'false',
    });
    // A settings page never carries playlist fields.
    expect(result.name, isEmpty);
    expect(result.server, isEmpty);
  });

  test('a settings payload with nothing to apply is refused', () {
    expect(PairingResult.fromJson({'mode': 'settings'}), isNull);
    expect(
        PairingResult.fromJson({'mode': 'settings', 'settings': {}}), isNull);
    expect(
        PairingResult.fromJson({
          'mode': 'settings',
          'settings': {'alien': 'yes'}
        }),
        isNull);
  });

  test('a names payload needs a list of renames', () {
    expect(PairingResult.fromJson({'mode': 'names'}), isNull);
    expect(PairingResult.fromJson({'mode': 'names', 'renames': []}), isNull);
    expect(PairingResult.fromJson({'mode': 'names', 'renames': 'nope'}), isNull);
    expect(
        PairingResult.fromJson({
          'mode': 'names',
          'renames': [
            {'id': '', 'name': ''}
          ],
        }),
        isNull);
  });
}
