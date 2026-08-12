import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/models/appointment_model.dart';
import 'package:DrsListing/widgets/appointment_info_card.dart';

import '../helpers/golden_fonts.dart';
import '../helpers/test_data.dart';

// ════════════════════════════════════════════════════════════════════
// Golden-image tests for the shared AppointmentInfoCard — the single
// source of truth for the full-width card layout used by BOTH the
// doctor's Appointments tab and the patient-history timeline.
//
// These goldens replace manual on-device layout verification: any change
// that alters the card's geometry, spacing, or typography (or reintroduces
// an overflow) fails the pixel comparison immediately, without needing a
// phone. Regenerate with:
//
//   flutter test --update-goldens test/widgets/appointment_info_card_golden_test.dart
//
// NOTE: goldens are platform-sensitive (font hinting/antialiasing differs
// across OSes), so the committed PNGs must be regenerated on the platform
// that runs them (here: Windows).
// ════════════════════════════════════════════════════════════════════

// Real fonts are loaded ONLY for this file (via [loadRealFonts] in
// setUpAll) so the goldens capture actual glyphs instead of the Ahem
// placeholder. Every other test keeps the default wide-block Ahem font —
// that strictness is what makes the existing 320px overflow regression
// tests catch layout bugs, so it must NOT be weakened globally.

// Fixed logical surface — 390dp iPhone-ish width with plenty of height so
// the tallest card (pending + actions + gallery) renders fully.
const Size _surface = Size(390, 1000);

Color _statusColor(String status) {
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

IconData _statusIcon(String status) {
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

String _initials(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'D';
}

/// Mirrors `_ModernAppointmentCard`'s shared [AppointmentCardHeader] —
/// avatar circle + name + status icon/text row.
Widget _doctorHeader(
  AppointmentModel a,
  String displayStatus,
  Color statusColor,
  IconData statusIcon,
) {
  return AppointmentCardHeader(
    name: a.patientName ?? 'Patient',
    statusLabel: displayStatus,
    statusIcon: statusIcon,
    statusColor: statusColor,
    avatarInitials: _initials(a.patientName ?? 'Patient'),
    avatarColor: const Color(0xFFE8EAF5),
  );
}

/// Mirrors `_ModernActionBtn` from the doctor's Appointments screen.
Widget _actionBtn(
  String label,
  IconData icon,
  Color color, {
  bool isPrimary = false,
}) {
  return Material(
    color: isPrimary ? color : color.withAlpha(15),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The doctor Appointments-tab card exactly as `_ModernAppointmentCard`
/// composes it (accent bar, avatar header, divider, consultation row,
/// actions).
Widget _doctorCard(
  AppointmentModel a, {
  required String displayStatus,
  bool isFinalized = false,
}) {
  final statusColor = _statusColor(displayStatus);
  final statusIcon = _statusIcon(displayStatus);
  return AppointmentInfoCard(
    appointment: a,
    onTap: () {},
    accentColor: statusColor,
    borderRadius: 20,
    padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
    shadowBlur: 16,
    shadowAlpha: 8,
    header: _doctorHeader(a, displayStatus, statusColor, statusIcon),
    displayStatus: displayStatus,
    statusColor: statusColor,
    statusIcon: statusIcon,
    infoBlocks: [?AppointmentInfoBlock.consultationOf(a)],
    prescriptionClickRow: true,
    actions: isFinalized
        ? null
        : Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 8,
            children: [
              _actionBtn('Cancel', Icons.close_rounded, AppColors.error),
              if (displayStatus == AppointmentStatus.pending)
                _actionBtn(
                  'Confirm',
                  Icons.check_circle_rounded,
                  AppColors.primary,
                  isPrimary: true,
                )
              else
                _actionBtn(
                  'Mark Completed',
                  Icons.check_circle_rounded,
                  AppColors.success,
                  isPrimary: true,
                ),
            ],
          ),
  );
}

/// The patient-history timeline entry exactly as `_buildTimelineEntry`
/// composes it: IntrinsicHeight Row with a 26px rail (node + connector)
/// on the left and the shared card on the right (Visit chips header,
/// status pill, symptoms, border).
Widget _historyCard(
  AppointmentModel a, {
  required int index,
  required bool isCurrent,
}) {
  final statusColor = _statusColor(a.status);
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline rail: node + connector (mirrors the history screen).
        SizedBox(
          width: 26,
          child: Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  border: Border.all(
                    color: statusColor.withAlpha(60),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(color: statusColor.withAlpha(45), blurRadius: 8),
                  ],
                ),
              ),
              Expanded(
                child: Container(width: 2, color: statusColor.withAlpha(25)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppointmentInfoCard(
            appointment: a,
            onTap: () {},
            borderColor: isCurrent
                ? AppColors.primary.withAlpha(90)
                : AppColors.textDisabled.withAlpha(22),
            borderWidth: isCurrent ? 1.6 : 1,
            shadowBlur: isCurrent ? 16 : 10,
            shadowAlpha: isCurrent ? 12 : 6,
            header: _visitChips(index, isCurrent),
            showStatusPill: true,
            displayStatus: a.status,
            statusColor: statusColor,
            statusIcon: _statusIcon(a.status),
            // Mirrors `_buildTimelineEntry` — consultation type as the
            // card's full-width row, hidden for legacy rows.
            infoBlocks: [?AppointmentInfoBlock.consultationOf(a)],
            showSymptoms: true,
          ),
        ),
      ],
    ),
  );
}

/// Visit # + optional Current chips — mirrors `_buildVisitChips`.
Widget _visitChips(int index, bool isCurrent) {
  return Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: 8,
    runSpacing: 6,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isCurrent
              ? AppColors.primary.withAlpha(16)
              : AppColors.bgSecondarySurface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isCurrent
                ? AppColors.primary.withAlpha(45)
                : AppColors.textCaption.withAlpha(30),
          ),
        ),
        child: Text(
          'Visit ${index + 1}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isCurrent ? AppColors.primary : AppColors.textCaption,
          ),
        ),
      ),
      if (isCurrent)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withAlpha(50)),
          ),
          child: const Text(
            'Current',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
    ],
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  Size surface = _surface,
  Color background = AppColors.bgMain,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: background,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: card,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('doctor pending card golden', (tester) async {
    final a = appointmentBasic(
      appointmentId: 'APT_G1',
      patientName: 'Rahul Sharma',
      patientPhone: '9898989898',
      appointmentDate: '2026-08-08',
      appointmentTime: '2:00 PM',
      status: AppointmentStatus.pending,
      consultationType: 'video',
      symptoms: 'Fever and body ache since yesterday',
      prescriptionUrls: const ['https://example.com/rx1.jpg'],
    );
    await _pumpCard(tester, _doctorCard(a, displayStatus: a.status));
    await expectLater(
      find.byType(AppointmentInfoCard),
      matchesGoldenFile('goldens/appointment_info_card_doctor_pending.png'),
    );
  });

  testWidgets('doctor completed card golden (no actions)', (tester) async {
    final a = appointmentBasic(
      appointmentId: 'APT_G2',
      patientName: 'Priya Verma',
      patientPhone: '9812345678',
      appointmentDate: '2026-08-06',
      appointmentTime: '9:30 AM',
      status: AppointmentStatus.completed,
      consultationType: 'clinic',
      prescriptionUrls: const [
        'https://example.com/rx1.jpg',
        'https://example.com/rx2.jpg',
      ],
    );
    await _pumpCard(
      tester,
      _doctorCard(a, displayStatus: a.status, isFinalized: true),
    );
    await expectLater(
      find.byType(AppointmentInfoCard),
      matchesGoldenFile('goldens/appointment_info_card_doctor_completed.png'),
    );
  });

  testWidgets('history current-visit card golden', (tester) async {
    final a = appointmentBasic(
      appointmentId: 'APT_G3',
      patientName: 'Reena',
      patientPhone: '9898989898',
      appointmentDate: '2026-08-08',
      appointmentTime: '2:00 PM',
      status: AppointmentStatus.completed,
      consultationType: 'video',
      symptoms: 'Recurring migraine with nausea',
      prescriptionUrls: const [
        'https://example.com/rx1.jpg',
        'https://example.com/rx2.jpg',
      ],
    );
    await _pumpCard(tester, _historyCard(a, index: 2, isCurrent: true));
    await expectLater(
      find.byType(AppointmentInfoCard),
      matchesGoldenFile('goldens/appointment_info_card_history_current.png'),
    );
  });

  testWidgets('history upcoming card golden (no prescription)', (tester) async {
    final a = appointmentBasic(
      appointmentId: 'APT_G4',
      patientName: 'Reena',
      patientPhone: '9898989898',
      appointmentDate: '2026-08-10',
      appointmentTime: '9:30 AM',
      status: AppointmentStatus.upcoming,
      consultationType: 'clinic',
      symptoms: 'Follow-up visit',
    );
    await _pumpCard(tester, _historyCard(a, index: 4, isCurrent: false));
    await expectLater(
      find.byType(AppointmentInfoCard),
      matchesGoldenFile('goldens/appointment_info_card_history_upcoming.png'),
    );
  });

  testWidgets('doctor card golden on a narrow 320dp screen', (tester) async {
    // The width class that previously overflowed — the golden locks the
    // full-width treatment so nothing is ever squeezed again.
    final a = appointmentBasic(
      appointmentId: 'APT_G5',
      patientName: 'Vippp Kumar',
      patientPhone: '9876543210',
      appointmentDate: '2026-08-08',
      appointmentTime: '10:30 AM',
      status: AppointmentStatus.pending,
      consultationType: 'video',
      prescriptionUrls: const ['https://example.com/rx1.jpg'],
    );
    await _pumpCard(
      tester,
      _doctorCard(a, displayStatus: a.status),
      surface: const Size(320, 1000),
    );
    await expectLater(
      find.byType(AppointmentInfoCard),
      matchesGoldenFile('goldens/appointment_info_card_doctor_narrow.png'),
    );
  });
}
