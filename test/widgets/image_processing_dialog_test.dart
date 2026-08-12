import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/widgets/image_processing_dialog.dart';

void main() {
  testWidgets(
    'ImageProcessingDialog.show opens a non-dismissible processing dialog',
    (tester) async {
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      ImageProcessingDialog.show();
      await tester.pump();

      // Spinner + processing copy are visible.
      expect(find.byType(ImageProcessingDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Processing Image…'), findsOneWidget);
      expect(
        find.text('Enhancing quality & preparing the prescription'),
        findsOneWidget,
      );

      // Barrier taps do NOT dismiss it (non-dismissible — the doctor can't
      // tap away mid-processing).
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ImageProcessingDialog), findsOneWidget);

      // Callers dismiss it with Get.back() once processing finishes.
      Get.back();
      await tester.pumpAndSettle();
      expect(find.byType(ImageProcessingDialog), findsNothing);
    },
  );
}
