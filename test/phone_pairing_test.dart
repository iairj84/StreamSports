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
