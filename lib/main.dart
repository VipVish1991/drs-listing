import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'app.dart';
import 'config/theme.dart';
import 'services/api_health_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/status_bar_service.dart';
import 'services/supabase_service.dart';
import 'services/local_storage_service.dart';
import 'controllers/auth_controller.dart';
import 'controllers/voice_controller.dart';
import 'controllers/doctor_search_controller.dart';
import 'controllers/appointment_controller.dart';
import 'controllers/profile_controller.dart';
import 'controllers/doctor_controller.dart';
import 'services/deep_link_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables from .env file
  // isOptional=true so the app doesn't crash if .env is missing
  await dotenv.load(fileName: '.env', isOptional: true);

  // Initialize services
  final supabaseService = SupabaseService();
  await supabaseService.init();

  final localStorageService = LocalStorageService();
  await localStorageService.init();

  // Firebase Cloud Messaging (push notifications). Non-fatal: without Play
  // Services / on desktop this degrades to a silent no-op, and notification
  // calls from the app are always fire-and-forget.
  await NotificationService.instance.init();

  // Inject dependencies.
  //
  // NOTE: HomeController is deliberately NOT registered here. It drives the
  // patient home's location fetch, GPS-off popup and location-permission
  // prompts — which must be asked ONLY on the patient side. It is created
  // by the patient MainShell when a patient actually opens their dashboard,
  // so the doctor side (and pre-login screens) never instantiate it and are
  // never asked for location.
  Get.put(AuthController(), permanent: true);
  Get.put(VoiceController(), permanent: true);
  Get.put(DoctorSearchController(), permanent: true);
  Get.put(AppointmentController(), permanent: true);
  Get.put(ProfileController(), permanent: true);
  Get.put(DoctorController(), permanent: true);

  // Run API health check in background (non-blocking). Results are
  // cached in ApiHealthService and displayed on the splash screen.
  ApiHealthService().checkAll();

  // Listen for drslisting:// deep links (cold + warm start). Non-blocking:
  // pending links are dispatched once the navigator becomes available.
  DeepLinkService.instance.start();

  runApp(const App());

  // Watch internet connectivity and show the app-wide "No internet
  // connection" banner while offline (connectivity_plus). Started after
  // runApp so the first Scaffold is registered before the initial check.
  ConnectivityService.instance.start();

  // App-wide system UI style: a solid BLACK status bar with white icons
  // (Android), light navigation bar, and dark status-bar text on iOS
  // (where the bar itself is transparent over the app's light surfaces).
  // Every screen inherits this default; screens can override locally.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bgMain,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Keep the native status bar black via the plugin as well (best-effort,
  // fire-and-forget — silently no-ops in tests).
  StatusBarService.applyTheme(AppTheme.lightTheme);
}
