import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nox_iptv/services/app_update_service.dart';
import 'package:nox_iptv/services/storage_service.dart';
import 'package:nox_iptv/utils/constants.dart';

AppRelease _release(int build, String version) => AppRelease(
      tag: 'v$version-$build',
      version: version,
      buildNumber: build,
      apkUrl: 'https://example.invalid/iptv-app.apk',
      sizeBytes: 80 * 1024 * 1024,
      notes: '',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('rolling mirrors', () {
    test('build comes out of the mirror body, not the digit-free tag', () {
      final parsed = AppUpdateService.parseMirrorBuild(
          'Rolling download.\n\n- Build: 0.2.61 (2554)\n- Size: 1 bytes\n');
      expect(parsed.version, '0.2.61');
      expect(parsed.build, 2554);
    });

    test('a mirror body without a build line offers no update', () {
      final parsed = AppUpdateService.parseMirrorBuild('Rolling download.\n');
      expect(parsed.version, isEmpty);
      expect(parsed.build, 0);
    });
  });

  group('testers on an early build', () {
    bool adopt({required int current, required int stable,
        required bool chose, required bool early}) =>
        AppUpdateService.shouldAdoptEarly(
          currentBuild: current,
          stableBuild: stable,
          choseChannel: chose,
          followsEarly: early,
        );

    test('a build ahead of stable with no channel chosen follows early', () {
      expect(adopt(current: 2584, stable: 2583, chose: false, early: false),
          isTrue);
    });

    test('an install level with stable stays on stable', () {
      expect(adopt(current: 2583, stable: 2583, chose: false, early: false),
          isFalse);
      expect(adopt(current: 2582, stable: 2583, chose: false, early: false),
          isFalse);
    });

    test('a channel the viewer picked is never overridden', () {
      expect(adopt(current: 2584, stable: 2583, chose: true, early: false),
          isFalse);
      expect(adopt(current: 2584, stable: 2583, chose: true, early: true),
          isFalse);
    });

    test('an unreadable stable mirror marks nothing as early', () {
      expect(adopt(current: 2584, stable: 0, chose: false, early: false),
          isFalse);
    });
  });

  group('stored channel choice', () {
    test('the untouched default is not a choice, picking one is', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      expect(storage.getUpdateChannel(), AppConstants.updateChannelStable);
      expect(storage.hasUpdateChannelChoice(), isFalse);
      await storage.setUpdateChannel(AppConstants.updateChannelEarly);
      expect(storage.hasUpdateChannelChoice(), isTrue);
      await storage.setUpdateChannel(AppConstants.updateChannelStable);
      expect(storage.hasUpdateChannelChoice(), isTrue);
    });
  });
}
