import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/appointment_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/doctor_model.dart';
import '../../models/payment_model.dart';
import '../../models/unavailable_range.dart';
import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../services/upi_payment_service.dart';
import '../../widgets/booking_block_banner.dart';
import '../../widgets/doctor_avatar.dart';
import '../../widgets/upi_app_picker_sheet.dart';
import '../../utils/extensions.dart';
import '../../utils/snackbar_helpers.dart';

/// How the online-pay (UPI) leg of booking ended.
enum _OnlinePayOutcome {
  /// Payment confirmed — book with the 'Paid' record.
  paid,

  /// Payment failed / not confirmed and the patient chose offline pay.
  payOffline,

  /// Nothing should book (dismissed / cancelled / no UPI app).
  cancelled,
}

/// Book Appointment screen that shows available time slots from the
/// doctor's [doctor_slots] table instead of free-text date/time input.
///
/// On load it fetches the doctor's weekly slots via [SupabaseService],
/// displays a 14-day date selector, and shows the matching time slots
/// as selectable chips grouped by consultation type.
class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _controller = Get.find<AppointmentController>();
  late DoctorModel doctor;

  final _patientNameController = TextEditingController();
  final _symptomsController = TextEditingController();

  /// Index into [dateOptions] — the selected date.
  int _selectedDateIndex = -1;

  /// The time slot string the user tapped (e.g. "09:00 AM").
  String _selectedTimeSlot = '';

  /// Whether slots are still loading.
  bool _slotsLoading = true;

  /// Why the per-doctor gate blocks this booking right now (an active
  /// Pending/Upcoming booking with THIS doctor), or null when booking is
  /// allowed. Populated when the screen loads the patient's appointments
  /// and re-checked right before the Book action.
  String? _bookingBlockMessage;

  /// ISO date keys (yyyy-MM-dd) inside the 14-day window that the doctor
  /// marked unavailable (doctors.unavailable_ranges) — booking is disabled
  /// on these dates.
  final Set<String> _unavailableIsoDates = {};

  /// The next 14 days as displayable items.
  late final List<_DateOption> dateOptions;

  /// The booked doctor's own UPI VPA (trimmed), or null when the doctor
  /// hasn't set one. Online Pay (UPI) is ONLY offered when this is set —
  /// a payment without a real receiving VPA can never complete, so the
  /// patient pays at the clinic instead.
  String? get _doctorUpiVpa {
    final upi = doctor.upiId?.trim() ?? '';
    return upi.isEmpty ? null : upi;
  }

  /// Quick-check whether all required fields are filled.
  bool get _canBook =>
      _patientNameController.text.isNotEmpty &&
      _selectedDateIndex >= 0 &&
      _selectedTimeSlot.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map;
    doctor = args['doctor'] as DoctorModel;

    // Pre-fill patient name
    final authController = Get.find<AuthController>();
    _patientNameController.text = authController.currentUser.value?.name ?? '';

    // Build the 14-day date list starting today
    dateOptions = List.generate(14, (i) {
      final d = DateTime.now().add(Duration(days: i));
      const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const fullDayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      const monthNames = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return _DateOption(
        date: d,
        dayLabel: dayLabels[d.weekday - 1],
        dateLabel: '${d.day}',
        monthLabel: monthNames[d.month],
        isoDate:
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        dayOfWeek: fullDayNames[d.weekday - 1],
      );
    });

    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() => _slotsLoading = true);
    // Unavailable dates come from the fresh DB fetch when it succeeds (the
    // doctor may have added/removed ranges since the detail screen loaded),
    // falling back to the passed doctor model only when the fetch fails or
    // returns nothing. The server-side DB trigger remains the final
    // authority either way.
    DoctorModel? dbDoctor;
    _unavailableIsoDates.clear();
    try {
      dbDoctor = await SupabaseService().getDoctorFromDb(doctor.placeId);
      final ranges = dbDoctor?.unavailableRanges ?? doctor.unavailableRanges;
      _unavailableIsoDates.addAll(
        UnavailableRange.matchingIsoDates(
          dateOptions.map((o) => o.isoDate),
          ranges,
        ),
      );
    } catch (_) {
      // Non-fatal — fall back to the ranges carried by the passed doctor
      // model so the rule still applies even if the fetch fails.
      _unavailableIsoDates.addAll(
        UnavailableRange.matchingIsoDates(
          dateOptions.map((o) => o.isoDate),
          doctor.unavailableRanges,
        ),
      );
    }
    await Future.wait([
      _controller.loadDoctorSlots(doctor.placeId),
      _controller.loadBookedSlots(doctor.placeId),
      // Refresh the patient's own appointments so the per-doctor gate
      // (active booking with this doctor) reflects the latest state.
      _controller.loadAppointments(),
    ]);
    if (!mounted) return;
    setState(() {
      // Refresh doctor-set fields from the DB row. The model that reaches
      // this screen usually comes from Google Places search (or the detail
      // screen's Places enrichment), which never carries upiId — without
      // this merge the "Consultation Payment" modal would not show the
      // clinic's receiving VPA even though it is saved on the doctors row.
      if (dbDoctor != null) {
        doctor = DoctorController.mergeDoctorSetFields(
          doctor,
          dbDoctor,
          null, // leave userId untouched
        );
      }
      _slotsLoading = false;
      _bookingBlockMessage = AppointmentController.bookingBlockMessage(
        _controller.appointments,
        doctorPlaceId: doctor.placeId,
      );
      // Pre-select today's next available (future) slot so the patient
      // can book in one tap instead of picking a date + time first.
      _autoSelectNextSlot();
    });
  }

  /// Auto-select and pre-highlight today's next available (future,
  /// not-yet-booked) time slot when the screen opens. Leaves the screen
  /// unselected when today has no bookable slot (doctor's off day, an
  /// unavailable date, or every slot already booked/passed) — the patient
  /// then picks another date, which clears the pre-selection as usual.
  void _autoSelectNextSlot() {
    if (dateOptions.isEmpty) return;

    // Index 0 is always today — the 14-day list starts at DateTime.now().
    final today = dateOptions.first;
    if (_isDateUnavailable(today)) return;
    final slots = _controller.getTimeSlotsForDay(today.dayOfWeek);
    for (final slot in slots) {
      if (_controller.isSlotBooked(today.isoDate, slot)) continue;
      if (_controller.isSlotInPast(today.isoDate, slot)) continue;
      _selectedDateIndex = 0;
      _selectedTimeSlot = slot;
      _controller.selectedDayOfWeek.value = today.dayOfWeek;
      return;
    }
  }

  /// True when [opt] falls inside one of the doctor's unavailable ranges.
  bool _isDateUnavailable(_DateOption opt) {
    return _unavailableIsoDates.contains(opt.isoDate);
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _bookAppointment() async {
    // Hide the keyboard so the user sees the result of the tap.
    FocusScope.of(context).unfocus();

    // Fresh attempt — drop any DB-gate rejection from a previous booking
    // attempt on this screen instance (the paid-but-rejected path skips
    // the failure handler that would have consumed it), so the field is
    // strictly "set by THIS attempt" when the failure branch reads it.
    _controller.serverBookingBlockMessage = null;

    // One active booking per doctor: a fresh appointments fetch + the
    // gate (an active Pending/Upcoming booking with THIS doctor) blocks
    // the booking with a clear message. Other doctors stay bookable.
    await _controller.loadAppointments();
    final blockMessage = AppointmentController.bookingBlockMessage(
      _controller.appointments,
      doctorPlaceId: doctor.placeId,
    );
    if (blockMessage != null) {
      showErrorSnackbar(blockMessage);
      setState(() => _bookingBlockMessage = blockMessage);
      return;
    }

    if (_patientNameController.text.isEmpty) {
      showErrorSnackbar('Please enter your name');
      return;
    }
    if (_selectedDateIndex < 0) {
      showErrorSnackbar('Please select a date');
      return;
    }
    if (_selectedTimeSlot.isEmpty) {
      showErrorSnackbar('Please select a time slot');
      return;
    }

    final selected = dateOptions[_selectedDateIndex];
    if (_isDateUnavailable(selected)) {
      showErrorSnackbar(
        'The doctor is unavailable on this date. Please pick another.',
      );
      return;
    }
    if (_controller.isSlotBooked(selected.isoDate, _selectedTimeSlot)) {
      showErrorSnackbar('This slot was just booked. Please pick another.');
      return;
    }
    if (_controller.isSlotInPast(selected.isoDate, _selectedTimeSlot)) {
      showErrorSnackbar('This slot has already passed. Please pick another.');
      return;
    }
    _controller.appointmentDate.value = selected.isoDate;
    _controller.appointmentTime.value = _selectedTimeSlot;
    _controller.patientName.value = _patientNameController.text;
    _controller.symptoms.value = _symptomsController.text;

    // ── Consultation payment ───────────────────────────────────────
    // Tele & Video consultations are paid for up-front: the patient picks
    // Online Pay (UPI intent) or Offline Pay (settle at the clinic), and
    // ONLY a CONFIRMED payment (UPI status 'success') books the
    // appointment — an unconfirmed ('submitted') payment never proceeds
    // (see _runUpiPayment). In-clinic visits book directly with an
    // offline "pay at clinic" record.
    final consultationType = _controller.getSlotTypeLabel(_selectedTimeSlot);
    final fee = _slotFee(consultationType);

    if (!_isPaidConsultationType(consultationType)) {
      // Clinic visit — no up-front payment; record an offline "pay at
      // clinic" row so the clinic has the payment history (skipped when
      // the slot has no fee).
      final success = await _controller.bookAppointment(
        doctor,
        payment: _offlinePayment(consultationType, fee),
      );
      await _handleBookingResult(selected, success);
      return;
    }

    // Tele / Video — ask how the patient wants to pay.
    final method = await _showPaymentMethodSheet(consultationType, fee);
    if (method == null) {
      // Dismissed — no booking.
      return;
    }

    final PaymentModel? payment;
    var onlinePaymentSucceeded = false;
    if (method == 'offline') {
      payment = _offlinePayment(consultationType, fee);
    } else {
      // Online — run the UPI intent; only a CONFIRMED payment (status
      // 'success') proceeds to booking. A declined/unconfirmed payment
      // shows a dialog offering Try Again / Pay Offline / Cancel — only
      // 'paid' reaches the booking call here.
      final (outcome, upiResult) = await _runUpiPayment(consultationType, fee);
      if (outcome == _OnlinePayOutcome.cancelled) return;
      if (outcome == _OnlinePayOutcome.payOffline) {
        // The patient switched to offline pay after the UPI attempt.
        final offlinePayment = _offlinePayment(consultationType, fee);
        final offlineSuccess = await _controller.bookAppointment(
          doctor,
          payment: offlinePayment,
        );
        await _handleBookingResult(selected, offlineSuccess);
        return;
      }
      onlinePaymentSucceeded = true;
      payment = PaymentModel(
        patientId: Get.find<AuthController>().currentUser.value?.id ?? '',
        doctorPlaceId: doctor.placeId,
        doctorName: doctor.name,
        consultationType: consultationType,
        paymentMethod: 'online',
        paymentStatus: 'Paid',
        amount: fee.toDouble(),
        transactionId: upiResult!.transactionId,
        upiId: _doctorUpiVpa,
      );
    }

    final success = await _controller.bookAppointment(doctor, payment: payment);
    if (!success && onlinePaymentSucceeded) {
      // The patient already paid but the slot was taken in the instant
      // since the pre-booking check — never show a bare "failed to book"
      // for money that went through.
      showErrorSnackbar(
        'Payment succeeded but the slot was just taken. Please contact '
        'the clinic for a refund.',
      );
      await _controller.loadBookedSlots(doctor.placeId);
      return;
    }
    await _handleBookingResult(selected, success);
  }

  /// Shared post-booking handling: success dialog + navigation, or the
  /// failure snackbar with a booked-slot refresh.
  Future<void> _handleBookingResult(_DateOption selected, bool success) async {
    if (success) {
      _controller.resetForm();
      _patientNameController.clear();
      _symptomsController.clear();
      // The success summary uses the app-wide dd-MM-yyyy display format.
      final displayDate =
          '${selected.date.day.toString().padLeft(2, '0')}-${selected.date.month.toString().padLeft(2, '0')}-${selected.date.year}';
      await _showBookingSuccessDialog(
        doctorName: doctor.name,
        date: displayDate,
        time: _selectedTimeSlot,
      );
      if (!mounted) return;
      Get.offAllNamed(AppRoutes.home);
      Future.delayed(const Duration(seconds: 1), () {
        if (Get.currentRoute == AppRoutes.home) {
          Get.toNamed(AppRoutes.appointmentHistory);
        }
      });
    } else {
      // The DB-level one-active-booking-per-doctor gate rejected the
      // insert (the patient booked on another device, or a previous
      // booking landed, in the window since the screen's pre-book check —
      // a UPI payment can take minutes) — surface the real gate message +
      // banner instead of the generic failure text. The message is
      // consumed once.
      final gateMsg = _controller.serverBookingBlockMessage;
      if (gateMsg != null) {
        showErrorSnackbar(gateMsg);
        setState(() => _bookingBlockMessage = gateMsg);
        _controller.serverBookingBlockMessage = null;
      } else {
        showErrorSnackbar('Failed to book appointment');
      }
      // The slot may have just been taken by someone else (the server-side
      // rule: a slot stays booked until the appointment is Cancelled) —
      // refresh the booked-slot set so it re-renders as disabled instead
      // of looking still available.
      await _controller.loadBookedSlots(doctor.placeId);
    }
  }

  /// Tele & Video consultations are paid up-front; in-clinic visits are
  /// settled at the clinic (offline record only).
  bool _isPaidConsultationType(String type) {
    return type == 'tele' || type == 'video';
  }

  /// Bottom sheet asking how the patient wants to pay for a Tele/Video
  /// consultation. Returns 'online' or 'offline'; null when dismissed.
  Future<String?> _showPaymentMethodSheet(String type, int fee) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF1C1C30)
        : const Color(0xFFF7F8FA);
    return Get.bottomSheet<String>(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: AppColors.primary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Consultation Payment',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHeading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_typeLabel(type)}  •  ₹$fee',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textCaption,
                        ),
                      ),
                      // Show the doctor's UPI ID so the patient knows
                      // who they are paying (when the doctor has set one).
                      if (_doctorUpiVpa != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Pay to: $_doctorUpiVpa',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Online Pay is only offered when the doctor has set a real
            // UPI ID — without one there is no account that can receive
            // the money, so the intent would fail (or worse, point at a
            // non-existent VPA). No doctor UPI ID → the patient pays at
            // the clinic.
            if (_doctorUpiVpa != null)
              PaymentMethodTile(
                icon: Icons.qr_code_2_rounded,
                title: 'Online Pay (UPI)',
                subtitle: 'Pay ₹$fee now via GPay / PhonePe / Paytm',
                color: AppColors.primary,
                onTap: () => Get.back(result: 'online'),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Online payment not available for this clinic yet — '
                        'please pay at the clinic.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.textHeading,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            PaymentMethodTile(
              icon: Icons.storefront_rounded,
              title: 'Offline Pay',
              subtitle: 'Pay ₹$fee at the clinic',
              color: AppColors.success,
              onTap: () => Get.back(result: 'offline'),
            ),
          ],
        ),
      ),
    );
  }

  /// Runs the UPI payment flow: lists installed UPI apps, lets the patient
  /// pick one, fires the intent and maps the outcome. A declined or
  /// unconfirmed payment shows a dialog (see [_showUpiProblemDialog]) that
  /// offers to retry with another UPI app, switch to offline pay, or
  /// cancel — 'retry' loops back to the app picker.
  ///
  /// Returns how the online-pay leg ended, plus the payment result when it
  /// actually succeeded (only for [_OnlinePayOutcome.paid]).
  Future<(_OnlinePayOutcome, UpiPaymentResult?)> _runUpiPayment(
    String type,
    int fee,
  ) async {
    // Safety net: never fire a UPI intent without a real receiving VPA
    // (the sheet already hides Online Pay in this case, but the booking
    // flow must not attempt a payment to a non-existent account).
    final upiVpa = _doctorUpiVpa;
    if (upiVpa == null) {
      showErrorSnackbar(
        'Online payment is not available for this clinic. Please choose '
        'Offline Pay.',
      );
      return (_OnlinePayOutcome.cancelled, null);
    }
    while (true) {
      final apps = await UpiPaymentService.instance.getInstalledUpiApps();
      if (apps.isEmpty) {
        showErrorSnackbar(
          'No UPI app found. Please install GPay / PhonePe / Paytm, or '
          'choose Offline Pay.',
        );
        return (_OnlinePayOutcome.cancelled, null);
      }

      // Let the patient choose which UPI app to pay with.
      if (!mounted) {
        return (_OnlinePayOutcome.cancelled, null);
      }
      final app = await UpiAppPickerSheet.show(
        context,
        apps,
        payeeUpiId: upiVpa,
        payeeName: doctor.name,
      );
      if (app == null) return (_OnlinePayOutcome.cancelled, null);

      final txnRef = 'APT${DateTime.now().millisecondsSinceEpoch}';
      final result = await UpiPaymentService.instance.pay(
        app: app,
        amount: fee.toDouble(),
        transactionRef: txnRef,
        note: '${_typeLabel(type)} fee — ${doctor.name}',
        // Pay straight into the clinic's own account — the doctor's UPI
        // ID, verified non-null by the guard above.
        receiverUpiAddress: upiVpa,
        receiverName: doctor.name,
      );

      if (result.isSuccess) {
        showSuccessSnackbar('Payment successful — booking your appointment…');
        return (_OnlinePayOutcome.paid, result);
      }
      // The dialog reads Theme.of(context), so the screen must still be
      // mounted after the UPI intent returned.
      if (!mounted) return (_OnlinePayOutcome.cancelled, null);
      final choice = await _showUpiProblemDialog(submitted: result.isSubmitted);
      if (!mounted) return (_OnlinePayOutcome.cancelled, null);
      if (choice == 'retry') continue; // pick another UPI app
      if (choice == 'offline') return (_OnlinePayOutcome.payOffline, null);
      return (_OnlinePayOutcome.cancelled, null);
    }
  }

  /// Dialog explaining a UPI payment that did not go through — either
  /// declined/cancelled by the bank or UPI app (failure) or
  /// initiated-but-unconfirmed (submitted). Always reassures about the
  /// money; a plain failure also offers **Try Again** (re-picks another
  /// UPI app), and both offer **Pay Offline** so the patient is never
  /// stuck without a way to book.
  ///
  /// Returns the chosen action: 'retry' (failure only), 'offline', or
  /// null when dismissed/cancelled.
  Future<String?> _showUpiProblemDialog({required bool submitted}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = submitted ? AppColors.warning : AppColors.error;
    return Get.dialog<String>(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: isDark ? const Color(0xFF1C1C30) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withAlpha(16),
                ),
                child: Icon(
                  submitted
                      ? Icons.help_outline_rounded
                      : Icons.cancel_rounded,
                  color: accent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                submitted ? 'Payment Not Confirmed' : 'Payment Failed',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.textHeading,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                submitted
                    ? 'The payment was not confirmed. If any money was '
                        'deducted, contact the clinic before paying again.'
                    : 'Your bank or UPI app declined the payment. No money '
                        'was deducted from your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: isDark ? Colors.white70 : AppColors.textBody,
                ),
              ),
              const SizedBox(height: 22),
              if (!submitted) ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => Get.back(result: 'retry'),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 46,
                child: submitted
                    ? ElevatedButton.icon(
                        onPressed: () => Get.back(result: 'offline'),
                        icon: const Icon(Icons.storefront_rounded, size: 18),
                        label: const Text(
                          'Pay Offline',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => Get.back(result: 'offline'),
                        icon: const Icon(Icons.storefront_rounded, size: 18),
                        label: const Text(
                          'Pay Offline',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.success,
                          side: BorderSide(
                            color: AppColors.success.withAlpha(120),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
              ),
              TextButton(
                onPressed: () => Get.back(), // null — dismissed
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : AppColors.textCaption,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  /// The 'pay at clinic' payment record used for offline bookings (and
  /// when the patient switches to offline pay after a failed UPI attempt).
  /// Returns null when the slot has no fee (nothing to record).
  PaymentModel? _offlinePayment(String consultationType, int fee) {
    if (fee <= 0) return null;
    return PaymentModel(
      patientId: Get.find<AuthController>().currentUser.value?.id ?? '',
      doctorPlaceId: doctor.placeId,
      doctorName: doctor.name,
      consultationType: consultationType,
      paymentMethod: 'offline',
      paymentStatus: 'Pending',
      amount: fee.toDouble(),
      // The clinic's receiving VPA when set — null otherwise (an offline
      // pay-at-clinic record must not carry a fake address).
      upiId: _doctorUpiVpa,
    );
  }

  Future<void> _showBookingSuccessDialog({
    required String doctorName,
    required String date,
    required String time,
  }) {
    return Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: AppColors.bgCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.success.withAlpha(30),
                      AppColors.success.withAlpha(10),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 48,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Appointment Booked!',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHeading,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                doctorName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$date  •  $time',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textBody,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You will receive a confirmation shortly.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textCaption),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.calendar_month_rounded, size: 19),
                  label: const Text(
                    'View Appointments',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final surfaceColor = isDark
        ? const Color(0xFF1C1C30)
        : const Color(0xFFF7F8FA);
    final inputFill = isDark
        ? const Color(0xFF1C1C30)
        : const Color(0xFFF3F4F6);
    final dividerColor = isDark
        ? Colors.white.withAlpha(8)
        : Colors.black.withAlpha(6);

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              _buildHeader(textColor),

              const SizedBox(height: 22),

              // ── Doctor card ──
              _buildDoctorCard(isDark, textColor, surfaceColor),

              // ── Per-doctor gate notice ──
              // Shown while the patient can't book THIS doctor right now
              // (an active Pending/Upcoming booking with them) — explains
              // why, so the block is never a surprise. Other doctors stay
              // bookable.
              if (_bookingBlockMessage != null) ...[
                const SizedBox(height: 16),
                BookingBlockBanner(message: _bookingBlockMessage!),
              ],

              const SizedBox(height: 28),

              _buildDivider(dividerColor),

              const SizedBox(height: 22),

              // ── Patient Details ──
              _buildPatientSection(textColor, inputFill),

              const SizedBox(height: 28),

              _buildDivider(dividerColor),

              const SizedBox(height: 22),

              // ── Select Date ──
              _buildDateSection(textColor, isDark),

              const SizedBox(height: 24),

              // ── Available Slots ──
              if (_selectedDateIndex >= 0 && !_slotsLoading)
                _buildSlotsSection(textColor, isDark, surfaceColor),

              if (_slotsLoading) _buildSlotsShimmer(isDark),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(isDark),
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader(Color textColor) {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: textColor.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: Get.back,
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 17,
              color: textColor,
            ),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'Book Appointment',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  // ── Doctor Card ───────────────────────────────────────────────

  Widget _buildDoctorCard(bool isDark, Color textColor, Color surfaceColor) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary.withAlpha(160)],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(left: 2.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C30) : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar ring
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withAlpha(80)],
                ),
              ),
              child: DoctorAvatar.circle(doctor: doctor, size: 54),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doctor.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      doctor.specialization ?? 'Doctor',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (doctor.rating != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4D85A).withAlpha(22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Color(0xFFF4D85A),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      doctor.rating!.ratingString,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF4D85A),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Patient Details ───────────────────────────────────────────

  Widget _buildPatientSection(Color textColor, Color inputFill) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patient Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _patientNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Patient Name',
            prefixIcon: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.textCaption,
              size: 20,
            ),
            filled: true,
            fillColor: inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _symptomsController,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Describe your symptoms',
            prefixIcon: Padding(
              padding: const EdgeInsets.only(bottom: 42),
              child: Icon(
                Icons.medical_information_rounded,
                color: AppColors.textCaption,
                size: 20,
              ),
            ),
            filled: true,
            fillColor: inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  // ── Date Section ──────────────────────────────────────────────

  Widget _buildDateSection(Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Select Date',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 8),
            if (_slotsLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (!_slotsLoading)
          SizedBox(
            height: 88,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: dateOptions.length,
              itemBuilder: (context, index) {
                final opt = dateOptions[index];
                final hasSlots = _controller.hasSlotsForDay(opt.dayOfWeek);
                final isUnavailable = _isDateUnavailable(opt);
                final isSelected = _selectedDateIndex == index;
                return _DateChip(
                  dateOption: opt,
                  hasSlots: hasSlots && !isUnavailable,
                  isUnavailable: isUnavailable,
                  isSelected: isSelected,
                  isDark: isDark,
                  onTap: hasSlots && !isUnavailable
                      ? () {
                          setState(() {
                            _selectedDateIndex = index;
                            _selectedTimeSlot = '';
                            _controller.selectedDayOfWeek.value = opt.dayOfWeek;
                          });
                        }
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Slots Section ─────────────────────────────────────────────

  Widget _buildSlotsSection(Color textColor, bool isDark, Color surfaceColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Slots',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final dayOfWeek = _controller.selectedDayOfWeek.value;
          final slots = _controller.getTimeSlotsForDay(dayOfWeek);
          final selectedIsoDate = _selectedDateIndex >= 0
              ? dateOptions[_selectedDateIndex].isoDate
              : '';

          // Doctor marked this date unavailable (leave/holiday) — booking
          // is disabled even though the weekly schedule has slots.
          if (_selectedDateIndex >= 0 &&
              _isDateUnavailable(dateOptions[_selectedDateIndex])) {
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The doctor is unavailable on this date. Please pick another day.',
                      style: TextStyle(color: AppColors.error, fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          }

          if (slots.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    color: AppColors.textCaption,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No slots available for this day. Try another date.',
                      style: TextStyle(
                        color: AppColors.textCaption,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Group by schedule type
          final Map<String, List<String>> grouped = {};
          for (final slot in slots) {
            final type = _controller.getSlotTypeLabel(slot);
            grouped.putIfAbsent(type, () => []);
            grouped[type]!.add(slot);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: grouped.entries.map((entry) {
              final typeEmoji = _typeEmoji(entry.key);
              final typeLabel = _typeLabel(entry.key);
              final typeColor = _typeColor(entry.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$typeEmoji $typeLabel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: typeColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withAlpha(10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '₹${_slotFee(entry.key)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: typeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value.map((timeSlot) {
                        final isTimeSelected = _selectedTimeSlot == timeSlot;
                        final isBooked = _controller.isSlotBooked(
                          selectedIsoDate,
                          timeSlot,
                        );
                        final isPast = _controller.isSlotInPast(
                          selectedIsoDate,
                          timeSlot,
                        );
                        final isDisabled = isBooked || isPast;
                        return GestureDetector(
                          onTap: isDisabled
                              ? null
                              : () => setState(
                                  () => _selectedTimeSlot = timeSlot,
                                ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isTimeSelected
                                  ? typeColor
                                  : isDisabled
                                  ? surfaceColor
                                  : (isDark
                                        ? const Color(0xFF1C1C30)
                                        : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isTimeSelected
                                    ? typeColor
                                    : isDisabled
                                    ? AppColors.textDisabled.withAlpha(35)
                                    : (isDark
                                          ? Colors.white.withAlpha(8)
                                          : const Color(0xFFE5E7EB)),
                                width: isTimeSelected ? 0 : 1,
                              ),
                              boxShadow: isTimeSelected
                                  ? [
                                      BoxShadow(
                                        color: typeColor.withAlpha(40),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isTimeSelected
                                      ? Icons.check_circle_rounded
                                      : isBooked
                                      ? Icons.lock_rounded
                                      : isPast
                                      ? Icons.history_rounded
                                      : Icons.schedule_rounded,
                                  size: 14,
                                  color: isTimeSelected
                                      ? Colors.white
                                      : isDisabled
                                      ? AppColors.textDisabled
                                      : AppColors.textCaption,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isBooked ? 'Booked' : timeSlot,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isTimeSelected
                                        ? Colors.white
                                        : isDisabled
                                        ? AppColors.textDisabled
                                        : textColor,
                                    decoration: isPast
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  // ── Bottom Bar ────────────────────────────────────────────────

  Widget _buildBottomBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF14142A).withAlpha(248)
            : Colors.white.withAlpha(248),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withAlpha(8)
                : Colors.black.withAlpha(6),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 35 : 10),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Selected summary
              if (_selectedDateIndex >= 0 && _selectedTimeSlot.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                        color: AppColors.textCaption,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${dateOptions[_selectedDateIndex].dayLabel}, ${dateOptions[_selectedDateIndex].dateLabel} ${dateOptions[_selectedDateIndex].monthLabel}  •  $_selectedTimeSlot',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textCaption,
                        ),
                      ),
                    ],
                  ),
                ),
              // Book button
              Obx(() {
                final isLoading = _controller.isLoading.value;
                final ready = _canBook && !isLoading;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: ready
                        ? LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withAlpha(210),
                            ],
                          )
                        : null,
                    color: ready
                        ? null
                        : (isDark
                              ? const Color(0xFF2A2A40)
                              : const Color(0xFFD1D5DB)),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: ready
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(45),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isLoading ? null : _bookAppointment,
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.approval_rounded,
                                    size: 20,
                                    color: ready
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white38
                                              : Colors.white70),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Book Appointment',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: ready
                                          ? Colors.white
                                          : (isDark
                                                ? Colors.white38
                                                : Colors.white70),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Divider ───────────────────────────────────────────────────

  Widget _buildDivider(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Divider(color: color, height: 1, thickness: 1),
    );
  }

  // ── Shimmer skeleton ──────────────────────────────────────────

  Widget _buildSlotsShimmer(bool isDark) {
    final base = isDark ? const Color(0xFF1C1C30) : const Color(0xFFECEAE4);
    final highlight = isDark
        ? const Color(0xFF2C2C42)
        : const Color(0xFFF6F2EA);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 130,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              itemBuilder: (context, index) => Container(
                width: 64,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 110,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 100,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 50,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              4,
              (i) => Container(
                width: i == 2 ? 100 : 80,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Container(
                width: 90,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 50,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              3,
              (i) => Container(
                width: 90,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _typeEmoji(String type) {
    switch (type) {
      case 'tele':
        return '📞';
      case 'video':
        return '🎥';
      case 'clinic':
        return '🏥';
      default:
        return '🩺';
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'tele':
        return 'Tele Consultation';
      case 'video':
        return 'Video Consultation';
      case 'clinic':
        return 'In-Clinic';
      default:
        return 'Consultation';
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'tele':
        return const Color(0xFF1E3A8A);
      case 'video':
        return const Color(0xFF6B21A8);
      case 'clinic':
        return const Color(0xFF92400E);
      default:
        return AppColors.primary;
    }
  }

  int _slotFee(String type) {
    for (final s in _controller.doctorSlots) {
      if (s.scheduleType == type && s.isEnabled) return s.fee;
    }
    switch (type) {
      case 'tele':
        return 500;
      case 'video':
        return 800;
      case 'clinic':
        return 1000;
      default:
        return 0;
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  Data classes
// ════════════════════════════════════════════════════════════════════

class _DateOption {
  final DateTime date;
  final String dayLabel;
  final String dateLabel;
  final String monthLabel;
  final String isoDate;
  final String dayOfWeek;

  const _DateOption({
    required this.date,
    required this.dayLabel,
    required this.dateLabel,
    required this.monthLabel,
    required this.isoDate,
    required this.dayOfWeek,
  });
}

// ════════════════════════════════════════════════════════════════════
//  Date chip widget
// ════════════════════════════════════════════════════════════════════

class _DateChip extends StatelessWidget {
  final _DateOption dateOption;
  final bool hasSlots;
  final bool isUnavailable;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  const _DateChip({
    required this.dateOption,
    required this.hasSlots,
    required this.isUnavailable,
    required this.isSelected,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = !hasSlots && !isSelected;
    final disabledColor = isDark
        ? const Color(0xFF1C1C30)
        : const Color(0xFFF3F4F6);
    // Unavailable dates get a distinct red tint so the patient can see
    // at a glance that the doctor set this period aside.
    final unavailColor = isDark
        ? const Color(0xFF3A1F1F)
        : const Color(0xFFFCEBEB);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : isUnavailable
              ? unavailColor
              : isDisabled
              ? disabledColor
              : (isDark ? const Color(0xFF1C1C30) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : isUnavailable
                ? AppColors.error.withAlpha(45)
                : hasSlots
                ? AppColors.primary.withAlpha(35)
                : (isDark
                      ? Colors.white.withAlpha(6)
                      : const Color(0xFFE5E7EB)),
            width: isSelected ? 0 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dateOption.dayLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white.withAlpha(200)
                      : isUnavailable
                      ? AppColors.error
                      : isDisabled
                      ? AppColors.textDisabled
                      : AppColors.textCaption,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateOption.dateLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : isUnavailable
                      ? AppColors.error
                      : isDisabled
                      ? AppColors.textDisabled
                      : (isDark ? Colors.white : AppColors.textHeading),
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                dateOption.monthLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white.withAlpha(180)
                      : isUnavailable
                      ? AppColors.error
                      : isDisabled
                      ? AppColors.textDisabled
                      : AppColors.textCaption,
                ),
              ),
              if (isUnavailable)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    '✕',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                  ),
                )
              else if (hasSlots && !isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(60),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
