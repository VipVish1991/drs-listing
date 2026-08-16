import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/appointment_model.dart';
import '../utils/text_sanitizer.dart';
import 'app_button.dart';
import 'appointment_details_sheet.dart';
import 'appointment_info_card.dart';

/// Patient-side appointment card (My Appointments screen).
///
/// Delegates to the shared [AppointmentInfoCard] so the patient list
/// renders pixel-identical cards to the doctor's Appointments tab: left
/// status-colored accent bar, avatar + name + status-below header, the
/// 2-column info grid (Date / Time), a full-width Consultation row where
/// the doctor's phone used to be (the phone itself lives in the details
/// sheet), the prescription "Click" row and the Map / Cancel action
/// chips (each only when the caller provides its callback).
/// Rescheduling is intentionally NOT a card chip anymore — the details
/// sheet is its single entry point.
class AppointmentCard extends StatelessWidget {
  final AppointmentModel appointment;

  /// The status to actually render (computed by the screen — accounts for
  /// appointments whose time has passed but whose stored status is stale).
  final String displayStatus;

  final VoidCallback onTap;
  final VoidCallback? onMap;
  final VoidCallback? onCancel;

  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.displayStatus,
    required this.onTap,
    this.onMap,
    this.onCancel,
  });

  // Same status color/icon mapping as the doctor side (single source of
  // truth in AppointmentDetailsSheet) so the two sides render identical
  // status glyphs and hues.
  Color _statusColor() => AppointmentDetailsSheet.statusColor(displayStatus);

  IconData _statusIcon() => AppointmentDetailsSheet.statusIcon(displayStatus);

  String _avatarInitial(String name) {
    return name.isNotEmpty ? name[0].toUpperCase() : 'D';
  }

  /// Stable soft pastel for the avatar circle (same palette as the doctor
  /// card's per-index colors; keyed on the name so it never flickers).
  Color _avatarColor(String name) {
    const palette = [
      Color(0xFFE8EAF5),
      Color(0xFFF0E6F8),
      Color(0xFFE6F2F5),
      Color(0xFFF5ECE6),
      Color(0xFFE6F0F0),
      Color(0xFFF0F0E6),
    ];
    final sum = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[sum % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();
    final statusIcon = _statusIcon();
    final doctorName = TextSanitizer.sanitize(
      appointment.doctorName ?? 'Doctor',
    );

    return Padding(
      // The patient history list has no horizontal padding of its own, so
      // the card keeps its own side margin (matches the pre-redesign look).
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AppointmentInfoCard(
        appointment: appointment,
        onTap: onTap,
        accentColor: statusColor,
        borderRadius: 20,
        padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
        shadowBlur: 12,
        shadowAlpha: 8,
        header: AppointmentCardHeader(
          name: doctorName,
          statusLabel: displayStatus,
          statusIcon: statusIcon,
          statusColor: statusColor,
          avatarInitials: _avatarInitial(doctorName),
          avatarColor: _avatarColor(doctorName),
        ),
        displayStatus: displayStatus,
        statusColor: statusColor,
        statusIcon: statusIcon,
        prescriptionClickRow: true,
        // The consultation type in the phone's former full-width spot —
        // the patient reads what they booked at a glance (the phone now
        // lives in the details sheet, reachable via the Call action).
        // Hidden for legacy rows without a stored type.
        infoBlocks: [?AppointmentInfoBlock.consultationOf(appointment)],
        // Pending (QR / browser booking): awaiting clinic confirmation.
        // Shown as a distinct banner so patients know their booking isn't
        // confirmed yet.
        extraRow: displayStatus == AppointmentStatus.pending
            ? _buildPendingBanner(statusColor)
            : null,
        actions: (onMap != null || onCancel != null)
            ? Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onMap != null)
                    AppActionChip(
                      icon: Icons.map_rounded,
                      label: 'Map',
                      color: AppColors.info,
                      onTap: onMap!,
                    ),
                  if (onCancel != null)
                    AppActionChip(
                      icon: Icons.close,
                      label: 'Cancel',
                      color: AppColors.error,
                      onTap: onCancel!,
                    ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildPendingBanner(Color statusColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withAlpha(50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Awaiting clinic confirmation — the clinic will confirm your appointment soon.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
