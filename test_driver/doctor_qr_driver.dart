/// Driver for the on-device doctor QR-dialog test.
///
/// Run with:
///   flutter drive \
///     --driver=test_driver/doctor_qr_driver.dart \
///     --target=integration_test/doctor_qr_dialog_test.dart \
///     -d `<device>`
///
/// Each `binding.takeScreenshot('name')` call lands here and is written to
/// `screenshots/<name>.png`.
library;

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      return true;
    },
  );
}
