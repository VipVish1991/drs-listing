import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/payment_history_controller.dart';
import '../../models/payment_model.dart';
import '../../services/local_storage_service.dart';
import '../../services/share_service.dart';
import '../../utils/payment_csv.dart';
import '../../utils/payment_summary.dart';
import '../doctor/doctor_main_shell.dart';

/// One month-year bucket with pre-computed aggregates.
class _MonthGroup {
  final int year;
  final int month;
  final String label; // e.g. "Aug 2026"
  final double paidTotal;
  final double pendingTotal;
  final int count;

  const _MonthGroup({
    required this.year,
    required this.month,
    required this.label,
    required this.paidTotal,
    required this.pendingTotal,
    required this.count,
  });

  /// The month-only key for filtering (e.g. "2026-08").
  String get isoKey => '$year-${month.toString().padLeft(2, '0')}';

  /// 'yyyy-MM' key for a date's month (e.g. "2026-08") — shared by the
  /// month filter, the window builder and the yearly summary lookups.
  static String isoKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Short month name for the custom-range labels ("Aug").
  static String monthAbbrev(int month) => _months[month];

  static const _months = [
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

  static String _label(int year, int month) => '${_months[month]} $year';

  /// The keys of the rolling 12-month window ending at [now], newest month
  /// first (e.g. Aug 2026 … Sep 2025). `DateTime` normalizes month ≤ 0, so
  /// `now.month - i` safely rolls back across year boundaries.
  static List<String> last12Months(DateTime now) {
    final keys = <String>[];
    for (var i = 0; i < 12; i++) {
      keys.add(isoKeyOf(DateTime(now.year, now.month - i, 1)));
    }
    return keys;
  }

  /// Month groups for the rolling 12-month window ending at [now], newest
  /// month first — the yearly strip's window figure (₹0 totals for months
  /// that have no payments). Payments older than the window simply fall
  /// outside it (reachable under "All").
  static List<_MonthGroup> buildWindow(
    List<PaymentModel> payments,
    DateTime now,
  ) {
    final byKey = <String, _MonthGroupBuilder>{};
    for (final p in payments) {
      final d = p.createdAt ?? p.paidAt;
      if (d == null) continue;
      final key = isoKeyOf(d);
      byKey.putIfAbsent(
        key,
        () => _MonthGroupBuilder(year: d.year, month: d.month),
      );
      byKey[key]!.add(p);
    }
    final groups = <_MonthGroup>[];
    for (final key in last12Months(now)) {
      final year = int.parse(key.substring(0, 4));
      final month = int.parse(key.substring(5, 7));
      final builder =
          byKey[key] ?? _MonthGroupBuilder(year: year, month: month);
      groups.add(builder.build());
    }
    return groups;
  }
}

class _MonthGroupBuilder {
  final int year;
  final int month;
  double _paid = 0;
  double _pending = 0;
  int _count = 0;

  _MonthGroupBuilder({required this.year, required this.month});

  void add(PaymentModel p) {
    if (p.isPaid) {
      _paid += p.amount;
    } else if (p.paymentStatus == 'Pending') {
      _pending += p.amount;
    }
    _count++;
  }

  _MonthGroup build() => _MonthGroup(
    year: year,
    month: month,
    label: _MonthGroup._label(year, month),
    paidTotal: _paid,
    pendingTotal: _pending,
    count: _count,
  );
}

/// Payment history list. Patient-facing by default: every consultation-fee
/// payment recorded for the logged-in patient (the `payments` table — UPI
/// online or offline pay-at-clinic, written at booking time). Tapping a row
/// opens a details sheet with the full record (transaction id, UPI id,
/// appointment id, …).
///
/// A horizontal filter bar above the list offers **"All"**, a **Custom
/// range** chip (arbitrary date-range picker), and the **"Last 30 days" /
/// "This month"** quick presets — the list, summary and CSV export all
/// scope to the selected range (or all payments under "All"). The
/// summary card's **yearly strip** compares the combined (paid + pending)
/// total for the rolling 12-month window with the **current month's** —
/// always global, unaffected by the filter — but when a range is selected
/// the comparison figure **follows that selected period** (its span +
/// total), so the strip reads "window vs what you're viewing". Both
/// halves are **tappable filter shortcuts**: the window stat resets the
/// filter to "All", the comparison stat jumps to the period it shows (the
/// selected range, or the "This month" preset when nothing is selected).
/// The **Paid / Pending pills** are status-filter shortcuts too: tapping
/// one narrows the list (and CSV export) to that status, composed on top
/// of the selected range — re-tapping the active pill, the "All" chip or
/// the strip's window stat clears it.
///
/// The last filter (custom range, quick preset, status pill, or "All") is
/// **remembered** locally, so reopening the screen restores exactly where
/// the user left off.
///
/// The same screen doubles as the DOCTOR-facing clinic payment history
/// when [loadPayments] is provided: the list then leads with the patient's
/// name instead of the doctor's, and the header/empty text can be
/// customized via [title] / [subtitle] / [emptyMessage].
class PaymentHistoryScreen extends StatefulWidget {
  /// Header title (default: 'Payments').
  final String? title;

  /// Header subtitle (default: 'Your consultation fee records').
  final String? subtitle;

  /// Empty-state body text (default: the patient-flavored message).
  final String? emptyMessage;

  /// Optional data source. When set, the screen loads through it instead
  /// of [PaymentHistoryController] (e.g. a doctor's clinic payments via
  /// [SupabaseService.getPaymentsForDoctor]) and cards show the patient's
  /// name. When null, the patient history controller is used as before.
  final Future<List<PaymentModel>> Function()? loadPayments;

  /// Testability hook: the clock the 12-month chip window is anchored to.
  /// Defaults to [DateTime.now] when null.
  final DateTime Function()? clock;

  const PaymentHistoryScreen({
    super.key,
    this.title,
    this.subtitle,
    this.emptyMessage,
    this.loadPayments,
    this.clock,
  });

  /// Human-readable label for a date range: "10 – 12 Aug 2026" (same
  /// month), "28 Jul – 2 Aug 2026" (cross-month), "28 Dec 2025 – 2 Jan
  /// 2026" (cross-year). Public so tests can cover all three forms.
  static String rangeLabel(DateTimeRange range) {
    final from = range.start;
    final to = range.end;
    final t = '${to.day} ${_MonthGroup.monthAbbrev(to.month)}';
    if (from.year == to.year && from.month == to.month) {
      return '${from.day} – $t ${to.year}';
    }
    final f = '${from.day} ${_MonthGroup.monthAbbrev(from.month)}';
    if (from.year == to.year) return '$f – $t ${to.year}';
    return '$f ${from.year} – $t ${to.year}';
  }

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  PaymentHistoryController? _controller;

  /// Doctor-mode list state (used only when [PaymentHistoryScreen.loadPayments]
  /// is set — the patient path delegates to [PaymentHistoryController]).
  final RxList<PaymentModel> _payments = <PaymentModel>[].obs;
  final RxBool _isLoading = false.obs;

  bool get _isDoctorMode => widget.loadPayments != null;

  /// Custom date-range filter — the only period scope besides "All"
  /// (set by the Custom-range picker or the "Last 30 days" / "This
  /// month" quick presets). Null = all payments.
  DateTimeRange? _customRange;

  /// Status filter ('Paid' | 'Pending') — a third filter axis composed on
  /// top of the month/range scope. Tapping the summary card's pills sets
  /// it; re-tapping the active pill (or choosing "All" / the strip's
  /// window stat) clears it. Null = all statuses.
  String? _selectedStatus;

  /// Whether the persisted filter has been re-applied after the list
  /// loaded. Guards the one-shot restore in the build path against
  /// re-running on every rebuild.
  bool _filterRestored = false;

  /// The full (unfiltered) payment list for computing month groups.
  List<PaymentModel> get _allPayments =>
      _isDoctorMode ? _payments : _controller!.payments;

  /// Anchor for the rolling 12-month window (the screen clock, or real
  /// now).
  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  /// The rolling 12-month window: one group per month, newest first —
  /// the yearly strip's left-hand figure. (No month chips are rendered;
  /// the window is a summary comparison, not a filter.)
  List<_MonthGroup> get _monthGroups =>
      _MonthGroup.buildWindow(_allPayments, _now);

  /// Combined (paid + pending) total across the whole 12-month window —
  /// the "yearly summary" figure, always global (unaffected by the
  /// selected filter).
  double get _windowTotal =>
      _monthGroups.fold(0.0, (sum, g) => sum + g.paidTotal + g.pendingTotal);

  /// Combined (paid + pending) total for the current (anchor) month —
  /// the comparison figure next to the 12-month window total.
  double get _currentMonthTotal {
    final key = _MonthGroup.isoKeyOf(_now);
    for (final g in _monthGroups) {
      if (g.isoKey == key) return g.paidTotal + g.pendingTotal;
    }
    return 0;
  }

  /// Label + combined (paid + pending) total for the yearly strip's
  /// right-hand stat: the ACTIVE filter scope when one is selected (a
  /// custom range's span), so the strip reads "window vs what you're
  /// viewing" instead of a fixed calendar month. Falls back to the
  /// current calendar month when nothing is selected.
  ///
  /// [filtered] is the list the summary card already computed, so the
  /// range total reuses it instead of re-filtering. Note a range may
  /// reach payments OLDER than the 12-month window — the period total
  /// can then exceed the window's left-hand figure; that's the intended
  /// "window vs selected period" comparison.
  (String, double) _stripComparisonFor(List<PaymentModel> filtered) {
    final range = _customRange;
    if (range != null) {
      return (
        PaymentHistoryScreen.rangeLabel(range),
        paidIncomeOf(filtered) + pendingIncomeOf(filtered),
      );
    }
    return ('Current month', _currentMonthTotal);
  }

  /// Filtered payments: the custom date range (or a quick preset's
  /// equivalent), or all payments when no range is set.
  List<PaymentModel> get _filteredPayments {
    final range = _customRange;
    if (range == null) return _allPayments;
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    // Exclusive upper bound (next midnight): microsecond timestamps on
    // the end day are still included.
    final end = DateTime(range.end.year, range.end.month, range.end.day + 1);
    return _allPayments.where((p) {
      final d = p.createdAt ?? p.paidAt;
      return d != null && !d.isBefore(start) && d.isBefore(end);
    }).toList();
  }

  /// The status-filtered view of the scope list: the month/range filter
  /// first, then the selected status pill (Paid / Pending) when one is
  /// active. This is what the list below renders and the CSV exports.
  /// The summary card's totals stay the SCOPE's (see [_buildSummaryCard])
  /// — the pills show the full paid vs pending split regardless.
  List<PaymentModel> get _visiblePayments {
    final status = _selectedStatus;
    if (status == null) return _filteredPayments;
    return _filteredPayments.where((p) => p.paymentStatus == status).toList();
  }

  /// Human label for the active filter scope (a custom range's span), or
  /// null when "All" is selected.
  String? get _scopeLabel {
    final range = _customRange;
    if (range == null) return null;
    return PaymentHistoryScreen.rangeLabel(range);
  }

  /// yyyy-MM-dd (the export filename segment for a custom range).
  String _isoDay(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// Opens the Material date-range picker; applying a range replaces
  /// whatever quick preset or range was active.
  Future<void> _pickCustomRange() async {
    final now = _now;
    var earliest = _allPayments
        .map((p) => p.createdAt ?? p.paidAt)
        .whereType<DateTime>()
        .fold<DateTime>(now, (a, b) => b.isBefore(a) ? b : a);
    // Guard firstDate <= lastDate (a future-dated payment would otherwise
    // make showDateRangePicker assert).
    if (earliest.isAfter(now)) earliest = now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: now,
      // Pin the picker's "today" to the screen clock so tests (and the
      // initial view) are deterministic.
      currentDate: now,
      // Only pass a previous selection when it still fits the picker's
      // bounds — the dialog asserts start < lastDate && end > firstDate,
      // which a saved single-day range ending on the earliest-payment day
      // would violate (end == firstDate), crashing debug builds on reopen.
      initialDateRange: _pickerInitialRange(now, earliest),
      helpText: 'Select payment date range',
      saveText: 'Apply',
    );
    if (range == null || !mounted) return;
    _applyFilter(range: range);
  }

  /// The previously saved range, but only when it still satisfies the
  /// date-picker's constraints (`start < lastDate`, `end > firstDate`)
  /// — [showDateRangePicker] asserts on `initialDateRange` otherwise.
  DateTimeRange? _pickerInitialRange(DateTime now, DateTime earliest) {
    final initial = _customRange;
    if (initial == null) return null;
    final firstDate = DateTime(earliest.year, earliest.month, earliest.day);
    if (!initial.start.isBefore(now) || !initial.end.isAfter(firstDate)) {
      return null;
    }
    return initial;
  }

  /// The "Last 30 days" quick preset: the trailing 30-day window ending
  /// today (day precision, so the chip's selected state is stable across
  /// rebuilds within the same calendar day).
  DateTimeRange get _last30DaysRange {
    final now = _now;
    return DateTimeRange(
      start: DateTime(now.year, now.month, now.day - 30),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  /// The "This month" quick preset: the current calendar month so far
  /// (first of month → today).
  DateTimeRange get _thisMonthRange {
    final now = _now;
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  /// Whether [range] equals the given preset's computed range —
  /// [DateTimeRange] has no `==`, so the bounds are compared by value.
  bool _matchesPreset(DateTimeRange? range, DateTimeRange preset) =>
      range != null && range.start == preset.start && range.end == preset.end;

  /// Applies a period filter (a custom range, or null for "All") and
  /// persists it so reopening the screen restores it. The status pill
  /// filter is left untouched (it composes on top).
  void _applyFilter({DateTimeRange? range}) {
    setState(() => _customRange = range);
    _persistFilter();
  }

  /// Sets (or clears, with null) the status pill filter and persists it —
  /// composed on top of whatever month/range scope is active.
  void _setStatus(String? status) {
    setState(() => _selectedStatus = status);
    _persistFilter();
  }

  /// Toggles the [status] pill filter: tapping the already-active pill
  /// clears it back to "all statuses" (a second tap is the escape hatch).
  void _toggleStatus(String status) {
    _setStatus(_selectedStatus == status ? null : status);
  }

  /// Clears EVERY filter — custom range and status — back to "All"
  /// (used by the All chip and the strip's window stat).
  void _resetFilters() {
    setState(() {
      _customRange = null;
      _selectedStatus = null;
    });
    _persistFilter();
  }

  /// Persists the full current filter state (range, status) under the
  /// single 'payment_history_filter' key.
  void _persistFilter() {
    LocalStorageService().savePaymentHistoryFilter(
      rangeStartIso: _customRange?.start.toIso8601String(),
      rangeEndIso: _customRange?.end.toIso8601String(),
      status: _selectedStatus,
    );
  }

  /// Re-applies the persisted filter (range / status) once the payment
  /// list has loaded. A legacy 'month' key saved by older builds is
  /// deliberately ignored — month chips no longer exist. Each axis
  /// restores independently (they compose). Runs exactly once, guarded by
  /// [_filterRestored].
  void _restoreSavedFilter() {
    final saved = LocalStorageService().getPaymentHistoryFilter();
    if (saved == null) return;
    final startIso = saved['range_start'];
    final endIso = saved['range_end'];
    if (startIso != null && endIso != null) {
      final start = DateTime.tryParse(startIso);
      final end = DateTime.tryParse(endIso);
      // Only reject reversed ranges — a single-day range (end == start)
      // is valid and must restore.
      if (start != null && end != null && !end.isBefore(start)) {
        setState(() => _customRange = DateTimeRange(start: start, end: end));
      }
    }
    final status = saved['status'];
    if (status == 'Paid' || status == 'Pending') {
      setState(() => _selectedStatus = status);
    }
    // An empty saved filter encodes "All" — nothing to restore.
  }

  /// Exports the CURRENTLY FILTERED records (the selected month, a custom
  /// range, or all when "All") as a CSV and opens the system share sheet.
  /// Non-fatal: empty selections and failures surface as a snackbar.
  Future<void> _exportCsv() async {
    final filtered = _visiblePayments;
    final scopeLabel = _scopeLabel;
    final range = _customRange;
    if (filtered.isEmpty) {
      Get.snackbar(
        'Nothing to export',
        scopeLabel != null
            ? 'No payment records in $scopeLabel'
            : 'No payment records to export',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    try {
      final csv = buildPaymentsCsv(
        filtered,
        nameFor: _primaryName,
        // The counterparty column is role-labeled: patients export who
        // they paid (Doctor Name), clinics export who paid them
        // (Patient Name).
        nameColumn: _isDoctorMode ? 'Patient Name' : 'Doctor Name',
      );
      // An active status pill is reflected in the filename + subject so a
      // Pending-only export can't masquerade as the full scope.
      final status = _selectedStatus;
      final statusTag = status == null ? '' : '_${status.toLowerCase()}';
      final filename = range != null
          ? 'payments_${_isoDay(range.start)}_${_isoDay(range.end)}'
                '$statusTag.csv'
          : 'payments_all$statusTag.csv';
      final subjectBase = scopeLabel != null
          ? 'Payment history — $scopeLabel'
          : 'Payment history — all records';
      final subject = status != null ? '$subjectBase · $status' : subjectBase;
      await ShareService.shareCsvFile(
        csv: csv,
        filename: filename,
        subject: subject,
      );
    } catch (_) {
      Get.snackbar(
        'Export failed',
        'Could not share the CSV. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isDoctorMode) {
      _load();
    } else {
      _controller = PaymentHistoryController.instance;
      _controller!.load();
    }
  }

  /// Doctor-mode loader — non-fatal like the patient controller: a failed
  /// load keeps whatever list is already shown.
  Future<void> _load() async {
    _isLoading.value = true;
    try {
      _payments.value = await widget.loadPayments!();
    } catch (_) {
      // Non-fatal — keep whatever we already have.
    } finally {
      _isLoading.value = false;
    }
  }

  /// Cards lead with the patient's name in doctor mode (who the payment
  /// belongs to), the doctor's name on the patient side (who was paid).
  String _primaryName(PaymentModel p) => _isDoctorMode
      ? (p.patientName ?? 'Patient')
      : (p.doctorName ?? 'Consultation');

  Future<void> _refresh() => _isDoctorMode ? _load() : _controller!.load();

  /// dd-MM-yyyy (the app-wide display format).
  String _dateLabel(DateTime time) {
    final d = time.day.toString().padLeft(2, '0');
    final m = time.month.toString().padLeft(2, '0');
    return '$d-$m-${time.year}';
  }

  /// dd-MM-yyyy, hh:mm AM/PM.
  String _dateTimeLabel(DateTime time) {
    final h24 = time.hour;
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final min = time.minute.toString().padLeft(2, '0');
    return '${_dateLabel(time)}, $h12:$min $period';
  }

  /// Color + icon for a payment status — the card's leading badge.
  (IconData, Color) _visualsFor(String status) {
    switch (status) {
      case 'Paid':
        return (Icons.check_circle_rounded, AppColors.success);
      case 'Pending':
        return (Icons.schedule_rounded, AppColors.warning);
      case 'Failed':
        return (Icons.cancel_rounded, AppColors.error);
      case 'Refunded':
        return (Icons.currency_rupee_rounded, AppColors.info);
      default:
        return (Icons.receipt_long_rounded, AppColors.textCaption);
    }
  }

  Color _statusColor(String status) => _visualsFor(status).$2;

  void _showDetails(PaymentModel p) {
    final paidOn = p.paidAt ?? p.createdAt;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _statusColor(p.paymentStatus).withAlpha(20),
                  ),
                  child: Icon(
                    _visualsFor(p.paymentStatus).$1,
                    color: _statusColor(p.paymentStatus),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _primaryName(p),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textHeading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.amountLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(p.paymentStatus),
              ],
            ),
            const SizedBox(height: 20),
            _DetailRow(
              icon: Icons.payments_rounded,
              label: 'Payment method',
              value: p.paymentMethodLabel,
            ),
            if (p.consultationTypeLabel != null)
              _DetailRow(
                icon: Icons.videocam_rounded,
                label: 'Consultation',
                value: p.consultationTypeLabel!,
              ),
            _DetailRow(
              icon: Icons.confirmation_number_rounded,
              label: 'Appointment ID',
              value: p.appointmentId.isEmpty ? '—' : p.appointmentId,
            ),
            if (p.transactionId != null)
              _DetailRow(
                icon: Icons.tag_rounded,
                label: 'Transaction ID',
                value: p.transactionId!,
              ),
            if (p.upiId != null)
              _DetailRow(
                icon: Icons.account_balance_wallet_rounded,
                label: 'UPI ID',
                value: p.upiId!,
              ),
            if (paidOn != null)
              _DetailRow(
                icon: Icons.event_rounded,
                label: p.paidAt != null ? 'Paid on' : 'Recorded on',
                value: _dateTimeLabel(paidOn),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: Get.back,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(70), width: 0.8),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
            _buildGradientHeader(),

            Expanded(
              child: Obx(() {
                final isLoading = _isDoctorMode
                    ? _isLoading.value
                    : _controller!.isLoading.value;
                final payments = _isDoctorMode
                    ? _payments
                    : _controller!.payments;
                // Re-apply the persisted filter once the list has data
                // (runs once per visit — a post-frame setState is
                // required because the builder is mid-build here).
                if (payments.isNotEmpty && !_filterRestored) {
                  _filterRestored = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _restoreSavedFilter();
                  });
                }
                if (isLoading && payments.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  );
                }
                if (payments.isEmpty) {
                  // Pull-to-refresh works here too — a transient load
                  // failure would otherwise show "No payments yet" with
                  // no way to retry short of leaving the screen.
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: AppColors.primary,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: _buildEmptyState(),
                          ),
                        );
                      },
                    ),
                  );
                }
                final filtered = _visiblePayments;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppColors.primary,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    // Summary card + filter bar + each payment row.
                    itemCount: filtered.length + 2,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildSummaryCard();
                      if (index == 1) {
                        return _buildFilterBar();
                      }
                      final payment = filtered[index - 2];
                      return _buildPaymentCard(payment, index - 2);
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(80),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: Get.back,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(25),
                border: Border.all(color: Colors.white.withAlpha(40)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title ?? 'Payments',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  widget.subtitle ?? 'Your consultation fee records',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Share / export the (filtered) payment records as CSV — hidden
          // until there's something to export.
          Obx(() {
            if (_allPayments.isEmpty) return const SizedBox.shrink();
            return Tooltip(
              message: 'Export CSV',
              child: GestureDetector(
                key: const Key('payment_history_export'),
                onTap: _exportCsv,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(25),
                    border: Border.all(color: Colors.white.withAlpha(40)),
                  ),
                  child: const Icon(
                    Icons.ios_share_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  /// Income summary leading the list: the settled (Paid) figure up front
  /// with the outstanding (Pending) amount alongside, so the patient sees
  /// their money picture at a glance. Totals reflect the selected custom
  /// range (or all payments when nothing is selected) — the SCOPE,
  /// regardless of the status pill, so the card always shows the full
  /// paid vs pending split. A yearly strip at the bottom compares the
  /// whole 12-month window's combined total with the current month's —
  /// global, regardless of the filter — but when a range is selected the
  /// comparison figure follows the selected period (its label + combined
  /// total). The Paid/Pending pills are STATUS FILTER shortcuts (see
  /// [_toggleStatus]) that narrow the LIST below without re-scoping
  /// these figures.
  Widget _buildSummaryCard() {
    final filtered = _filteredPayments;
    final paidTotal = paidIncomeOf(filtered);
    final pendingTotal = pendingIncomeOf(filtered);
    // The record count follows the VISIBLE (status-filtered) list so the
    // footer always matches what's rendered below.
    final count = _visiblePayments.length;
    // ' Pending' / ' Paid' appended after the count when a status pill is
    // active — empty when not, so the footer reads '3 payment records'.
    final statusSuffix = _selectedStatus == null ? '' : ' $_selectedStatus';
    final records = count == 1 ? 'record' : 'records';
    final scopeLabel = _scopeLabel;
    final (comparisonLabel, comparisonTotal) = _stripComparisonFor(filtered);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF095E4C)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(70),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                scopeLabel != null
                    ? 'Payment Summary — $scopeLabel'
                    : 'Payment Summary',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withAlpha(190),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '₹${PaymentModel.formatAmount(paidTotal)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'total paid',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSummaryPill(
                label: 'Paid',
                amount: paidTotal,
                color: const Color(0xFF6EE7B7),
                pillKey: const Key('summary_pill_paid'),
                isActive: _selectedStatus == 'Paid',
                onTap: () => _toggleStatus('Paid'),
              ),
              _buildSummaryPill(
                label: 'Pending',
                amount: pendingTotal,
                color: const Color(0xFFFCD34D),
                pillKey: const Key('summary_pill_pending'),
                isActive: _selectedStatus == 'Pending',
                onTap: () => _toggleStatus('Pending'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scopeLabel != null
                ? '$count$statusSuffix payment $records in $scopeLabel'
                : '$count$statusSuffix payment $records',
            style: const TextStyle(fontSize: 11.5, color: Colors.white60),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withAlpha(45), height: 1),
          const SizedBox(height: 12),
          // Yearly summary strip: whole-window total vs current month.
          // Both halves are TAPPABLE filter shortcuts — the left stat
          // resets the filter to "All", the right stat jumps to the
          // period it's showing (the selected range, or the current
          // month when nothing is selected).
          Row(
            children: [
              Expanded(
                child: _buildYearStat(
                  'Last 12 months',
                  _windowTotal,
                  statKey: const Key('year_strip_left'),
                  onTap: _resetFilters,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: Colors.white.withAlpha(45),
              ),
              const SizedBox(width: 12),
              Expanded(
                // The comparison figure follows the selected period (a
                // custom range); "Current month" is the no-filter
                // fallback — NOT "This month", which would collide with
                // the quick-preset chip in the filter bar.
                child: _buildYearStat(
                  comparisonLabel,
                  comparisonTotal,
                  statKey: const Key('year_strip_right'),
                  onTap: _jumpToStripPeriod,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The strip figures are combined — unlike the 'total paid'
          // headline above — so the reader isn't left guessing. The tap
          // hint makes the strip's filter-shortcut role discoverable.
          const Text(
            'Totals include paid + pending · Tap a pill or figure to filter',
            style: TextStyle(fontSize: 10.5, color: Colors.white60),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.08, end: 0);
  }

  /// Horizontal scrollable row of filter chips — "All", the custom-range
  /// chip, and the **"Last 30 days" / "This month" quick presets**.
  /// Selecting a chip filters the list below; ranges (preset or picked)
  /// are mutually exclusive (each replaces the previous one) and "All"
  /// clears everything. Every chip carries a long-press / hover tooltip
  /// describing its action, and taps ripple (Material + InkWell).
  Widget _buildFilterBar() {
    // Cache the preset ranges + their selected state — the getters
    // recompute on every access and each chip needs both twice.
    final last30 = _last30DaysRange;
    final last30Selected = _matchesPreset(_customRange, last30);
    final thisMonth = _thisMonthRange;
    final thisMonthSelected = _matchesPreset(_customRange, thisMonth);
    final presetActive = last30Selected || thisMonthSelected;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // "All" chip — resets every filter (range + status).
          _FilterChip(
            label: 'All',
            tooltip: 'Show all payment records',
            isSelected: _customRange == null && _selectedStatus == null,
            onTap: _resetFilters,
          ),
          // Custom date-range chip — opens the range picker; applying a
          // range replaces whatever preset/range was active. Stays
          // unselected while a quick preset supplies the active range.
          _FilterChip(
            label: 'Custom range',
            tooltip: 'Pick a custom date range',
            sublabel: _customRange != null && !presetActive
                ? PaymentHistoryScreen.rangeLabel(_customRange!)
                : null,
            isSelected: _customRange != null && !presetActive,
            onTap: _pickCustomRange,
          ),
          // "Last 30 days" quick preset — one-tap range shortcut (its
          // span badge shows only while selected, keeping the bar compact).
          _FilterChip(
            label: 'Last 30 days',
            tooltip: 'Show the last 30 days',
            sublabel: last30Selected
                ? PaymentHistoryScreen.rangeLabel(last30)
                : null,
            isSelected: last30Selected,
            onTap: () => _applyFilter(range: last30),
          ),
          // "This month" quick preset — one-tap range shortcut.
          _FilterChip(
            label: 'This month',
            tooltip: "Show this month's records",
            sublabel: thisMonthSelected
                ? PaymentHistoryScreen.rangeLabel(thisMonth)
                : null,
            isSelected: thisMonthSelected,
            onTap: () => _applyFilter(range: thisMonth),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0);
  }

  /// One breakdown pill on the summary card ('Paid ₹12500' / 'Pending
  /// ₹3000'). When [onTap] is given the pill becomes a STATUS FILTER
  /// shortcut: tapping it narrows the list to that status (re-tapping the
  /// active one clears it), and [isActive] highlights it with a check.
  /// The amount always shows the SCOPE's split — the pill filters the
  /// list without re-scoping the summary figures. [pillKey] (used by
  /// tests to tap the pill) is only honored when [onTap] is set.
  Widget _buildSummaryPill({
    required String label,
    required double amount,
    required Color color,
    Key? pillKey,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? color.withAlpha(60) : Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive ? color.withAlpha(230) : color.withAlpha(120),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) ...[
            Icon(Icons.check_rounded, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            '$label ₹${PaymentModel.formatAmount(amount)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        key: pillKey,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: pill,
        ),
      ),
    );
  }

  /// One half of the yearly summary strip at the bottom of the summary
  /// card: a label over its combined (paid + pending) amount. When
  /// [onTap] is given the half becomes tappable (transparent Material +
  /// InkWell so the ripple shows over the card's gradient) — the strip
  /// then doubles as a filter shortcut: the left half resets to All, the
  /// right half jumps to the period it shows. [statKey] (used by tests to
  /// tap the half) is only honored when [onTap] is set — a key passed to
  /// a non-tappable stat is ignored.
  Widget _buildYearStat(
    String label,
    double amount, {
    Key? statKey,
    VoidCallback? onTap,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(190)),
        ),
        const SizedBox(height: 3),
        Text(
          '₹${PaymentModel.formatAmount(amount)}',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: Material(
        key: statKey,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: content,
          ),
        ),
      ),
    );
  }

  /// Applies the period the yearly strip's RIGHT stat represents, so
  /// tapping it jumps straight into what it's showing: the active custom
  /// range when one is selected (a harmless re-apply), or the "This
  /// month" preset when nothing is — the "window vs current month"
  /// comparison becomes the actual filter.
  void _jumpToStripPeriod() {
    final range = _customRange;
    if (range != null) {
      _applyFilter(range: range);
      return;
    }
    _applyFilter(range: _thisMonthRange);
  }

  Widget _buildPaymentCard(PaymentModel p, int index) {
    final (icon, color) = _visualsFor(p.paymentStatus);
    final paidOn = p.paidAt ?? p.createdAt;
    return Material(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showDetails(p),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withAlpha(45), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(6),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Leading status badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: color.withAlpha(22),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  // Doctor + meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _primaryName(p),
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textHeading,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              p.amountLabel,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textHeading,
                              ),
                            ),
                          ],
                        ),
                        if (p.consultationTypeLabel != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            p.consultationTypeLabel!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textBody,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (paidOn != null)
                              _buildMetaChip(
                                icon: Icons.event_rounded,
                                label: _dateLabel(paidOn),
                                color: AppColors.textCaption,
                              ),
                            _buildMetaChip(
                              icon: p.paymentMethod == 'online'
                                  ? Icons.account_balance_wallet_rounded
                                  : Icons.storefront_rounded,
                              label: p.paymentMethodLabel,
                              color: p.paymentMethod == 'online'
                                  ? AppColors.info
                                  : AppColors.secondary,
                            ),
                            _buildStatusChip(p.paymentStatus),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms, delay: (index * 80).ms)
        .slideY(begin: 0.1, end: 0, duration: 300.ms);
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(55), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withAlpha(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            // The clinic empty state is doctor-flavored: the doctor sees
            // the fee perspective, the patient the payment one.
            _isDoctorMode ? 'No fees collected yet' : 'No payments yet',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textHeading,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              widget.emptyMessage ??
                  // Doctor side: fees the CLINIC receives. (app.dart no
                  // longer passes this — the screen owns the doctor
                  // default so both entry points can never drift.)
                  (_isDoctorMode
                      ? 'Consultation fees from your patients — online via '
                            'UPI or offline at the clinic — will show up '
                            'here as they book and settle.'
                      : 'Consultation fees you pay — online via UPI or offline '
                            'at the clinic — will show up here after you book '
                            'an appointment.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textCaption,
                height: 1.5,
              ),
            ),
          ),
          // Doctor-only call to action: jump back to the (already-open)
          // dashboard shell's Appointments tab, where the bookings these
          // fees come from are managed. Hidden on the patient side.
          if (_isDoctorMode) ...[
            const SizedBox(height: 24),
            _buildViewAppointmentsCta(),
          ],
        ],
      ),
    );
  }

  /// The "View Appointments" call to action on the doctor empty state —
  /// mirrors the patient appointment history's pill (icon tile + label +
  /// chevron) so the two empty states share one visual family.
  Widget _buildViewAppointmentsCta() {
    return GestureDetector(
          key: const ValueKey('doctor_payment_empty_cta'),
          onTap: _goToAppointments,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withAlpha(50)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(20),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.event_available_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'View Appointments',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: AppColors.primary.withAlpha(150),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 600.ms, delay: 200.ms)
        .slideY(begin: 0.1, end: 0, duration: 400.ms);
  }

  /// Pops back to the dashboard shell already beneath this screen and
  /// switches it to the Appointments tab (where fees get settled). Safe
  /// when no shell is mounted (e.g. widget tests): the switch is a no-op
  /// and the back is a no-op on a root route.
  void _goToAppointments() {
    DoctorMainShell.switchToTab(DoctorMainShell.appointmentsTab);
    Get.back();
  }
}

/// A selectable filter chip in the horizontal filter bar (All / Custom
/// range / quick presets). Taps ripple (Material + InkWell, like the rest
/// of the bar) and a long-press / hover [Tooltip] explains what the chip
/// does.
class _FilterChip extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool isSelected;
  final VoidCallback onTap;

  /// Help text shown on long-press (mobile) / hover (desktop) — what the
  /// chip does. The tap still lands on the [InkWell], so the ripple and
  /// the filter action are unaffected.
  final String tooltip;

  const _FilterChip({
    required this.label,
    this.sublabel,
    required this.isSelected,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        // Snappier than the default 1.5s so the hint feels responsive on
        // long-press and hover.
        waitDuration: const Duration(milliseconds: 500),
        child: Semantics(
          // InkWell already announces the chip as a button; this adds
          // the selected state so screen readers hear which chip is
          // active (parity with the summary pills).
          selected: isSelected,
          child: Material(
            color: isSelected ? AppColors.primary : AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textCaption.withAlpha(35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textHeading,
                      ),
                    ),
                    if (sublabel != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withAlpha(25)
                              : AppColors.primary.withAlpha(12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sublabel!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white.withAlpha(220)
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textCaption,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
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
