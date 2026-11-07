// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// ExoPlayer load-control values for the main (platform-view) player.
///
/// The app offers these as buffering presets. Multiview's texture players
/// never receive them: several decoders on one device must not each reserve a
/// deep buffer.
class PlayerBufferPolicy {
  const PlayerBufferPolicy({
    this.minBufferMs,
    this.maxBufferMs,
    this.bufferForPlaybackMs,
    this.bufferForPlaybackAfterRebufferMs,
  });

  /// Media kept before the player considers its buffer full.
  final int? minBufferMs;

  /// Upper bound on buffered media.
  final int? maxBufferMs;

  /// How much must be buffered before playback starts.
  final int? bufferForPlaybackMs;

  /// How much must be buffered before playback resumes after a rebuffer.
  final int? bufferForPlaybackAfterRebufferMs;
}

/// Applied to every main player created after it is set. Null (the default)
/// keeps this package's own tuned values.
PlayerBufferPolicy? mainPlayerBufferPolicy;
