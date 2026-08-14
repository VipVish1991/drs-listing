import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../routes/app_routes.dart';
import '../../services/local_storage_service.dart';
import '../../services/status_bar_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat(reverse: true);
    // The whole app uses a solid black status bar (white icons) — applied
    // here too via the status-bar plugin (theme-based).
    StatusBarService.apply(background: AppColors.primary, isDark: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    // First-launch onboarding takes priority: skip the location prompt
    // until the user has actually entered the app (the home flow prompts
    // for location anyway).
    final storage = LocalStorageService();
    final needsOnboarding = !storage.isOnboardingDone();
    final authController = Get.find<AuthController>();

    // Let the session restore settle (bounded) so the role gate below sees
    // the real user — a returning doctor must never be asked for the
    // patient-side location.
    for (var i = 0; i < 20 && authController.isLoading.value; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // The GPS/location prompt is PATIENT-only: the doctor dashboard has no
    // use for a patient's location, so a doctor is never asked.
    if (!needsOnboarding && !authController.isDoctor) {
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled && mounted) {
          await _promptLocationService();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    try {
      if (authController.isLoggedIn.value) {
        // A returning (already logged-in) user has clearly been through
        // onboarding before — mark it done so it never shows later.
        // Best-effort: a storage hiccup must never block login/home.
        if (needsOnboarding) {
          try {
            await storage.setOnboardingDone();
          } catch (_) {}
        }
        // Wait for auth status to settle, then navigate by role
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          await authController.navigateToRoleBasedHome();
        }
      } else if (needsOnboarding) {
        // First launch → onboarding first, then login.
        if (mounted) Get.offAllNamed(AppRoutes.onboarding);
      } else {
        if (mounted) Get.offAllNamed(AppRoutes.login);
      }
    } catch (_) {
      if (mounted) Get.offAllNamed(AppRoutes.login);
    }
  }

  Future<void> _promptLocationService() async {
    await Get.dialog(
      PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              const Icon(Icons.gps_fixed, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Location Required',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DrsListing needs your location turned on to find nearby '
                'doctors, hospitals, and healthcare providers for you.',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withAlpha(80)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please enable GPS / Location Services from your '
                        'device settings to continue.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Geolocator.openLocationSettings(),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Open Location Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  final enabled = await Geolocator.isLocationServiceEnabled();
                  if (enabled && mounted) Get.back();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text("I've enabled GPS — check again"),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The rest of the app uses a WHITE status bar with black text, but
    // the splash is a dark green gradient — a white bar would look broken
    // over it, so this local override keeps the dark bar with white icons
    // while this screen is visible.
    // (statusBarBrightness is the iOS-only field: kept dark here so the
    // status-bar text stays WHITE over the splash's dark gradient.)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary,
                AppColors.primaryDark,
                Color(0xFF064A3C),
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // Decorative circles
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -100,
                  left: -80,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(8),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.15,
                  right: -20,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2DCA9A).withAlpha(30),
                    ),
                  ),
                ),

                // Main content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Spacer(flex: 2),

                      // Lottie animation
                      SizedBox(
                            width: 180,
                            height: 180,
                            child: Lottie.asset(
                              'assets/lottie/medical_heartbeat.json',
                              fit: BoxFit.contain,
                            ),
                          )
                          .animate()
                          .scale(
                            begin: const Offset(0.6, 0.6),
                            end: const Offset(1, 1),
                            duration: 800.ms,
                            curve: Curves.easeOutBack,
                          )
                          .fadeIn(duration: 600.ms),

                      const SizedBox(height: 28),

                      // App name
                      Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Drs',
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w300,
                                    color: Colors.white.withAlpha(220),
                                    letterSpacing: -1,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Listing',
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 600.ms, delay: 300.ms)
                          .slideY(
                            begin: 0.3,
                            end: 0,
                            duration: 600.ms,
                            curve: Curves.easeOutCubic,
                            delay: 300.ms,
                          ),

                      const SizedBox(height: 10),

                      // AI Badge
                      Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(30),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withAlpha(60),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'AI',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 4,
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 600.ms)
                          .slideY(
                            begin: 0.3,
                            end: 0,
                            duration: 500.ms,
                            delay: 600.ms,
                          ),

                      const SizedBox(height: 14),

                      // Tagline
                      Text(
                            'Your AI Health Assistant',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withAlpha(170),
                              letterSpacing: 0.3,
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 900.ms)
                          .slideY(
                            begin: 0.3,
                            end: 0,
                            duration: 500.ms,
                            delay: 900.ms,
                          ),

                      const Spacer(flex: 2),

                      // Bottom branding
                      Column(
                        children: [
                          // Pulse dots
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  3,
                                  (i) => Container(
                                    margin: EdgeInsets.symmetric(horizontal: 3),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withAlpha(
                                        (50 +
                                                (25 *
                                                    ((_pulseController.value +
                                                            (i * 0.33)) %
                                                        1)))
                                            .round(),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Powered by AI · Connecting you to the best care',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withAlpha(100),
                              letterSpacing: 0.5,
                            ),
                          ).animate().fadeIn(duration: 800.ms, delay: 1200.ms),
                        ],
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
