import 'package:video_player_android/video_player_android.dart';

/// Buffering presets offered in Settings > Playback & preferences.
///
/// "Automatic" keeps the values this build is tuned with. The others trade
/// start-up time for a deeper cushion — the only lever a viewer has over a
/// provider that paces badly or a link that keeps hiccuping.
class PlaybackBufferPreset {
  const PlaybackBufferPreset(this.id, this.label, this.detail, this.policy);

  final String id;
  final String label;
  final String detail;
  final PlayerBufferPolicy? policy;
}

const playbackBufferPresets = <PlaybackBufferPreset>[
  PlaybackBufferPreset('auto', 'Automatic (recommended)',
      'The tuning this build ships with', null),
  PlaybackBufferPreset(
      'quick',
      'Quick start',
      'Starts after about 1 s · least tolerant of hiccups',
      PlayerBufferPolicy(
          minBufferMs: 8000,
          maxBufferMs: 20000,
          bufferForPlaybackMs: 1000,
          bufferForPlaybackAfterRebufferMs: 2000)),
  PlaybackBufferPreset(
      'balanced',
      'Balanced',
      'Starts after about 3 s · fewer rebuffers',
      PlayerBufferPolicy(
          minBufferMs: 20000,
          maxBufferMs: 45000,
          bufferForPlaybackMs: 3000,
          bufferForPlaybackAfterRebufferMs: 5000)),
  PlaybackBufferPreset(
      'steady',
      'Smoothest',
      'Starts after about 6 s · most tolerant of hiccups',
      PlayerBufferPolicy(
          minBufferMs: 45000,
          maxBufferMs: 90000,
          bufferForPlaybackMs: 6000,
          bufferForPlaybackAfterRebufferMs: 9000)),
];

Set<String> get playbackBufferPresetIds =>
    {for (final preset in playbackBufferPresets) preset.id};

PlaybackBufferPreset playbackBufferPreset(String id) =>
    playbackBufferPresets.firstWhere((preset) => preset.id == id,
        orElse: () => playbackBufferPresets.first);

/// Makes [id] the buffer policy for the next main player this device creates.
void applyPlaybackBufferPreset(String id) =>
    mainPlayerBufferPolicy = playbackBufferPreset(id).policy;
