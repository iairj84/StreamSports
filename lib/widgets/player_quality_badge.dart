import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player_hdr/video_player_hdr.dart';
import '../utils/video_quality.dart';

/// Picture quality of the stream that is actually playing, read from the
/// decoder's selected video track — never from the provider's channel name,
/// which routinely claims 4K for a 1080p feed (see `qualityLabelForTrack`).
///
/// Renders nothing until a track height is known, so a stream whose track API
/// does not answer simply has no badge. Track metadata is sampled on open and
/// then a few times a minute: switching rendition mid-stream changes it, but
/// nothing here opens a stream or probes the provider.
class PlayerQualityBadge extends StatefulWidget {
  const PlayerQualityBadge(
      {super.key, required this.controller, this.compact = false});

  final VideoPlayerHdrController? controller;
  final bool compact;

  @override
  State<PlayerQualityBadge> createState() => _PlayerQualityBadgeState();
}

class _PlayerQualityBadgeState extends State<PlayerQualityBadge> {
  Timer? _timer;
  String? _label;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PlayerQualityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _label = null;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _read());
    // Deferred: a controller handed over during a build is not initialized
    // yet, and asking for tracks then would answer for the previous stream.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _read();
    });
  }

  Future<void> _read() async {
    final controller = widget.controller;
    if (_reading || controller == null || !controller.value.isInitialized) {
      return;
    }
    _reading = true;
    try {
      if (!controller.isVideoTrackSupportAvailable()) return;
      final tracks = await controller
          .getVideoTracks()
          .timeout(const Duration(seconds: 2));
      if (tracks.isEmpty) return;
      var selected = tracks.first;
      for (final track in tracks) {
        if (track.isSelected) {
          selected = track;
          break;
        }
      }
      final height = selected.height ?? 0;
      final label = height <= 0
          ? null
          : qualityLabelForTrack(height: height, frameRate: selected.frameRate);
      if (mounted && label != null && label != _label) {
        setState(() => _label = label);
      }
    } catch (_) {
      // Best-effort metadata: a track API that times out or throws leaves the
      // badge hidden rather than showing a guess.
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 7 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: widget.compact ? 11 : 12,
              height: 1.15,
              letterSpacing: .5,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
    );
  }
}
