import 'dart:math';

/// Generates a random 4-digit OTP code (0000–9999, zero-padded).
///
/// Client-side demo OTP — the app generates and verifies the code itself;
/// there is no server/SMS involvement. The code is surfaced to the user in
/// a top toast so testers can read it without hunting through the field.
String generateDemoOtp() {
  return Random().nextInt(10000).toString().padLeft(4, '0');
}
