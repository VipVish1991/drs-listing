import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/doctor_search_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../services/launch_service.dart';
import '../../utils/place_type.dart';
import '../../widgets/app_button.dart';
import '../../widgets/doctor_card.dart';
import '../../widgets/category_filter_sheet.dart';
import '../../widgets/search_radius_sheet.dart';
import '../../routes/app_routes.dart';
import '../../models/doctor_model.dart';
import '../../widgets/haptic_button.dart';

class DoctorSearchScreen extends StatefulWidget {
  const DoctorSearchScreen({super.key});

  @override
  State<DoctorSearchScreen> createState() => _DoctorSearchScreenState();
}

class _DoctorSearchScreenState extends State<DoctorSearchScreen> {
  final _controller = Get.find<DoctorSearchController>();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final RxBool isRefreshing = false.obs;

  @override
  void initState() {
    super.initState();

    // Handle search triggered via route arguments (e.g. from splash or deep link)
    final args = Get.arguments;
    if (args is Map && args.containsKey('specialist')) {
      _controller.searchBySpecialization(args['specialist']);
    }

    // Watch for external search triggers from the bottom navigation bar
    // (e.g. tapping "Find Cardiologists near you" from a chat bubble).
    ever(_controller.pendingSearchSpecialization, (specialist) {
      if (specialist.isNotEmpty) {
        _controller.pendingSearchSpecialization.value = '';
        _controller.searchBySpecialization(specialist);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    isRefreshing.close();
    super.dispose();
  }

  /// Pull-to-refresh handler — keeps the existing list visible while
  /// re-fetching data instead of switching to the shimmer skeleton.
  Future<void> _onRefresh() async {
    isRefreshing.value = true;
    final saved = _controller.doctors.toList();
    try {
      await _controller.searchDoctors();
      // If refresh returned nothing and set an error, restore old data
      if (_controller.doctors.isEmpty &&
          _controller.errorMessage.value.isNotEmpty) {
        _controller.doctors.value = saved;
      }
    } finally {
      isRefreshing.value = false;
    }
  }

  void _openCategorySheet() {
    Get.bottomSheet(
      CategoryFilterSheet(
        onSelect: (name) => _controller.searchBySpecialization(name),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  /// Parses a distance string like "558 m" or "2.3 km" into meters.
  /// Unparsable/missing distances sort to the end rather than crashing.
  double _distanceMeters(DoctorModel doctor) {
    final raw = doctor.distance;
    if (raw == null || raw.isEmpty) return double.infinity;
    final cleaned = raw.toLowerCase().replaceAll(',', '').trim();
    final match = RegExp(r'([\d.]+)').firstMatch(cleaned);
    if (match == null) return double.infinity;
    final value = double.tryParse(match.group(1)!) ?? double.infinity;
    return cleaned.contains('km') ? value * 1000 : value;
  }

  /// Client-side guarantee that "Nearest" actually sorts the list, even if
  /// the controller's own sorting doesn't kick in for some reason.
  List<DoctorModel> _applyDistanceSort(List<DoctorModel> doctors) {
    if (!_controller.sortByDistance.value) return doctors;
    final sorted = [...doctors];
    sorted.sort((a, b) => _distanceMeters(a).compareTo(_distanceMeters(b)));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // Header with gradient accent
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primary.withAlpha(20), Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      AppBackButton(onPressed: () => Get.back()),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Find Doctors',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                      AppBackButton(
                        icon: Icons.tune,
                        iconColor: AppColors.primary,
                        background: AppColors.primary.withAlpha(30),
                        onPressed: _openCategorySheet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Search Bar — Zocdoc-style white card with shadow
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(8),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search doctors, hospitals...',
                        hintStyle: TextStyle(
                          color: AppColors.textCaption.withAlpha(180),
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.textCaption,
                          size: 22,
                        ),
                        suffixIcon: Obx(
                          () =>
                              (_controller.searchQuery.value.isNotEmpty ||
                                  _controller.isLoading.value)
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_controller.isLoading.value)
                                      const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    else
                                      HapticButton(
                                        scaleEnd: 0.90,
                                        onTap: () {
                                          _controller.searchQuery.value =
                                              _searchController.text;
                                          _controller.searchDoctors();
                                          FocusScope.of(context).unfocus();
                                        },
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withAlpha(
                                              30,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.search_rounded,
                                            color: AppColors.primary,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    HapticButton(
                                      scaleEnd: 0.90,
                                      hapticType:
                                          HapticFeedbackType.selectionClick,
                                      onTap: () {
                                        _searchController.clear();
                                        _controller.clearSearch();
                                      },
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.textCaption
                                              .withAlpha(20),
                                        ),
                                        child: const Icon(
                                          Icons.clear_rounded,
                                          color: AppColors.textCaption,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        fillColor: Colors.transparent,
                        filled: true,
                      ),
                      onSubmitted: (value) {
                        _controller.searchQuery.value = value;
                        _controller.searchDoctors();
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Filters row
            SizedBox(
              height: 55,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: [
                  Obx(
                    () => _FilterChip(
                      icon: Icons.star,
                      label: _controller.minRating.value > 0
                          ? '${_controller.minRating.value.toStringAsFixed(0)}+'
                          : 'Rating',
                      isActive: _controller.minRating.value > 0,
                      onTap: () => _showRatingFilter(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Type filter chips — uses place_type.dart for icons and labels.
                  Obx(() {
                    final active = _controller.filterType.value;
                    final counts = _controller.typeFilterCounts;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: kTypeFilterOptions.map((type) {
                        final isActive = active == type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _TypeChip(
                            icon: type == 'All'
                                ? Icons.all_inclusive_rounded
                                : placeTypeIcon(type),
                            label: type == 'All' ? 'All' : type,
                            count: counts[type] ?? 0,
                            isActive: isActive,
                            onTap: () => _controller.setTypeFilter(type),
                          ),
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(width: 8),
                  Obx(
                    () => _FilterChip(
                      icon: _controller.sortByDistance.value
                          ? Icons.near_me
                          : Icons.sort,
                      label: 'Nearest',
                      isActive: _controller.sortByDistance.value,
                      onTap: _controller.toggleSortByDistance,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Obx(
                    () => _FilterChip(
                      icon: Icons.radar,
                      label: '${_controller.searchRadiusKm} km',
                      isActive: false,
                      onTap: () => _showSearchRadiusSettings(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Obx(() {
                    final spec = _controller.selectedSpecialization.value;
                    if (spec.isEmpty) return const SizedBox.shrink();
                    return _FilterChip(
                      icon: Icons.close,
                      label: spec,
                      isActive: true,
                      activeColor: AppColors.primary,
                      onTap: _controller.clearSearch,
                    );
                  }),
                  Obx(() {
                    if (!_controller.isAnyFilterActive) {
                      return const SizedBox.shrink();
                    }
                    return _FilterChip(
                      icon: Icons.refresh,
                      label: 'Clear',
                      isActive: false,
                      onTap: () {
                        _searchController.clear();
                        _controller.clearSearch();
                      },
                    );
                  }),
                ],
              ),
            ),

            // Doctor list — crossfade between shimmer and real content
            Expanded(
              child: Obx(() {
                // Use AnimatedSwitcher so the shimmer smoothly fades into
                // the search results (or error/empty states) when loading
                // completes.  Stable ValueKey children let the switcher detect
                // the transition trigger.
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeIn,
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: _controller.isLoading.value && !isRefreshing.value
                      ? _buildShimmerList(key: const ValueKey('shimmer'))
                      : _buildContent(
                          key: ValueKey(
                            'content_${_controller.filterType.value}'
                            '_${_controller.searchQuery.value}',
                          ),
                          textColor: textColor,
                          bodyColor: bodyColor,
                        ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    String message,
    Color textColor,
    Color bodyColor, {
    Key? key,
  }) {
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withAlpha(25),
              ),
              child: const Icon(
                Icons.cloud_off,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: bodyColor,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _controller.searchDoctors(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withAlpha(120)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color bodyColor, {Key? key}) {
    return Center(
      key: key,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgSecondarySurface,
            ),
            child: const Icon(
              Icons.search_off,
              size: 40,
              color: AppColors.textCaption,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Search for doctors',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Type a name above or tap the filter icon to browse by category',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: bodyColor.withAlpha(160)),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openCategorySheet,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Browse categories'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withAlpha(120)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(Color textColor, Color bodyColor, {Key? key}) {
    return Center(
      key: key,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.sentiment_dissatisfied,
            size: 48,
            color: AppColors.textCaption,
          ),
          const SizedBox(height: 16),
          Text(
            'No doctors found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search or expand your filters',
            style: TextStyle(fontSize: 14, color: bodyColor.withAlpha(160)),
          ),
        ],
      ),
    );
  }

  /// Builds the non-loading content: error state, empty state, no-results,
  /// or the actual doctor list.
  Widget _buildContent({
    required Key key,
    required Color textColor,
    required Color bodyColor,
  }) {
    if (_controller.errorMessage.value.isNotEmpty) {
      return _buildErrorState(
        _controller.errorMessage.value,
        textColor,
        bodyColor,
        key: const ValueKey('error'),
      );
    }

    if (_controller.doctors.isEmpty) {
      return _buildEmptyState(
        textColor,
        bodyColor,
        key: const ValueKey('empty'),
      );
    }

    final doctors = _applyDistanceSort(_controller.filteredDoctors);

    if (doctors.isEmpty) {
      return _buildNoResults(
        textColor,
        bodyColor,
        key: const ValueKey('noresults'),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        key: const ValueKey('results'),
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        itemCount: doctors.length + _footerCount,
        itemBuilder: (context, index) {
          if (index >= doctors.length) {
            return _buildListFooter(bodyColor);
          }

          final doctor = doctors[index];
          return Obx(() {
            final pc = Get.find<ProfileController>();
            return DoctorCard(
              doctor: doctor,
              onTap: () {
                _controller.selectDoctor(doctor);
                Get.toNamed(
                  AppRoutes.doctorDetail,
                  arguments: {'doctor': doctor},
                );
              },
              onMap: () => LaunchService.map(doctor.latitude, doctor.longitude),
              isFavorited: pc.isDoctorSaved(doctor.placeId),
              onToggleFavorite: (_) => pc.toggleFavorite(doctor),
            );
          });
        },
      ),
    );
  }

  /// Shimmer loading skeleton: renders 5 placeholder doctor cards
  /// with animated shimmer while results are being fetched.
  Widget _buildShimmerList({Key? key}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2A2A3E)
        : const Color(0xFFE8E4DA);
    final highlightColor = isDark
        ? const Color(0xFF3A3A4E)
        : const Color(0xFFF4EFE4);

    return ListView.builder(
      key: key,
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: avatar + name/specialization/stars
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(68, 68, borderRadius: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShimmerBox(180, 16),
                          const SizedBox(height: 8),
                          _ShimmerBox(120, 13),
                          const SizedBox(height: 8),
                          _ShimmerBox(90, 12),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Stat row
                _ShimmerBox(double.infinity, 44, borderRadius: 14),
                const SizedBox(height: 12),
                // Detail rows
                _ShimmerBox(double.infinity, 14),
                const SizedBox(height: 8),
                _ShimmerBox(double.infinity, 14),
                const SizedBox(height: 8),
                _ShimmerBox(160, 14),
                const SizedBox(height: 14),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _ShimmerBox(double.infinity, 44, borderRadius: 14),
                    ),
                    const SizedBox(width: 10),
                    _ShimmerBox(44, 44, borderRadius: 14),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Number of extra items to append to the list after the last result.
  /// Always 1 when the list is non-empty so the pagination footer (loading
  /// / load-more / end-of-list) is always visible.
  int get _footerCount => _controller.doctors.isNotEmpty ? 1 : 0;

  /// Footer widget shown below the last result.
  Widget _buildListFooter(Color bodyColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          'Showing all results',
          style: TextStyle(fontSize: 12, color: AppColors.textCaption),
        ),
      ),
    );
  }

  void _showSearchRadiusSettings() {
    showSearchRadiusSheet(
      currentKm: _controller.searchRadiusKm,
      onSelected: () {
        Get.back();
        _controller.searchDoctors();
      },
    );
  }

  void _showRatingFilter() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Minimum Rating',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [1, 2, 3, 4, 5].map((rating) {
                return GestureDetector(
                  onTap: () {
                    _controller.minRating.value = rating.toDouble();
                    Get.back();
                  },
                  child: Column(
                    children: [
                      Icon(
                        Icons.star,
                        size: 40,
                        color: rating <= 3
                            ? AppColors.accent
                            : AppColors.textCaption,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$rating+',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textHeading,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerBox(this.width, this.height, {this.borderRadius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color? activeColor;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final ac = activeColor ?? AppColors.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? ac.withAlpha(30)
            : isDark
            ? const Color(0xFF1A1A2E).withAlpha(200)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? ac.withAlpha(80)
              : AppColors.textDisabled.withAlpha(40),
          width: 1,
        ),
        boxShadow: isActive
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(6),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: HapticButton(
        scaleEnd: 0.95,
        hapticType: HapticFeedbackType.selectionClick,
        animationDuration: const Duration(milliseconds: 150),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? ac : AppColors.textCaption,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? ac : AppColors.textBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Styled type filter chip with icon, label, count badge, and colour.
/// Filled primary colour when active, white when idle.
class _TypeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int count;
  final VoidCallback onTap;

  const _TypeChip({
    required this.icon,
    required this.label,
    required this.isActive,
    this.count = 0,
    required this.onTap,
  });

  /// Derive the chip colour from the type label.
  /// NOTE: 'All' must be handled explicitly because
  /// getPlaceTypeColor('All') falls through to AppColors.accent,
  /// which is wrong for the "All" chip.
  Color get _chipColor {
    if (label == 'All') return AppColors.primary;
    return getPlaceTypeColor(label);
  }

  @override
  Widget build(BuildContext context) {
    final chipColor = _chipColor;
    return HapticButton(
      scaleEnd: 0.95,
      hapticType: HapticFeedbackType.selectionClick,
      animationDuration: const Duration(milliseconds: 150),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? chipColor : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? chipColor : chipColor.withAlpha(50),
            width: isActive ? 0 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: chipColor.withAlpha(60),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isActive ? Colors.white : chipColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? Colors.white : AppColors.textHeading,
              ),
            ),
            // Count badge (only show when > 0 and chip is not active)
            if (count > 0 && !isActive) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: chipColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: chipColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
