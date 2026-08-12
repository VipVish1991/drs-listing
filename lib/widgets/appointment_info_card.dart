import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/appointment_model.dart';
import 'prescription_gallery.dart';

/// Shared appointment-card header: soft avatar circle with initials + name
/// + a status line (icon + text) BELOW the name. Used by BOTH the doctor's
/// Appointments tab and the patient's My Appointments cards so the two
/// sides render pixel-identical headers.
class AppointmentCardHeader extends StatelessWidget {
  final String name;
  final String statusLabel;
  final IconData statusIcon;
  final Color statusColor;
  final String avatarInitials;
  final Color avatarColor;

  const AppointmentCardHeader({
    super.key,
    required this.name,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusColor,
    required this.avatarInitials,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarColor,
            border: Border.all(color: statusColor.withAlpha(50), width: 2),
          ),
          child: Center(
            child: Text(
              avatarInitials,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: statusColor.withAlpha(200),
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
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHeading,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(statusIcon, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-width info row data for the shared card body — one labelled,
/// icon-led row below the 2-column grid (e.g. the cards' "Consultation"
/// type where the phone used to be).
class AppointmentInfoBlock {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const AppointmentInfoBlock({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  /// The consultation-type row every card shows (patient card, doctor
  /// Appointments tab, patient-history timeline): "Consultation" with the
  /// booking's [AppointmentModel.consultationTypeLabel] and a storefront /
  /// videocam icon. Returns `null` for legacy rows without a stored type,
  /// so all three card sites stay in lockstep without duplicating the
  /// label/icon/color mapping.
  static AppointmentInfoBlock? consultationOf(AppointmentModel a) {
    final label = a.consultationTypeLabel;
    if (label == null) return null;
    return AppointmentInfoBlock(
      label: 'Consultation',
      value: label,
      icon: consultationIconOf(a),
      color: AppColors.info,
    );
  }

  /// The icon for a consultation type — storefront for in-clinic visits,
  /// videocam for tele/video. Shared by the card rows and the details
  /// sheet's header chip so the mapping never drifts.
  static IconData consultationIconOf(AppointmentModel a) =>
      a.consultationType == 'clinic'
      ? Icons.storefront_rounded
      : Icons.videocam_rounded;
}

/// Shared appointment-card layout used by the doctor's Appointments tab
/// (`DoctorAppointmentsScreen`), the patient's My Appointments screen
/// (`AppointmentCard`) and the doctor-side patient-history timeline
/// (`PatientHistoryScreen`).
///
/// Owns the card shell (bgCard, rounded corners, shadow, optional
/// status-colored accent bar / border), the optional header + divider
/// area, and the standard body: an optional status pill, a 2-column info
/// grid (Date / Time in soft tinted blocks so nothing is squeezed or
/// truncated on narrow screens) with optional full-width info rows
/// below it (consultation / patient phone — see [AppointmentInfoBlock]),
/// an optional extra full-width row, Symptoms, the prescription section
/// (compact thumbnail strip or the new "Click" row) and an optional
/// action row.
///
/// Screen-specific chrome (the timeline's Visit # / Current chips) is
/// passed in via [header] / [actions], keeping this widget the single
/// source of truth for the shared card body.
class AppointmentInfoCard extends StatelessWidget {
  final AppointmentModel appointment;

  /// Card tap (opens details). `null` → the card is not tappable.
  final VoidCallback? onTap;

  /// When set, a full-height status-colored accent bar renders on the
  /// card's left edge (appointment-list look).
  final Color? accentColor;

  /// Card outline color (patient-history "current visit" highlight).
  /// `null` → no border.
  final Color? borderColor;
  final double borderWidth;

  /// Custom header (appointment lists: [AppointmentCardHeader]; history:
  /// the Visit # / Current chips).
  final Widget? header;

  /// When true a full-width status pill (icon + status text) renders
  /// above the info grid (patient-history timeline look).
  final bool showStatusPill;
  final String? displayStatus;
  final Color statusColor;
  final IconData? statusIcon;

  /// Extra row inserted after the info grid (e.g. the patient card's
  /// pending-confirmation banner).
  final Widget? extraRow;

  /// Full-width info rows below the grid (see [AppointmentInfoBlock]) —
  /// e.g. the doctor card's / patient card's "Consultation" type in the
  /// phone's former spot, or the history timeline's single Consultation
  /// row. Rendered top-to-bottom in list order.
  final List<AppointmentInfoBlock> infoBlocks;

  /// When true the prescription section renders as the "Click" row (label
  /// + first thumbnail + a light-green Click pill opening the fullscreen
  /// viewer) — the shared appointment-list look. When false it renders
  /// the compact thumbnail strip (patient-history timeline look).
  final bool prescriptionClickRow;

  /// Action buttons (a `Wrap` of chips). `null` → none.
  final Widget? actions;

  /// When set, tapping a prescription thumbnail on this card invokes this
  /// with the tapped image's index (within the appointment's own
  /// prescription list) instead of the default per-gallery viewer — e.g.
  /// the patient-history timeline opens the shared swipeable
  /// all-prescriptions gallery at that image.
  final void Function(int index)? onPrescriptionThumbnailTap;

  /// Whether the appointment's symptoms block renders on the card. The
  /// history timeline shows it; the appointment-list cards keep symptoms
  /// inside the details sheet only.
  final bool showSymptoms;

  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double shadowBlur;
  final int shadowAlpha;

  const AppointmentInfoCard({
    super.key,
    required this.appointment,
    this.onTap,
    this.accentColor,
    this.borderColor,
    this.borderWidth = 1,
    this.header,
    this.showStatusPill = false,
    this.displayStatus,
    required this.statusColor,
    this.statusIcon,
    this.extraRow,
    this.infoBlocks = const [],
    this.prescriptionClickRow = false,
    this.actions,
    this.onPrescriptionThumbnailTap,
    this.showSymptoms = false,
    this.borderRadius = 18,
    this.padding = const EdgeInsets.all(16),
    this.shadowBlur = 10,
    this.shadowAlpha = 6,
  });

  @override
  Widget build(BuildContext context) {
    Widget inner = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildBody(context),
      ),
    );

    if (onTap != null) {
      inner = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: inner,
        ),
      );
    }

    if (accentColor != null) {
      // CrossAxisAlignment.stretch (not the Row default) so the accent
      // bar actually fills the card's full height under IntrinsicHeight.
      inner = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(borderRadius),
                  bottomLeft: Radius.circular(borderRadius),
                ),
              ),
            ),
            Expanded(child: inner),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(shadowAlpha),
            blurRadius: shadowBlur,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: inner,
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    final a = appointment;
    final children = <Widget>[];

    void gap() => children.add(const SizedBox(height: 12));
    void gapLarge() => children.add(const SizedBox(height: 14));

    if (header != null) {
      children.add(header!);
    }

    if (showStatusPill && displayStatus != null && displayStatus!.isNotEmpty) {
      gap();
      children.add(
        _buildPill(
          statusIcon ?? Icons.info_outline_rounded,
          displayStatus!,
          statusColor,
        ),
      );
    }

    // ── 2-column info grid: Date / Time ── (the consultation type now
    // renders as the card's full-width info row below — the phone's
    // former spot on the patient card — so it is easy to read.)
    final blocks = <Widget>[];
    if ((a.displayDate ?? '').isNotEmpty) {
      blocks.add(
        _InfoBlock(
          icon: Icons.calendar_month_rounded,
          color: AppColors.primary,
          label: 'Date',
          value: a.displayDate!,
        ),
      );
    }
    if ((a.appointmentTime ?? '').isNotEmpty) {
      blocks.add(
        _InfoBlock(
          icon: Icons.access_time_rounded,
          color: AppColors.accent,
          label: 'Time',
          value: a.appointmentTime!,
        ),
      );
    }
    if (blocks.isNotEmpty) {
      gap();
      children.add(_buildInfoGrid(blocks));
    }
    // The full-width info rows (each spans the whole card, not a half-
    // width grid cell) — each side passes whatever it wants here: the
    // doctor card's / patient card's consultation type.
    for (final block in infoBlocks) {
      gap();
      children.add(
        SizedBox(
          width: double.infinity,
          child: _InfoBlock(
            icon: block.icon,
            color: block.color,
            label: block.label,
            value: block.value,
          ),
        ),
      );
    }

    if (extraRow != null) {
      gap();
      children.add(extraRow!);
    }

    if (showSymptoms && (a.symptoms ?? '').trim().isNotEmpty) {
      gap();
      children.add(_buildSymptomsBox(a.symptoms!));
    }

    if (a.prescriptionUrls.isNotEmpty) {
      gapLarge();
      children.add(
        prescriptionClickRow
            ? _buildPrescriptionClickRow(context, a)
            : PrescriptionGallery(
                urls: a.prescriptionUrls,
                compact: true,
                onThumbnailTap: onPrescriptionThumbnailTap == null
                    ? null
                    : (context, index) => onPrescriptionThumbnailTap!(index),
              ),
      );
    }

    if (actions != null) {
      gapLarge();
      children.add(actions!);
    }

    return children;
  }

  /// Two-column grid of [blocks]: each row holds two half-width cells (or
  /// one half-width cell + an empty spacer when the count is odd). Plain
  /// Rows are used (no LayoutBuilder) so the card still works inside the
  /// timeline's IntrinsicHeight wrapper — LayoutBuilder cannot report
  /// intrinsic dimensions.
  Widget _buildInfoGrid(List<Widget> blocks) {
    final rows = <Widget>[];
    for (var i = 0; i < blocks.length; i += 2) {
      final first = blocks[i];
      final second = i + 1 < blocks.length ? blocks[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second ?? const SizedBox.shrink()),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }

  /// Prescription section in the shared appointment-list look: a label row
  /// (folder icon + "Prescription") over a row with the first 9:16
  /// thumbnail on the left and a light-green "Click" pill (with chevron)
  /// on the right — both open the swipeable fullscreen viewer.
  Widget _buildPrescriptionClickRow(BuildContext context, AppointmentModel a) {
    final urls = a.prescriptionUrls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.folder_open_rounded,
              size: 15,
              color: AppColors.accent,
            ),
            const SizedBox(width: 6),
            Text(
              urls.length == 1
                  ? 'Prescription'
                  : 'Prescriptions (${urls.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : AppColors.textCaption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            GestureDetector(
              onTap: () => _openViewer(context, a, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  urls.first,
                  width: 54,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _thumbPlaceholder(),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return _thumbPlaceholder();
                  },
                ),
              ),
            ),
            const Spacer(),
            Material(
              color: AppColors.success.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openViewer(context, a, 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        // Matches the reference card's uppercase pill copy.
                        'CLICK',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openViewer(BuildContext context, AppointmentModel a, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrescriptionViewer(urls: a.prescriptionUrls, initialIndex: index),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 54,
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.accent.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(
          Icons.image_rounded,
          color: AppColors.textDisabled,
          size: 24,
        ),
      ),
    );
  }

  /// Full-width tinted pill (status pill in the history timeline).
  Widget _buildPill(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Full-width symptoms note box (history timeline look).
  Widget _buildSymptomsBox(String symptoms) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withAlpha(25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notes_rounded, size: 16, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              symptoms,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft tinted cell of the card's 2-column info grid — icon box + label
/// above a bold value (the shared appointment-list look).
class _InfoBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _InfoBlock({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withAlpha(18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textCaption.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHeading,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
