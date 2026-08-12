import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/constants.dart';
import '../models/doctor_model.dart';

/// Generates shareable deep links for a doctor's slot‑management page,
/// with QR‑code rendering and system share‑sheet integration.
class ShareService {
  ShareService._();

  /// Build a shareable deep‑link string for [doctor].
  static String buildManageSlotsLink(DoctorModel doctor) {
    return AppConstants.manageSlotsDeepLink(doctor.placeId);
  }

  /// Share the doctor's slot‑management link via the system share sheet.
  static Future<void> shareDoctorLink(DoctorModel doctor) async {
    final link = buildManageSlotsLink(doctor);
    final text = [
      '🏥 Manage your appointment slots for ${doctor.name}',
      '',
      'Open this link in DrsListing to set up your weekly schedule:',
      link,
      '',
      '— Sent via DrsListing',
    ].join('\n');

    await Share.share(text, subject: 'Manage your slots — ${doctor.name}');
  }

  /// Share the doctor's public booking‑page URL (the QR link patients
  /// scan) via the system share sheet — e.g. WhatsApp, SMS, email.
  static Future<void> shareBookingPageLink(
    String bookingUrl, {
    String? doctorName,
  }) async {
    final text = <String>[
      if (doctorName != null && doctorName.isNotEmpty)
        '🏥 Book an appointment with $doctorName',
      if (doctorName != null && doctorName.isNotEmpty) '',
      'Tap the link to book your appointment:',
      bookingUrl,
      '',
      '— Sent via DrsListing',
    ].join('\n');

    await Share.share(
      text,
      subject: 'Book an appointment — ${doctorName ?? 'DrsListing'}',
    );
  }

  /// Writes [csv] to a temporary file and shares it via the system share
  /// sheet (WhatsApp, email, Drive, …). [filename] should carry a `.csv`
  /// extension (e.g. `payments_2026-08.csv` or `patient_history.csv`).
  /// Non-fatal by design: the caller decides how to surface a failure.
  static Future<void> shareCsvFile({
    required String csv,
    required String filename,
    required String subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'text/csv'),
    ], subject: subject);
  }

  /// Copy the deep‑link to clipboard.
  static void copyManagementLink(DoctorModel doctor) {
    final link = buildManageSlotsLink(doctor);
    Clipboard.setData(ClipboardData(text: link));
    Get.snackbar(
      'Link Copied',
      'Management link copied to clipboard',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  /// Display a bottom‑sheet dialog with a QR code encoding the
  /// management link for [doctor].
  static void showQrCodeSheet(DoctorModel doctor) {
    final link = buildManageSlotsLink(doctor);

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Doctor Management QR Code',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              doctor.name,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // QR Code
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: link,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: Color(0xFF1F2937),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Scan to open slot management',
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFF6B7280).withAlpha(200),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => shareDoctorLink(doctor),
                icon: const Icon(Icons.share_rounded, size: 20),
                label: const Text(
                  'Share Link',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2937),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => copyManagementLink(doctor),
                icon: const Icon(Icons.copy_rounded, size: 20),
                label: const Text(
                  'Copy Link',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F2937),
                  side: BorderSide(
                    color: const Color(0xFF1F2937).withAlpha(40),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
