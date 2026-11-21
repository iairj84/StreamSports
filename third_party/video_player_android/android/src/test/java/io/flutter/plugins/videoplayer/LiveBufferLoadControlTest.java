package io.flutter.plugins.videoplayer;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import androidx.media3.common.C;
import androidx.media3.common.Timeline;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.LoadControl;
import androidx.media3.exoplayer.analytics.PlayerId;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/**
 * BUF-001: what the load control demands before the main player (re)starts.
 *
 * <p>The delegate stands in for the main player's DefaultLoadControl, starting once 500 ms is
 * buffered - the threshold this build ships with. A stall that reaches it with a zero duration
 * therefore means the wrapper is still waiting for its own reserve.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public final class LiveBufferLoadControlTest {
  private static final long START_US = 500_000L;
  private DefaultLoadControl delegate;

  @Before
  public void setUp() {
    delegate = mock(DefaultLoadControl.class);
    when(delegate.shouldStartPlayback(any()))
        .thenAnswer(
            call ->
                ((LoadControl.Parameters) call.getArgument(0)).bufferedDurationUs >= START_US);
    LiveBufferLoadControl.setDefaultLiveReserveMs(0);
  }

  @After
  public void tearDown() {
    LiveBufferLoadControl.setDefaultLiveReserveMs(0);
  }

  @Test
  public void firstStartKeepsTheFastStart() {
    LiveBufferLoadControl control =
        new LiveBufferLoadControl(delegate, /* autoRebufferFloor= */ true);
    assertTrue(
        control.shouldStartPlayback(parameters(/* bufferedUs= */ 600_000, /* rebuffering= */ false)));
  }

  @Test
  public void aStallWithNothingChosenWaitsForThreeSeconds() {
    LiveBufferLoadControl control = new LiveBufferLoadControl(delegate, true);
    assertFalse(
        "500 ms of media is not enough after a stall",
        control.shouldStartPlayback(parameters(1_000_000, true)));
    assertTrue(
        "3 s is the floor", control.shouldStartPlayback(parameters(3_000_000, true)));
  }

  @Test
  public void aChosenBufferingPresetKeepsItsOwnThreshold() {
    LiveBufferLoadControl control =
        new LiveBufferLoadControl(delegate, /* autoRebufferFloor= */ false);
    assertTrue(
        control.shouldStartPlayback(parameters(1_000_000, true)));
  }

  @Test
  public void anExplicitReserveOverridesTheFloor() {
    LiveBufferLoadControl control = new LiveBufferLoadControl(delegate, true);
    control.setLiveReserveMs(1500);
    assertFalse(control.shouldStartPlayback(parameters(1_400_000, true)));
    assertTrue(control.shouldStartPlayback(parameters(1_500_000, true)));
  }

  @Test
  public void gradualResumesAtOnce() {
    LiveBufferLoadControl control = new LiveBufferLoadControl(delegate, true);
    control.setLiveReserveMs(-1);
    assertTrue(control.shouldStartPlayback(parameters(600_000, true)));
  }

  @Test
  public void theAppDefaultAppliesBeforeThePlayerHasItsOwnChoice() {
    LiveBufferLoadControl.setDefaultLiveReserveMs(4000);
    LiveBufferLoadControl control = new LiveBufferLoadControl(delegate, true);
    assertFalse(
        "the app's 4 s reserve still applies to a new player",
        control.shouldStartPlayback(parameters(3_000_000, true)));
    // A per-player Off is a choice of its own: it replaces the 4 s default with the 3 s floor.
    control.setLiveReserveMs(0);
    assertTrue(control.shouldStartPlayback(parameters(3_000_000, true)));
  }

  private static LoadControl.Parameters parameters(long bufferedUs, boolean rebuffering) {
    return new LoadControl.Parameters(
        PlayerId.UNSET,
        Timeline.EMPTY,
        /* mediaPeriodId= */ null,
        /* playbackPositionUs= */ 0,
        bufferedUs,
        /* playbackSpeed= */ 1f,
        /* playWhenReady= */ true,
        rebuffering,
        /* targetBufferBytes= */ C.TIME_UNSET,
        /* lastRebufferRealtimeMs= */ 0);
  }
}
