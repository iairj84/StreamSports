import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/services/app_update_service.dart';

AppRelease _release(int build, String version) => AppRelease(
      tag: 'v$version-$build',
      version: version,
      buildNumber: build,
      apkUrl: 'https://example.invalid/iptv-app.apk',
      sizeBytes: 80 * 1024 * 1024,
      notes: '',
    );

void main() {
  group('published release tags', () {
    test('version and build come out of the real tag format', () {
      final parsed = parseReleaseTag('v0.1.5-2470-sports-epg');
      expect(parsed.version, '0.1.5');
      expect(parsed.build, 2470);
    });

    test('a tag without a build number is compared by version only', () {
      final parsed = parseReleaseTag('v0.2.0');
      expect(parsed.version, '0.2.0');
      expect(parsed.build, 0);
    });

    test('a tag with no version at all does not look like an update', () {
      final parsed = parseReleaseTag('nightly');
      expect(parsed.build, 0);
      expect(
          _release(parsed.build, parsed.version)
              .isNewerThan(currentVersion: '0.1.5', currentBuild: 2470),
          isFalse);
    });
  });

  group('update ordering', () {
    test('only a higher build counts as an update', () {
      expect(
          _release(2471, '0.1.5')
              .isNewerThan(currentVersion: '0.1.5', currentBuild: 2470),
          isTrue);
      expect(
          _release(2470, '0.1.5')
              .isNewerThan(currentVersion: '0.1.5', currentBuild: 2470),
          isFalse);
    });

    test('a version-only release still updates an older install', () {
      expect(
          _release(0, '0.2.0')
              .isNewerThan(currentVersion: '0.1.5', currentBuild: 0),
          isTrue);
      expect(
          _release(0, '0.1.5')
              .isNewerThan(currentVersion: '0.1.5', currentBuild: 0),
          isFalse);
    });

    test('the label and size describe the download', () {
      final release = _release(2471, '0.1.5');
      expect(release.label, '0.1.5 (2471)');
      expect(release.sizeLabel, '80.0 MB');
    });
  });
}
