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
 * the ordinary 500 ms start, and - when the viewer has also left Buffering on Automatic - holds a
 * stall until {@link #AUTO_REBUFFER_FLOOR_US}. Everything else - byte budgets, allocation,
 * continuation, back buffer - is delegated unchanged.
 */
@UnstableApi
public final class LiveBufferLoadControl implements LoadControl {
  /**
   * How long a stall waits when the viewer has chosen nothing: Live buffer Off with the Automatic
   * Buffering preset. Live TS arrives at real-time speed, so after a stall the buffer refills at 1x
   * and resuming at the delegate's 500 ms walks straight into the provider's next gap. 3 s sits
   * between that start and Multiview's 4 s resume, and is a floor only for the untouched defaults.
   */
  static final long AUTO_REBUFFER_FLOOR_US = 3_000_000L;

  /** No value for this player yet: use the app default. */
  private static final long UNSET = Long.MIN_VALUE;

  private final DefaultLoadControl delegate;

  /** Whether an Off reserve holds a stall for {@link #AUTO_REBUFFER_FLOOR_US}. */
  private final boolean autoRebufferFloor;

  /**
   * This player's Live buffer choice in ms - negative is Gradual, 0 is Off - or {@link #UNSET} to
   * use the app default. The raw value is kept because Off and Gradual differ here: Off holds a
   * stall, Gradual resumes at once and earns its cushion by playing slightly slow.
   */
  private volatile long liveMs = UNSET;

  /**
   * The app's setting, applied from the very first start of every new main player. The per-player
   * value only arrives after the player is ready, which is too late to build a cushion.
   */
  private static volatile long defaultLiveMs;

  public static void setDefaultLiveReserveMs(long ms) {
    defaultLiveMs = ms;
  }

  /**
   * @param autoRebufferFloor whether an Off reserve holds a stall: true when no Buffering preset is
   *     set, so the delegate's thresholds are this build's tuning rather than the viewer's choice.
   */
  public LiveBufferLoadControl(@NonNull DefaultLoadControl delegate, boolean autoRebufferFloor) {
    this.delegate = delegate;
    this.autoRebufferFloor = autoRebufferFloor;
  }

  public void setLiveReserveMs(long ms) {
    liveMs = ms;
  }

  @Override
  public boolean shouldStartPlayback(Parameters p) {
    final long ms = liveMs != UNSET ? liveMs : defaultLiveMs;
    long reserveUs = Math.max(0, ms) * 1000L;
    // A stall interrupts playback that was already running; media3 leaves this false for the
    // first start and for seeks, which must stay 500 ms fast.
    if (ms == 0 && autoRebufferFloor && p.rebuffering) {
      reserveUs = AUTO_REBUFFER_FLOOR_US;
    }
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
