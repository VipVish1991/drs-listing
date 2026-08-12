import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/widgets/image_processing_dialog.dart';

import '../helpers/golden_fonts.dart';

// ════════════════════════════════════════════════════════════════════
// Golden-image test for the ImageProcessingDialog — the non-dismissible
// "Processing Image…" loading shown between the doctor's camera capture
// and the prescription preview. Locks the dialog's geometry, spacing, and
// typography pixel-for-pixel so a layout regression (padding, sizes, copy)
// fails the comparison without needing a device. Regenerate with:
//
//   flutter test --update-goldens test/widgets/image_processing_dialog_golden_test.dart
//
// NOTE: goldens are platform-sensitive (font hinting/antialiasing differs
// across OSes), so the committed PNG must be regenerated on the platform
// that runs them (here: Windows).
// ════════════════════════════════════════════════════════════════════

/// Pumps the dialog exactly as production shows it (via [Get.dialog]).
///
/// The spinner is an indeterminate animation, so this must NOT use
/// pumpAndSettle — fixed-duration pumps leave the CircularProgressIndicator
/// at a deterministic angle, making the captured frame reproducible.
Future<void> _pumpDialog(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: SizedBox()),
    ),
  );

  ImageProcessingDialog.show();
  await tester.pump(); // push the dialog route
  await tester.pump(
    const Duration(milliseconds: 350),
  ); // entrance fade-in done; spinner at a fixed angle
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('image processing dialog golden', (tester) async {
    await _pumpDialog(tester);

    await expectLater(
      find.byType(ImageProcessingDialog),
      matchesGoldenFile('goldens/image_processing_dialog.png'),
    );
  });
}
