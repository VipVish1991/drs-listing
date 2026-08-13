import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The permission_handler platform channel
/// (permission_handler_platform_interface 4.x). An unmocked platform
/// channel NEVER resolves under the fake test clock, and the home
/// screen's GPS→mic permission sequencing
/// ([HomeScreen._runPermissionSequencedSetup]) awaits the microphone
/// probe — so every test that pumps the home screen must resolve it.
const MethodChannel _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

/// Registers a mock on the permission_handler channel that reports the
/// microphone as GRANTED. Lets the home screen's sequencing flow run to
/// its end (GPS gate → mic probe → welcome) instead of stalling at the
/// probe forever.
void mockMicPermissionGranted() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            // PermissionStatus.granted.
            return 1;
          case 'requestPermissions':
            // microphone (permission type index) → granted. Not reached
            // while checkPermissionStatus reports granted, kept for
            // completeness.
            return <int, int>{0: 1};
          case 'openAppSettings':
            return true;
          case 'shouldShowRequestPermissionRationale':
            return false;
          default:
            return null;
        }
      });
}

/// Removes the permission-channel mock, restoring the unmocked behavior.
void clearMicPermissionMock() {
  TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, null);
}
