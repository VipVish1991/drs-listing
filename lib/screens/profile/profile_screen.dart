import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/notification_center_controller.dart';
import '../../services/local_storage_service.dart';
import '../../widgets/search_radius_sheet.dart';
import '../../widgets/edit_name_dialog.dart';
import '../../routes/app_routes.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileController _controller = Get.find<ProfileController>();
  final AuthController _authController = Get.find<AuthController>();
  late final NotificationCenterController _notifications;

  /// Whether the patient home screen auto-plays the welcome video +
  /// greeting. Mirrors LocalStorageService so the settings row chip and
  /// the toggle sheet stay in sync.
  bool _welcomeAutoPlayEnabled = true;

  @override
  void initState() {
    super.initState();
    _notifications = NotificationCenterController.instance;
    _notifications.load();
    _welcomeAutoPlayEnabled = LocalStorageService().isWelcomeAutoPlayEnabled();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Gradient Header with Profile Card ──
              _buildGradientHeader(),

              const SizedBox(height: 20),

              // ── Menu Items ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSectionHeader(
                  icon: Icons.flash_on_rounded,
                  label: 'Quick Actions',
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _MenuItem(
                      icon: Icons.favorite_rounded,
                      label: 'Saved Doctors',
                      color: AppColors.healthHeart,
                      onTap: () => Get.toNamed(AppRoutes.savedDoctors),
                    ),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: Icons.calendar_month_rounded,
                      label: 'Appointment History',
                      color: AppColors.primary,
                      onTap: () => Get.toNamed(AppRoutes.appointmentHistory),
                    ),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Payment History',
                      color: AppColors.success,
                      onTap: () => Get.toNamed(AppRoutes.paymentHistory),
                    ),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: Icons.language_rounded,
                      label: 'Language Settings',
                      color: AppColors.accent,
                      trailing: Obx(
                        () => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            AppConstants.resolveLanguageName(
                              _controller.selectedLanguage.value,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      onTap: () => _showLanguageSettings(),
                    ),
                    const SizedBox(height: 8),
                    Obx(
                      () => _MenuItem(
                        icon: Icons.radar_rounded,
                        label: 'Search Radius',
                        color: AppColors.info,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_controller.searchRadiusKm} km',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        onTap: () => _showSearchRadiusSettings(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Obx(() {
                      final unread = _notifications.unreadCount.value;
                      return _MenuItem(
                        icon: Icons.notifications_active_rounded,
                        label: 'Notification Center',
                        color: AppColors.accent,
                        trailing: unread > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : null,
                        onTap: () => Get.toNamed(AppRoutes.notificationCenter),
                      );
                    }),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: Icons.settings_rounded,
                      label: 'Notification Settings',
                      color: AppColors.info,
                      onTap: () => Get.toNamed(AppRoutes.notificationSettings),
                    ),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: Icons.smart_toy_rounded,
                      label: 'Auto-Play Welcome',
                      color: AppColors.accent,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _welcomeAutoPlayEnabled ? 'On' : 'Off',
                          key: const ValueKey('welcome_auto_play_chip'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      onTap: _showWelcomeSettings,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSectionHeader(
                  icon: Icons.info_outline_rounded,
                  label: 'About',
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _MenuItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About DrsListing',
                      color: AppColors.textBody,
                      onTap: () => Get.toNamed(AppRoutes.about),
                    ),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: Icons.help_outline_rounded,
                      label: 'Help & Support',
                      color: AppColors.textBody,
                      onTap: () => Get.toNamed(AppRoutes.help),
                    ),
                    const SizedBox(height: 8),
                    _MenuItem(
                      icon: Icons.shield_outlined,
                      label: 'Privacy Policy',
                      color: AppColors.textBody,
                      onTap: () => Get.toNamed(AppRoutes.privacyPolicy),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Logout ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => _showLogoutDialog(),
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
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientHeader() {
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
            color: AppColors.primary.withAlpha(80),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Obx(() {
        final u = _authController.currentUser.value;
        if (_authController.isLoading.value) {
          return _buildProfileShimmer();
        }
        return Row(
          children: [
            // Avatar
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
                  (u?.name ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u?.name ?? 'User',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.phone_rounded,
                        size: 14,
                        color: Colors.white.withAlpha(180),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        u?.mobile ?? 'N/A',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withAlpha(170),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Edit icon — opens the name editor popup.
            GestureDetector(
              key: const ValueKey('profile_edit_name_button'),
              onTap: _showEditNameDialog,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(25),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        );
      }),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildSectionHeader({required IconData icon, required String label}) {
    return Row(
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
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textHeading,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileShimmer() {
    final baseColor = Colors.white.withAlpha(30);
    final highlightColor = Colors.white.withAlpha(60);

    return Row(
      children: [
        Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showLogoutDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              _controller.logout();
              Get.back();
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
  }

  /// Shows a popup to edit the user's display name. Saving persists the
  /// new name to Supabase and refreshes [AuthController.currentUser] so
  /// the header updates in place. Shared with the doctor dashboard
  /// header via [showEditNameDialog].
  Future<void> _showEditNameDialog() async {
    final user = _authController.currentUser.value;
    await showEditNameDialog(
      currentName: user?.name ?? '',
      onSave: _authController.updateUserName,
    );
  }

  void _showSearchRadiusSettings() {
    showSearchRadiusSheet(
      currentKm: _controller.searchRadiusKm,
      onSelected: () {
        _controller.setSearchRadiusKm(_controller.searchRadiusKm.value);
        Get.back();
      },
    );
  }

  /// Opens the Auto-Play Welcome bottom sheet — a switch that controls
  /// whether the patient home screen plays the avatar video + greeting
  /// automatically. The greeting voice always starts together with the
  /// video ("With the video" — the only timing preset). The choice is
  /// persisted locally so it survives restarts.
  void _showWelcomeSettings() {
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24),
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
            Text(
              'Auto-Play Welcome',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The health assistant video and its greeting play '
              'automatically when you open the home screen — the greeting '
              'starts together with the video.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textCaption,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.primary,
                      activeTrackColor: AppColors.primary.withAlpha(60),
                      secondary: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.accent.withAlpha(25),
                        ),
                        child: Icon(
                          _welcomeAutoPlayEnabled
                              ? Icons.smart_toy_rounded
                              : Icons.videocam_off_rounded,
                          color: _welcomeAutoPlayEnabled
                              ? AppColors.accent
                              : AppColors.textCaption,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        _welcomeAutoPlayEnabled
                            ? 'Welcome plays automatically'
                            : 'Welcome stays paused',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textHeading,
                        ),
                      ),
                      subtitle: Text(
                        _welcomeAutoPlayEnabled
                            ? 'Tap to keep the avatar quiet'
                            : 'Tap to let the avatar greet you again',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textCaption,
                        ),
                      ),
                      value: _welcomeAutoPlayEnabled,
                      onChanged: (v) {
                        setSheetState(() => _welcomeAutoPlayEnabled = v);
                        setState(() => _welcomeAutoPlayEnabled = v);
                        LocalStorageService().setWelcomeAutoPlayEnabled(v);
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageSettings() {
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(24),
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
            Text(
              'Preferred Language',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textHeading,
              ),
            ),
            const SizedBox(height: 16),
            ...AppConstants.supportedLanguages.map((lang) {
              final isSelected =
                  AppConstants.resolveLanguageCode(
                    _controller.selectedLanguage.value,
                  ) ==
                  lang['code'];
              return ListTile(
                key: ValueKey('lang_option_${lang['code']}'),
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? AppColors.primary : AppColors.textCaption,
                ),
                title: Text(
                  lang['name']!,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? AppColors.primary : AppColors.textBody,
                  ),
                ),
                onTap: () {
                  _controller.setLanguage(lang['code']!);
                  Get.back();
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withAlpha(30),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              title: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textHeading,
                ),
              ),
              trailing:
                  trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textCaption.withAlpha(150),
                    size: 22,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
