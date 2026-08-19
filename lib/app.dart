import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'config/theme.dart';
import 'models/appointment_model.dart';
import 'models/doctor_model.dart';
import 'models/payment_model.dart';
import 'models/user_model.dart';
import 'routes/app_routes.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/main_shell.dart';
import 'screens/doctor_search/doctor_search_screen.dart';
import 'screens/doctor_search/doctor_detail_screen.dart';
import 'screens/appointment/book_appointment_screen.dart';
import 'screens/appointment/reschedule_appointment_screen.dart';
import 'screens/appointment/appointment_history_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/payment_history_screen.dart';
import 'screens/profile/saved_doctors_screen.dart';
import 'screens/profile/notification_settings_screen.dart';
import 'screens/profile/notification_center_screen.dart';
import 'screens/profile/about_screen.dart';
import 'screens/profile/help_screen.dart';
import 'screens/profile/privacy_policy_screen.dart';
import 'screens/web/web_booking_screen.dart';
import 'screens/doctor/nearby_doctors_screen.dart';
import 'screens/doctor/doctor_availability_screen.dart';
import 'screens/doctor/doctor_main_shell.dart';
import 'screens/doctor/patient_history_screen.dart';
import 'screens/doctor/doctor_register_screen.dart';
import 'screens/doctor/otp_verification_screen.dart';
import 'controllers/auth_controller.dart';
import 'controllers/doctor_controller.dart';
import 'services/connectivity_service.dart';
import 'services/local_storage_service.dart';
import 'services/supabase_service.dart';
import 'routes/app_route_observer.dart';
import 'utils/web_booking_url.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app is actually closed/terminated, clear the Places API
    // response cache to free memory (requirement: every app close clears
    // the cache). We deliberately do NOT clear on `paused` (brief
    // backgrounding) so the cache survives quick app switches and can
    // still reduce API cost on the next open.
    if (state == AppLifecycleState.detached) {
      LocalStorageService().clearPlacesCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'DrsListing',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Root messenger — lets ConnectivityService show/hide the offline
      // banner from anywhere without a BuildContext.
      scaffoldMessengerKey: appScaffoldMessengerKey,
      navigatorObservers: [appRouteObserver],
      initialRoute: _initialRoute(),
      getPages: [
        GetPage(
          name: AppRoutes.splash,
          page: () => const SplashScreen(),
        ),
        GetPage(
          name: AppRoutes.onboarding,
          page: () => const OnboardingScreen(),
        ),
        GetPage(
          name: AppRoutes.login,
          page: () => const LoginScreen(),
        ),
        GetPage(
          name: AppRoutes.register,
          page: () => const RegisterScreen(),
        ),
        GetPage(
          name: AppRoutes.home,
          page: () => MainShell(),
        ),
        GetPage(
          name: AppRoutes.doctorSearch,
          page: () => const DoctorSearchScreen(),
        ),
        GetPage(
          name: AppRoutes.doctorDetail,
          page: () => DoctorDetailScreen(),
        ),
        GetPage(
          name: AppRoutes.bookAppointment,
          page: () => const BookAppointmentScreen(),
        ),
        GetPage(
          name: AppRoutes.rescheduleAppointment,
          page: () => const RescheduleAppointmentScreen(),
        ),
        GetPage(
          name: AppRoutes.appointmentHistory,
          page: () => const AppointmentHistoryScreen(),
        ),
        GetPage(
          name: AppRoutes.paymentHistory,
          page: () => const PaymentHistoryScreen(),
        ),
        GetPage(
          name: AppRoutes.doctorPaymentHistory,
          page: () => PaymentHistoryScreen(
            subtitle: 'Fees collected at your clinic',
            // The doctor-flavored empty state (title + body + "View
            // Appointments" CTA) is owned by the screen in doctor mode.
            loadPayments: _loadDoctorPayments,
          ),
        ),
        GetPage(
          name: AppRoutes.profile,
          page: () => ProfileScreen(),
        ),
        GetPage(
          name: AppRoutes.savedDoctors,
          page: () => const SavedDoctorsScreen(),
        ),
        GetPage(
          name: AppRoutes.nearbyDoctors,
          page: () => const NearbyDoctorsScreen(),
        ),
        GetPage(
          name: AppRoutes.doctorRegister,
          page: () => const DoctorRegisterScreen(),
        ),
        GetPage(
          name: AppRoutes.otpVerification,
          page: () {
            final args = Get.arguments;
            final displayName = args is Map
                ? (args['displayName']?.toString() ?? '')
                : '';
            final mobile = args is Map
                ? (args['mobile']?.toString() ?? '')
                : '';
            final role = args is Map
                ? (args['role']?.toString() ?? UserModel.roleDoctor)
                : UserModel.roleDoctor;
            final doctor = args is Map
                ? (args['doctor'] as DoctorModel?)
                : null;
            return OtpVerificationScreen(
              displayName: displayName,
              mobile: mobile,
              role: role,
              doctor: doctor,
            );
          },
        ),
        GetPage(
          name: AppRoutes.doctorAvailability,
          page: () {
            final doctor = Get.arguments['doctor'] as DoctorModel;
            return DoctorAvailabilityScreen(doctor: doctor);
          },
        ),
        GetPage(
          name: AppRoutes.doctorDashboard,
          page: () {
            // Try to get doctor from route arguments first; fall back to
            // the currently loaded doctor in DoctorController (e.g. when
            // navigating without arguments after a DB lookup failure).
            final doctor = Get.arguments is Map
                ? (Get.arguments['doctor'] as DoctorModel?)
                : null;

            final controller = Get.find<DoctorController>();
            final resolvedDoctor =
                doctor ?? controller.currentDoctor.value;

            if (resolvedDoctor != null) {
              controller.setDoctor(resolvedDoctor);
              Get.find<AuthController>()
                  .ensureDoctorState(resolvedDoctor);
            }

            return const DoctorMainShell();
          },
        ),
        GetPage(
          name: AppRoutes.patientHistory,
          page: () {
            final args = Get.arguments;
            final appointments = args is Map
                ? ((args['appointments'] as List?) ?? const [])
                      .whereType<AppointmentModel>()
                      .toList()
                : <AppointmentModel>[];
            return PatientHistoryScreen(
              appointments: appointments,
              highlightId: args is Map
                  ? args['highlightId']?.toString()
                  : null,
            );
          },
        ),
        GetPage(
          name: AppRoutes.notificationSettings,
          page: () => const NotificationSettingsScreen(),
        ),
        GetPage(
          name: AppRoutes.notificationCenter,
          page: () => const NotificationCenterScreen(),
        ),
        GetPage(
          name: AppRoutes.about,
          page: () => const AboutScreen(),
        ),
        GetPage(
          name: AppRoutes.help,
          page: () => const HelpScreen(),
        ),
        GetPage(
          name: AppRoutes.privacyPolicy,
          page: () => const PrivacyPolicyScreen(),
        ),
        GetPage(
          name: AppRoutes.webBooking,
          page: () => const WebBookingScreen(),
        ),
      ],
    );
  }
}

/// When the Flutter web app is opened via a booking URL (e.g.
/// `bookingHost/#/web-booking?doctor=X`), the initial route must be
/// `/web-booking` so the WebBookingScreen renders directly. Without this,
/// `initialRoute: '/'` loads the splash screen, whose `_navigate()` call
/// destroys the web-booking route and shows a blank page.
String _initialRoute() {
  if (!kIsWeb) return AppRoutes.splash;
  try {
    final fragment = Uri.base.fragment;
    if (isWebBookingFragment(fragment)) {
      return AppRoutes.webBooking;
    }
  } catch (_) {}
  return AppRoutes.splash;
}

/// Loads the logged-in doctor's clinic payment rows for the doctor payment
/// history screen (same doctor-scoped RLS path as the appointments screen).
/// Returns an empty list when nobody is logged in.
Future<List<PaymentModel>> _loadDoctorPayments() async {
  final user = Get.find<AuthController>().currentUser.value;
  final id = user?.id;
  if (id == null) return const [];
  final rows = await SupabaseService().getPaymentsForDoctor(id);
  return rows.map((r) => PaymentModel.fromJson(r)).toList();
}
