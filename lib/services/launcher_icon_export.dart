import 'package:flutter/services.dart';

/// One piece of cut-out artwork a launcher can use in place of the square
/// app icon.
class LauncherIconArt {
  const LauncherIconArt({
    required this.asset,
    required this.fileName,
    required this.title,
    required this.subtitle,
  });

  /// Path inside the bundle.
  final String asset;

  /// Name the file gets once it is on the device's storage.
  final String fileName;
  final String title;
  final String subtitle;
}

/// The cut-out logos from the designed pack, white ink first because most
/// launcher wallpapers are dark.
const launcherIconArt = <LauncherIconArt>[
  LauncherIconArt(
      asset: 'assets/icon/logo_transparent.png',
      fileName: 'streamsports-mark-white.png',
      title: 'White mark',
      subtitle: 'For dark or mid-tone backgrounds'),
  LauncherIconArt(
      asset: 'assets/icon/logo_transparent_light.png',
      fileName: 'streamsports-mark-blue.png',
      title: 'Blue mark',
      subtitle: 'For light backgrounds'),
  LauncherIconArt(
      asset: 'assets/icon/banner_transparent.png',
      fileName: 'streamsports-banner-white.png',
      title: 'White banner',
      subtitle: '16:9 lockup, for dark backgrounds'),
  LauncherIconArt(
      asset: 'assets/icon/banner_transparent_light.png',
      fileName: 'streamsports-banner-blue.png',
      title: 'Blue banner',
      subtitle: '16:9 lockup, for light backgrounds'),
];

/// What happened when the artwork was written out.
enum LauncherIconSave {
  /// The file is in Pictures/StreamSports.
  saved,

  /// Older Android releases write the file themselves and need storage
  /// permission the viewer declined.
  permissionDenied,
  failed,

  /// Not the Android app, so there is no channel to write through.
  unavailable,
}

/// Puts the bundled artwork where another launcher can pick it.
///
/// Projectivy keeps its own picture per app, and its chooser only offers
/// files already on the device — which used to mean copying a PNG onto the
/// television by hand. The artwork now ships inside the app, and the platform
/// side writes it into the shared Pictures folder.
class LauncherIconExport {
  LauncherIconExport({AssetBundle? bundle, MethodChannel? channel})
      : _bundle = bundle ?? rootBundle,
        _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.nox.nox_iptv/media_library';

  final AssetBundle _bundle;
  final MethodChannel _channel;

  Future<LauncherIconSave> save(LauncherIconArt art) async {
    try {
      final data = await _bundle.load(art.asset);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final reply = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': art.fileName,
        'mime': 'image/png',
      });
      switch (reply) {
        case 'saved':
          return LauncherIconSave.saved;
        case 'permission':
          return LauncherIconSave.permissionDenied;
        default:
          return LauncherIconSave.failed;
      }
    } on MissingPluginException {
      return LauncherIconSave.unavailable;
    } catch (_) {
      return LauncherIconSave.failed;
    }
  }
}
