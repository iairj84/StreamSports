import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AUD-002: the viewer's provider logins live in shared preferences, so no OS
/// backup may carry them off the device. These tests read the shipped
/// configuration rather than a copy of it, so a manifest edit that re-enables
/// auto-backup fails here instead of quietly shipping.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final extraction =
      File('android/app/src/main/res/xml/data_extraction_rules.xml')
          .readAsStringSync();
  final fullBackup =
      File('android/app/src/main/res/xml/backup_rules.xml').readAsStringSync();

  String applicationTag() {
    final match = RegExp(r'<application\b[^>]*>').firstMatch(manifest);
    expect(match, isNotNull, reason: 'The manifest has no <application> tag.');
    return match!.group(0)!;
  }

  test('auto-backup is off and both rule files are declared', () {
    final tag = applicationTag();
    expect(tag, contains('android:allowBackup="false"'));
    expect(tag, contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'Android 12+ reads the extraction rules.');
    expect(tag, contains('android:fullBackupContent="@xml/backup_rules"'),
        reason: 'Android 11 and lower read fullBackupContent.');
  });

  test('the extraction rules keep every domain out of both transports', () {
    for (final section in ['cloud-backup', 'device-transfer']) {
      expect(extraction, contains('<$section>'));
      expect(
          extraction, contains('<exclude domain="sharedpref" path="." />'));
    }
    // Both sections must exclude the preferences: a single shared exclude would
    // let a device-to-device migration copy the passwords even though the cloud
    // backup does not.
    final cloud = extraction.substring(extraction.indexOf('<cloud-backup>'),
        extraction.indexOf('</cloud-backup>'));
    final transfer = extraction.substring(
        extraction.indexOf('<device-transfer>'),
        extraction.indexOf('</device-transfer>'));
    expect(cloud, contains('domain="sharedpref"'));
    expect(transfer, contains('domain="sharedpref"'));
    // The local backup files sit in the app's files directory and are
    // unencrypted by design, so they must not travel either.
    expect(cloud, contains('domain="file"'));
    expect(transfer, contains('domain="file"'));
  });

  test('the full-backup rules exclude preferences and files', () {
    expect(fullBackup, contains('<full-backup-content>'));
    expect(fullBackup, contains('<exclude domain="sharedpref" path="." />'));
    expect(fullBackup, contains('<exclude domain="file" path="." />'));
  });
}
