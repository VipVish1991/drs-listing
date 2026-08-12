import 'package:flutter/material.dart';

/// Wraps a [child] (typically an [Image]) in an [InteractiveViewer] with the
/// standard photo-gallery zoom gestures:
///
/// - **Pinch** to zoom in/out (0.5×–4×, pan while zoomed).
/// - **Double-tap** to zoom in to [doubleTapScale] centered on the tapped
///   point; double-tap again (or at any zoom > 1.5×) returns to 1×.
///
/// Used by the full-screen prescription viewers so the zoom behavior is
/// identical everywhere. Zoom resets automatically when a new page is shown,
/// because each gallery page builds its own fresh instance.
class ZoomableImage extends StatefulWidget {
  /// The content to make zoomable — typically `Image.network(..., fit:
  /// BoxFit.contain)` with its own error/loading builders.
  final Widget child;

  final double minScale;

  final double maxScale;

  /// Scale reached by a double-tap zoom-in. Tapping again returns to 1×.
  final double doubleTapScale;

  const ZoomableImage({
    super.key,
    required this.child,
    this.minScale = 0.5,
    this.maxScale = 4.0,
    this.doubleTapScale = 2.5,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _zoomController;
  late Animation<Matrix4> _zoomAnimation;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformationChanged);
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _zoomAnimation = Matrix4Tween(
      begin: Matrix4.identity(),
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(parent: _zoomController, curve: Curves.easeOut),
    );
    _zoomController.addListener(() {
      _transformationController.value = _zoomAnimation.value;
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    _currentScale = _transformationController.value.getMaxScaleOnAxis();
  }

  /// Double-tap zooms in toward the tapped point; a second double-tap (or a
  /// tap while already zoomed past 1.5×) animates back to 1×.
  void _handleDoubleTap(TapDownDetails details) {
    // Where the tap landed, in the content's coordinate space — the point
    // that must stay under the finger after zooming.
    final scene = _transformationController.toScene(details.localPosition);
    final targetScale = _currentScale > 1.5 ? 1.0 : widget.doubleTapScale;
    final end = targetScale == 1.0
        ? Matrix4.identity()
        : Matrix4.identity()
          ..translate(
            -scene.dx * (targetScale - 1.0),
            -scene.dy * (targetScale - 1.0),
          )
          ..scale(targetScale);
    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: end,
    ).animate(
      CurvedAnimation(parent: _zoomController, curve: Curves.easeOut),
    );
    _zoomController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque so double-taps land anywhere on the viewport, not only on
      // pixels the image itself covers.
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        child: widget.child,
      ),
    );
  }
}
