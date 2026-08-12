import 'package:flutter/material.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// The (placeholder) video platform captured at load time — restore this
/// in a test's tearDown after installing [FakeVideoPlayerPlatform] so the
/// fake never leaks into the next test.
final VideoPlayerPlatform originalVideoPlatform = VideoPlayerPlatform.instance;

/// Minimal fake video platform so [HealthAssistantVideo]'s controller can
/// initialize and report play/pause taps in widget tests (the real
/// platform plugin is absent on a bare test binding). Emits a single
/// `initialized` event so `initialize()` completes; every other call is a
/// no-op that keeps the controller's position-polling timer harmless.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    return _nextPlayerId++;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // Emit the initialized event once a listener is attached — a non-null
    // duration marks the controller initialized and completes its
    // initialize() future.
    return Stream<VideoEvent>.multi((controller) {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 30),
          size: const Size(270, 480),
          rotationCorrection: 0,
        ),
      );
    });
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    // An opaque hit-test surface the size of the box: the parent Stack
    // (StackFit.expand) and the avatar's GestureDetector only receive a
    // tap where a child is hit, so the surface must fill its area.
    // (SizedBox.shrink() collapses to 0×0 here and the tap misses.)
    return const ColoredBox(color: Colors.transparent);
  }
}
