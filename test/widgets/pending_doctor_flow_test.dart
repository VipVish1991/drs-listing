import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:DrsListing/config/theme.dart';
import 'package:DrsListing/controllers/auth_controller.dart';
import 'package:DrsListing/models/doctor_model.dart';
import 'package:DrsListing/routes/app_routes.dart';
import 'package:DrsListing/screens/auth/login_screen.dart';
import 'package:DrsListing/screens/auth/register_screen.dart';
import '../helpers/test_data.dart';

/// Test-only AuthController that skips platform-channel usage in onInit.
class _TestAuthController extends AuthController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Intentionally empty: skip checkAuthStatus to avoid
    // MissingPluginException for flutter_secure_storage in test env.
  }
}

/// Minimal bootstrap screen that navigates to [route] with [arguments]
/// once the navigator is available — Get.arguments must come from a real
/// route, it cannot be assigned directly in a test.
class _LaunchTo extends StatelessWidget {
  final String route;
  final Object? arguments;

  const _LaunchTo(this.route, {this.arguments});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.toNamed(route, arguments: arguments);
    });
    return const SizedBox.shrink();
  }
}

/// Pumps a GetMaterialApp with the auth routes registered and navigates
/// to [route] carrying [arguments].
Future<void> _pumpWithArgs(
  WidgetTester tester, {
  required String route,
  Object? arguments,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.lightTheme,
      getPages: [
        GetPage(name: AppRoutes.login, page: () => const LoginScreen()),
        GetPage(name: AppRoutes.register, page: () => const RegisterScreen()),
      ],
      home: _LaunchTo(route, arguments: arguments),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Get.reset();
    Get.put<AuthController>(_TestAuthController(), permanent: true);
  });

  tearDown(() {
    Get.reset();
  });

  group('LoginScreen forwards pendingDoctor to RegisterScreen', () {
    testWidgets('Create Account link carries the pendingDoctor through', (
      tester,
    ) async {
      final doctor = doctorBasic(placeId: 'pending_doc_flow');

      await _pumpWithArgs(
        tester,
        route: AppRoutes.login,
        arguments: {'pendingDoctor': doctor},
      );

      // Login screen reached with the pendingDoctor argument intact.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect((Get.arguments as Map)['pendingDoctor'], same(doctor));

      // Tap the "Create Account" link (rendered inside a RichText span
      // whose full text is "Don't have an account? Create Account"). It
      // sits below the fold of the test viewport, so scroll it into view
      // first.
      final createAccountLink = find.textContaining(
        'Create Account',
        findRichText: true,
      );
      await tester.ensureVisible(createAccountLink);
      await tester.pumpAndSettle();
      await tester.tap(createAccountLink);
      await tester.pumpAndSettle();

      // RegisterScreen was pushed with the pendingDoctor forwarded.
      expect(find.byType(RegisterScreen), findsOneWidget);
      final args = Get.arguments;
      expect(args, isA<Map>());
      final forwarded = (args as Map)['pendingDoctor'];
      expect(forwarded, isA<DoctorModel>());
      expect((forwarded as DoctorModel).placeId, 'pending_doc_flow');
    });

    testWidgets('no pendingDoctor → register args omit the key entirely', (
      tester,
    ) async {
      await _pumpWithArgs(
        tester,
        route: AppRoutes.login,
        arguments: {'mobile': '9876543210'},
      );

      expect(find.byType(LoginScreen), findsOneWidget);

      // The register link forwards _mobileController.text, so the mobile
      // must actually be typed into the login field first.
      await tester.enterText(
        find.widgetWithText(TextField, 'Mobile Number'),
        '9876543210',
      );

      final createAccountLink = find.textContaining(
        'Create Account',
        findRichText: true,
      );
      await tester.ensureVisible(createAccountLink);
      await tester.pumpAndSettle();
      await tester.tap(createAccountLink);
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      final args = Get.arguments;
      expect(args, isA<Map>());
      // The null-aware element must have OMITTED the key (not set it null).
      expect((args as Map).containsKey('pendingDoctor'), isFalse);
      expect(args['mobile'], '9876543210');
    });
  });

  group('RegisterScreen consumes forwarded arguments', () {
    testWidgets('pre-fills the mobile number passed from login', (
      tester,
    ) async {
      final doctor = doctorBasic(placeId: 'pending_doc_flow');

      await _pumpWithArgs(
        tester,
        route: AppRoutes.register,
        arguments: {
          'mobile': '9876543210',
          'pendingDoctor': doctor,
        },
      );

      final mobileField = tester.widget<TextField>(
        find.widgetWithText(TextField, '9876543210'),
      );
      expect(mobileField.controller?.text, '9876543210');
    });

    testWidgets('renders fine when pendingDoctor is null', (tester) async {
      await _pumpWithArgs(
        tester,
        route: AppRoutes.register,
        arguments: {'mobile': '9876543210'},
      );

      // 'Create Account' appears twice on the register screen (title +
      // button), so assert presence rather than uniqueness.
      expect(find.text('Create Account'), findsWidgets);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
    });
  });
}
