import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/doctor_search_controller.dart';
import '../../routes/app_routes.dart';

class SavedDoctorsScreen extends StatelessWidget {
  const SavedDoctorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ProfileController>();

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Column(
          children: [
            // ── Gradient Header ──
            _buildHeader(controller),

            const SizedBox(height: 12),

            // ── Saved doctors list ──
            Expanded(
              child: Obx(() {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeIn,
                  switchOutCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: controller.isLoading.value
                      ? _buildShimmerList(
                          key: const ValueKey('shimmer'),
                        )
                      : _buildContent(
                          key: const ValueKey('content'),
                          controller: controller,
                        ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ProfileController controller) {
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
                border: Border.all(
                  color: Colors.white.withAlpha(40),
                ),
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
                const Text(
                  'Saved Doctors',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Obx(() => Text(
                  '${controller.savedDoctors.length} doctor${controller.savedDoctors.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(170),
                  ),
                )),
              ],
            ),
          ),
          // Delete all button
          Obx(() {
            if (controller.savedDoctors.isEmpty) {
              return const SizedBox.shrink();
            }
            return GestureDetector(
              onTap: () async {
                final confirm = await Get.dialog<bool>(
                  AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Text('Clear all'),
                    content: const Text('Remove all saved doctors?'),
                    actions: [
                      TextButton(
                        onPressed: () => Get.back(result: false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: AppColors.textCaption),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Get.back(result: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Remove all'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  for (final d in controller.savedDoctors.toList()) {
                    await controller.removeSavedDoctor(d.placeId);
                  }
                }
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(25),
                  border: Border.all(
                    color: Colors.white.withAlpha(40),
                  ),
                ),
                child: const Icon(
                  Icons.delete_sweep_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildContent({
    required Key key,
    required ProfileController controller,
  }) {
    if (controller.savedDoctors.isEmpty) {
      return _buildEmptyState(key: key);
    }

    return RefreshIndicator(
      key: key,
      onRefresh: () => controller.loadSavedDoctors(),
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: controller.savedDoctors.length,
        itemBuilder: (context, index) {
          final doctor = controller.savedDoctors[index];
          return _SavedDoctorCard(
            doctorName: doctor.name,
            specialization: doctor.specialization,
            address: doctor.address,
            rating: doctor.rating,
            distance: doctor.distance,
            isOpen: doctor.isOpen,
            onTap: () {
              Get.find<DoctorSearchController>().selectDoctor(doctor);
              Get.toNamed(
                AppRoutes.doctorDetail,
                arguments: {'doctor': doctor},
              );
            },
            onDelete: () => controller.removeSavedDoctor(doctor.placeId),
          ).animate().fadeIn(
            duration: 300.ms,
            delay: (index * 80).ms,
          ).slideY(begin: 0.1, end: 0, duration: 300.ms);
        },
      ),
    );
  }

  Widget _buildShimmerList({Key? key}) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: const Color(0xFFE8E4DA),
          highlightColor: const Color(0xFFF4EFE4),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _ShimmerBox(52, 52, borderRadius: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerBox(160, 15),
                      const SizedBox(height: 8),
                      _ShimmerBox(100, 13),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _ShimmerBox(12, 12),
                          const SizedBox(width: 4),
                          _ShimmerBox(60, 11),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _ShimmerBox(6, 6, borderRadius: 3),
                          const SizedBox(width: 4),
                          _ShimmerBox(30, 11),
                        ],
                      ),
                    ],
                  ),
                ),
                _ShimmerBox(40, 40, borderRadius: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({Key? key}) {
    return Center(
      key: key,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.healthHeart.withAlpha(30),
                  AppColors.primary.withAlpha(20),
                ],
              ),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              size: 44,
              color: AppColors.healthHeart,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No saved doctors yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textHeading,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tap the bookmark icon on any doctor\'s profile to save them here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textCaption.withAlpha(180),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedDoctorCard extends StatelessWidget {
  final String doctorName;
  final String? specialization;
  final String? address;
  final double? rating;
  final String? distance;
  final bool? isOpen;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedDoctorCard({
    required this.doctorName,
    this.specialization,
    this.address,
    this.rating,
    this.distance,
    this.isOpen,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: avatar + info + delete ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withAlpha(180),
                            AppColors.secondary.withAlpha(200),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          (doctorName.isNotEmpty ? doctorName[0] : 'D')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Doctor info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doctorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textHeading,
                            ),
                          ),
                          if (specialization != null &&
                              specialization!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              specialization!,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primary.withAlpha(200),
                              ),
                            ),
                          ],
                          if (rating != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                ...List.generate(5, (i) {
                                  return Icon(
                                    i < rating!.floor()
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 12,
                                    color: AppColors.accent,
                                  );
                                }),
                                const SizedBox(width: 4),
                                Text(
                                  rating!.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textCaption,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Delete button
                    GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.error,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Info chips ──
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (distance != null && distance!.isNotEmpty)
                          _InfoChip(
                            icon: Icons.near_me_rounded,
                            label: distance!,
                            color: AppColors.info,
                          ),
                        if (isOpen != null) ...[
                          const SizedBox(width: 6),
                          _InfoChip(
                            icon: isOpen!
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            label: isOpen! ? 'Open Now' : 'Closed',
                            color: isOpen!
                                ? Colors.green
                                : AppColors.textDisabled,
                          ),
                        ],
                        if (address != null && address!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _InfoChip(
                            icon: Icons.location_on_outlined,
                            label: address!,
                            color: AppColors.textCaption,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Action buttons ──
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.person_search, size: 16),
                        label: const Text(
                          'Profile',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(
                            color: AppColors.primary.withAlpha(80),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
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
