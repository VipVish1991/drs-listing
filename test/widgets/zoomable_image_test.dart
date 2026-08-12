import 'package:DrsListing/widgets/zoomable_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpZoomable(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ZoomableImage(
              child: Container(
                width: 200,
                height: 300,
                color: Colors.teal,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Current zoom factor read off the InteractiveViewer's transformation
  /// controller — independent of the widget's internals.
  double scale(WidgetTester tester) {
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    return viewer.transformationController!.value.getMaxScaleOnAxis();
  }

  Future<void> doubleTap(WidgetTester tester, {Offset? at}) async {
    final finder = find.byType(ZoomableImage);
    if (at == null) {
      await tester.tap(finder);
    } else {
      await tester.tapAt(at);
    }
    await tester.pump(const Duration(milliseconds: 80));
    if (at == null) {
      await tester.tap(finder);
    } else {
      await tester.tapAt(at);
    }
    await tester.pumpAndSettle();
  }

  /// Pinches two fingers apart from the widget center — the standard
  /// pinch-to-zoom-in gesture — and returns the resulting zoom factor.
  Future<double> pinchIn(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(ZoomableImage));
    final g1 = await tester.startGesture(center - const Offset(30, 0));
    final g2 = await tester.startGesture(center + const Offset(30, 0));
    await tester.pump();
    // Small opening move first so the scale recognizer accepts the gesture
    // with both fingers already down (a single huge move would capture a
    // mid-move reference span and under-report the zoom).
    await g1.moveBy(const Offset(-20, 0));
    await g2.moveBy(const Offset(20, 0));
    await tester.pump();
    await g1.moveBy(const Offset(-80, 0));
    await g2.moveBy(const Offset(80, 0));
    await tester.pump();
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
    return scale(tester);
  }

  /// The full transform matrix of the on-screen InteractiveViewer — lets
  /// tests assert BOTH the scale and the translation (a full collapse back
  /// to identity, not just a scale reset).
  Matrix4 transform(WidgetTester tester) {
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    return viewer.transformationController!.value;
  }

  testWidgets('double-tap zooms in to 2.5x and double-tap again returns to 1x',
      (tester) async {
    await pumpZoomable(tester);
    expect(scale(tester), closeTo(1.0, 0.01));

    await doubleTap(tester);
    expect(scale(tester), closeTo(2.5, 0.01));

    await doubleTap(tester);
    expect(scale(tester), closeTo(1.0, 0.01));
  });

  testWidgets('double-tap at an already-collapsed 1x state re-zooms '
      '(toggle round-trip)', (tester) async {
    await pumpZoomable(tester);

    // 1x → 2.5x → 1x (the collapse path)…
    await doubleTap(tester);
    expect(scale(tester), closeTo(2.5, 0.01));
    await doubleTap(tester);
    expect(scale(tester), closeTo(1.0, 0.01));

    // …then double-tap AGAIN from identity: the scale-based toggle must
    // re-zoom rather than stay collapsed.
    await doubleTap(tester);
    expect(scale(tester), closeTo(2.5, 0.01));

    // The re-zoom is a fresh zoom about the tapped point — the box's
    // center stays pinned under the finger, with no drift carried over
    // from the previous zoom/collapse cycle. The tap point is expressed
    // in the widget's own (local) coordinate space — the box is
    // shrink-wrapped to its child, so its top-left is not the viewport
    // origin.
    final rect = tester.getRect(find.byType(ZoomableImage));
    final localCenter = rect.center - rect.topLeft;
    final transformed = MatrixUtils.transformPoint(transform(tester), localCenter);
    expect(transformed.dx, closeTo(localCenter.dx, 1.0));
    expect(transformed.dy, closeTo(localCenter.dy, 1.0));
  });

  testWidgets('pinch gesture zooms in to a genuine pinch scale, not the '
      'double-tap scale', (tester) async {
    await pumpZoomable(tester);

    final pinchScale = await pinchIn(tester);
    // A real pinch lands well beyond 2x — and deliberately NOT on the
    // double-tap's own 2.5x, so the collapse test below exercises a
    // genuinely different zoom state.
    expect(pinchScale, greaterThan(2.0));
    expect(pinchScale, isNot(closeTo(2.5, 0.05)));
  });

  testWidgets('double-tap while pinch-zoomed collapses back to exactly 1x',
      (tester) async {
    await pumpZoomable(tester);

    // Pinch to a scale above the 1.5x collapse threshold — not the 2.5x
    // the double-tap itself produces.
    final pinchScale = await pinchIn(tester);
    expect(pinchScale, greaterThan(1.5));

    // A double-tap while zoomed collapses back to 1x — the toggle is
    // scale-based (> 1.5x → 1x), so it must work from a pinch zoom too,
    // not just from the double-tap's own 2.5x state.
    await doubleTap(tester);

    // Full reset: scale AND translation return to identity.
    final m = transform(tester);
    expect(m.getMaxScaleOnAxis(), closeTo(1.0, 1e-9));
    expect(m.getTranslation().x, closeTo(0.0, 1e-9));
    expect(m.getTranslation().y, closeTo(0.0, 1e-9));
  });

  testWidgets('double-tap zooms toward the tapped point, not just the center',
      (tester) async {
    await pumpZoomable(tester);

    // Double-tap near the top-left corner of the viewport.
    final topLeft = tester.getTopLeft(find.byType(ZoomableImage));
    final tapPoint = topLeft + const Offset(40, 40);
    await doubleTap(tester, at: tapPoint);

    expect(scale(tester), closeTo(2.5, 0.01));
    // The tapped content point stays under the finger: after zooming the
    // transformed position of the tap point is still the tap point.
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final transformed =
        MatrixUtils.transformPoint(
          viewer.transformationController!.value,
          const Offset(40, 40),
        );
    expect(transformed.dx, closeTo(40, 1.0));
    expect(transformed.dy, closeTo(40, 1.0));
  });
}
