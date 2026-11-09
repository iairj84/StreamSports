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
