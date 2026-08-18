import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../controllers/web_booking_controller.dart';
import '../../models/appointment_model.dart';
import '../../models/doctor_slot_model.dart';
import '../../models/payment_model.dart';

/// Web-based booking screen — designed for browser / Flutter web.
///
/// Two-panel layout on wide screens (≥800px): booking form on the left,
/// payment + summary on the right. Single-column on narrow screens.
///
/// **Booking tab**: doctor info → date → slot → patient details → payment → confirm
/// **History tab**: expandable appointment cards with full details + cancel
class WebBookingScreen extends StatefulWidget {
  const WebBookingScreen({super.key});

  @override
  State<WebBookingScreen> createState() => _WebBookingScreenState();
}

class _WebBookingScreenState extends State<WebBookingScreen>
    with SingleTickerProviderStateMixin {
  late final WebBookingController _c;
  late final TabController _tabController;

  /// Extracts the doctor placeId from route arguments, URL query
  /// parameters, OR the hash fragment (Flutter web hash routing puts
  /// query params inside the hash: #/web-booking?doctor=X).
  static String? _doctorFromUrl() {
    // 1. In-app navigation via Get.toNamed
    final args = Get.arguments;
    if (args is Map && args['doctor'] != null) {
      return args['doctor'].toString();
    }
    // 2. Standard URL query parameters (e.g. ?doctor=X)
    final fromQuery = Uri.base.queryParameters['doctor'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    // 3. Hash fragment — Flutter web default routing puts everything
    //    after # into the fragment: #/web-booking?doctor=X&token=Y
    final fragment = Uri.base.fragment;
    if (fragment.isNotEmpty) {
      final hashUri = Uri.parse(
        fragment.startsWith('/') ? fragment : '/$fragment',
      );
      final fromHash = hashUri.queryParameters['doctor'];
      if (fromHash != null && fromHash.isNotEmpty) return fromHash;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _c = Get.put(WebBookingController(), permanent: false);
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final placeId = _doctorFromUrl();
      if (placeId != null && placeId.isNotEmpty) {
        _c.loadDoctor(placeId);
        _c.loadHistory();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 800;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookingTab(isWide),
                  _buildHistoryTab(isWide),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Header
  // ════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(30),
                  border: Border.all(color: Colors.white.withAlpha(60), width: 2),
                ),
                child: const Center(
                  child: Icon(Icons.medical_services_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Book Appointment',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    SizedBox(height: 2),
                    Text('Pick a slot, pay online or at the clinic',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: const [
                Tab(text: 'Book Now'),
                Tab(text: 'My Bookings'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Booking Tab
  // ════════════════════════════════════════════════════════════════════

  Widget _buildBookingTab(bool isWide) {
    return Obx(() {
      if (_c.bookingSuccess.value) return _buildSuccessView();
      if (_c.isLoadingDoctor.value) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
      }
      if (_c.doctorError.value.isNotEmpty) {
        return _buildErrorView(_c.doctorError.value);
      }
      if (_c.doctor.value == null) {
        return _buildErrorView(
            'No doctor selected. Scan a QR code or open a booking link.');
      }

      final hPad = isWide ? (((Get.width) - 820) / 2).clamp(16.0, 200.0) : 16.0;

      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column — booking form
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPad, 20, 12, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDoctorCard(),
                    const SizedBox(height: 18),
                    _buildStepHeader(1, 'Choose Date & Time'),
                    const SizedBox(height: 10),
                    _buildDateGrid(),
                    const SizedBox(height: 14),
                    _buildSlotPicker(),
                    const SizedBox(height: 18),
                    _buildStepHeader(2, 'Your Details'),
                    const SizedBox(height: 10),
                    _buildPatientForm(),
                    const SizedBox(height: 18),
                    _buildBookButton(),
                  ],
                ),
              ),
            ),
            // Right column — payment + summary
            SizedBox(
              width: 340,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(12, 20, hPad, 40),
                child: Column(
                  children: [
                    _buildBookingSummary(),
                    const SizedBox(height: 16),
                    _buildPaymentSection(),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      // Narrow — single column
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDoctorCard(),
            const SizedBox(height: 18),
            _buildStepHeader(1, 'Choose Date & Time'),
            const SizedBox(height: 10),
            _buildDateGrid(),
            const SizedBox(height: 14),
            _buildSlotPicker(),
            const SizedBox(height: 18),
            _buildStepHeader(2, 'Your Details'),
            const SizedBox(height: 10),
            _buildPatientForm(),
            const SizedBox(height: 18),
            _buildPaymentSection(),
            const SizedBox(height: 16),
            _buildBookingSummary(),
            const SizedBox(height: 16),
            _buildBookButton(),
            const SizedBox(height: 40),
          ],
        ),
      );
    });
  }

  // ── Step header ──────────────────────────────────────────────────

  Widget _buildStepHeader(int number, String title) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('$number',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textHeading)),
      ],
    );
  }

  // ── Doctor card ──────────────────────────────────────────────────

  Widget _buildDoctorCard() {
    final doc = _c.doctor.value!;
    return _card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              doc.name.isNotEmpty ? doc.name[0].toUpperCase() : 'D',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textHeading)),
                if (doc.specialization != null) ...[
                  const SizedBox(height: 3),
                  Text(doc.specialization!,
                      style: const TextStyle(fontSize: 13, color: AppColors.textBody)),
                ],
                if (doc.address != null) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppColors.textCaption),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(doc.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textCaption)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          if (doc.rating != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded, size: 16, color: AppColors.accent),
                const SizedBox(width: 4),
                Text(doc.rating!.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHeading)),
              ]),
            ),
        ],
      ),
    );
  }

  // ── Date grid ────────────────────────────────────────────────────

  Widget _buildDateGrid() {
    final opts = _c.dateOptions;
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: opts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final opt = opts[i];
          final sel = _c.selectedDateIndex.value == i;
          final unavail = _c.isDateUnavailable(opt);
          return GestureDetector(
            onTap: unavail ? null : () => setState(() => _c.selectDate(i)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 72,
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.primary
                    : unavail
                        ? AppColors.textDisabled.withAlpha(30)
                        : AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? AppColors.primary : AppColors.textDisabled.withAlpha(60)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${opt.date.day}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: sel ? Colors.white : AppColors.textHeading)),
                  const SizedBox(height: 2),
                  Text(_monthName(opt.date.month),
                      style: TextStyle(
                          fontSize: 11,
                          color: sel ? Colors.white70 : AppColors.textCaption)),
                  const SizedBox(height: 2),
                  Text(opt.dayLabel,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white60 : AppColors.textBody),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Slot picker ──────────────────────────────────────────────────

  Widget _buildSlotPicker() {
    return Obx(() {
      final dow = _c.selectedDayOfWeek.value;
      if (dow.isEmpty) return _card(child: _hint('Pick a date to see slots'));
      final schedules = _c.daySchedules(dow);
      if (schedules.isEmpty) return _card(child: _hint('No slots available'));

      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...schedules.map((s) => _slotGroup(s)),
          ],
        ),
      );
    });
  }

  Widget _slotGroup(DoctorSlot s) {
    final color = _typeColor(s.scheduleType);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_typeEmoji(s.scheduleType), style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Flexible(child: Text(_typeLabel(s.scheduleType),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
            const SizedBox(width: 8),
            _feeChip(s.fee, color),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: s.slots.map((t) {
              final sel = _c.selectedTimeSlot.value == t && _c.selectedType.value == s.scheduleType;
              final booked = _c.isSlotBooked(_c.selectedDate.value, t);
              final past = _c.isSlotInPast(_c.selectedDate.value, t);
              final disabled = booked || past;
              return GestureDetector(
                onTap: disabled ? null : () => _c.selectSlot(t, s.scheduleType),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel
                        ? color
                        : disabled
                            ? AppColors.textDisabled.withAlpha(20)
                            : color.withAlpha(10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel
                          ? color
                          : disabled
                              ? AppColors.textDisabled.withAlpha(40)
                              : color.withAlpha(30),
                    ),
                  ),
                  child: Text(t,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel
                              ? Colors.white
                              : disabled
                                  ? AppColors.textDisabled
                                  : color)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _feeChip(int fee, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withAlpha(15), borderRadius: BorderRadius.circular(6)),
      child: Text('₹$fee',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ── Patient form ─────────────────────────────────────────────────

  Widget _buildPatientForm() {
    return _card(
      child: Column(
        children: [
          _field('Full Name', Icons.person_outline_rounded,
              onChanged: (v) => _c.patientName.value = v),
          const SizedBox(height: 12),
          _field('Phone Number', Icons.phone_outlined,
              type: TextInputType.phone,
              onChanged: (v) => _c.patientPhone.value = v),
          const SizedBox(height: 12),
          _field('Symptoms / Reason for visit', Icons.healing_outlined,
              lines: 3, onChanged: (v) => _c.symptoms.value = v),
        ],
      ),
    );
  }

  // ── Payment section ──────────────────────────────────────────────

  Widget _buildPaymentSection() {
    return Obx(() {
      final fee = _c.selectedFee;
      if (fee <= 0) return const SizedBox.shrink();

      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.payment_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Payment — ₹$fee',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textHeading)),
              ),
            ]),
            const SizedBox(height: 14),
            // Pay at Clinic
            _payTile(
              icon: Icons.payments_rounded,
              title: 'Pay at Clinic',
              sub: 'Pay ₹$fee when you visit',
              color: AppColors.success,
              sel: _c.paymentMethod.value == 'offline' || _c.paymentMethod.value.isEmpty,
              onTap: () => _c.paymentMethod.value = 'offline',
            ),
            // Online UPI
            if (_c.upiId != null && _c.upiId!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _payTile(
                icon: Icons.qr_code_2_rounded,
                title: 'Pay Online (UPI)',
                sub: 'Scan QR code or use UPI link',
                color: AppColors.primary,
                sel: _c.paymentMethod.value == 'online',
                onTap: () => _c.paymentMethod.value = 'online',
              ),
            ],
            // QR code + intent
            if (_c.paymentMethod.value == 'online' && _c.upiId != null) ...[
              const SizedBox(height: 16),
              _upiPanel(fee),
            ],
          ],
        ),
      );
    });
  }

  Widget _upiPanel(int fee) {
    final vpa = _c.upiId!;
    final name = _c.doctor.value?.name ?? 'Doctor';
    final uri = 'upi://pay?pa=$vpa&pn=$name&am=$fee&cu=INR';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withAlpha(25)),
      ),
      child: Column(
        children: [
          // QR code
          Container(
            padding: const EdgeInsets.all(12),
            decoration:
                BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(
              data: uri,
              version: QrVersions.auto,
              size: 170,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textHeading,
            ),
          ),
          const SizedBox(height: 10),
          Text('Scan with GPay / PhonePe / Paytm',
              style: TextStyle(fontSize: 12, color: AppColors.textBody)),
          const SizedBox(height: 4),
          Text('₹$fee',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 12),
          _kv('Pay to', vpa),
          const SizedBox(height: 4),
          _kv('Amount', '₹$fee'),
          const SizedBox(height: 4),
          _kv('Note', 'Consultation fee'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () async {
                final u = Uri.parse(uri);
                if (await canLaunchUrl(u)) {
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Pay via UPI App',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('After payment, tap "Book Appointment" below.',
              style: TextStyle(fontSize: 11, color: AppColors.textCaption)),
        ],
      ),
    );
  }

  // ── Booking summary (right column / below payment on mobile) ─────

  Widget _buildBookingSummary() {
    return Obx(() {
      if (_c.selectedDate.isEmpty) return const SizedBox.shrink();

      final dateOpt = _c.dateOptions
          .where((o) => o.isoDate == _c.selectedDate.value)
          .firstOrNull;
      final fee = _c.selectedFee;
      final slot = _c.selectedTimeSlot.value;
      final type = _c.selectedType.value;

      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.receipt_long_rounded,
                  size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Flexible(
                child: Text('Booking Summary',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHeading)),
              ),
            ]),
            const SizedBox(height: 12),
            if (dateOpt != null) _kv('Date', dateOpt.displayDate),
            if (slot.isNotEmpty) ...[
              const SizedBox(height: 4),
              _kv('Time', slot),
            ],
            if (type.isNotEmpty) ...[
              const SizedBox(height: 4),
              _kv('Type', _typeLabel(type)),
            ],
            if (_c.patientName.value.isNotEmpty) ...[
              const SizedBox(height: 4),
              _kv('Patient', _c.patientName.value),
            ],
            if (_c.patientPhone.value.isNotEmpty) ...[
              const SizedBox(height: 4),
              _kv('Phone', _c.patientPhone.value),
            ],
            if (fee > 0) ...[
              const SizedBox(height: 8),
              Divider(color: AppColors.textDisabled.withAlpha(50)),
              const SizedBox(height: 8),
              Row(children: [
                const Flexible(child: Text('Total',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textBody))),
                const Spacer(),
                Text('₹$fee',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ]),
            ],
          ],
        ),
      );
    });
  }

  // ── Book button ──────────────────────────────────────────────────

  Widget _buildBookButton() {
    return Obx(() {
      final err = _c.bookingError.value;
      return Column(
        children: [
          if (err.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withAlpha(30)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(err,
                        style: const TextStyle(fontSize: 13, color: AppColors.error))),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _c.canBook ? () => _c.bookAppointment() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.textDisabled.withAlpha(60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _c.isBooking.value
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : const Text('Book Appointment',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      );
    });
  }

  // ════════════════════════════════════════════════════════════════════
  // Success view
  // ════════════════════════════════════════════════════════════════════

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.success.withAlpha(20)),
              child: const Icon(Icons.check_circle_rounded,
                  size: 48, color: AppColors.success),
            ),
            const SizedBox(height: 20),
            const Text('Booking Confirmed!',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textHeading)),
            const SizedBox(height: 8),
            Text('Appointment ID: ${_c.bookedAppointmentId.value ?? ''}',
                style: const TextStyle(fontSize: 14, color: AppColors.textBody)),
            const SizedBox(height: 6),
            Text('${_c.selectedDate.value} at ${_c.selectedTimeSlot.value}',
                style: const TextStyle(fontSize: 14, color: AppColors.textBody)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    _c.resetForm();
                    _tabController.animateTo(0);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withAlpha(60)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Book Another'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    _c.resetForm();
                    _tabController.animateTo(1);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('View Bookings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // History Tab — full appointment cards with expandable details
  // ════════════════════════════════════════════════════════════════════

  Widget _buildHistoryTab(bool isWide) {
    return Obx(() {
      if (_c.isLoadingHistory.value) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
      }
      if (_c.historyAppointments.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.primary.withAlpha(15)),
                child: const Icon(Icons.event_busy_rounded,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text('No bookings yet',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHeading)),
              const SizedBox(height: 6),
              const Text('Book your first appointment',
                  style: TextStyle(fontSize: 13, color: AppColors.textCaption)),
            ],
          ),
        );
      }

      final pad = isWide ? (((Get.width) - 700) / 2).clamp(16.0, 200.0) : 16.0;
      return RefreshIndicator(
        onRefresh: () => _c.loadHistory(),
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
          itemCount: _c.historyAppointments.length,
          itemBuilder: (_, i) => _historyCard(_c.historyAppointments[i]),
        ),
      );
    });
  }

  Widget _historyCard(AppointmentModel a) {
    final status = _c.effectiveStatus(a);
    final payment = _c.historyPayments[a.appointmentId];
    final sc = _statusColor(status);
    final expanded = _c.expandedAppointmentId.value == a.appointmentId;
    final canCancel = status == 'Upcoming' || status == 'Pending';

    return GestureDetector(
      onTap: () => _c.toggleExpand(a.appointmentId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: expanded ? sc.withAlpha(60) : sc.withAlpha(30), width: expanded ? 2 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(expanded ? 12 : 6),
                blurRadius: expanded ? 16 : 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          children: [
            // ── Compact header ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: sc.withAlpha(15),
                    child: Icon(_statusIcon(status), size: 18, color: sc),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.doctorName ?? 'Doctor',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textHeading)),
                        const SizedBox(height: 2),
                        Text(
                            '${a.displayDate ?? a.appointmentDate}  •  ${a.appointmentTime ?? ''}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textBody)),
                      ],
                    ),
                  ),
                  if (payment != null)
                    Text('₹${payment.amountLabel}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHeading)),
                  const SizedBox(width: 10),
                  _statusChip(status, sc),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded,
                        size: 22, color: AppColors.textCaption),
                  ),
                ],
              ),
            ),

            // ── Expanded detail section ──
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: _historyDetail(a, payment, status, canCancel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyDetail(
      AppointmentModel a, PaymentModel? payment, String status, bool canCancel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.textDisabled.withAlpha(40)),
          const SizedBox(height: 10),
          // Detail grid — two columns
          _detailGrid(a, status),
          // Payment details
          if (payment != null) ...[
            const SizedBox(height: 12),
            _paymentDetailBlock(payment),
          ],
          // Refund details
          if (payment?.refundMethod != null) ...[
            const SizedBox(height: 10),
            _refundDetailBlock(payment!),
          ],
          // Cancel button
          if (canCancel) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmCancel(a),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Cancel Appointment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withAlpha(60)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailGrid(AppointmentModel a, String status) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _infoTile(Icons.badge_rounded, 'Appointment ID', a.appointmentId),
        _infoTile(Icons.calendar_month_rounded, 'Date',
            a.displayDate ?? a.appointmentDate ?? '—'),
        _infoTile(Icons.access_time_rounded, 'Time',
            a.appointmentTime ?? '—'),
        if (a.consultationTypeLabel != null)
          _infoTile(_consultIcon(a.consultationType), 'Consultation',
              a.consultationTypeLabel!),
        if (a.patientName != null)
          _infoTile(Icons.person_rounded, 'Patient', a.patientName!),
        if ((a.patientPhone ?? '').isNotEmpty)
          _infoTile(Icons.phone_rounded, 'Phone', a.patientPhone!),
        if ((a.symptoms ?? '').isNotEmpty)
          _infoTile(Icons.healing_outlined, 'Symptoms', a.symptoms!),
        _infoTile(Icons.flag_rounded, 'Status', status),
      ],
    );
  }

  Widget _paymentDetailBlock(PaymentModel p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _paymentStatusColor(p.paymentStatus).withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: _paymentStatusColor(p.paymentStatus).withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_rounded,
                size: 16, color: AppColors.textHeading),
            const SizedBox(width: 8),
            const Text('Payment Details',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHeading)),
            const Spacer(),
            _statusChip(p.paymentStatus, _paymentStatusColor(p.paymentStatus)),
          ]),
          const SizedBox(height: 8),
          _kv('Amount', p.amountLabel),
          const SizedBox(height: 4),
          _kv('Method', p.paymentMethodLabel),
          if (p.consultationTypeLabel != null) ...[
            const SizedBox(height: 4),
            _kv('Consultation', p.consultationTypeLabel!),
          ],
          if (p.paidAt != null) ...[
            const SizedBox(height: 4),
            _kv('Paid on', _dateTimeLabel(p.paidAt!)),
          ],
          if (p.transactionId != null) ...[
            const SizedBox(height: 4),
            _kv('Transaction ID', p.transactionId!),
          ],
        ],
      ),
    );
  }

  Widget _refundDetailBlock(PaymentModel p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.currency_rupee_rounded,
                size: 16, color: AppColors.info),
            const SizedBox(width: 8),
            const Text('Refund Details',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.info)),
          ]),
          const SizedBox(height: 8),
          _kv('Refunded via', p.refundMethodLabel ?? '—'),
          if (p.refundedAt != null) ...[
            const SizedBox(height: 4),
            _kv('Refunded on', _dateTimeLabel(p.refundedAt!)),
          ],
          if (p.refundUpiId != null) ...[
            const SizedBox(height: 4),
            _kv('Refund UPI ID', p.refundUpiId!),
          ],
          if (p.refundTransactionId != null) ...[
            const SizedBox(height: 4),
            _kv('Refund txn ID', p.refundTransactionId!),
          ],
        ],
      ),
    );
  }

  void _confirmCancel(AppointmentModel a) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Appointment?'),
        content: Text(
            'Are you sure you want to cancel your appointment with ${a.doctorName ?? 'this doctor'} on ${a.displayDate ?? a.appointmentDate} at ${a.appointmentTime}?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child:
                Text('Keep', style: TextStyle(color: AppColors.textCaption)),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              _c.cancelAppointment(a.appointmentId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Shared helpers
  // ════════════════════════════════════════════════════════════════════

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.error.withAlpha(15)),
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.textBody)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                final placeId = _doctorFromUrl();
                if (placeId != null) _c.loadDoctor(placeId);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.textDisabled.withAlpha(30)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: child,
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(text,
            style: const TextStyle(fontSize: 14, color: AppColors.textCaption)),
      ),
    );
  }

  Widget _field(String label, IconData icon,
      {TextInputType? type, int lines = 1,
      required ValueChanged<String> onChanged}) {
    return TextField(
      keyboardType: type,
      maxLines: lines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Row(
      children: [
        Text('$key: ', style: const TextStyle(fontSize: 12, color: AppColors.textCaption)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHeading)),
        ),
      ],
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textCaption),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(fontSize: 12, color: AppColors.textCaption)),
          Expanded(
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHeading)),
          ),
        ],
      ),
    );
  }

  Widget _payTile({
    required IconData icon,
    required String title,
    required String sub,
    required Color color,
    required bool sel,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? color.withAlpha(10) : AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? color : AppColors.textDisabled.withAlpha(50),
              width: sel ? 2 : 1),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHeading)),
                const SizedBox(height: 2),
                Text(sub,
                    style:
                        const TextStyle(fontSize: 11.5, color: AppColors.textBody)),
              ],
            ),
          ),
          Icon(
              sel
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: sel ? color : AppColors.textCaption),
        ]),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  String _monthName(int m) =>
      ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
          'Oct', 'Nov', 'Dec'][m];

  String _typeEmoji(String t) => switch (t) {
        'tele' => '📞',
        'video' => '🎥',
        'clinic' => '🏥',
        _ => '🩺',
      };

  String _typeLabel(String t) => switch (t) {
        'tele' => 'Tele Consultation',
        'video' => 'Video Consultation',
        'clinic' => 'In-Clinic',
        _ => 'Consultation',
      };

  Color _typeColor(String t) => switch (t) {
        'tele' => AppColors.primary,
        'video' => const Color(0xFF4A9FE7),
        'clinic' => AppColors.accent,
        _ => AppColors.primary,
      };

  Color _statusColor(String s) => switch (s) {
        'Completed' => AppColors.success,
        'Cancelled' => AppColors.error,
        'Pending' => AppColors.warning,
        _ => AppColors.primary,
      };

  IconData _statusIcon(String s) => switch (s) {
        'Completed' => Icons.check_circle_rounded,
        'Cancelled' => Icons.cancel_rounded,
        'Pending' => Icons.hourglass_top_rounded,
        _ => Icons.schedule_rounded,
      };

  IconData _consultIcon(String? t) => switch (t) {
        'tele' => Icons.phone_rounded,
        'video' => Icons.videocam_rounded,
        'clinic' => Icons.local_hospital_rounded,
        _ => Icons.medical_services_rounded,
      };

  Color _paymentStatusColor(String s) => switch (s) {
        'Paid' => AppColors.success,
        'Pending' => AppColors.warning,
        'Failed' => AppColors.error,
        'Refunded' => AppColors.info,
        _ => AppColors.textCaption,
      };

  String _dateTimeLabel(DateTime d) {
    final h24 = d.hour;
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day-$month-${d.year}, $h12:$min $period';
  }
}
