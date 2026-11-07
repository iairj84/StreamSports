import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player_hdr/video_player_hdr.dart';

import '../models/channel.dart';
import 'subtitle_tracks.dart';

/// Settings > Playback > Live buffer, forwarded to the vendored Android player.
///
/// [ms] is how much live video must be buffered before playback starts, and
/// before it resumes after a stall, so a provider's short dropouts play out of
/// the cushion. `-1` selects Gradual: start at once, then play at 96 % until a
/// reserve covers the gaps. Only live channels are affected; a finite stream
/// keeps the ordinary start.
class LiveBuffer {
  LiveBuffer._();

  static const _methods = MethodChannel('vespertv/live_buffer');

  /// The current choice: 0 off, -1 Gradual, otherwise a reserve in ms.
  static int ms = 0;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The reserve every new main player starts with. The per-player call arrives
  /// after the player is ready — too late to build a cushion on the first start.
  static Future<void> setDefault(int value) async {
    ms = value;
    if (!_supported) return;
    try {
      await _methods.invokeMethod<void>('setLiveBufferDefault', {'ms': value});
    } on MissingPluginException {
      // A native build without the port keeps the 500 ms start.
    } on PlatformException catch (e) {
      debugPrint('LiveBuffer: configuration failed (${e.code})');
    }
  }

  static Future<void> configure(
      VideoPlayerHdrController controller, Channel channel) async {
    if (!_supported) return;
    final live = Channel.isLiveId(channel.rawId);
    try {
      await _methods.invokeMethod<void>('setLiveBuffer', {
        'playerId': SubtitleTracks.playerIdOf(controller),
        'ms': live ? ms : 0,
      });
    } on MissingPluginException {
      // A native build without the port retains its buffering policy.
    } on PlatformException catch (e) {
      debugPrint('LiveBuffer: player configuration failed (${e.code})');
    }
  }
}
