# Local patches on top of upstream video_player_android 2.12.2

This directory is a patched copy of the pub.dev package
[`video_player_android` 2.12.2](https://pub.dev/packages/video_player_android/versions/2.12.2),
pinned via `dependency_overrides` in the root `pubspec.yaml`.
Keep the native versions and downstream notices in sync when updating it.

## Baseline

Commit `e839d1c` ("Release 0.1.5") imported the pristine upstream tree
(55 files, additions only). Every divergence below is a later commit that
touched this directory; nothing else differs from upstream 2.12.2.

## Patch list (oldest first)

### 1. Buffer policy — trade start-up time for a deeper playback buffer
Commit `e0bf5fa` ("Let the viewer trade start-up time for a deeper playback
buffer.", 2026-11-07). Adds a `buffer_policy.dart` surface and plumbs a
policy option through the pigeon messages into the ExoPlayer setup:

- `lib/src/buffer_policy.dart` (new)
- `lib/src/android_video_player.dart`, `lib/video_player_android.dart`
- `pigeons/messages.dart`, `lib/src/messages.g.dart`
- `android/src/main/java/io/flutter/plugins/videoplayer/VideoPlayerOptions.java`
- `android/src/main/java/io/flutter/plugins/videoplayer/VideoPlayerPlugin.java`
- `android/src/main/java/io/flutter/plugins/videoplayer/platformview/PlatformViewVideoPlayer.java`
- `android/src/main/java/io/flutter/plugins/videoplayer/Messages.kt`

### 2. Live buffer reserve and Gradual mode for live channels
Commit `8c8921a` ("Add a live buffer reserve and Gradual mode for live
channels"). Adds a live-only `LoadControl` plus its Java bridge and wires it
into the player and platform view:

- `android/src/main/java/io/flutter/plugins/videoplayer/LiveBufferLoadControl.java` (new)
- `android/src/main/java/io/flutter/plugins/videoplayer/LiveBufferBridge.java` (new)
- `android/src/main/java/io/flutter/plugins/videoplayer/VideoPlayer.java`
- `android/src/main/java/io/flutter/plugins/videoplayer/VideoPlayerPlugin.java`
- `android/src/main/java/io/flutter/plugins/videoplayer/platformview/PlatformViewVideoPlayer.java`

### 3. MediaPeriodId import fix for the live load control
Commit `422fe8b` ("Import the live load control's MediaPeriodId from its
enclosing class"). One-line import fix in `LiveBufferLoadControl.java`.

## Upgrading the fork

1. Download the pristine upstream tag for the new version and diff it
   against `e839d1c:third_party/video_player_android` to confirm the
   baseline moved cleanly.
2. Re-apply the three patches above in order (or cherry-pick the commits
   onto the new tree and resolve conflicts).
3. Regenerate the pigeon outputs if `pigeons/messages.dart` changed
   (`lib/src/messages.g.dart`, `Messages.kt`), update the version in this
   directory's `pubspec.yaml`, and extend this file with the new baseline.
4. Re-run the app's playback and live-buffer tests; the analysis exclusion
   for `third_party/**` in the root `analysis_options.yaml` means analyzer
   drift here stays silent, so tests are the safety net.
