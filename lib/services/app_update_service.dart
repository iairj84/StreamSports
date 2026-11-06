import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/constants.dart';
import 'storage_service.dart';

/// One published build, as listed in the project's GitHub releases.
@immutable
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.sizeBytes,
    required this.notes,
  });

  /// The release tag exactly as published (`v0.1.5-2470`).
  final String tag;
  final String version;

  /// Android versionCode parsed out of the tag; 0 when the tag carries none.
  final int buildNumber;
  final String apkUrl;
  final int sizeBytes;
  final String notes;

  String get label => buildNumber > 0 ? '$version ($buildNumber)' : version;

  String get sizeLabel => sizeBytes <= 0
      ? ''
      : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// Newer than the running build. Build numbers are the real ordering (a
  /// version string alone can't tell two builds of 0.1.5 apart), falling back
  /// to the version string only for tags that don't carry one.
  bool isNewerThan({required String currentVersion, required int currentBuild}) {
    if (buildNumber > 0 && currentBuild > 0) return buildNumber > currentBuild;
    return _compareVersions(version, currentVersion) > 0;
  }
}

/// `v0.1.5-2470-sports-epg` -> version `0.1.5`, build `2470`.
({String version, int build}) parseReleaseTag(String tag) {
  final versionMatch = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(tag);
  if (versionMatch == null) return (version: tag, build: 0);
  final buildMatch =
      RegExp(r'(\d+)').firstMatch(tag.substring(versionMatch.end));
  return (
    version: versionMatch.group(0)!,
    build: int.tryParse(buildMatch?.group(1) ?? '') ?? 0,
  );
}

int _compareVersions(String a, String b) {
  final left = a.split('.');
  final right = b.split('.');
  for (var i = 0; i < left.length || i < right.length; i++) {
    final l = i < left.length ? int.tryParse(left[i]) ?? 0 : 0;
    final r = i < right.length ? int.tryParse(right[i]) ?? 0 : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// What happened when a downloaded APK was handed to the package installer.
enum AppInstallResult { started, needsPermission, missingFile, failed }

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;
}

/// In-app updates from the project's own GitHub releases.
///
/// There is no store listing to notify anyone, so this is the whole update
/// path: find the newest release with an APK asset, download it into the app
/// cache, then let Android's package installer replace the app in place. Data
/// survives because the package id and signing key never change.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService(this._storage);

  static const MethodChannel _channel =
      MethodChannel('com.nox.nox_iptv/updater');

  /// How often a background check may run. App start is the only trigger, so
  /// an hourly interval keeps a fresh build within reach of the next launch
  /// without hitting GitHub on every rebuild of the widget tree.
  static const Duration checkInterval = Duration(hours: 1);

  final StorageService _storage;

  PackageInfo? _info;
  File? _downloaded;
  bool _checkedThisSession = false;

  AppRelease? available;
  bool checking = false;
  bool downloading = false;
  double? downloadProgress;
  String? error;

  /// True once a check completed in this session, so the UI can tell
  /// "nothing found" apart from "not asked yet".
  bool checked = false;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;
  bool get hasDownload => _downloaded?.existsSync() ?? false;
  String get currentVersion => _info?.version ?? '—';
  String get currentLabel => _info == null
      ? '—'
      : '${_info!.version} (${_info!.buildNumber})';

  Future<void> load() async {
    if (_info != null) return;
    _info = await PackageInfo.fromPlatform();
    notifyListeners();
  }

  /// Asks GitHub for the newest published APK and stores it in [available]
  /// only when it is actually newer than this build.
  Future<AppRelease?> check({bool manual = false}) async {
    if (checking) return available;
    checking = true;
    error = null;
    if (manual) checked = false;
    notifyListeners();
    try {
      await load();
      final release = await _latestRelease();
      final build = int.tryParse(_info?.buildNumber ?? '') ?? 0;
      available = release != null &&
              release.isNewerThan(
                  currentVersion: currentVersion, currentBuild: build)
          ? release
          : null;
      await _storage.setLastUpdateCheck(DateTime.now());
      return available;
    } on AppUpdateException catch (e) {
      error = e.message;
      return null;
    } catch (_) {
      error =
          'Could not reach the update server. Check the connection and try again.';
      return null;
    } finally {
      checking = false;
      checked = true;
      notifyListeners();
    }
  }

  /// Startup check: at most once per [checkInterval], skipped entirely for a
  /// build the viewer already said to skip. Returns the release to offer, if
  /// any.
  Future<AppRelease?> checkIfDue() async {
    if (_checkedThisSession) return available;
    _checkedThisSession = true;
    final last = _storage.getLastUpdateCheck();
    if (last != null && DateTime.now().difference(last) < checkInterval) {
      return available;
    }
    final release = await check();
    if (release == null) return null;
    if (_storage.getSkippedUpdateVersion() == release.tag) return null;
    return release;
  }

  Future<AppRelease?> _latestRelease() async {
    final response = await http
        .get(
          Uri.parse(
              'https://api.github.com/repos/${AppConstants.updateRepository}/releases?per_page=30'),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': AppConstants.appName,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) {
      throw const AppUpdateException(
          'No releases are published for this app yet.');
    }
    if (response.statusCode == 403) {
      throw const AppUpdateException(
          'The update server is rate limiting this device. Try again later.');
    }
    if (response.statusCode != 200) {
      throw AppUpdateException(
          'The update server answered ${response.statusCode}. Try again later.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return null;
    AppRelease? best;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      if (entry['draft'] == true) continue;
      final tag = (entry['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty) continue;
      final assets = entry['assets'];
      if (assets is! List) continue;
      Map? apk;
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (!name.endsWith('.apk')) continue;
        apk = asset;
        break;
      }
      if (apk == null) continue;
      final url = apk['browser_download_url'] as String? ?? '';
      if (url.isEmpty) continue;
      final parsed = parseReleaseTag(tag);
      final candidate = AppRelease(
        tag: tag,
        version: parsed.version,
        buildNumber: parsed.build,
        apkUrl: url,
        sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
        notes: (entry['body'] as String? ?? '').trim(),
      );
      if (best == null ||
          candidate.buildNumber > best.buildNumber ||
          (candidate.buildNumber == best.buildNumber &&
              _compareVersions(candidate.version, best.version) > 0)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Downloads [available] into the cache directory. Returns null on failure,
  /// leaving [error] set for the UI.
  Future<File?> download() async {
    final release = available;
    if (release == null || downloading) return _downloaded;
    downloading = true;
    downloadProgress = 0;
    error = null;
    notifyListeners();
    final client = http.Client();
    IOSink? sink;
    try {
      final directory = Directory('${(await getTemporaryDirectory()).path}/updates');
      await directory.create(recursive: true);
      // Cache is reclaimable by the OS anyway; never keep two installers.
      for (final stale in directory.listSync()) {
        try {
          stale.deleteSync();
        } catch (_) {
          // Another process still holds it — harmless, the new file is named
          // after this release anyway.
        }
      }
      final safeTag = release.tag.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
      final file = File('${directory.path}/StreamSports-$safeTag.apk');
      final request = http.Request('GET', Uri.parse(release.apkUrl))
        ..headers['User-Agent'] = AppConstants.appName;
      final response = await client.send(request).timeout(
            const Duration(seconds: 30),
          );
      if (response.statusCode != 200) {
        throw AppUpdateException(
            'The update download failed (${response.statusCode}).');
      }
      sink = file.openWrite();
      final total = response.contentLength ?? release.sizeBytes;
      var received = 0;
      var reported = -1;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total <= 0) continue;
        final percent = ((received / total) * 100).floor();
        if (percent == reported) continue;
        reported = percent;
        downloadProgress = received / total;
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      _downloaded = file;
      downloadProgress = 1;
      return file;
    } on AppUpdateException catch (e) {
      error = e.message;
      return null;
    } catch (_) {
      error = 'The update could not be downloaded. Try again.';
      return null;
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        // Partial file is deleted by the next download attempt.
      }
      client.close();
      downloading = false;
      notifyListeners();
    }
  }

  /// Hands the downloaded APK to Android's package installer.
  Future<AppInstallResult> install() async {
    final file = _downloaded;
    if (!isAndroid) return AppInstallResult.failed;
    if (file == null || !file.existsSync()) return AppInstallResult.missingFile;
    try {
      final result =
          await _channel.invokeMethod<String>('installApk', {'path': file.path});
      switch (result) {
        case 'started':
          return AppInstallResult.started;
        case 'permission':
          return AppInstallResult.needsPermission;
        case 'missing':
          return AppInstallResult.missingFile;
        default:
          return AppInstallResult.failed;
      }
    } on PlatformException catch (e) {
      error = e.message;
      return AppInstallResult.failed;
    } catch (_) {
      return AppInstallResult.failed;
    }
  }

  /// Opens the system screen that grants "install unknown apps" to this app —
  /// Android requires that switch before a package installer intent may run.
  Future<void> openInstallPermissionSettings() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('openInstallSettings');
    } catch (_) {
      // Nothing else to do: the installer will ask again next attempt.
    }
  }

  /// Remember this build so the startup prompt stops offering it.
  Future<void> skipCurrent() async {
    final tag = available?.tag;
    if (tag != null) await _storage.setSkippedUpdateVersion(tag);
  }

  /// Forget the current offer (used by a cancelled prompt).
  void dismiss() {
    available = null;
    notifyListeners();
  }
}
