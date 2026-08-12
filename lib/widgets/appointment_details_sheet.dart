import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../models/appointment_model.dart';
import '../models/payment_model.dart';
import '../services/launch_service.dart';
import 'appointment_info_card.dart';
import 'prescription_gallery.dart';

/// Shared appointment-details bottom sheet used by both the doctor's
/// appointments screen and the patient's appointment history screen.
///
/// The two screens pass their own [displayStatus] (the doctor labels
/// blank statuses as 'Upcoming'; the patient screen auto-completes past
/// slots) and [headerName] (the doctor screen shows the patient name,
/// the patient screen shows the doctor name).
class AppointmentDetailsSheet {
  AppointmentDetailsSheet._();

  /// Opens the details bottom sheet for [appointment].
  ///
  /// [displayStatus] is the status to render (screens compute it
  /// themselves). [headerName] is the title shown next to the avatar.
  /// [extraRows] are appended after the standard Date/Time/ID rows and
  /// before the phone row (e.g. a Patient row on the patient side).
  /// [footerActions] are placed under the "Call Now" button (e.g. a
  /// "View Doctor Profile" button on the patient side).
  /// [closeKey] keys the close button so widget tests can find it.
  ///
  /// [phoneNumber] overrides the number to render and dial. Defaults to
  /// [AppointmentModel.callNumber] (the patient side calls the doctor);
  /// the doctor side passes [AppointmentModel.patientPhone] instead so the
  /// modal shows the PATIENT's number.
  ///
  /// [payment] is the `payments` row recorded for this appointment (when
  /// one exists) — rendered as a fee card right beside the footer actions
  /// (e.g. Reschedule): amount + status chip + method, plus the paid date
  /// and UPI transaction id when known. Null → no payment card.
  static void show({
    required AppointmentModel appointment,
    required String displayStatus,
    required String headerName,
    Key? closeKey,
    List<Widget>? extraRows,
    List<Widget>? footerActions,
    String? phoneNumber,
    PaymentModel? payment,
  }) {
    final statusColor = AppointmentDetailsSheet.statusColor(displayStatus);
    final phone = phoneNumber ?? appointment.callNumber;
    // Status accent for the header's fee chip. Always non-null (the
    // fallback is inert — the chip only renders when a payment exists, so
    // the caller's status color is what's shown). Computed once here so
    // the Wrap's collection-if doesn't need a local.
    final feeColor = payment == null
        ? AppColors.textCaption
        : AppointmentPaymentCard.statusColor(payment.paymentStatus);

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.bgMain,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textCaption.withAlpha(90),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // ── Header ──
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor.withAlpha(15),
                      border: Border.all(
                        color: statusColor.withAlpha(60),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        initials(headerName),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textHeading,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              statusIcon(displayStatus),
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              displayStatus,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                        // ── Consultation type + fee chips (tele / video /
                        //    clinic + ₹ amount) — what the patient booked
                        //    and what it costs, surfaced right in the
                        //    header. Each is hidden when its data is
                        //    missing (legacy rows without a stored type /
                        //    no payment row / a free ₹0 slot). A Wrap (not
                        //    a Row) so a long label drops to a second line
                        //    instead of overflowing at extreme text
                        //    scales. ──
                        if (appointment.consultationTypeLabel != null ||
                            (payment != null && payment.amount > 0)) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (appointment.consultationTypeLabel != null)
                                Container(
                                  key: const ValueKey(
                                    'details_sheet_consultation_chip',
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withAlpha(14),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.info.withAlpha(40),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        AppointmentInfoBlock.consultationIconOf(
                                          appointment,
                                        ),
                                        size: 12,
                                        color: AppColors.info,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        appointment.consultationTypeLabel!,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.info,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // ── Fee chip — the consultation amount from
                              //    the payment row, tinted by its status
                              //    (green when Paid, amber when Pending,
                              //    …) so the settlement state reads at a
                              //    glance before opening the full card. A
                              //    long-press Tooltip spells the status out
                              //    for color-blind users. ──
                              if (payment != null && payment.amount > 0)
                                Tooltip(
                                  message:
                                      '${payment.amountLabel} · '
                                      '${payment.paymentStatus}',
                                  child: Container(
                                    key: const ValueKey(
                                      'details_sheet_fee_chip',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: feeColor.withAlpha(14),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: feeColor.withAlpha(40),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.currency_rupee_rounded,
                                          size: 12,
                                          color: feeColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          PaymentModel.formatAmount(
                                            payment.amount,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: feeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    key: closeKey,
                    onTap: () => Get.back(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.textCaption.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.textCaption,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ── Standard details ──
              AppointmentDetailRow(
                icon: Icons.calendar_month_rounded,
                iconColor: AppColors.primary,
                label: 'Date',
                value: appointment.displayDate ?? 'N/A',
              ),
              AppointmentDetailRow(
                icon: Icons.access_time_rounded,
                iconColor: AppColors.accent,
                label: 'Time',
                value: appointment.appointmentTime ?? 'N/A',
              ),
              AppointmentDetailRow(
                icon: Icons.badge_rounded,
                iconColor: AppColors.info,
                label: 'Appointment ID',
                value: appointment.appointmentId,
              ),
              // Screen-specific rows (e.g. Patient name on the patient
              // side). The consultation type has no detail row of its own —
              // the header chip covers it.
              if (extraRows != null) ...extraRows,
              if (phone != null && phone.isNotEmpty)
                AppointmentDetailRow(
                  icon: Icons.phone_rounded,
                  iconColor: AppColors.success,
                  label: 'Phone',
                  value: phone,
                  onTap: () => LaunchService.phone(phone),
                  showCallIcon: true,
                ),
              // ── Uploaded prescription photos (doctor or patient view) ──
              if (appointment.prescriptionUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                PrescriptionGallery(urls: appointment.prescriptionUrls),
              ],

              // ── Symptoms / notes (full detail lives in the sheet) ──
              if ((appointment.symptoms ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.textCaption.withAlpha(15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.healing_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Symptoms / Notes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textCaption,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appointment.symptoms!,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.textBody,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ── Call action ──
              if (phone != null && phone.isNotEmpty) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => LaunchService.phone(phone),
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: const Text(
                      'Call Now',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
              // ── Fee / payment — rendered right beside the footer
              //    actions (e.g. Reschedule) so the patient and doctor see
              //    what the consultation costs and how it was settled. ──
              if (payment != null) ...[
                const SizedBox(height: 16),
                AppointmentPaymentCard(payment: payment),
              ],
              // Screen-specific actions (e.g. View Doctor Profile).
              if (footerActions != null && footerActions.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...footerActions,
              ],
            ],
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  /// Status accent color used by the sheet (and by screens that render
  /// their own status chips) so the mapping stays in one place.
  static Color statusColor(String status) {
    switch (status) {
      case 'Completed':
        return AppColors.success;
      case 'Cancelled':
        return AppColors.error;
      case AppointmentStatus.pending:
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  /// Status icon used by the sheet header (and screens' own status chips).
  static IconData statusIcon(String status) {
    switch (status) {
      case 'Completed':
        return Icons.check_circle_rounded;
      case 'Cancelled':
        return Icons.cancel_rounded;
      case AppointmentStatus.pending:
        return Icons.hourglass_top_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  /// Initials for an avatar, e.g. "Dr. Smith" → "DS".
  static String initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'D';
  }
}

/// Fee/payment block rendered inside the details sheet when a `payments`
/// row exists for the appointment: the amount up front, a status chip
/// (Paid / Pending / Failed / Refunded), the payment method (Online UPI /
/// Offline Clinic), plus the paid date and the UPI transaction id when
/// known. Status colours mirror the payment-history screen (Paid → green,
/// Pending → amber, Failed → red, Refunded → blue).
class AppointmentPaymentCard extends StatelessWidget {
  final PaymentModel payment;

  const AppointmentPaymentCard({super.key, required this.payment});

  /// Status accent color — the single source of truth shared by the
  /// payment card and the sheet header's fee chip, so both tint the same
  /// way (Paid → green, Pending → amber, Failed → red, Refunded → blue).
  static Color statusColor(String status) {
    switch (status) {
      case 'Paid':
        return AppColors.success;
      case 'Pending':
        return AppColors.warning;
      case 'Failed':
        return AppColors.error;
      case 'Refunded':
        return AppColors.info;
      default:
        return AppColors.textCaption;
    }
  }

  (IconData, Color) _visualsFor(String status) {
    switch (status) {
      case 'Paid':
        return (Icons.check_circle_rounded, statusColor(status));
      case 'Pending':
        return (Icons.schedule_rounded, statusColor(status));
      case 'Failed':
        return (Icons.cancel_rounded, statusColor(status));
      case 'Refunded':
        return (Icons.currency_rupee_rounded, statusColor(status));
      default:
        return (Icons.receipt_long_rounded, statusColor(status));
    }
  }

  String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _visualsFor(payment.paymentStatus);
    final paidOn = payment.paidAt;
    final showTxn =
        payment.paymentMethod == 'online' &&
        (payment.transactionId ?? '').isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 20,
                  color: AppColors.textHeading,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textCaption,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      payment.amountLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHeading,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha(16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withAlpha(60), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 4),
                    Text(
                      payment.paymentStatus,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PaymentInfoRow(
            icon: Icons.payment_rounded,
            color: AppColors.primary,
            label: 'Method',
            value: payment.paymentMethodLabel,
          ),
          if (paidOn != null)
            _PaymentInfoRow(
              icon: Icons.event_available_rounded,
              color: AppColors.success,
              label: 'Paid on',
              value: _dateLabel(paidOn),
            ),
          if (showTxn)
            _PaymentInfoRow(
              icon: Icons.receipt_long_rounded,
              color: AppColors.info,
              label: 'Transaction',
              value: payment.transactionId!,
            ),
        ],
      ),
    );
  }
}

/// One labelled line inside [AppointmentPaymentCard] (method / paid date /
/// transaction id).
class _PaymentInfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _PaymentInfoRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textCaption),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textHeading,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled info row inside the appointment-details sheet. When
/// [onTap] is provided the whole row is tappable (e.g. opening the
/// dialer for the phone number).
class AppointmentDetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool showCallIcon;

  const AppointmentDetailRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
    this.showCallIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textCaption.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHeading,
                  ),
                ),
              ],
            ),
          ),
          if (showCallIcon) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.phone_rounded,
                size: 16,
                color: AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: row,
    );
  }
}
