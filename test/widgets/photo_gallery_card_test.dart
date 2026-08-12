import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/widgets/photo_gallery_card.dart';
import 'package:DrsListing/widgets/zoomable_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Load dotenv with a placeholder so AppConstants.googleMapsApiKey
  // doesn't throw NotInitializedError during widget builds.
  setUpAll(() {
    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=test_key');
  });

  const photos = ['ref-1', 'ref-2', 'ref-3'];

  Future<void> pumpGallery(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FullscreenPhotoGallery(photos: photos, initialIndex: 0),
      ),
    );
    await tester.pump();
  }

  testWidgets('fullscreen gallery uses the shared pinch + double-tap zoom', (
    tester,
  ) async {
    await pumpGallery(tester);

    // Counter + the same zoom hint as the prescription viewers.
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byType(ZoomableImage), findsOneWidget);
    expect(find.text(AppConstants.zoomHintText), findsOneWidget);

    // Double-tap zooms in to 2.5x...
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

    // ...and double-tap again returns to 1x.
    await tester.tap(find.byType(ZoomableImage));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(ZoomableImage));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.0, 0.01));
  });

  testWidgets('swiping still browses photos while zoomed view resets per page', (
    tester,
  ) async {
    await pumpGallery(tester);

    // Zoom the first page, then swipe — the next page is a fresh
    // ZoomableImage at 1x.
    await tester.tap(find.byType(ZoomableImage));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(ZoomableImage));
    await tester.pumpAndSettle();
    final before = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer).first,
    );
    expect(
      before.transformationController!.value.getMaxScaleOnAxis(),
      closeTo(2.5, 0.01),
    );

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    final after = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer).first,
    );
    expect(
      after.transformationController!.value.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
  });
}
