// VesperTV port: Settings > Playback > Live buffer, over MethodChannel
// "vespertv/live_buffer". Dart owns the choice; this only forwards it to the players.
package io.flutter.plugins.videoplayer;

import android.util.LongSparseArray;
import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

@OptIn(markerClass = UnstableApi.class)
final class LiveBufferBridge implements MethodChannel.MethodCallHandler {
  private final LongSparseArray<VideoPlayer> players;
  private final MethodChannel methods;

  LiveBufferBridge(@NonNull BinaryMessenger messenger, @NonNull LongSparseArray<VideoPlayer> players) {
    this.players = players;
    methods = new MethodChannel(messenger, "vespertv/live_buffer");
    methods.setMethodCallHandler(this);
  }

  void dispose() {
    methods.setMethodCallHandler(null);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    if ("setLiveBufferDefault".equals(call.method)) {
      Number ms = call.argument("ms");
      LiveBufferLoadControl.setDefaultLiveReserveMs(ms == null ? 0 : ms.longValue());
      result.success(null);
      return;
    }
    if (!"setLiveBuffer".equals(call.method)) {
      result.notImplemented();
      return;
    }
    Number idArg = call.argument("playerId");
    VideoPlayer player = idArg == null ? null : players.get(idArg.longValue());
    if (player == null) {
      result.error("no_player", "No player " + idArg, null);
      return;
    }
    Number ms = call.argument("ms");
    player.setLiveBuffer(ms == null ? 0 : ms.longValue());
    result.success(null);
  }
}
