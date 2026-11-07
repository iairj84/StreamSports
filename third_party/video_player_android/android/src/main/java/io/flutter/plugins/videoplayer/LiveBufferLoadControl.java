// VesperTV port: the Live buffer reserve for the main player.
package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.common.Timeline;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.LoadControl;
import androidx.media3.exoplayer.analytics.PlayerId;
import androidx.media3.exoplayer.source.MediaSource.MediaPeriodId;
import androidx.media3.exoplayer.source.TrackGroupArray;
import androidx.media3.exoplayer.trackselection.ExoTrackSelection;
import androidx.media3.exoplayer.upstream.Allocator;

/**
 * A {@link LoadControl} that adds a live reserve over the main player's existing load control.
 *
 * <p>Settings > Playback > Live buffer: live playback starts, and resumes after a stall, only once
 * this much media is buffered, so short dropouts from the provider play out of the cushion. 0 keeps
 * the ordinary 500 ms start. Everything else - byte budgets, allocation, continuation, back buffer
 * - is delegated unchanged.
 */
@UnstableApi
public final class LiveBufferLoadControl implements LoadControl {
  private final DefaultLoadControl delegate;

  /** This player's reserve; negative means "not set for this player, use the default". */
  private volatile long liveReserveUs = -1;

  /**
   * The app's setting, applied from the very first start of every new main player. The per-player
   * value only arrives after the player is ready, which is too late to build a cushion.
   */
  private static volatile long defaultLiveReserveUs;

  public static void setDefaultLiveReserveMs(long ms) {
    defaultLiveReserveUs = Math.max(0, ms) * 1000L;
  }

  public LiveBufferLoadControl(@NonNull DefaultLoadControl delegate) {
    this.delegate = delegate;
  }

  public void setLiveReserveMs(long ms) {
    liveReserveUs = Math.max(0, ms) * 1000L;
  }

  @Override
  public boolean shouldStartPlayback(Parameters p) {
    final long reserveUs = liveReserveUs >= 0 ? liveReserveUs : defaultLiveReserveUs;
    if (reserveUs <= 0 || p.bufferedDurationUs / p.playbackSpeed >= reserveUs) {
      return delegate.shouldStartPlayback(p);
    }
    // Zero time asks the existing non-zero-threshold delegate whether its byte budget permits
    // starting anyway. Keep that escape hatch: a high-bitrate stream on a RAM-capped device must
    // not wait forever for a reserve that cannot fit.
    return delegate.shouldStartPlayback(
        new Parameters(
            p.playerId,
            p.timeline,
            p.mediaPeriodId,
            p.playbackPositionUs,
            0,
            p.playbackSpeed,
            p.playWhenReady,
            p.rebuffering,
            C.TIME_UNSET,
            p.lastRebufferRealtimeMs));
  }

  @Override
  public void onPrepared(PlayerId id) {
    delegate.onPrepared(id);
  }

  @Override
  public void onTracksSelected(
      Parameters p,
      TrackGroupArray groups,
      ExoTrackSelection[] selections) {
    delegate.onTracksSelected(p, groups, selections);
  }

  @Override
  public void onStopped(PlayerId id) {
    delegate.onStopped(id);
  }

  @Override
  public void onReleased(PlayerId id) {
    delegate.onReleased(id);
  }

  @Override
  public androidx.media3.exoplayer.upstream.Allocator getAllocator(
      PlayerId id) {
    return delegate.getAllocator(id);
  }

  @Override
  public long getBackBufferDurationUs(PlayerId id) {
    return delegate.getBackBufferDurationUs(id);
  }

  @Override
  public boolean retainBackBufferFromKeyframe(
      PlayerId id) {
    return delegate.retainBackBufferFromKeyframe(id);
  }

  @Override
  public boolean shouldContinueLoading(Parameters p) {
    return delegate.shouldContinueLoading(p);
  }

  @Override
  public boolean shouldContinuePreloading(
      PlayerId id,
      Timeline timeline,
      MediaPeriodId period,
      long bufferedUs) {
    return delegate.shouldContinuePreloading(id, timeline, period, bufferedUs);
  }
}
