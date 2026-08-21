import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/payment_model.dart';
import '../../services/local_storage_service.dart';
import '../../services/quantupi_payment_service.dart';
import '../../routes/app_routes.dart';
import '../../utils/appointment_dialogs.dart';
import '../../utils/doctor_appointment_actions.dart';
import '../../utils/snackbar_helpers.dart';
import '../../utils/upi_qr_parser.dart';
import '../../widgets/appointment_date_filter.dart';
import '../../widgets/appointment_details_sheet.dart';
import '../../widgets/appointment_info_card.dart';
import '../../widgets/appointment_search.dart';
import '../../widgets/upi_qr_scanner_screen.dart';

class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({super.key});

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen> {
  final _controller = Get.find<DoctorController>();

  /// Selected date string (yyyy-MM-dd). Defaults to today.
  late String _selectedDate;

  /// Whether the header search field is visible. While searching, the
  /// date filter is hidden and results span every date.
  bool _isSearching = false;

  /// Current search query (raw text as typed).
  String _searchQuery = '';

  /// Consultation-type filter: 0 = All, 1 = Online, 2 = Offline.
  late int _consultationFilter;

  final TextEditingController _searchController = TextEditingController();

  /// Session-level memory of an online refund the UPI app CONFIRMED but
  /// whose payment record failed to update. Keyed by payment id: a later
  /// Refund tap on the same payment must RETRY THE RECORD — never send a
  /// second refund to the patient. (In-memory only — if the app is killed
  /// and relaunched the payment still shows Paid, so the clinic should
  /// verify with the patient before re-sending.)
  final Map<String, _PendingOnlineRefund> _unrecordedOnlineRefunds = {};

  @override
  void initState() {
    super.initState();
    _consultationFilter = LocalStorageService().getAppointmentFilter();
    final now = DateTime.now();
    _selectedDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    return status.isEmpty ? 'Upcoming' : status;
  }

  Color _avatarBg(int index) {
    const colors = [
      Color(0xFFE8EAF5),
      Color(0xFFF0E6F8),
      Color(0xFFE6F2F5),
      Color(0xFFF5ECE6),
      Color(0xFFE6F0F0),
      Color(0xFFF0F0E6),
    ];
    return colors[index % colors.length];
  }

  /// Single-letter avatar initial (matches the patient-side card and the
  /// reference design's one-letter avatars).
  String _avatarInitial(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'P';
  }

  Future<bool?> _handleCancel(AppointmentModel a) =>
      showCancelAppointmentDialog(_controller, a);

  Future<bool?> _handleComplete(AppointmentModel a) =>
      showCompleteAppointmentDialog(_controller, a);


  void _handleConfirm(AppointmentModel a) {
    showConfirmAppointmentDialog(_controller, a);
  }

  /// "Mark Paid" confirm — only offered for OFFLINE payments still
  /// Pending (the clinic has actually received the cash). Online payments
  /// are settled at booking time and need no clinic action.
  void _handleMarkPaid(AppointmentModel a, PaymentModel p) {
    _confirmPaymentAction(a, p, status: 'Paid');
  }

  /// "Refund" — opens the refund method picker (Online UPI / Cash), then
  /// records the refunded payment in Supabase with the chosen details.
  Future<void> _handleRefund(AppointmentModel a, PaymentModel p) async {
    // A refund was ALREADY sent for this payment earlier in this session
    // (the UPI app confirmed it) but the payment record could not be
    // updated. Tapping Refund again must NEVER fire a second UPI refund —
    // retry recording the sent refund instead.
    final pending = _unrecordedOnlineRefunds[p.id];
    if (pending != null) {
      await _retryUnrecordedOnlineRefund(a, p, pending);
      return;
    }
    final method = await _showRefundMethodSheet(a, p);
    if (method == null || !mounted) return;
    if (method == 'cash') {
      _confirmPaymentAction(
        a,
        p,
        status: 'Refunded',
        refundMethod: 'cash',
        refundedAt: DateTime.now(),
      );
    } else {
      await _runOnlineRefund(a, p);
    }
  }

  void _confirmPaymentAction(
    AppointmentModel a,
    PaymentModel p, {
    required String status,
    String? refundMethod,
    DateTime? refundedAt,
    String? refundUpiId,
    String? refundTransactionId,
    String? refundRawResponse,
  }) {
    final isPaid = status == 'Paid';
    // Tracks the in-flight server update so the confirm button shows a
    // spinner and can't be double-tapped while the status flip runs.
    var busy = false;
    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(isPaid ? 'Mark Payment Paid' : 'Refund Payment'),
            content: Text(
              isPaid
                  ? 'Confirm ${p.amountLabel} received from '
                        '${a.patientName ?? 'patient'} for this appointment?'
                  : 'Mark ${p.amountLabel} as refunded to '
                        '${a.patientName ?? 'patient'}?',
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Get.back(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textCaption),
                ),
              ),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        // Show the in-button loading spinner and lock the
                        // dialog until the server answers.
                        setState(() => busy = true);
                        // Only claim success when the status flip actually
                        // landed server-side — a silent RLS denial or
                        // offline write must never show a false
                        // "Payment marked as Paid".
                        final ok = await _controller.markPaymentStatus(
                          p,
                          status,
                          refundMethod: refundMethod,
                          refundedAt: refundedAt,
                          refundUpiId: refundUpiId,
                          refundTransactionId: refundTransactionId,
                          refundRawResponse: refundRawResponse,
                        );
                        if (!context.mounted) return;
                        Get.back();
                        if (ok) {
                          showSuccessSnackbar(
                            isPaid
                                ? 'Payment marked as Paid'
                                : 'Payment marked as Refunded',
                          );
                        } else {
                          showErrorSnackbar(
                            'Could not update the payment. Please try again.',
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPaid ? AppColors.success : AppColors.info,
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isPaid ? 'Mark Paid' : 'Refund'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Bottom sheet: how should the refund be given back — Online (the
  /// clinic's UPI app pays the patient's VPA) or Cash (at the clinic).
  /// Returns 'online' / 'cash', or null when dismissed.
  Future<String?> _showRefundMethodSheet(AppointmentModel a, PaymentModel p) {
    return Get.bottomSheet<String>(
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
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.info.withAlpha(15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.currency_rupee_rounded,
                      size: 22,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Refund ${p.amountLabel}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textHeading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'How should the refund reach '
                          '${a.patientName ?? 'the patient'}?',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _RefundMethodTile(
                icon: Icons.qr_code_2_rounded,
                title: 'Online (UPI)',
                subtitle: 'Send ${p.amountLabel} from your UPI app to the '
                    'patient — enter the VPA from their UPI QR code',
                color: AppColors.primary,
                onTap: () => Get.back(result: 'online'),
              ),
              const SizedBox(height: 10),
              _RefundMethodTile(
                icon: Icons.payments_rounded,
                title: 'Cash',
                subtitle: 'Hand over ${p.amountLabel} at the clinic',
                color: AppColors.success,
                onTap: () => Get.back(result: 'cash'),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  /// Online refund: the clinic's UPI app pays the PATIENT's own VPA. The
  /// payment is marked Refunded ONLY when the UPI app CONFIRMS the refund
  /// ('success') — an unconfirmed payment never flips the status (same
  /// rule as the booking flow), so a failed/cancelled refund is retried
  /// instead of being recorded.
  Future<void> _runOnlineRefund(AppointmentModel a, PaymentModel p) async {
    final vpa = await _askPatientUpiVpa(a, p);
    if (vpa == null || !mounted) return;

    // Sends exactly like the booking flow: the Quantupi package fires the
    // `upi://pay` intent and Android's system chooser lists every
    // installed UPI app (GPay/PhonePe/Paytm/…) to send from.
    final result = await QuantupiPaymentService.instance.pay(
      receiverUpiId: vpa,
      receiverName: a.patientName ?? 'Patient',
      amount: p.amount,
      transactionRef: 'RFD${DateTime.now().millisecondsSinceEpoch}',
      note: 'Refund — ${a.appointmentId}',
    );
    if (!mounted) return;

    if (result.isSuccess) {
      // The money LEFT the clinic — the record must land, or a later
      // Refund tap would send a second refund. Retry the write (it is
      // idempotent: same refund txn) and, if it still fails, remember the
      // sent refund so a re-tap retries the RECORD, never the payment.
      final recorded = await _recordOnlineRefund(
        p,
        vpa: vpa,
        transactionId: result.transactionId,
        rawResponse: result.rawResponse,
      );
      if (recorded) {
        _unrecordedOnlineRefunds.remove(p.id);
        showSuccessSnackbar(
          'Refund of ${p.amountLabel} sent — payment marked as Refunded',
        );
      } else {
        // Payments shown on the cards always carry a server id.
        _unrecordedOnlineRefunds[p.id!] = _PendingOnlineRefund(
          vpa: vpa,
          transactionId: result.transactionId,
          rawResponse: result.rawResponse,
        );
        showErrorSnackbar(
          'Refund of ${p.amountLabel} was sent to '
          '${a.patientName ?? 'the patient'}, but the payment record could '
          'not be updated. The refund is NOT recorded yet — do NOT send it '
          'again. Tap Refund again to retry recording it.',
        );
      }
    } else {
      // The UPI app did NOT return a confirmed success. This is a known
      // limitation of intent-based UPI: many apps (Paytm, PhonePe, GPay)
      // return Status=FAILURE or no usable response even when the money
      // ACTUALLY moved (the on-device smoke test saw Paytm return FAILURE
      // instantly for a ₹1 test). Never record a refund on an unconfirmed
      // response — but DO let the doctor verify in their UPI app and
      // record the refund if it genuinely went through, so a real refund
      // is not stranded as Paid forever.
      final confirmed = await _askRefundConfirmation(a, p, vpa);
      if (!mounted || confirmed == null) return;
      if (!confirmed) {
        // The doctor verified the refund did NOT go through — nothing was
        // sent/recorded, the payment stays Paid. For a 'submitted'
        // (unconfirmed) payment the money MAY have gone out, so the
        // message never tells them to just re-send.
        showErrorSnackbar(
          result.isSubmitted
              ? 'Refund not confirmed by the UPI app — the payment was '
                    'NOT marked as refunded. Check with the patient whether '
                    'the refund arrived BEFORE sending it again.'
              : 'Refund failed or was cancelled — nothing was sent and the '
                    'payment was NOT marked as refunded. You can try again.',
        );
        return;
      }
      // The doctor verified the refund went through in their UPI app —
      // record it (same retry logic as the confirmed path).
      final recorded = await _recordOnlineRefund(
        p,
        vpa: vpa,
        transactionId: result.transactionId,
        rawResponse: result.rawResponse,
      );
      if (recorded) {
        _unrecordedOnlineRefunds.remove(p.id);
        showSuccessSnackbar(
          'Refund of ${p.amountLabel} recorded — payment marked as Refunded',
        );
      } else {
        // Payments shown on the cards always carry a server id.
        _unrecordedOnlineRefunds[p.id!] = _PendingOnlineRefund(
          vpa: vpa,
          transactionId: result.transactionId,
          rawResponse: result.rawResponse,
        );
        showErrorSnackbar(
          'Refund of ${p.amountLabel} was sent to '
          '${a.patientName ?? 'the patient'}, but the payment record could '
          'not be updated. The refund is NOT recorded yet — do NOT send it '
          'again. Tap Refund again to retry recording it.',
        );
      }
    }
  }

  /// After a non-success UPI response, asks the doctor to verify in their
  /// own UPI app whether the refund actually went through. Intent-based
  /// UPI often returns Status=FAILURE or no usable response even when the
  /// money moved, so the doctor's check is the source of truth. Returns
  /// `true` when the doctor confirms the refund went through, `false`
  /// when it did not, `null` when dismissed.
  Future<bool?> _askRefundConfirmation(
    AppointmentModel a,
    PaymentModel p,
    String vpa,
  ) {
    return Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Refund not confirmed'),
        content: SingleChildScrollView(
          child: Text(
            'The UPI app did not return a success response for the refund '
            'to $vpa. Open your UPI app and check whether '
            '${p.amountLabel} was actually sent to '
            '${a.patientName ?? 'the patient'}.\n\n'
            'If it went through, tap "Yes, mark as Refunded" so the '
            'payment is recorded as refunded.',
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.textBody,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text(
              'It did not go through',
              style: TextStyle(color: AppColors.textCaption),
            ),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Yes, mark as Refunded'),
          ),
        ],
      ),
    );
  }

  /// Records an online refund that the UPI app CONFIRMED, retrying the
  /// write a couple of times: a transient network/RLS failure right after
  /// the money left must not strand the payment as Paid. The UPDATE is
  /// idempotent (same refund transaction id), so retrying is safe.
  /// Returns `true` only when the record landed server-side.
  Future<bool> _recordOnlineRefund(
    PaymentModel p, {
    required String vpa,
    String? transactionId,
    String? rawResponse,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final ok = await _controller.markPaymentStatus(
        p,
        'Refunded',
        refundMethod: 'online',
        refundedAt: DateTime.now(),
        refundUpiId: vpa,
        refundTransactionId: transactionId,
        refundRawResponse: rawResponse,
      );
      if (ok) return true;
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    return false;
  }

  /// Re-entry point when a confirmed online refund could not be recorded:
  /// retries ONLY the record write — a second UPI refund is never fired.
  Future<void> _retryUnrecordedOnlineRefund(
    AppointmentModel a,
    PaymentModel p,
    _PendingOnlineRefund pending,
  ) async {
    final recorded = await _recordOnlineRefund(
      p,
      vpa: pending.vpa,
      transactionId: pending.transactionId,
      rawResponse: pending.rawResponse,
    );
    if (!mounted) return;
    if (recorded) {
      _unrecordedOnlineRefunds.remove(p.id);
      showSuccessSnackbar(
        'Refund of ${p.amountLabel} recorded — payment marked as Refunded',
      );
    } else {
      showErrorSnackbar(
        'The payment record still could not be updated — the refund is NOT '
        'recorded and was NOT sent again. Note the refund transaction '
        '${pending.transactionId ?? '—'} and contact support.',
      );
    }
  }

  /// Asks for the patient's UPI ID (VPA) — the value their UPI QR code
  /// encodes, or shown in their UPI app — so the clinic can send the
  /// online refund to it. Returns the trimmed VPA, or null when dismissed.
  Future<String?> _askPatientUpiVpa(AppointmentModel a, PaymentModel p) {
    final vpaController = TextEditingController();
    return Get.dialog<String>(
      StatefulBuilder(
        builder: (context, setState) {
          final vpa = vpaController.text.trim();
          final valid = vpa.isNotEmpty && vpa.contains('@');
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Refund via UPI'),
            // Scrolls on small screens / large text instead of overflowing
            // the fixed dialog height (the long instructions wrap to many
            // lines at narrow widths).
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask the patient for their UPI ID (VPA) — shown in '
                    'their UPI app, or scan their UPI QR code and enter '
                    'the VPA it encodes. ${p.amountLabel} will be sent '
                    'from your UPI app to ${a.patientName ?? 'the patient'}.',
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: AppColors.textBody,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: vpaController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Patient UPI ID (e.g. name@upi)',
                      prefixIcon: const Icon(Icons.qr_code_2_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Scan the patient's UPI QR code and fill the field
                  // with the VPA it encodes — no typing needed.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final raw = await Get.to<String>(
                          () => const UpiQrScannerScreen(),
                        );
                        if (raw == null || !mounted) return;
                        final vpa = extractVpaFromQr(raw);
                        if (vpa == null || !isValidVpa(vpa)) {
                          showErrorSnackbar(
                            'No UPI ID found in that QR code — ask the '
                            'patient for their UPI ID and type it.',
                          );
                          return;
                        }
                        vpaController.text = vpa;
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withAlpha(90),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 20,
                      ),
                      label: const Text("Scan Patient's UPI QR Code"),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textCaption),
                ),
              ),
              ElevatedButton(
                onPressed: valid ? () => Get.back(result: vpa) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Send Refund'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (!_isSearching)
              AppointmentDateFilter(
                    appointments: _controller.appointments,
                    selectedDate: _selectedDate,
                    onDateSelected: (dateKey) {
                      setState(() => _selectedDate = dateKey);
                    },
                  )
                  // Same entrance animation family as the header, with a slight
                  // stagger so the filter glides in right after it.
                  .animate()
                  .fadeIn(duration: 350.ms, delay: 120.ms)
                  .slideY(begin: -0.08, end: 0, duration: 350.ms),
            // ── Online / Offline filter chips ──
            if (!_isSearching) _buildConsultationFilter(),

            Expanded(child: _buildAppointmentsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
            const Color(0xFF095E4C),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(60),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Obx(() {
        final doctor = _controller.currentDoctor.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(30),
                    border: Border.all(
                      color: Colors.white.withAlpha(60),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      doctor != null && doctor.name.isNotEmpty
                          ? doctor.name[0]
                          : 'D',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Appointments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Manage your patient appointments',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                AppointmentSearchToggle(
                  toggleKey: const ValueKey('appointments_search_toggle'),
                  isSearching: _isSearching,
                  onToggle: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchController.clear();
                        _searchQuery = '';
                      }
                    });
                  },
                ),
              ],
            ),
            if (_isSearching) ...[
              const SizedBox(height: 14),
              AppointmentSearchField(
                controller: _searchController,
                hintText: 'Search by patient, phone, status, date…',
                onQueryChanged: (value) {
                  setState(() => _searchQuery = value.trim());
                },
              ),
            ],
          ],
        );
      }),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  List<AppointmentModel> _visibleAppointments() {
    List<AppointmentModel> pool;
    if (!_isSearching) {
      pool = _controller.getAppointmentsForDate(_selectedDate);
    } else {
      pool = filterAppointmentsForSearch(
        _controller.appointments,
        _searchQuery,
      );
    }
    return _applyConsultationFilter(pool);
  }

  /// Filter [list] by the selected Online / Offline / All chip.
  List<AppointmentModel> _applyConsultationFilter(List<AppointmentModel> list) {
    if (_consultationFilter == 0) return list; // All
    final wantOnline = _consultationFilter == 1;
    return list.where((a) {
      final isOnline =
          a.consultationType == 'tele' || a.consultationType == 'video';
      return wantOnline ? isOnline : !isOnline;
    }).toList();
  }

  /// Select a consultation filter and persist the choice.
  VoidCallback _selectFilter(int index) {
    return () {
      setState(() => _consultationFilter = index);
      LocalStorageService().setAppointmentFilter(index);
    };
  }

  /// Compact row of three filter chips: All · Online · Offline.
  /// Each chip shows a count badge of matching appointments for the
  /// currently selected date.
  Widget _buildConsultationFilter() {
    final dayAppts = _controller.getAppointmentsForDate(_selectedDate);
    final allCount = dayAppts.length;
    final onlineCount = dayAppts.where((a) => a.isRemoteConsultation).length;
    final offlineCount = allCount - onlineCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          _DocFilterChip(
            label: 'All',
            count: allCount,
            selected: _consultationFilter == 0,
            onTap: _selectFilter(0),
          ),
          const SizedBox(width: 8),
          _DocFilterChip(
            label: 'Online',
            icon: Icons.videocam_rounded,
            count: onlineCount,
            selected: _consultationFilter == 1,
            onTap: _selectFilter(1),
          ),
          const SizedBox(width: 8),
          _DocFilterChip(
            label: 'Offline',
            icon: Icons.storefront_rounded,
            count: offlineCount,
            selected: _consultationFilter == 2,
            onTap: _selectFilter(2),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 180.ms);
  }

  void _showAppointmentDetails(AppointmentModel a) {
    // The controller holds the doctor's FULL appointment list (no date
    // filter), so the "has this mobile number visited before?" check is
    // instant — no extra query. Patients with prior visits open the
    // timeline history page; first-time patients keep the quick sheet.
    final phone = a.patientPhone?.trim() ?? '';
    final history = phone.isEmpty
        ? <AppointmentModel>[]
        : _controller.appointments
              .where((x) => (x.patientPhone?.trim() ?? '') == phone)
              .toList();
    if (history.length > 1) {
      Get.toNamed(
        AppRoutes.patientHistory,
        arguments: {'appointments': history, 'highlightId': a.appointmentId},
      );
      return;
    }
    final payment = _controller.paymentsByAppointment[a.appointmentId];
    // "Mark Completed" is gated on the consultation fee being settled —
    // while the payment is still Pending (unpaid), the action renders
    // disabled until the clinic marks it Paid (or Refunded), exactly like
    // the card button.
    final paymentPending =
        payment != null && payment.paymentStatus == 'Pending';
    AppointmentDetailsSheet.show(
      appointment: a,
      displayStatus: _statusLabel(a.status),
      headerName: a.patientName ?? 'Patient',
      closeKey: const ValueKey('appointment_details_close'),
      phoneNumber: a.patientPhone ?? '',
      // Fee/payment recorded for this appointment (same map the cards use),
      // so the sheet shows what the consultation costs and how it stands.
      payment: payment,
      // Doctor actions right inside the sheet (same compact pills as the
      // cards): mark the consultation complete or cancel it — handy right
      // after the video meeting closes and the app returns.
      showDoctorActions: true,
      onCancel: () => _handleCancel(a),
      onComplete: paymentPending ? null : () => _handleComplete(a),
      // Persist a newly created Meet link so the patient joins the same
      // room on their side.
      onSaveMeetLink: (link) =>
          _controller.saveMeetLink(a.appointmentId, link),
    );
  }

  Widget _buildAppointmentsList() {
    return Obx(() {
      if (_controller.isLoadingAppointments.value) {
        return _buildShimmer();
      }

      final dayAppts = _visibleAppointments();

      // Key changes on filter/date/search switch → triggers
      // AnimatedSwitcher crossfade.
      final filterKey = ValueKey(
        '${_consultationFilter}_${_selectedDate}_${_isSearching}_$_searchQuery',
      );

      if (dayAppts.isEmpty) {
        final isSearchEmpty = _isSearching && _searchQuery.isNotEmpty;
        final empty = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withAlpha(20),
                ),
                child: Icon(
                  isSearchEmpty
                      ? Icons.search_off_rounded
                      : Icons.event_busy_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isSearchEmpty ? 'No results found' : 'No appointments',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHeading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isSearchEmpty
                    ? 'No appointments match “$_searchQuery”'
                    : 'No appointments for $_selectedDate',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textCaption,
                ),
              ),
            ],
          ),
        )
            // The "No appointments" / "No results" notice enters with the
            // same fade + slide family as the rest of the screen.
            .animate()
            .fadeIn(duration: 300.ms, curve: Curves.easeOut)
            .slideY(begin: 0.08, end: 0, duration: 300.ms, curve: Curves.easeOut);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(key: filterKey, child: empty),
        );
      }

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(
          key: filterKey,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: dayAppts.length,
        itemBuilder: (context, index) {
          final a = dayAppts[index];
          final status = _statusLabel(a.status);
          final isFinalized = status == 'Cancelled' || status == 'Completed';
          final isPending = status == AppointmentStatus.pending;

          // Per-card Obx for the payment line: ListView's itemBuilder runs
          // lazily, AFTER the outer Obx builder — outside GetX's reactive
          // tracking — so a payment lookup there alone never subscribes
          // anything and a Mark Paid / Refund reload
          // (loadPayments → paymentsByAppointment.value = …) leaves the
          // card stale. Reading the map synchronously inside its own Obx
          // makes each visible card rebuild in place when the payment
          // status flips (Pending → Paid / Refunded: chip updates, settle
          // actions disappear).
          return Obx(() {
            final payment =
                _controller.paymentsByAppointment[a.appointmentId];
            final paymentActionable =
                payment != null &&
                payment.paymentMethod == 'offline' &&
                payment.paymentStatus == 'Pending';
            // A payment is refundable when money actually changed hands
            // (Paid — online or offline) OR when an offline fee is still
            // outstanding (Pending, the legacy "not collected" refund).
            final refundable =
                payment != null &&
                (payment.paymentStatus == 'Paid' ||
                    (payment.paymentMethod == 'offline' &&
                        payment.paymentStatus == 'Pending'));
            // "Mark Completed" is gated on the consultation fee being
            // settled: while the payment is still Pending (unpaid), the
            // button renders disabled until the clinic marks it Paid (or
            // Refunded) — the doctor must not complete a booking that
            // hasn't been paid for.
            final paymentPending =
                payment != null && payment.paymentStatus == 'Pending';

            return _ModernAppointmentCard(
              appointment: a,
              displayStatus: status,
              isFinalized: isFinalized,
              statusColor: AppointmentDetailsSheet.statusColor(status),
              statusIcon: AppointmentDetailsSheet.statusIcon(status),
              avatarInitials: _avatarInitial(a.patientName ?? 'Patient'),
              avatarColor: _avatarBg(index),
              index: index,
              payment: payment,
              onMarkPaid: payment != null && paymentActionable
                  ? () => _handleMarkPaid(a, payment)
                  : null,
              onRefund: payment != null && refundable
                  ? () => _handleRefund(a, payment)
                  : null,
              hasPendingRefund: payment != null &&
                  _unrecordedOnlineRefunds.containsKey(payment.id),
              onTap: () => _showAppointmentDetails(a),
              onCancel: () => _handleCancel(a),
              onConfirm: isPending ? () => _handleConfirm(a) : null,
              onComplete: paymentPending
                  ? null
                  : () => _handleComplete(a),
            );
          });
        },
      ),
      ),
      );
    });
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: 3,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8E4DA),
        highlightColor: const Color(0xFFF4EFE4),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Modern appointment card with name, date, time, and description
// ════════════════════════════════════════════════════════════════════
class _ModernAppointmentCard extends StatelessWidget {
  final AppointmentModel appointment;
  final String displayStatus;
  final bool isFinalized;
  final Color statusColor;
  final IconData statusIcon;
  final String avatarInitials;
  final Color avatarColor;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  /// Null while the consultation fee is still Pending (unpaid) — the
  /// button then renders disabled instead of opening the complete flow.
  final VoidCallback? onComplete;

  /// The payment recorded against this appointment (if any). Rows render
  /// Mark Paid (offline Pending) and/or Refund (Paid — any method — or
  /// offline Pending) actions; every other status renders as an
  /// informational chip.
  final PaymentModel? payment;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onRefund;

  /// When true the Refund button label changes to "Retry Recording"
  /// and a yellow warning banner appears — tells the doctor the UPI
  /// money was already sent but the payment record still needs to be
  /// updated in Supabase.
  final bool hasPendingRefund;

  const _ModernAppointmentCard({
    required this.appointment,
    required this.displayStatus,
    required this.isFinalized,
    required this.statusColor,
    required this.statusIcon,
    required this.avatarInitials,
    required this.avatarColor,
    required this.index,
    required this.onTap,
    required this.onCancel,
    this.onConfirm,
    this.onComplete,
    this.payment,
    this.onMarkPaid,
    this.onRefund,
    this.hasPendingRefund = false,
  });

  @override
  Widget build(BuildContext context) {
    final a = appointment;

    return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: AppointmentInfoCard(
            appointment: a,
            onTap: onTap,
            accentColor: statusColor,
            borderRadius: 20,
            // Left pad 14 (not 16) so the 5px accent bar + content spacing
            // stays pixel-identical to the pre-extraction card.
            padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
            shadowBlur: 16,
            shadowAlpha: 8,
            header: AppointmentCardHeader(
              name: a.patientName ?? 'Patient',
              statusLabel: displayStatus,
              statusIcon: statusIcon,
              statusColor: statusColor,
              avatarInitials: avatarInitials,
              avatarColor: avatarColor,
            ),
            // Full-width info row below the grid: the consultation type
            // (what the patient booked — hidden for legacy rows) sits in
            // the phone's former spot. The patient's phone now lives only
            // in the details sheet (Call Now / dial row).
            infoBlocks: [?AppointmentInfoBlock.consultationOf(a)],
            displayStatus: displayStatus,
            statusColor: statusColor,
            statusIcon: statusIcon,
            // Payment line (amount + status chip, Mark Paid/Refund actions
            // for offline Pending rows) — renders between the info grid
            // and the appointment action buttons.
            extraRow: payment != null ? _buildPaymentRow(payment!) : null,
            // Shared appointment-list look: label + first thumbnail + a
            // light-green "Click" pill opening the fullscreen viewer.
            prescriptionClickRow: true,
            // Wrap (not Row) so the action buttons flow to a second line on
            // narrow screens / large text scales instead of overflowing the
            // card edge.
            actions: isFinalized
                ? null
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _ModernActionBtn(
                        label: 'Cancel',
                        icon: Icons.close_rounded,
                        color: AppColors.error,
                        onTap: onCancel,
                      ),
                      if (displayStatus == AppointmentStatus.pending &&
                          onConfirm != null)
                        _ModernActionBtn(
                          label: 'Confirm',
                          icon: Icons.check_circle_rounded,
                          color: AppColors.primary,
                          onTap: onConfirm!,
                          isPrimary: true,
                        )
                      else
                        _ModernActionBtn(
                          label: 'Mark Completed',
                          icon: Icons.check_circle_rounded,
                          color: AppColors.success,
                          onTap: onComplete,
                          isPrimary: true,
                          enabled: onComplete != null,
                        ),
                    ],
                  ),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms, delay: (index * 80).ms)
        .slideY(begin: 0.05, end: 0);
  }

  /// Payment line between the info grid and the action buttons: amount +
  /// status chip, plus Mark Paid (offline Pending) and/or Refund (Paid or
  /// offline Pending) actions when the row can be settled.
  Widget _buildPaymentRow(PaymentModel p) {
    final color = p.paymentStatus == 'Paid'
        ? AppColors.success
        : p.paymentStatus == 'Refunded'
        ? AppColors.info
        : p.paymentStatus == 'Failed'
        ? AppColors.error
        : AppColors.warning;
    final hasActions = onMarkPaid != null || onRefund != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 15,
                color: AppColors.textHeading,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Payment \u00b7 ${p.amountLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHeading,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withAlpha(60), width: 0.8),
                ),
                child: Text(
                  p.paymentStatus,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          // Yellow warning banner when a refund was already sent via
          // UPI but the payment record couldn't be updated — tapping
          // Refund again retries the RECORD only (no second UPI send).
          if (hasPendingRefund) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Refund already sent via UPI — tap Retry below to '
                      'record it. Do NOT send again.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasActions) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (onMarkPaid != null)
                  _ModernActionBtn(
                    label: 'Mark Paid',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                    onTap: onMarkPaid!,
                    isPrimary: true,
                  ),
                if (onRefund != null)
                  _ModernActionBtn(
                    label: hasPendingRefund
                        ? 'Retry Recording'
                        : 'Refund',
                    icon: hasPendingRefund
                        ? Icons.replay_rounded
                        : Icons.currency_rupee_rounded,
                    color: hasPendingRefund
                        ? AppColors.warning
                        : AppColors.info,
                    onTap: onRefund!,
                  ),
              ],
            ),
          ],
          // Refund details shown on the doctor card when the payment was
          // refunded — the Refund button is already hidden (onRefund is
          // null for 'Refunded'), so this row replaces the action buttons
          // with the refund summary (method + date + amount).
          if (p.paymentStatus == 'Refunded') ...[
            const SizedBox(height: 10),
            _RefundDetailRow(payment: p),
          ],
        ],
      ),
    );
  }
}


/// An online refund the UPI app CONFIRMED but whose payment record has not
/// been updated yet — the details needed to re-record it without sending
/// money again.
class _PendingOnlineRefund {
  final String vpa;
  final String? transactionId;
  final String? rawResponse;

  const _PendingOnlineRefund({
    required this.vpa,
    this.transactionId,
    this.rawResponse,
  });
}

/// One option row in the refund method sheet — icon + title + subtitle,
/// tappable, tinted in [color].
class _RefundMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RefundMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHeading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: AppColors.textCaption,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }
}


class _ModernActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool isPrimary;

  /// When false the pill renders greyed-out and inert — used for the
  /// "Mark Completed" action while a fee payment is still Pending.
  final bool enabled;

  const _ModernActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // Disabled: flat grey pill, muted text, no tap handler.
    final Color bg = enabled
        ? (isPrimary ? color : color.withAlpha(15))
        : AppColors.textCaption.withAlpha(14);
    final Color fg = enabled
        ? (isPrimary ? Colors.white : color)
        : AppColors.textCaption.withAlpha(140);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // A no-op handler while disabled: with a null onTap the InkWell
        // adds no gesture recognizer, so the tap falls through to the
        // card's own InkWell beneath and opens the details sheet instead
        // of doing nothing. This recognizer is the deepest, so it wins
        // the gesture arena and swallows the tap.
        onTap: enabled ? onTap : () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              // Flexible + ellipsis: at large system text scales a Wrap
              // can hand this row a constraint tighter than the label's
              // intrinsic width — the label then shrinks instead of
              // overflowing by a sub-pixel.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Refund summary shown inside the doctor card's payment row when the
/// payment was refunded. Shows refund method, date so the doctor
/// doesn't need to open the details sheet to confirm the refund
/// was recorded.
class _RefundDetailRow extends StatelessWidget {
  final PaymentModel payment;

  const _RefundDetailRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    final method = payment.refundMethodLabel ?? '—';
    final refundedOn = payment.refundedAt;
    final dateStr = refundedOn != null
        ? '${refundedOn.day.toString().padLeft(2, '0')}-'
              '${refundedOn.month.toString().padLeft(2, '0')}-${refundedOn.year}'
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.currency_rupee_rounded,
            size: 14,
            color: AppColors.info,
          ),
          const SizedBox(width: 6),
          Text(
            'Refunded $method',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.info,
            ),
          ),
          if (dateStr != null) ...[
            const SizedBox(width: 8),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.info.withAlpha(200),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small rounded filter chip used by the consultation-type tabs.
class _DocFilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _DocFilterChip({
    required this.label,
    this.icon,
    this.count = 0,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withAlpha(20)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary.withAlpha(80)
                : AppColors.textCaption.withAlpha(40),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon!,
                size: 13,
                color: selected
                    ? AppColors.primary
                    : AppColors.textCaption.withAlpha(160),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.primary
                    : AppColors.textCaption.withAlpha(180),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withAlpha(30)
                    : AppColors.textCaption.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textCaption.withAlpha(160),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
