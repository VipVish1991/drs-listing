import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/doctor_model.dart';
import '../../models/unavailable_range.dart';
import '../../services/launch_service.dart';
import '../../services/share_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/snackbar_helpers.dart';
import '../../widgets/photo_gallery_card.dart';

class DoctorProfileScreen extends StatelessWidget {
  const DoctorProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<DoctorController>();
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Obx(() {
          // Show full-page shimmer skeleton while Place Details are
          // being fetched from the Google Places API.
          if (controller.isLoadingProfile.value) {
            return _ShimmerSkeleton();
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                _buildHeader(controller),
                const SizedBox(height: 20),
                _buildClinicPhotos(controller),
                const SizedBox(height: 24),
                _buildInfoSection(controller),
                const SizedBox(height: 24),
                _buildClinicDetails(controller),
                const SizedBox(height: 24),
                _buildUpiCard(controller),
                const SizedBox(height: 24),
                _buildAvailabilityCard(controller),
                const SizedBox(height: 24),
                _buildBottomActions(controller),
                const SizedBox(height: 24),
                _buildLogoutButton(),
                const SizedBox(height: 16),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHeader(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;
      if (doctor == null) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
          child: const Row(
            children: [
              Text(
                'Doctor Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
      }

      return Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
              color: AppColors.primary.withAlpha(70),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(30),
                    border: Border.all(
                      color: Colors.white.withAlpha(60),
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      doctor.name.isNotEmpty
                          ? doctor.name[0].toUpperCase()
                          : 'D',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doctor.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if ((doctor.specialization ?? '').isNotEmpty)
                        Text(
                          doctor.specialization!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withAlpha(200),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFFFB800),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            doctor.rating?.toStringAsFixed(1) ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                          if (doctor.userRatingsTotal != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '(${doctor.userRatingsTotal} reviews)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
    });
  }

  /// Clinic / hospital / doctor photo gallery — shows all Google Places
  /// photos for this place (same shared gallery used on the doctor detail
  /// screen, including the fullscreen viewer).
  Widget _buildClinicPhotos(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;
      if (doctor == null || doctor.photos.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: PhotoGalleryCard(doctor: doctor),
      );
    });
  }

  Widget _buildInfoSection(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;
      if (doctor == null) return const SizedBox();

      final items = <MapEntry<String, String?>>[
        MapEntry('Specialization', doctor.specialization),
        MapEntry('Hospital', doctor.hospitalName),
        MapEntry('Phone', doctor.phoneNumber),
        MapEntry('Email', doctor.internationalPhoneNumber),
        MapEntry('Address', doctor.address),
        MapEntry('Website', doctor.website),
        MapEntry('Experience', doctor.experienceYears?.toString()),
        MapEntry('Business Status', doctor.businessStatus),
      ];

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(6),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Professional Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHeading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...items.where((e) => e.value != null && e.value!.isNotEmpty).map(
                (e) {
                  final icon = _infoIcon(e.key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.key,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textCaption,
                                ),
                              ),
                              const SizedBox(height: 2),
                              InkWell(
                                onTap: e.key == 'Phone'
                                    ? () => LaunchService.phone(e.value!)
                                    : e.key == 'Website'
                                    ? () => LaunchService.url(e.value!)
                                    : null,
                                child: Text(
                                  e.value ?? 'N/A',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        e.key == 'Phone' || e.key == 'Website'
                                        ? AppColors.primary
                                        : AppColors.textHeading,
                                    decoration:
                                        e.key == 'Phone' || e.key == 'Website'
                                        ? TextDecoration.underline
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 400.ms, delay: 150.ms);
    });
  }

  Widget _buildClinicDetails(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;
      if (doctor == null) return const SizedBox();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(6),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.business_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Clinic Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHeading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Categories / Types
              if (doctor.types.isNotEmpty) ...[
                _DetailChipRow(
                  icon: Icons.category_rounded,
                  label: 'Categories',
                  chips: doctor.types
                      .map((t) => t.replaceAll('_', ' '))
                      .toList(),
                ),
                const SizedBox(height: 14),
              ],
              // Business status
              if (doctor.businessStatus != null) ...[
                _DetailInfoRow(
                  icon: Icons.circle_rounded,
                  iconColor: doctor.businessStatus == 'OPERATIONAL'
                      ? AppColors.success
                      : AppColors.warning,
                  label: 'Status',
                  value: doctor.businessStatus!.replaceAll('_', ' '),
                ),
                const SizedBox(height: 12),
              ],
              // Price level
              if (doctor.priceLevel != null) ...[
                _DetailInfoRow(
                  icon: Icons.monetization_on_rounded,
                  iconColor: AppColors.accent,
                  label: 'Price Level',
                  value: '₩' * (doctor.priceLevel! + 1),
                ),
                const SizedBox(height: 12),
              ],
              // Distance
              if ((doctor.distance ?? '').isNotEmpty) ...[
                _DetailInfoRow(
                  icon: Icons.near_me_rounded,
                  iconColor: AppColors.info,
                  label: 'Distance',
                  value: doctor.distance!,
                ),
                const SizedBox(height: 12),
              ],
              // Editorial summary
              if ((doctor.editorialSummary ?? '').isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'About',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textCaption,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            doctor.editorialSummary!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textBody,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
    });
  }

  /// UPI Payment ID card — shows the clinic's UPI VPA (or a fallback
  /// notice) and lets the doctor set / change it. Online consultation
  /// fees are paid to this VPA in the booking flow.
  Widget _buildUpiCard(DoctorController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _UpiIdCard(controller: controller),
    ).animate().fadeIn(duration: 400.ms, delay: 210.ms);
  }

  /// Availability status card — an "Available / Unavailable" button that
  /// opens a calendar range picker so the doctor can mark start/end dates
  /// when they are NOT available (leave, holiday, travel). The current
  /// status reflects whether today falls inside any saved range.
  Widget _buildAvailabilityCard(DoctorController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _AvailabilityCard(controller: controller),
    ).animate().fadeIn(duration: 400.ms, delay: 220.ms);
  }

  /// Bottom action row with three buttons: Directions, Share, Book Appointment.
  Widget _buildBottomActions(DoctorController controller) {
    return Obx(() {
      final doctor = controller.currentDoctor.value;
      if (doctor == null) return const SizedBox();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.directions_rounded,
                label: 'Directions',
                color: AppColors.info,
                onTap: () =>
                    LaunchService.map(doctor.latitude, doctor.longitude),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.share_rounded,
                label: 'Share',
                color: AppColors.accent,
                onTap: () => ShareService.shareDoctorLink(doctor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.qr_code_2_rounded,
                label: 'Book',
                color: AppColors.primary,
                onTap: () => _showBookingQrDialog(doctor),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms, delay: 250.ms);
    });
  }

  /// Shows a QR code that patients scan with their phone camera to open
  /// the booking page. The QR encodes AppConstants.bookingPageUrl — a
  /// static booking page (booking.html — source in the drsListing-web
  /// GitHub repo, github.com/VipVish1991/drsListing-web) served from a
  /// free static host, which posts to the booking-page Edge Function as a
  /// JSON API. (A static page is required because Supabase rewrites
  /// text/html GET responses to text/plain on the shared *.supabase.co
  /// domain.) The page collects name / mobile / description, registers
  /// the user if needed, and books for today (status: Pending).
  void _showBookingQrDialog(DoctorModel doctor) {
    final bookingUrl = AppConstants.bookingPageUrl(
      doctor.placeId,
      doctorName: doctor.name,
    );

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppColors.bgCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Title + subtitle ──
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan to Book',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(Get.context!).brightness ==
                                    Brightness.dark
                                ? Colors.white
                                : AppColors.textHeading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Patient scans with phone camera',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textCaption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Doctor name ──
              Text(
                doctor.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHeading,
                ),
                textAlign: TextAlign.center,
              ),
              if ((doctor.specialization ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  doctor.specialization!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),

              // ── QR code ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withAlpha(40)),
                ),
                child: QrImageView(
                  data: bookingUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),

              // ── Booking URL (tappable) ──
              InkWell(
                onTap: () => LaunchService.url(bookingUrl),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    bookingUrl,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── How it works ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HowItWorksRow(
                      number: '1',
                      text: 'Patient scans the QR code with their camera',
                    ),
                    SizedBox(height: 8),
                    _HowItWorksRow(
                      number: '2',
                      text: 'Booking page opens in their browser',
                    ),
                    SizedBox(height: 8),
                    _HowItWorksRow(
                      number: '3',
                      text: 'They enter name, mobile & description',
                    ),
                    SizedBox(height: 8),
                    _HowItWorksRow(
                      number: '4',
                      text:
                          "Appointment is booked for today \u2014 you'll see it \n"
                          'in your dashboard as Pending',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Actions ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ShareService.shareBookingPageLink(
                        bookingUrl,
                        doctorName: doctor.name,
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withAlpha(60),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => LaunchService.url(bookingUrl),
                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: const Text('Open Page'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    final authCtrl = Get.find<AuthController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: () {
            Get.dialog(
              AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text('Logout'),
                content: const Text('Are you sure you want to logout?'),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textCaption),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Get.back();
                      authCtrl.logout();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Logout'),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text(
            'Logout',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: AppColors.error.withAlpha(15),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 250.ms);
  }

  IconData _infoIcon(String key) {
    switch (key) {
      case 'Specialization':
        return Icons.local_hospital_rounded;
      case 'Hospital':
        return Icons.business_rounded;
      case 'Phone':
        return Icons.phone_rounded;
      case 'Email':
        return Icons.email_rounded;
      case 'Address':
        return Icons.location_on_rounded;
      case 'Website':
        return Icons.language_rounded;
      case 'Experience':
        return Icons.timeline_rounded;
      case 'Business Status':
        return Icons.info_rounded;
      default:
        return Icons.circle_rounded;
    }
  }
}

class _DetailInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _DetailInfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withAlpha(20),
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textCaption,
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
      ],
    );
  }
}

class _DetailChipRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> chips;

  const _DetailChipRow({
    required this.icon,
    required this.label,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textCaption,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: chips.map((chip) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      chip,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of the "How it works" instructions in the booking QR dialog.
class _HowItWorksRow extends StatelessWidget {
  final String number;
  final String text;

  const _HowItWorksRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textBody,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}


/// Doctor-set availability: an "Available / Unavailable" status button that
/// opens the calendar range picker, plus the list of saved unavailable date
/// ranges with delete buttons. Everything persists to the doctors table's
/// `unavailable_ranges` column and updates the shared [DoctorController] so
/// the dashboard reflects it immediately.
class _AvailabilityCard extends StatefulWidget {
  final DoctorController controller;
  const _AvailabilityCard({required this.controller});

  @override
  State<_AvailabilityCard> createState() => _AvailabilityCardState();
}

class _AvailabilityCardState extends State<_AvailabilityCard> {
  bool _saving = false;

  DoctorController get controller => widget.controller;

  DoctorModel? get _doctor => controller.currentDoctor.value;

  List<UnavailableRange> get _ranges =>
      _doctor?.unavailableRanges ?? const <UnavailableRange>[];

  /// Whether today falls inside any unavailable range — drives the
  /// Available/Unavailable status shown on the toggle button.
  bool get _isUnavailableToday => _ranges.any((r) => r.isActive);

  /// Opens the calendar range picker (start → end) and saves the new
  /// unavailable period.
  Future<void> _addUnavailableRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
      helpText: 'Select Unavailable Period',
      saveText: 'Mark Unavailable',
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: scheme.copyWith(
              primary: AppColors.primary,
              secondary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.bgCard,
              onSurface: AppColors.textHeading,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;

    final newRange = UnavailableRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(picked.end.year, picked.end.month, picked.end.day),
    );
    await _save([..._ranges, newRange]);
  }

  Future<void> _removeRange(UnavailableRange range) async {
    await _save(_ranges.where((r) => r != range).toList());
  }

  Future<void> _save(List<UnavailableRange> ranges) async {
    final doctor = _doctor;
    if (doctor == null) return;
    setState(() => _saving = true);
    try {
      final userId = Get.find<AuthController>().currentUser.value?.id;
      if (userId == null) return;
      await SupabaseService().saveDoctorUnavailableRanges(
        doctor.placeId,
        ranges,
        userId: userId,
      );
      if (mounted) {
        controller.currentDoctor.value = doctor.copyWith(
          unavailableRanges: ranges,
        );
      }
    } catch (_) {
      if (mounted) {
        showErrorSnackbar('Could not save availability. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _isUnavailableToday
        ? AppColors.error
        : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ──
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                _isUnavailableToday
                    ? Icons.event_busy_rounded
                    : Icons.event_available_rounded,
                size: 18,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              const Text(
                'Availability Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHeading,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isUnavailableToday
                          ? Icons.cancel_rounded
                          : Icons.check_circle_rounded,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isUnavailableToday ? 'Unavailable' : 'Available',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Toggle button (Available / Unavailable) → calendar ──
          Material(
            color: statusColor.withAlpha(12),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _saving ? null : _addUnavailableRange,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      color: statusColor,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isUnavailableToday
                                ? 'Marked Unavailable'
                                : 'Currently Available',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textHeading,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isUnavailableToday
                                ? 'Tap to add or change unavailable dates'
                                : 'Tap to mark dates when you are unavailable',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withAlpha(160)
                                  : AppColors.textCaption,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_saving)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: statusColor,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Saved unavailable ranges ──
          if (_ranges.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Unavailable dates',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withAlpha(180)
                    : AppColors.textCaption,
              ),
            ),
            const SizedBox(height: 10),
            ..._ranges.map(
              (range) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withAlpha(35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_busy_rounded,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          range.label,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textHeading,
                          ),
                        ),
                      ),
                      if (range.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withAlpha(15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Now',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: _saving ? null : () => _removeRange(range),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.error,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove unavailable period',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Patients can book you any day your weekly schedule is active.',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark
                    ? Colors.white.withAlpha(150)
                    : AppColors.textCaption,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Action button for the bottom row — icon with label below, styled
/// as a rounded card with a subtle background tint.
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
      color: color.withAlpha(15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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

/// Full-page shimmer skeleton shown while Place Details are being
/// fetched from the Google Places API.
class _ShimmerSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFE8E4DA),
        highlightColor: const Color(0xFFF4EFE4),
        child: Column(
          children: [
            // ── Header skeleton ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(180),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  // Avatar circle
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(60),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 160,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(60),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Clinic Photos skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.textDisabled.withAlpha(100),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Photo strip
                    SizedBox(
                      height: 140,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 3,
                        itemBuilder: (_, _) => Container(
                          width: 180,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: AppColors.textDisabled.withAlpha(60),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Professional Info skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Container(
                      width: 180,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.textDisabled.withAlpha(100),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Info rows
                    ...List.generate(
                      4,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.textDisabled.withAlpha(60),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 60,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: AppColors.textDisabled.withAlpha(60),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 160,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: AppColors.textDisabled.withAlpha(80),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Bottom actions skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(
                  3,
                  (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                        left: i > 0 ? 10 : 0,
                        right: i < 2 ? 10 : 0,
                      ),
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.textDisabled.withAlpha(60),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Logout button skeleton ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled.withAlpha(60),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Doctor-set UPI Payment ID: shows the clinic's UPI VPA (the address that
/// receives online consultation fees) with an edit dialog that persists to
/// the doctors table's `upi_id` column via [DoctorController.updateDoctorUpiId].
///
/// Build is wrapped in its own [Obx] (same pattern as the header / info
/// sections) so the card live-updates when [DoctorController.currentDoctor]
/// changes — a bare StatelessWidget would not react to the Rx value because
/// the read happens in the child State's build, outside the screen-level
/// Obx's dependency window.
class _UpiIdCard extends StatelessWidget {
  final DoctorController controller;
  const _UpiIdCard({required this.controller});

  String? get _upiId => controller.currentDoctor.value?.upiId;

  Future<void> _edit(BuildContext context) async {
    // The dialog owns its TextEditingController (created in initState,
    // disposed when the dialog State unmounts) so the field is never used
    // after disposal during the route's exit animation.
    final saved = await Get.dialog<bool>(
      _UpiEditDialog(
        initialUpiId: _upiId ?? '',
        controller: controller,
      ),
    );
    if (saved == true && context.mounted) {
      showSuccessSnackbar('UPI Payment ID updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final upiId = _upiId?.trim() ?? '';
      final hasUpi = upiId.isNotEmpty;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'UPI Payment ID',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHeading,
                    ),
                  ),
                ),
                Material(
                  color: AppColors.primary.withAlpha(12),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _edit(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.edit_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasUpi ? 'Edit' : 'Add',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: hasUpi
                    ? AppColors.primary.withAlpha(8)
                    : AppColors.textCaption.withAlpha(8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasUpi
                      ? AppColors.primary.withAlpha(35)
                      : AppColors.textCaption.withAlpha(25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasUpi
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: hasUpi ? AppColors.primary : AppColors.textCaption,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      // No app-wide fallback VPA exists, so an unset ID
                      // simply means the patient pays at the clinic.
                      hasUpi ? upiId : 'Not set — patients pay at the clinic.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hasUpi
                            ? AppColors.textHeading
                            : AppColors.textCaption,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Online consultation fees are paid to this UPI ID.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textCaption,
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Edit dialog for the doctor's UPI Payment ID: a prefilled text field
/// with Save (shows an in-button spinner while saving) / Cancel. Owns its
/// [TextEditingController] for its whole lifecycle so the field is never
/// used after disposal.
class _UpiEditDialog extends StatefulWidget {
  final String initialUpiId;
  final DoctorController controller;

  const _UpiEditDialog({
    required this.initialUpiId,
    required this.controller,
  });

  @override
  State<_UpiEditDialog> createState() => _UpiEditDialogState();
}

class _UpiEditDialogState extends State<_UpiEditDialog> {
  late final TextEditingController _textController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialUpiId);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.controller.updateDoctorUpiId(_textController.text);
      if (mounted) Get.back(result: true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnackbar('Could not save the UPI ID. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('UPI Payment ID'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patients pay online consultation fees to this UPI ID '
            '(e.g. clinic@okhdfcbank). Leave it empty to fall back to '
            'pay-at-clinic.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textCaption,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _textController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              labelText: 'UPI ID',
              hintText: 'clinic@okhdfcbank',
              prefixIcon: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Get.back(result: false),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textCaption),
          ),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
