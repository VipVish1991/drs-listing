import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/widgets/prescription_gallery.dart';
import 'package:DrsListing/widgets/zoomable_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const urls = [
    'https://example.com/rx-1.jpg',
    'https://example.com/rx-2.jpg',
    'https://example.com/rx-3.jpg',
  ];

  testWidgets('grid thumbnails use 9:16 portrait cells', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrescriptionGallery(urls: urls)),
      ),
    );
    await tester.pump();

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    // width / height = 9 / 16 → full-height portrait pages.
    expect(delegate.childAspectRatio, closeTo(9 / 16, 1e-9));
  });

  testWidgets('fullscreen viewer uses the shared pinch + double-tap zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PrescriptionGallery(urls: urls)),
      ),
    );
    await tester.pump();

    // Tap the first grid thumbnail → fullscreen viewer.
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byType(ZoomableImage), findsOneWidget);
    // The zoom hint sits next to the counter.
    expect(find.text(AppConstants.zoomHintText), findsOneWidget);

    // And the double-tap gesture works end-to-end inside the viewer.
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.0, 0.01));

    await tester.tap(find.byType(ZoomableImage));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(ZoomableImage));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
  });

  testWidgets('compact strip renders portrait 54×96 thumbnails', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrescriptionGallery(urls: urls, compact: true),
        ),
      ),
    );
    await tester.pump();

    // Horizontal strip…
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.scrollDirection, Axis.horizontal);

    // …with 9:16 portrait thumbnails (54×96), one per URL.
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(urls.length));
    for (final image in images) {
      expect(image.width, 54);
      expect(image.height, 96);
      expect(image.fit, BoxFit.cover);
    }
  });
}
