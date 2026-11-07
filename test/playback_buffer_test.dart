import 'package:flutter_test/flutter_test.dart';
import 'package:nox_iptv/utils/playback_buffer.dart';
import 'package:video_player_android/video_player_android.dart';

void main() {
  test('the automatic preset keeps the shipped tuning', () {
    expect(playbackBufferPreset('auto').policy, isNull);
    expect(playbackBufferPreset('not-a-preset').id, 'auto');
    expect(playbackBufferPresetIds, hasLength(playbackBufferPresets.length));
  });

  test('deeper presets wait longer and keep a consistent budget', () {
    final quick = playbackBufferPreset('quick').policy!;
    final balanced = playbackBufferPreset('balanced').policy!;
    final steady = playbackBufferPreset('steady').policy!;
    final ordered = [quick, balanced, steady];
    for (var i = 1; i < ordered.length; i++) {
      expect(ordered[i].bufferForPlaybackMs!,
          greaterThan(ordered[i - 1].bufferForPlaybackMs!));
      expect(ordered[i].bufferForPlaybackAfterRebufferMs!,
          greaterThan(ordered[i - 1].bufferForPlaybackAfterRebufferMs!));
      expect(
          ordered[i].maxBufferMs!, greaterThan(ordered[i - 1].maxBufferMs!));
    }
    for (final policy in ordered) {
      expect(policy.minBufferMs!, lessThanOrEqualTo(policy.maxBufferMs!));
      expect(
          policy.bufferForPlaybackMs!, lessThanOrEqualTo(policy.maxBufferMs!));
      expect(policy.bufferForPlaybackAfterRebufferMs!,
          lessThanOrEqualTo(policy.maxBufferMs!));
    }
  });

  test('applying a preset sets the main player policy', () {
    applyPlaybackBufferPreset('steady');
    expect(mainPlayerBufferPolicy?.bufferForPlaybackMs, 6000);
    expect(mainPlayerBufferPolicy?.maxBufferMs, 90000);
    applyPlaybackBufferPreset('auto');
    expect(mainPlayerBufferPolicy, isNull);
  });
}
