import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:DrsListing/app.dart';
import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/auth/login_screen.dart';
import 'package:DrsListing/screens/onboarding/onboarding_screen.dart';
import 'package:DrsListing/services/local_storage_service.dart';

/// Test-only AuthController that skips platform-channel usage in onInit.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus to avoid
    // MissingPluginException for flutter_secure_storage in test env.
  }
}

/// Pumps the onboarding screen with the login route registered.
///
/// Note: explicit [tester.pump] calls are used instead of pumpAndSettle
/// because the looping Lottie animations never settle.
Future<void> _pumpOnboarding(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      getPages: [
        GetPage(name: AppRoutes.login, page: () => const LoginScreen()),
        GetPage(
          name: AppRoutes.onboarding,
          page: () => const OnboardingScreen(),
        ),
      ],
      initialRoute: AppRoutes.onboarding,
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

/// Taps the circular "Next" button and waits for the page transition.
///
/// Two pumps are required: the first starts the page animation (its
/// ticker only begins on the next frame), the second lets it finish.
Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_forward));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

/// The splash screen's location check calls the geolocator platform
/// channel, which never completes in widget tests. Mock it to report the
/// service as enabled so the splash can finish navigating.
void _mockLocationServiceEnabled(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async {
      if (call.method == 'isLocationServiceEnabled') return true;
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      null,
    );
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  group('OnboardingScreen', () {
    testWidgets('renders 3 pages in order with a Lottie on each', (
      tester,
    ) async {
      await _pumpOnboarding(tester);

      // Page 1
      expect(find.text('Find Trusted Doctors'), findsOneWidget);
      expect(find.byType(Lottie), findsOneWidget);

      // Page 2
      await _tapNext(tester);
      expect(find.text('Book Appointments Instantly'), findsOneWidget);

      // Page 3
      await _tapNext(tester);
      expect(find.text('Your AI Health Assistant'), findsOneWidget);
      // The final CTA button label (currently 'Start').
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Start marks onboarding done and routes to login', (
      tester,
    ) async {
      await _pumpOnboarding(tester);

      await _tapNext(tester);
      await _tapNext(tester);

      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(LocalStorageService().isOnboardingDone(), isTrue);
    });

    testWidgets('Skip also marks onboarding done and routes to login', (
      tester,
    ) async {
      await _pumpOnboarding(tester);

      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(LocalStorageService().isOnboardingDone(), isTrue);
    });
  });

  group('Splash routing (first vs later launch)', () {
    testWidgets('first launch → onboarding after the splash', (tester) async {
      // onboarding_done flag absent → first launch (location check is
      // skipped on the first launch, so no geolocator mock needed).
      SharedPreferences.setMockInitialValues({});
      await LocalStorageService().init();

      await tester.pumpWidget(const App());
      // Splash delays ~0.4s before navigating; give the route change time.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Find Trusted Doctors'), findsOneWidget);
    });

    testWidgets('onboarding already done → login after the splash', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'onboarding_done': true});
      await LocalStorageService().init();
      // The splash's location check hangs without a platform handler.
      _mockLocationServiceEnabled(tester);

      await tester.pumpWidget(const App());
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));

      // Login screen headline.
      expect(find.text('Welcome Back!'), findsOneWidget);
    });
  });
}
