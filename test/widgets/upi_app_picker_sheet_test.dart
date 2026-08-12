import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:upi_india/upi_india.dart';

import 'package:DrsListing/widgets/upi_app_picker_sheet.dart';

/// Builds a fake discovered UPI app.
///
/// The test-constructed app never assigns `icon` (a `late` field), so
/// accessing it throws — the sheet's placeholder icon renders, exactly
/// what the icon test below asserts.
UpiApp _fakeApp(String name, String package) => UpiApp(name, package);

void main() {
  group('UpiAppPickerSheet', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      List<UpiApp> apps,
    ) async {
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: Center(child: UpiAppPickerSheet(apps: apps)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Pumps a host screen with a button that opens the picker via the
    /// public `UpiAppPickerSheet.show` helper, capturing the result.
    Future<void> pumpOpener(
      WidgetTester tester,
      List<UpiApp> apps,
      void Function(UpiApp?) onResult,
    ) async {
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    onResult(await UpiAppPickerSheet.show(context, apps));
                  },
                  child: const Text('open picker'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders the title, app-count pill, every app and Cancel',
        (tester) async {
      final apps = [
        _fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user'),
        _fakeApp('PhonePe', 'com.phonepe.app'),
        _fakeApp('Paytm', 'net.one97.paytm'),
      ];
      await pumpSheet(tester, apps);

      expect(find.text('Pay with'), findsOneWidget);
      expect(find.text('3 apps'), findsOneWidget);
      expect(find.text('GPay'), findsOneWidget);
      expect(find.text('PhonePe'), findsOneWidget);
      expect(find.text('Paytm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('singular count pill reads "1 app"', (tester) async {
      await pumpSheet(
        tester,
        [_fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user')],
      );
      expect(find.text('1 app'), findsOneWidget);
    });

    testWidgets('each app row shows an icon (placeholder when none set)',
        (tester) async {
      final apps = [
        _fakeApp('GPay', 'gpay'),
        _fakeApp('PhonePe', 'phonepe'),
        _fakeApp('Paytm', 'paytm'),
      ];
      await pumpSheet(tester, apps);

      // The test apps carry no icon bytes, so every row falls back to the
      // generic rupee placeholder — exactly one icon per app.
      expect(find.byIcon(Icons.currency_rupee_rounded), findsNWidgets(3));
    });

    testWidgets('a long app list scrolls instead of overflowing',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final apps = List.generate(
        12,
        (i) => _fakeApp('UPI App ${i + 1}', 'com.test.upi$i'),
      );
      await pumpSheet(tester, apps);

      // No overflow exception occurred (pumpSheet would have failed).
      // The last app starts below the fold and only becomes hittable after
      // the list is scrolled. ensureVisible scrolls the ancestor scrollable
      // deterministically (independent of row height / font metrics).
      expect(find.text('UPI App 12').hitTestable(), findsNothing);
      await tester.ensureVisible(find.text('UPI App 12'));
      await tester.pumpAndSettle();
      expect(find.text('UPI App 12').hitTestable(), findsOneWidget);
    });

    testWidgets('tapping an app returns the selected UpiApp',
        (tester) async {
      UpiApp? picked;
      final apps = [
        _fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user'),
        _fakeApp('PhonePe', 'com.phonepe.app'),
      ];
      await pumpOpener(tester, apps, (result) => picked = result);

      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      expect(find.text('Pay with'), findsOneWidget);
      await tester.tap(find.text('PhonePe'));
      await tester.pumpAndSettle();

      expect(picked?.name, 'PhonePe');
      // The sheet closed after the selection.
      expect(find.text('Pay with'), findsNothing);
    });

    testWidgets('Cancel dismisses the picker with null', (tester) async {
      UpiApp? picked;
      var resolved = false;
      final apps = [_fakeApp('GPay', 'com.google.android.apps.nbu.paisa.user')];
      await pumpOpener(tester, apps, (result) {
        resolved = true;
        picked = result;
      });

      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(resolved, isTrue);
      expect(picked, isNull);
      expect(find.text('Pay with'), findsNothing);
    });
  });
}
