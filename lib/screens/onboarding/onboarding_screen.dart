import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:lottie/lottie.dart';
import '../../config/theme.dart';
import '../../routes/app_routes.dart';
import '../../services/local_storage_service.dart';
import '../../services/status_bar_service.dart';

/// First-launch onboarding, shown only once before the login screen.
///
/// Three pages, each with a project-themed Lottie animation:
/// 1. Find Trusted Doctors   — `doctor_search.json`
/// 2. Book Appointments      — `appointment_calendar.json`
/// 3. AI Health Assistant    — `hospital.json`
///
/// Completing (or skipping) the flow marks onboarding as done in local
/// storage so it never appears again on this device.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    // The onboarding sits on the light app background → dark status bar
    // icons via the status-bar plugin (theme-based).
    StatusBarService.apply(background: AppColors.bgMain, isDark: false);
  }

  Future<void> _finish() async {
    await LocalStorageService().setOnboardingDone();
    if (!mounted) return;
    Get.offAllNamed(AppRoutes.login);
  }

  Widget _lottie(String asset) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Lottie.asset(asset, fit: BoxFit.contain),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pageDecoration = PageDecoration(
      pageColor: AppColors.bgMain,
      imagePadding: EdgeInsets.symmetric(horizontal: 32),
      titleTextStyle: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.textHeading,
        height: 1.2,
      ),
      bodyTextStyle: TextStyle(
        fontSize: 15,
        color: AppColors.textBody,
        height: 1.55,
      ),
      titlePadding: EdgeInsets.only(top: 8, bottom: 18),
      bodyPadding: EdgeInsets.symmetric(horizontal: 28),
    );

    final nextButton = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(45),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 24),
    );

    // IntroductionScreen already renders a full-screen Scaffold (see its
    // `globalBackgroundColor`); no outer Scaffold is needed.
    return IntroductionScreen(
      globalBackgroundColor: AppColors.bgMain,
      pages: [
        PageViewModel(
          title: 'Find Trusted Doctors',
          body:
              'Discover verified doctors & specialists near you with '
              'genuine ratings, reviews and real-time availability.',
          image: _lottie('assets/lottie/doctor_search.json'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: 'Book Appointments Instantly',
          body:
              'Pick the time that suits you and book in seconds — '
              'no phone calls, no waiting rooms, no hassle.',
          image: _lottie('assets/lottie/appointment_calendar.json'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: 'Your AI Health Assistant',
          body:
              'Get instant, AI-powered answers to your health questions '
              'anytime, and stay connected to the best care.',
          image: _lottie('assets/lottie/hospital.json'),
          decoration: pageDecoration,
        ),
      ],
      onDone: _finish,
      onSkip: _finish,
      showSkipButton: true,
      skip: const Text(
        'Skip',
        style: TextStyle(
          color: AppColors.textCaption,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      next: nextButton,
      done: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Text(
            'Start',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      dotsDecorator: DotsDecorator(
        size: const Size(10, 10),
        activeSize: const Size(26, 10),
        activeColor: AppColors.primary,
        color: AppColors.textDisabled,
        spacing: const EdgeInsets.symmetric(horizontal: 4),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
        ),
      ),
    );
  }
}
