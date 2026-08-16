import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../models/doctor_model.dart';
import '../../models/doctor_slot_model.dart';
import '../../models/unavailable_range.dart';
import '../../services/launch_service.dart';
import '../../services/places_service.dart';
import '../../services/share_service.dart';
import '../../utils/extensions.dart';
import '../../utils/snackbar_helpers.dart';
import '../../widgets/doctor_avatar.dart';
import '../../widgets/doctor_mini_map.dart';
import '../../widgets/photo_gallery_card.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/doctor_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../models/user_model.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/time_slot_generator.dart';

/// Modern, fully scrollable Doctor Detail screen with a parallax header,
/// floating action buttons, and a sticky bottom bar.
class DoctorDetailScreen extends StatefulWidget {
  const DoctorDetailScreen({super.key});

  @override
  State<DoctorDetailScreen> createState() => _DoctorDetailScreenState();
}

class _DoctorDetailScreenState extends State<DoctorDetailScreen> {
  /// Resolves the doctor shown by this screen from either navigation shape:
  ///   - full object:  arguments: {'doctor': DoctorModel}  (search / saved)
  ///   - minimal:      arguments: {'placeId': ..., 'doctorName': ...}
  ///                   (appointment history — no DoctorModel available)
  /// The screen fetches full details by placeId on load, so the minimal
  /// shape is enough to bootstrap without a `Null` cast crash.
  late final DoctorModel _initialDoctor = _resolveInitialDoctor();
  final PlacesService _placesService = PlacesService();
  final ScrollController _scrollController = ScrollController();

  DoctorModel _resolveInitialDoctor() {
    final args = Get.arguments;
    if (args is Map && args['doctor'] is DoctorModel) {
      return args['doctor'] as DoctorModel;
    }
    // Appointment-history navigation passes only placeId + doctorName.
    final placeId = args is Map ? (args['placeId']?.toString() ?? '') : '';
    final name = args is Map ? (args['doctorName']?.toString() ?? '') : '';
    return DoctorModel(placeId: placeId, name: name.isEmpty ? 'Doctor' : name);
  }

  static const double _kExpandedHeight = 240; // smaller hero

  late DoctorModel _doctor;
  bool _isLoading = true;
  bool _detailsFailed = false;
  bool _isCollapsed = false;

  /// Doctor-set unavailable date ranges (from the doctors table).
  List<UnavailableRange> _unavailableRanges = const [];

  /// The doctor's weekly availability slots (available time slots).
  List<DoctorSlot> _weeklySlots = const [];

  @override
  void initState() {
    super.initState();
    _doctor = _initialDoctor;
    _scrollController.addListener(_onScroll);
    _fetchDetails();
    _loadAvailability();
  }

  /// Fetches the doctor's availability from the DB: the unavailable date
  /// ranges (doctors table) and the weekly slot schedule (doctor_slots) so
  /// patients can see both in the profile and book accordingly.
  Future<void> _loadAvailability() async {
    try {
      final dbDoctor = await SupabaseService().getDoctorFromDb(
        _initialDoctor.placeId,
      );
      final slots = await SupabaseService().getDoctorSlots(
        _initialDoctor.placeId,
      );
      if (mounted) {
        setState(() {
          _unavailableRanges =
              dbDoctor?.unavailableRanges ?? const <UnavailableRange>[];
          _weeklySlots = slots;
          // Merge doctor-set fields from the DB row (upiId, availability)
          // into the shown doctor — Places search never returns them, and
          // the model is what gets passed to the booking screen when the
          // patient taps Book Appointment.
          if (dbDoctor != null) {
            _doctor = DoctorController.mergeDoctorSetFields(
              _doctor,
              dbDoctor,
              _doctor.userId,
            );
          }
        });
      }
    } catch (_) {
      // Non-fatal — the card just shows nothing when availability can't load.
    }
  }

  void _onScroll() {
    final collapsed =
        _scrollController.hasClients &&
        _scrollController.offset > (_kExpandedHeight - kToolbarHeight);
    if (collapsed != _isCollapsed) {
      setState(() => _isCollapsed = collapsed);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    setState(() => _isLoading = true);
    try {
      final details = await _placesService.getDoctorDetails(
        _initialDoctor.placeId,
      );
      if (details != null && mounted) {
        setState(() {
          _doctor = details.copyWith(
            distance: _initialDoctor.distance,
            experienceYears: _initialDoctor.experienceYears,
            symptomsMap: _initialDoctor.symptomsMap,
            // Preserve the DB-merged UPI VPA set by _loadAvailability —
            // the Places model never carries it, and this setState can
            // land after the availability merge (both start from
            // initState, so ordering is not guaranteed).
            upiId: _doctor.upiId,
          );
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _detailsFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Google Places photos — try to load if photo reference is available
    final heroImage = _doctor.photos.isNotEmpty
        ? PlacesService().getPhotoUrl(_doctor.photos.first, maxWidth: 800)
        : null;

    // Color that adapts based on whether the app bar is collapsed.
    final Color appBarFgColor = _isCollapsed
        ? (isDark ? Colors.white : Colors.black)
        : Colors.white;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: _isLoading
          ? _buildLoadingSkeleton(isDark)
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                // ─── Sliver App Bar with Parallax Hero ───
                SliverAppBar(
                  expandedHeight: _kExpandedHeight,
                  pinned: true,
                  floating: false,
                  backgroundColor: _isCollapsed
                      ? (isDark ? const Color(0xFF1A1A2E) : Colors.white)
                      : Colors.transparent,
                  elevation: _isCollapsed ? 2 : 0,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        heroImage != null
                            ? Image.network(
                                heroImage,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _heroGradientFallback(),
                              )
                            : _heroGradientFallback(),
                        // Gradient overlay
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withAlpha(70),
                                Colors.transparent,
                                Colors.black.withAlpha(80),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      _doctor.name,
                      style: TextStyle(
                        color: appBarFgColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    centerTitle: true,
                  ),
                  leading: _GlassIconButton(
                    icon: Icons.arrow_back_ios_new,
                    iconColor: appBarFgColor,
                    onTap: () => Get.back(),
                  ),
                  actions: [
                    Obx(() {
                      final pc = Get.find<ProfileController>();
                      final isSaved = pc.isDoctorSaved(_doctor.placeId);
                      return _GlassIconButton(
                        icon: isSaved ? Icons.favorite : Icons.favorite_border,
                        iconColor: isSaved
                            ? AppColors.healthHeart
                            : appBarFgColor,
                        onTap: () async {
                          final nowFav = await pc.toggleFavorite(_doctor);
                          if (nowFav) {
                            showSuccessSnackbar('Doctor saved to favorites');
                          } else {
                            showSuccessSnackbar(
                              'Doctor removed from favorites',
                            );
                          }
                        },
                      );
                    }),
                  ],
                ),

                // ─── Main Content ───
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 50),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Identity block (name, specialization, location, stats)
                      _buildIdentityBlock(isDark),
                      const SizedBox(height: 24),
                      // Quick Actions
                      _QuickActionsRow(doctor: _doctor),
                      const SizedBox(height: 20),
                      // Location Mini-Map
                      if (_doctor.latitude != null &&
                          _doctor.longitude != null) ...[
                        _LocationMapCard(doctor: _doctor, isDark: isDark),
                        const SizedBox(height: 20),
                      ],
                      if (_detailsFailed) _buildRefreshBanner(),
                      // About
                      if (_doctor.editorialSummary?.isNotEmpty ?? false) ...[
                        _AboutCard(doctor: _doctor, isDark: isDark),
                        const SizedBox(height: 20),
                      ],
                      // Business Chips
                      if (_doctor.businessStatus != null ||
                          _doctor.priceLevel != null ||
                          _doctor.plusCode != null ||
                          _doctor.vicinity != null ||
                          _doctor.distance != null) ...[
                        _BusinessChipsCard(doctor: _doctor, isDark: isDark),
                        const SizedBox(height: 20),
                      ],
                      // Contact
                      _ContactCard(doctor: _doctor, isDark: isDark),
                      const SizedBox(height: 20),
                      // UPI Payment ID — shown when the doctor has set a
                      // receiving VPA (online consultation fees are paid
                      // to this address in the booking flow). Hidden for
                      // doctors without one — they collect at the clinic.
                      if ((_doctor.upiId ?? '').trim().isNotEmpty) ...[
                        _UpiIdCard(doctor: _doctor, isDark: isDark),
                        const SizedBox(height: 20),
                      ],
                      // Availability — weekly slots + unavailable dates
                      if (_unavailableRanges.isNotEmpty ||
                          _weeklySlots.any((s) => s.isEnabled)) ...[
                        _AvailabilityCard(
                          isDark: isDark,
                          unavailableRanges: _unavailableRanges,
                          weeklySlots: _weeklySlots,
                        ),
                        const SizedBox(height: 20),
                      ],
                      // Hours
                      if (_doctor.openingHours.isNotEmpty ||
                          _doctor.openingHoursPeriods.isNotEmpty) ...[
                        _HoursCard(doctor: _doctor, isDark: isDark),
                        const SizedBox(height: 20),
                      ],
                      // Photo gallery — show all Google Places photos
                      if (_doctor.photos.isNotEmpty) ...[
                        PhotoGalleryCard(doctor: _doctor, isDark: isDark),
                        const SizedBox(height: 20),
                      ],
                      // Reviews
                      if (_doctor.reviews.isNotEmpty) ...[
                        _ReviewsCard(doctor: _doctor, isDark: isDark),
                        const SizedBox(height: 20),
                      ],
                      // Extra Details
                      _ExtraDetailsCard(doctor: _doctor, isDark: isDark),
                    ]),
                  ),
                ),
              ],
            ),
      // ─── Sticky Bottom Action Bar ───
      bottomNavigationBar: _isLoading
          ? null
          : _StickyActionBar(doctor: _doctor),
    );
  }

  Widget _heroGradientFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
      ),
    );
  }

  // ── Identity Block ──
  Widget _buildIdentityBlock(bool isDark) {
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final capColor = AppColors.textCaption;

    String? city, area;
    for (final comp in _doctor.addressComponents) {
      final types =
          (comp['types'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (types.contains('locality')) city = comp['long_name']?.toString();
      if (types.contains('sublocality') || types.contains('neighborhood')) {
        area = comp['long_name']?.toString();
      }
    }
    final locationLabel = [
      area,
      city,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return Column(
      children: [
        Text(
          _doctor.name,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              text: _doctor.specialization ?? 'Healthcare Provider',
              color: AppColors.primary,
              filled: true,
            ),
            if (_doctor.primaryType != null)
              _Pill(
                text: _doctor.primaryType!,
                color: AppColors.accent,
                filled: true,
              ),
            if (_doctor.isOpen != null)
              _Pill(
                text: _doctor.isOpen == true ? 'Open now' : 'Closed',
                color: _doctor.isOpen == true
                    ? AppColors.success
                    : AppColors.error,
                filled: true,
              ),
          ],
        ),
        if (locationLabel.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, size: 14, color: capColor),
              const SizedBox(width: 4),
              Text(
                locationLabel,
                style: TextStyle(fontSize: 13, color: capColor),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _StatsRow(doctor: _doctor, isDark: isDark),
      ],
    );
  }

  Widget _buildRefreshBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Some details may be unavailable',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _fetchDetails,
            child: const Text(
              'Retry',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading Skeleton ──
  Widget _buildLoadingSkeleton(bool isDark) {
    final base = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE8E4DA);
    final highlight = isDark
        ? const Color(0xFF3A3A4E)
        : const Color(0xFFF4EFE4);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Column(
        children: [
          Container(
            height: _kExpandedHeight,
            width: double.infinity,
            color: base,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _shimmerBox(200, 24),
                  const SizedBox(height: 12),
                  _shimmerBox(140, 28, borderRadius: 20),
                  const SizedBox(height: 20),
                  _shimmerBox(double.infinity, 70, borderRadius: 18),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _shimmerBox(
                          double.infinity,
                          64,
                          borderRadius: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _shimmerBox(
                          double.infinity,
                          64,
                          borderRadius: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildPhotoGridShimmer(),
                  const SizedBox(height: 20),
                  _shimmerBox(double.infinity, 150, borderRadius: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shimmer placeholder that mimics the _PhotoGalleryCard layout:
  /// a section card with header icon + title, and a 3-column grid of
  /// square shimmer tiles to show where photos will load.
  Widget _buildPhotoGridShimmer() {
    // 3-column grid: (screenWidth - 20padding*2 - 20cardPadding*2 - 8spacing*2) / 3
    // Approximate as a fixed container with known dimensions.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header: icon + title
          Row(
            children: [
              _shimmerBox(36, 36, borderRadius: 10),
              const SizedBox(width: 12),
              _shimmerBox(100, 16),
            ],
          ),
          const SizedBox(height: 16),
          // 2 rows × 3 columns of square photo tiles
          ...List.generate(
            2,
            (row) => Padding(
              padding: EdgeInsets.only(bottom: row == 0 ? 8 : 0),
              child: Row(
                children: List.generate(
                  3,
                  (col) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: col < 2 ? 8 : 0),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox(double width, double height, {double borderRadius = 8}) {
    return Container(
      width: width == double.infinity ? double.infinity : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Frosted glass icon button (used in the floating top bar)
// ════════════════════════════════════════════════════════════════════
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  const _GlassIconButton({
    required this.icon,
    this.iconColor = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withAlpha(40),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Stats row (rating / reviews / experience)
// ════════════════════════════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _StatsRow({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    final items = <Widget>[];
    void addStat(IconData icon, Color color, String value, String label) {
      if (items.isNotEmpty) items.add(_vertDivider());
      items.add(
        Expanded(
          child: _StatItem(
            icon: icon,
            color: color,
            value: value,
            label: label,
            textColor: textColor,
            bodyColor: bodyColor,
          ),
        ),
      );
    }

    if (doctor.rating != null) {
      addStat(
        Icons.star,
        const Color(0xFFF4B400),
        doctor.rating!.ratingString,
        'Rating',
      );
    }
    addStat(
      Icons.people,
      AppColors.success,
      doctor.userRatingsTotal?.toString() ?? '0',
      'Reviews',
    );
    addStat(
      Icons.work_history,
      AppColors.info,
      doctor.experienceYears?.toString() ?? '—',
      'Yrs Exp',
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withAlpha(
          isDark ? 12 : 5,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: items),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final Color textColor;
  final Color bodyColor;

  const _StatItem({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.textColor,
    required this.bodyColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 10.5, color: bodyColor)),
      ],
    );
  }
}

Widget _vertDivider() {
  return Container(
    height: 32,
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: AppColors.textCaption.withAlpha(50),
  );
}

// ════════════════════════════════════════════════════════════════════
// Pill / chip used for statuses & badges
// ════════════════════════════════════════════════════════════════════
class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const _Pill({required this.text, required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(filled ? 26 : 16),
        borderRadius: BorderRadius.circular(20),
        border: filled
            ? null
            : Border.all(color: color.withAlpha(120), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Converts a Google Places API time string (24h HHMM format) to 12h AM/PM.
/// Handles edge cases: null, empty, non-4-char, and leading-zero-stripped
/// strings (e.g. "900" for 9:00 AM — pads to "0900" before parsing).
String formatGoogleTime(String? t) {
  if (t == null || t.isEmpty) return t ?? '';
  // Google may strip leading zeros: "900" → "0900"
  final padded = t.padLeft(4, '0');
  if (padded.length != 4) return t;
  final hour = int.tryParse(padded.substring(0, 2)) ?? 0;
  final min = padded.substring(2);
  final period = hour >= 12 ? 'PM' : 'AM';
  final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$h12:$min $period';
}

/// Masks a phone number by replacing the last 5 digits with "XXXXX".
/// E.g. "+91 9876543210" → "+91 98765XXXXX"
/// E.g. "9876543210" → "98765XXXXX"
String _maskPhoneNumber(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  if (phone.length <= 5) return 'XXXXX';
  // Keep first part (everything except last 5 digits)
  final visible = phone.substring(0, phone.length - 5);
  return '${visible}XXXXX';
}

// ════════════════════════════════════════════════════════════════════
// Quick actions row (Directions / Website — Call removed)
// ════════════════════════════════════════════════════════════════════
class _QuickActionsRow extends StatelessWidget {
  final DoctorModel doctor;
  const _QuickActionsRow({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      Expanded(
        child: _QuickActionButton(
          icon: Icons.directions,
          label: 'Directions',
          color: AppColors.info,
          onTap: () => LaunchService.map(doctor.latitude, doctor.longitude),
        ),
      ),
    ];
    if ((doctor.website ?? '').isNotEmpty) {
      actions.add(const SizedBox(width: 10));
      actions.add(
        Expanded(
          child: _QuickActionButton(
            icon: Icons.language,
            label: 'Website',
            color: AppColors.accent,
            onTap: () => LaunchService.url(doctor.website),
          ),
        ),
      );
    }
    return Row(children: actions);
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Sticky bottom action bar (Directions / Book Appointment)
// "Book Appointment" shows a spinner in the button while checking slots.
// ════════════════════════════════════════════════════════════════════
class _StickyActionBar extends StatefulWidget {
  final DoctorModel doctor;
  const _StickyActionBar({required this.doctor});

  @override
  State<_StickyActionBar> createState() => _StickyActionBarState();
}

class _StickyActionBarState extends State<_StickyActionBar> {
  bool _isCheckingSlots = false;
  bool _isLoadingSlots = false;
  bool _isLoadingDashboard = false;

  DoctorModel get doctor => widget.doctor;

  /// Opens the slot management screen with a loading state in the button.
  Future<void> _openManageSlots() async {
    if (_isLoadingSlots) return;
    setState(() => _isLoadingSlots = true);

    try {
      final auth = Get.find<AuthController>();

      // ── Guard: user must be logged in to manage slots ──
      if (auth.currentUser.value == null) {
        setState(() => _isLoadingSlots = false);
        Get.toNamed(AppRoutes.login, arguments: {'pendingDoctor': doctor});
        return;
      }

      final supabase = SupabaseService();
      await supabase.saveDoctorToDb(
        doctor.copyWith(userId: auth.currentUser.value?.id),
      );

      if (!auth.isDoctor) {
        final authService = AuthService();
        final updatedUser = await authService.updateRole(
          auth.currentUser.value!,
          UserModel.roleDoctor,
          doctorPlaceId: doctor.placeId,
        );
        auth.currentUser.value = updatedUser;
      }

      if (!mounted) return;
      setState(() => _isLoadingSlots = false);
      Get.toNamed(AppRoutes.doctorAvailability, arguments: {'doctor': doctor});
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSlots = false);
      // Navigate anyway — the availability screen handles errors
      Get.toNamed(AppRoutes.doctorAvailability, arguments: {'doctor': doctor});
    }
  }

  /// Opens the doctor dashboard with a loading state in the button.
  Future<void> _openDashboard() async {
    if (_isLoadingDashboard) return;
    setState(() => _isLoadingDashboard = true);

    try {
      final auth = Get.find<AuthController>();

      // ── Guard: user must be logged in to access dashboard ──
      if (auth.currentUser.value == null) {
        setState(() => _isLoadingDashboard = false);
        Get.toNamed(AppRoutes.login, arguments: {'pendingDoctor': doctor});
        return;
      }

      final supabase = SupabaseService();
      await supabase.saveDoctorToDb(
        doctor.copyWith(userId: auth.currentUser.value?.id),
      );

      if (!auth.isDoctor) {
        final authService = AuthService();
        final updatedUser = await authService.updateRole(
          auth.currentUser.value!,
          UserModel.roleDoctor,
          doctorPlaceId: doctor.placeId,
        );
        auth.currentUser.value = updatedUser;
      }

      // Load doctor into DoctorController so the dashboard has data
      final controller = Get.find<DoctorController>();
      await controller.setDoctor(doctor);

      if (!mounted) return;
      setState(() => _isLoadingDashboard = false);
      Get.toNamed(AppRoutes.doctorDashboard, arguments: {'doctor': doctor});
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingDashboard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            _CircleActionButton(
              icon: Icons.directions,
              color: AppColors.info,
              onTap: () => LaunchService.map(doctor.latitude, doctor.longitude),
            ),
            const SizedBox(width: 10),
            // Schedule button — only visible to doctors
            Obx(() {
              final auth = Get.find<AuthController>();
              if (!auth.isDoctor) return const SizedBox();
              return _CircleActionButton(
                icon: Icons.schedule_rounded,
                color: AppColors.accent,
                isLoading: _isLoadingSlots,
                onTap: _openManageSlots,
              );
            }),
            // Dashboard button — only visible to doctors
            Obx(() {
              final auth = Get.find<AuthController>();
              if (!auth.isDoctor) return const SizedBox();
              return Row(
                children: [
                  const SizedBox(width: 10),
                  _CircleActionButton(
                    icon: Icons.dashboard_rounded,
                    color: AppColors.primary,
                    isLoading: _isLoadingDashboard,
                    onTap: _openDashboard,
                  ),
                ],
              );
            }),
            const SizedBox(width: 10),
            _CircleActionButton(
              icon: Icons.share_rounded,
              color: const Color(0xFF10B981),
              onTap: () => ShareService.shareDoctorLink(doctor),
            ),
            const SizedBox(width: 10),
            // Book Appointment button — shows spinner while checking slots
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
                onPressed: _isCheckingSlots
                    ? null
                    : () => _handleBookAppointment(),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isCheckingSlots
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          key: ValueKey('idle'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_month_rounded, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Book Appointment',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBookAppointment() async {
    if (_isCheckingSlots) return;
    setState(() => _isCheckingSlots = true);

    try {
      final supabase = SupabaseService();
      final hasSlots = await _checkDoctorSlots(
        supabase,
        doctor,
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() => _isCheckingSlots = false);

      if (!hasSlots) {
        // Show contact details popup with Call/SMS buttons
        await _showNoSlotsContactModal(doctor);
        return;
      }

      // ── Step 2: Show contact details modal ──
      final proceed = await _showContactDetailsModal(doctor);
      if (proceed != true) return;

      // ── Step 3: Navigate to booking page ──
      if (!mounted) return;
      Get.toNamed(AppRoutes.bookAppointment, arguments: {'doctor': doctor});
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingSlots = false);
      // Still allow booking on error
      final proceed = await _showContactDetailsModal(doctor);
      if (proceed == true) {
        Get.toNamed(AppRoutes.bookAppointment, arguments: {'doctor': doctor});
      }
    }
  }

  static Future<bool> _checkDoctorSlots(
    SupabaseService supabase,
    DoctorModel doctor,
  ) async {
    try {
      final slots = await supabase.getDoctorSlots(doctor.placeId);
      return slots.any((s) => s.isEnabled && s.slots.isNotEmpty);
    } catch (_) {
      // If Supabase fails (e.g. no network), still allow booking
      return true;
    }
  }

  /// Shows a contact details dialog when no slots are available.
  ///
  /// Only Call and SMS are offered (WhatsApp/Email removed). The SMS
  /// opens pre-filled with a generic booking template that includes the
  /// patient's name, the doctor's name, and the doctor's number. The whole
  /// dialog scrolls so it can never overflow on small screens.
  static Future<void> _showNoSlotsContactModal(DoctorModel doctor) async {
    final phone = doctor.phoneNumber ?? '';

    // Patient identity for the SMS template — the message is sent by the
    // patient, so their own name/mobile are used (not the doctor's).
    final patient = Get.find<AuthController>().currentUser.value;
    final patientName = (patient?.name ?? '').trim();
    final patientLabel = patientName.isNotEmpty ? patientName : 'Patient';
    final patientMobile = (patient?.mobile ?? '').trim();
    final smsMessage = StringBuffer(
      'Hi ${doctor.name}, my name is $patientLabel and I would like to '
      'book an appointment with you. Please let me know the available slots.',
    );
    if (patientMobile.isNotEmpty) {
      smsMessage.write(' My number is $patientMobile.');
    }
    smsMessage.write(' Thank you!');

    return Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DoctorAvatar.circle(doctor: doctor, size: 64),
            const SizedBox(height: 12),
            Text(
              doctor.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textHeading,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if ((doctor.specialization ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  doctor.specialization!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.warning),
                  SizedBox(width: 6),
                  Text(
                    'No online slots available',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Scrollable content + actions — prevents the RenderFlex bottom
        // overflow that occurred with the old fixed-height layout on
        // small screens.
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Online booking is currently unavailable for this doctor. '
                'Please call or send an SMS to schedule an appointment.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textBody,
                  height: 1.4,
                ),
              ),
              if (phone.isNotEmpty) const SizedBox(height: 12),
              if (phone.isNotEmpty)
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHeading,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (phone.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.phone_rounded,
                          label: 'Call',
                          color: AppColors.success,
                          onTap: () {
                            Get.back();
                            LaunchService.phone(phone);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.sms_rounded,
                          label: 'SMS',
                          color: AppColors.info,
                          onTap: () {
                            Get.back();
                            LaunchService.sms(
                              phone,
                              message: smsMessage.toString(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                if (phone.isNotEmpty) const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Get.back(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textCaption,
                      side: BorderSide(
                        color: AppColors.textCaption.withAlpha(50),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<bool?> _showContactDetailsModal(DoctorModel doctor) async {
    final phone = doctor.phoneNumber ?? '';
    final address = doctor.address ?? '';
    final website = doctor.website ?? '';

    return Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: Column(
          children: [
            DoctorAvatar.circle(doctor: doctor, size: 64),
            const SizedBox(height: 12),
            Text(
              doctor.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textHeading,
              ),
              textAlign: TextAlign.center,
            ),
            if ((doctor.specialization ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  doctor.specialization!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            // Phone
            if (phone.isNotEmpty)
              _ContactRow(
                icon: Icons.phone_rounded,
                iconColor: AppColors.success,
                label: 'Phone',
                value: phone,
                onTap: () => LaunchService.phone(phone),
              ),
            const SizedBox(height: 10),
            // Address
            if (address.isNotEmpty)
              _ContactRow(
                icon: Icons.location_on_rounded,
                iconColor: AppColors.info,
                label: 'Address',
                value: address,
                onTap: () =>
                    LaunchService.map(doctor.latitude, doctor.longitude),
              ),
            const SizedBox(height: 10),
            // Website
            if (website.isNotEmpty)
              _ContactRow(
                icon: Icons.language_rounded,
                iconColor: AppColors.accent,
                label: 'Website',
                value: website.replaceFirst('https://', ''),
                onTap: () => LaunchService.url(website),
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Get.back(result: true),
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text(
                  'Continue to Book',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ContactRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: iconColor.withAlpha(12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
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
                        color: iconColor.withAlpha(180),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: iconColor.withAlpha(150),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small action button used in the no-slots contact dialog actions row.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  const _CircleActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(22),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: isLoading ? null : onTap,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isLoading
              ? Padding(
                  key: const ValueKey('loading'),
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: color,
                    ),
                  ),
                )
              : Padding(
                  key: const ValueKey('idle'),
                  padding: const EdgeInsets.all(14),
                  child: Icon(icon, color: color, size: 22),
                ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Location Mini-Map card (uses google_maps_flutter)
// ════════════════════════════════════════════════════════════════════
class _LocationMapCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;

  const _LocationMapCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.map_rounded,
        iconColor: AppColors.info,
        title: 'Location',
      ),
      child: DoctorMiniMap(doctor: doctor),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Shared section card + header
// ════════════════════════════════════════════════════════════════════
class _SectionCard extends StatelessWidget {
  final bool isDark;
  final Widget header;
  final Widget child;
  const _SectionCard({
    required this.isDark,
    required this.header,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 16), child],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: iconColor.withAlpha(30),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textHeading,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// About (editorial summary)
// ════════════════════════════════════════════════════════════════════
class _AboutCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _AboutCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;
    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.info_outline,
        iconColor: AppColors.accent,
        title: 'About',
      ),
      child: Text(
        doctor.editorialSummary!,
        style: TextStyle(fontSize: 13.5, height: 1.6, color: bodyColor),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// At a glance (business status / price level / vicinity / distance / plus code)
// ════════════════════════════════════════════════════════════════════
class _BusinessChipsCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _BusinessChipsCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (doctor.businessStatus != null) {
      chips.add(
        _Pill(
          text: doctor.businessStatus!.replaceAll('_', ' '),
          color: doctor.businessStatus == 'OPERATIONAL'
              ? AppColors.success
              : AppColors.warning,
          filled: true,
        ),
      );
    }
    if (doctor.priceLevel != null) {
      chips.add(
        _Pill(
          text: '₩' * (doctor.priceLevel! + 1),
          color: AppColors.textCaption,
          filled: true,
        ),
      );
    }
    if (doctor.distance != null) {
      chips.add(
        _Pill(text: doctor.distance!, color: AppColors.info, filled: true),
      );
    }
    if (doctor.vicinity != null) {
      chips.add(
        _Pill(text: doctor.vicinity!, color: AppColors.primary, filled: true),
      );
    }
    if (doctor.plusCode != null) {
      chips.add(
        _Pill(text: doctor.plusCode!, color: AppColors.accent, filled: true),
      );
    }
    if (doctor.wheelchairAccessible == true) {
      chips.add(
        _Pill(
          text: '♿ Wheelchair Accessible',
          color: AppColors.info,
          filled: true,
        ),
      );
    } else if (doctor.wheelchairAccessible == false) {
      chips.add(
        _Pill(
          text: 'No Wheelchair Access',
          color: AppColors.textCaption,
          filled: true,
        ),
      );
    }

    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.business,
        iconColor: AppColors.info,
        title: 'At a Glance',
      ),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Contact details
// ════════════════════════════════════════════════════════════════════
class _ContactCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _ContactCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.contact_phone,
        iconColor: AppColors.success,
        title: 'Contact',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((doctor.phoneNumber ?? '').isNotEmpty)
            _ContactTile(
              icon: Icons.phone,
              label: _maskPhoneNumber(doctor.phoneNumber),
              color: AppColors.success,
              onTap:
                  null, // Phone dialer disabled — use "Book Appointment" instead
            ),
          if ((doctor.internationalPhoneNumber ?? '').isNotEmpty &&
              doctor.internationalPhoneNumber != doctor.phoneNumber)
            _ContactTile(
              icon: Icons.phone_in_talk,
              label: _maskPhoneNumber(doctor.internationalPhoneNumber),
              color: AppColors.success,
              onTap: null, // Phone dialer disabled
            ),
          if ((doctor.website ?? '').isNotEmpty)
            _ContactTile(
              icon: Icons.language,
              label: doctor.website!.replaceFirst('https://', ''),
              color: AppColors.accent,
              onTap: () => LaunchService.url(doctor.website),
            ),
          if ((doctor.url ?? '').isNotEmpty)
            _ContactTile(
              icon: Icons.map,
              label: 'View on Map',
              color: AppColors.info,
              onTap: () => LaunchService.url(doctor.url),
            ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on,
                size: 18,
                color: AppColors.textCaption,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  doctor.address ?? 'N/A',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: bodyColor,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Read-only UPI Payment ID card for the patient-facing doctor profile:
/// shows the clinic's receiving UPI VPA (the address online consultation
/// fees are paid to in the booking flow). Only rendered when the doctor
/// has set one — no VPA means the patient pays at the clinic.
class _UpiIdCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _UpiIdCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final upiId = (doctor.upiId ?? '').trim();
    if (upiId.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.account_balance_wallet_rounded,
        iconColor: AppColors.primary,
        title: 'UPI Payment ID',
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withAlpha(35),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                upiId,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textHeading,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'Pay here',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ContactTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withAlpha(28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: color.withAlpha(180),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Availability — weekly available time slots + doctor-set unavailable dates
// ════════════════════════════════════════════════════════════════════
class _AvailabilityCard extends StatelessWidget {
  final bool isDark;
  final List<UnavailableRange> unavailableRanges;
  final List<DoctorSlot> weeklySlots;

  const _AvailabilityCard({
    required this.isDark,
    required this.unavailableRanges,
    required this.weeklySlots,
  });

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;
    const dayOrder = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    // ── Available time slots: enabled weekly schedule per day ──
    final dayChips = <Widget>[];
    for (final day in dayOrder) {
      final daySlots = weeklySlots
          .where((s) => s.dayOfWeek == day && s.isEnabled && s.slots.isNotEmpty)
          .toList();
      if (daySlots.isEmpty) continue;
      String? earliest24, latest24;
      for (final s in daySlots) {
        if (earliest24 == null || s.startTime.compareTo(earliest24) < 0) {
          earliest24 = s.startTime;
        }
        if (latest24 == null || s.endTime.compareTo(latest24) > 0) {
          latest24 = s.endTime;
        }
      }
      if (earliest24 == null || latest24 == null) continue;
      dayChips.add(
        _AvailPill(
          color: AppColors.success,
          text:
              '${day.substring(0, 3)}  ${to12h(earliest24)} – ${to12h(latest24)}',
        ),
      );
    }

    final hasActiveRanges = unavailableRanges.isNotEmpty;
    return _SectionCard(
      isDark: isDark,
      header: _SectionHeader(
        icon: hasActiveRanges
            ? Icons.event_busy_rounded
            : Icons.event_available_rounded,
        iconColor: hasActiveRanges ? AppColors.error : AppColors.success,
        title: 'Availability',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available time slots',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white.withAlpha(190)
                  : AppColors.textCaption,
            ),
          ),
          const SizedBox(height: 10),
          if (dayChips.isEmpty)
            Text(
              'No online slots configured yet.',
              style: TextStyle(
                fontSize: 12.5,
                color: bodyColor.withAlpha(180),
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: dayChips),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            'Unavailable dates',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white.withAlpha(190)
                  : AppColors.textCaption,
            ),
          ),
          const SizedBox(height: 10),
          if (!hasActiveRanges)
            Text(
              'The doctor is currently taking bookings on all scheduled days.',
              style: TextStyle(fontSize: 12.5, color: bodyColor.withAlpha(180)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unavailableRanges
                  .map(
                    (r) => _AvailPill(
                      color: AppColors.error,
                      text: r.label,
                      icon: Icons.event_busy_rounded,
                    ),
                  )
                  .toList(),
            ),
          if (hasActiveRanges) ...[
            const SizedBox(height: 10),
            Text(
              'Online booking is disabled on the dates above.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.error.withAlpha(180),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small pill used in the availability card.
class _AvailPill extends StatelessWidget {
  final Color color;
  final String text;
  final IconData? icon;
  const _AvailPill({required this.color, required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Working hours — real-time hours banner + detailed per-day schedule
// ════════════════════════════════════════════════════════════════════
class _HoursCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;

  const _HoursCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hasPeriods = doctor.openingHoursPeriods.isNotEmpty;
    final hasCurrentHours = doctor.currentOpeningHours != null;

    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.access_time,
        iconColor: AppColors.accent,
        title: 'Working Hours',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Real-time hours banner from Google's current_opening_hours
          if (hasCurrentHours) ...[
            _CurrentHoursBanner(
              currentHours: doctor.currentOpeningHours!,
              isDark: isDark,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Text(
              'Regular Schedule',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withAlpha(180)
                    : AppColors.textCaption,
              ),
            ),
            const SizedBox(height: 8),
          ],
          hasPeriods
              ? _DetailedHours(doctor: doctor, isDark: isDark)
              : _SimpleHours(doctor: doctor, isDark: isDark),
        ],
      ),
    );
  }
}

/// Prominent banner showing today's real-time hours from Google.
class _CurrentHoursBanner extends StatelessWidget {
  final Map<String, dynamic> currentHours;
  final bool isDark;

  const _CurrentHoursBanner({required this.currentHours, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    // Extract today's text from weekday_text list
    final weekdayText = currentHours['weekday_text'] as List<dynamic>?;
    final openNow = currentHours['open_now'] as bool?;

    // Find the current day's entry
    // Google Places API uses 0=Sunday, 1=Monday, ..., 6=Saturday
    final todayIndex = DateTime.now().weekday % 7; // 0=Sunday, 1=Monday
    String? todayHours;
    if (weekdayText != null &&
        todayIndex >= 0 &&
        todayIndex < weekdayText.length) {
      todayHours = weekdayText[todayIndex].toString();
    }

    // If no weekday_text, try period-based today
    if (todayHours == null) {
      final periods = currentHours['periods'] as List<dynamic>?;
      if (periods != null) {
        final todayPeriods = periods.where((p) {
          final day = p['open']?['day'] as int?;
          return day == todayIndex;
        }).toList();
        if (todayPeriods.isNotEmpty) {
          final parts = todayPeriods.map((p) {
            final open = _fmtTime(p['open']?['time']?.toString());
            final close = _fmtTime(p['close']?['time']?.toString());
            return '$open – $close';
          });
          todayHours = parts.join(', ');
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (openNow == true ? AppColors.success : AppColors.warning).withAlpha(
              22,
            ),
            (openNow == true ? AppColors.success : AppColors.warning).withAlpha(
              8,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (openNow == true ? AppColors.success : AppColors.warning)
              .withAlpha(60),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (openNow == true ? AppColors.success : AppColors.warning)
                  .withAlpha(30),
            ),
            child: Icon(
              openNow == true ? Icons.check_circle : Icons.access_time,
              color: openNow == true ? AppColors.success : AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Real-time',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: bodyColor.withAlpha(180),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (openNow == true
                                    ? AppColors.success
                                    : AppColors.warning)
                                .withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        openNow == true ? 'Open Now' : 'Closed',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: openNow == true
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  todayHours ?? 'Hours not available',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: bodyColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTime(String? t) {
    return formatGoogleTime(t);
  }
}

class _SimpleHours extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _SimpleHours({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;
    if (doctor.openingHours.isEmpty) {
      return Text(
        'Hours not available',
        style: TextStyle(
          fontSize: 13,
          color: bodyColor.withAlpha(180),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      children: doctor.openingHours.map((hour) {
        final isToday = _isTodayHour(hour);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday ? AppColors.primary : AppColors.textDisabled,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hour,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: bodyColor,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  bool _isTodayHour(String hour) {
    final now = DateTime.now();
    const dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final todayName = dayNames[now.weekday - 1];
    return hour.toLowerCase().contains(todayName.toLowerCase());
  }
}

class _DetailedHours extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _DetailedHours({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;
    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final p in doctor.openingHoursPeriods) {
      final day = p['open']?['day'] as int? ?? 0;
      grouped.putIfAbsent(day, () => []);
      grouped[day]!.add(p);
    }

    return Column(
      children: List.generate(7, (dayIndex) {
        final periods = grouped[dayIndex] ?? [];
        final isToday = dayIndex == DateTime.now().weekday % 7;
        final dayName = dayNames[dayIndex];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  dayName.substring(0, 3),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: isToday ? AppColors.primary : bodyColor,
                  ),
                ),
              ),
              Expanded(
                child: periods.isEmpty
                    ? const Text(
                        'Closed',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textCaption,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: periods.map((p) {
                          final open = p['open'];
                          final close = p['close'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '${_formatTime(open?['time']?.toString() ?? '')} – ${_formatTime(close?['time']?.toString() ?? '')}',
                              style: TextStyle(
                                fontSize: 13,
                                color: bodyColor,
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  String _formatTime(String t) {
    return formatGoogleTime(t);
  }
}

// ════════════════════════════════════════════════════════════════════
// Patient reviews
// ════════════════════════════════════════════════════════════════════
class _ReviewsCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _ReviewsCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final capColor = isDark ? const Color(0xFF999999) : AppColors.textCaption;

    final total = doctor.reviews.length;
    final avgRating = doctor.rating ?? 0.0;
    final distribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in doctor.reviews) {
      final stars = (r['rating'] as num?)?.toInt() ?? 0;
      if (stars >= 1 && stars <= 5) {
        distribution[stars] = (distribution[stars] ?? 0) + 1;
      }
    }

    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.star,
        iconColor: Color(0xFFF4B400),
        title: 'Patient Reviews',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF4B400).withAlpha(18),
                  const Color(0xFFF4B400).withAlpha(4),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Text(
                      avgRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < avgRating.round()
                              ? Icons.star
                              : Icons.star_border,
                          size: 14,
                          color: const Color(0xFFF4B400),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total review${total == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: capColor),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: List.generate(5, (i) {
                      final starLevel = 5 - i;
                      final count = distribution[starLevel] ?? 0;
                      final pct = total > 0 ? count / total : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              child: Text(
                                '$starLevel',
                                style: TextStyle(fontSize: 11, color: capColor),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.star,
                              size: 10,
                              color: Color(0xFFF4B400),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  backgroundColor: AppColors.textDisabled
                                      .withAlpha(50),
                                  valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFFF4B400),
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 22,
                              child: Text(
                                '$count',
                                style: TextStyle(fontSize: 11, color: capColor),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...doctor.reviews
              .take(6)
              .map((review) => _ReviewTile(review: review, isDark: isDark)),
          if (doctor.reviews.length > 6)
            Center(
              child: TextButton(
                onPressed: () => _showAllReviews(context),
                child: Text(
                  'View all ${doctor.reviews.length} review${doctor.reviews.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAllReviews(BuildContext context) {
    Get.bottomSheet(
      Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'All Reviews',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHeading,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: doctor.reviews.length,
                itemBuilder: (context, index) =>
                    _ReviewTile(review: doctor.reviews[index], isDark: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Map<String, dynamic> review;
  final bool isDark;
  const _ReviewTile({required this.review, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;
    final capColor = isDark ? const Color(0xFF999999) : AppColors.textCaption;

    final authorName = review['author_name']?.toString() ?? 'Anonymous';
    final authorPhoto = review['profile_photo_url']?.toString();
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final text = review['text']?.toString() ?? '';
    final relativeTime = review['relative_time_description']?.toString();
    final language = review['language']?.toString();
    final isTranslated = review['translated'] == true;
    final time = review['time'] as int?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 8 : 4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.bgSecondarySurface,
                backgroundImage: (authorPhoto != null && authorPhoto.isNotEmpty)
                    ? NetworkImage(authorPhoto)
                    : null,
                child: (authorPhoto == null || authorPhoto.isEmpty)
                    ? Text(
                        authorName.isNotEmpty
                            ? authorName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: bodyColor,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            authorName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (relativeTime != null)
                          Text(
                            relativeTime,
                            style: TextStyle(fontSize: 11, color: capColor),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ...List.generate(
                          5,
                          (i) => Icon(
                            i < rating ? Icons.star : Icons.star_border,
                            size: 14,
                            color: i < rating
                                ? const Color(0xFFF4B400)
                                : AppColors.textDisabled,
                          ),
                        ),
                        if (language != null && language != 'en')
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              language.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (isTranslated)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.translate,
                              size: 12,
                              color: AppColors.info,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 2),
              child: Text(
                _formatTimestamp(time),
                style: TextStyle(fontSize: 10, color: capColor.withAlpha(150)),
              ),
            ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 6),
              child: Text(
                text,
                style: TextStyle(fontSize: 13, color: bodyColor, height: 1.45),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    const months = [
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ════════════════════════════════════════════════════════════════════
// Extra details (types only — address components removed)
// ════════════════════════════════════════════════════════════════════
class _ExtraDetailsCard extends StatelessWidget {
  final DoctorModel doctor;
  final bool isDark;
  const _ExtraDetailsCard({required this.doctor, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final hasTypes = doctor.types.isNotEmpty;
    if (!hasTypes) return const SizedBox.shrink();

    return _SectionCard(
      isDark: isDark,
      header: const _SectionHeader(
        icon: Icons.info_outline,
        iconColor: AppColors.accent,
        title: 'More Details',
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: doctor.types.map((t) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              t.replaceAll('_', ' '),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
