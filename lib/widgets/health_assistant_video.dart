import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';
import '../config/theme.dart';

/// Plays the health-assistant welcome video (`health_assisten.mp4`) at its
/// own natural portrait aspect ratio, with no frame, ring, or background
/// behind it — just the video floating on a fully transparent background.
///
/// Autoplays + loops. The video carries no audio track, so the TTS
/// greeting provides the voice. Tapping the video pauses/resumes it, and
/// reports the new state via [onPlayingChanged] so the parent can
/// pause/resume TTS speech (and the mic) in step with it — one tap stops
/// everything, the next tap starts it all again. If the video can't be
/// loaded (unsupported codec on the current platform, or the test environment
/// where the platform plugin is absent), it degrades to a transparent
/// placeholder with the health icon.
class HealthAssistantVideo extends StatefulWidget {
  /// Width of the video. Height follows automatically from the video's
  /// own (portrait) aspect ratio once it's loaded.
  final double width;

  /// Whether the video starts playing as soon as it's loaded. When false
  /// it loads and shows its first frame paused, and starts playing once
  /// [autoPlay] flips to true (e.g. the welcome-flow delay on the home
  /// screen). Defaults to true.
  final bool autoPlay;

  /// Called after every tap with the video's new play state — `false`
  /// when the tap paused it, `true` when the next tap resumed it. The
  /// parent uses this to pause/resume TTS speech (and stop the mic) in
  /// lockstep with the video.
  final ValueChanged<bool>? onPlayingChanged;

  final String assetPath;

  const HealthAssistantVideo({
    super.key,
    this.width = 220,
    this.autoPlay = true,
    this.onPlayingChanged,
    this.assetPath = 'assets/video/health_assisten.mp4',
  });

  @override
  State<HealthAssistantVideo> createState() => _HealthAssistantVideoState();
}

class _HealthAssistantVideoState extends State<HealthAssistantVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  /// Whether the video is currently intended to play — toggled by tapping
  /// it, independent of any external state.
  late bool _playing;

  @override
  void initState() {
    super.initState();
    _playing = widget.autoPlay;
    _initVideo();
  }

  @override
  void didUpdateWidget(HealthAssistantVideo oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Start/pause the video when autoPlay flips (the welcome-flow delay
    // on the home screen waits ~1.5s before the avatar video kicks in).
    if (widget.autoPlay != oldWidget.autoPlay) {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        if (widget.autoPlay) {
          _playing = true;
          controller.play();
        } else {
          _playing = false;
          controller.pause();
        }
      }
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset(widget.assetPath);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      // No audio track in the source video — keep volume at 0 regardless.
      await controller.setVolume(0);

      if (widget.autoPlay) {
        await controller.play();
      } else {
        // Show the first frame paused until autoPlay flips to true.
        await controller.pause();
      }

      setState(() => _ready = true);
    } catch (_) {
      // Video unavailable (unsupported codec/platform or tests) — show
      // the transparent placeholder instead.
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Tapping the video pauses/resumes it. Every tap reports the new
  /// state via [HealthAssistantVideo.onPlayingChanged] so the parent can
  /// pause/resume TTS speech (and stop the mic) in step — one tap stops
  /// everything, the next tap starts it all again.
  void _toggleVideoPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() => _playing = !_playing);

    if (_playing) {
      controller.play();
    } else {
      controller.pause();
    }

    widget.onPlayingChanged?.call(_playing);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady =
        _ready && controller != null && controller.value.isInitialized;

    // The video's own aspect ratio once it's loaded (typically portrait
    // for this asset); a sensible portrait default beforehand so nothing
    // jumps around once it becomes ready.
    final aspectRatio = isReady ? controller.value.aspectRatio : 9 / 16;

    return GestureDetector(
      onTap: isReady ? _toggleVideoPlayback : null,
      child: SizedBox(
        width: widget.width,
        // Background stays fully transparent — no card, ring, or fill
        // behind the video at any state (loading/ready/failed).
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildContent(isReady),
              if (isReady)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withAlpha(140),
                      border: Border.all(
                        color: Colors.white.withAlpha(200),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isReady) {
    final controller = _controller;

    if (isReady) {
      return VideoPlayer(controller!);
    }

    if (_failed) {
      // Transparent placeholder — just the health icon, no background.
      return const Center(
        child: Icon(
          Icons.health_and_safety_rounded,
          color: AppColors.primary,
          size: 44,
        ),
      );
    }

    // Loading — spinner on a transparent background.
    return Center(
      child: SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.primary.withAlpha(200),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}
