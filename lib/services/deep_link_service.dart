import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';

import '../config/constants.dart';
import '../controllers/doctor_controller.dart';
import '../routes/app_routes.dart';
import '../utils/snackbar_helpers.dart';
import 'launch_service.dart';

/// The action a `drslisting://` deep link maps to.
sealed class DeepLinkTarget {
  const DeepLinkTarget();
}

/// `drslisting://book/<placeId>` → open the doctor's booking page.
class BookingDeepLinkTarget extends DeepLinkTarget {
  const BookingDeepLinkTarget(this.placeId);

  final String placeId;
}

/// `drslisting://manage-slots/<placeId>` → open the doctor's slot
/// management dashboard.
class ManageSlotsDeepLinkTarget extends DeepLinkTarget {
  const ManageSlotsDeepLinkTarget(this.placeId);

  final String placeId;
}

/// Parses a [uri] into a deep-link target, or `null` if it isn't a
/// supported link.
///
/// Accepts both forms:
///   - custom scheme: `drslisting://book/<placeId>` (host = route)
///   - universal/app link: `https://drslisting.ai/book/<placeId>`
///     (first path segment = route, second = placeId)
///
/// Kept as a pure function so the routing logic is unit-testable without
/// the native app_links plugin.
DeepLinkTarget? parseDeepLink(Uri uri) {
  if (uri.scheme == AppConstants.deepLinkScheme) {
    // drslisting://book/<placeId>  (host carries the route)
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    final placeId = Uri.decodeComponent(segments.first);
    if (placeId.isEmpty) return null;
    return _targetForRoute(uri.host, placeId);
  }

  if (uri.scheme == 'https' &&
      (uri.host == AppConstants.appLinksHost ||
          uri.host == 'www.${AppConstants.appLinksHost}')) {
    // https://drslisting.ai/book/<placeId>  (path carries the route)
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    final placeId = Uri.decodeComponent(segments[1]);
    if (placeId.isEmpty) return null;
    return _targetForRoute(segments[0], placeId);
  }

  return null;
}

DeepLinkTarget? _targetForRoute(String route, String placeId) {
  switch (route) {
    case 'book':
      return BookingDeepLinkTarget(placeId);
    case 'manage-slots':
      return ManageSlotsDeepLinkTarget(placeId);
    default:
      return null;
  }
}

/// Routes incoming `drslisting://` deep links in-app.
///
/// The custom scheme is registered natively on Android (intent filters in
/// AndroidManifest.xml) and iOS (CFBundleURLTypes in Info.plist). This
/// service listens for both cold-start (app launched via a link) and
/// warm-start (app already running) links and routes them accordingly.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Start listening for deep links. Safe to call once during startup.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Cold start: the app was launched by opening a deep link.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        unawaited(handleUri(initial));
      }
    } catch (_) {
      // Deep links unavailable on this platform — non-fatal.
    }

    // Warm start: the app is already running and receives a link.
    _sub = _appLinks.uriLinkStream.listen(
      handleUri,
      onError: (Object _) {
        // Non-fatal.
      },
    );
  }

  /// Routes a single incoming link to its target.
  ///
  /// Public so tests (and any non-plugin link source) can drive routing
  /// directly without the native app_links plugin.
  Future<void> handleUri(Uri uri) async {
    final target = parseDeepLink(uri);
    switch (target) {
      case BookingDeepLinkTarget(:final placeId):
        // Product decision: the booking flow lives on the web page, so
        // open it in the system browser.
        await LaunchService.url(AppConstants.bookingPageUrl(placeId));
      case ManageSlotsDeepLinkTarget(:final placeId):
        await _openManageSlots(placeId);
      case null:
        break;
    }
  }

  Future<void> _openManageSlots(String placeId) async {
    // A cold-start link may arrive before the navigator exists — wait
    // for Get.context to become available first.
    await _waitForNavigator();

    final doctorController = Get.find<DoctorController>();
    await doctorController.loadDoctorFromDb(placeId);
    final doctor = doctorController.currentDoctor.value;
    if (doctor == null) {
      showErrorSnackbar('Doctor not found for this link');
      return;
    }
    Get.toNamed(AppRoutes.doctorDashboard);
  }

  Future<void> _waitForNavigator() async {
    for (var i = 0; i < 50 && Get.context == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Cancel the stream subscription (e.g. when the app is disposed).
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
