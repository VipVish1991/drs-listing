import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../controllers/auth_controller.dart';
import '../controllers/notification_center_controller.dart';
import '../models/user_model.dart';
import '../routes/app_routes.dart';
import '../widgets/in_app_notification_banner.dart';
import 'supabase_service.dart';

/// Firebase Cloud Messaging wrapper.
///
/// Responsibilities:
///   * Initialize Firebase + request notification permission + fetch the
///     device's FCM registration token.
///   * Persist that token on the caller's `users` row (multi-device array)
///     so the notifications Edge Function can reach this device.
///   * Push appointment events to the notifications Edge Function:
///       - appointment booked  → the DOCTOR is notified
///       - status changed      → the PATIENT is notified
///   * Show a SYSTEM banner (heads-up + sound) for pushes that arrive in the
///     foreground — with an in-app overlay banner as fallback — and
///     navigate on tap.
///
/// **Test/plugin safety:** every method is wrapped so a missing Firebase
/// native plugin (widget tests, unsupported desktop, no Play Services)
/// degrades to a silent no-op instead of crashing the app.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final SupabaseService _supabase = SupabaseService();

  /// True once Firebase has initialized (native config present). Token
  /// fetch + registration stay disabled until this is set.
  bool _firebaseReady = false;

  /// The last token fetched from FCM for THIS device.
  String? _token;

  /// Guards against overlapping token fetches (init + login can race).
  bool _fetchingToken = false;

  /// Guards against duplicate listener registration across init calls.
  bool _listenersAttached = false;

  /// Posts real SYSTEM notifications for pushes that arrive while the app is
  /// in the foreground (FCM only auto-displays while backgrounded). Uses the
  /// same high-importance channel as native background pushes, so both look
  /// identical (heads-up banner + sound).
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// True once the local-notifications plugin initialized (channel ready).
  bool _localNotifReady = false;

  // ── Lifecycle ────────────────────────────────────────────────────

  /// Initialize Firebase + FCM and start listening for messages.
  /// Called once from main() after Supabase init. Non-fatal on failure.
  ///
  /// Each step is isolated so one hiccup (permission dialog, token fetch on
  /// an emulator without Play Services, offline first launch) can never
  /// disable the whole pipeline: the token is re-fetched lazily by
  /// [syncTokenForCurrentUser] on the next login/registration.
  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      // No Firebase config (e.g. iOS without GoogleService-Info.plist) or
      // native plugin missing — notifications simply no-op.
      debugPrint('⚠️ [NotificationService] Firebase init failed (non-fatal): $e');
      return;
    }

    // Listeners first — they don't need permission or a token.
    _attachListeners();

    // Permission is best-effort: a denial must NOT block the token fetch
    // (the token still enables data-only pushes and works once the user
    // grants permission later).
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint(
        '⚠️ [NotificationService] permission request failed (non-fatal): $e',
      );
    }

    // Local-notifications plugin: lets the app post a REAL system banner for
    // foreground pushes (the OS would otherwise only show it while the app
    // is backgrounded). Reuses the native channel created by the Application
    // class, so foreground and background pushes look identical. Isolated and
    // non-fatal — if it fails, foreground pushes fall back to the in-app
    // overlay banner.
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        // Permissions are already requested via FirebaseMessaging above.
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
        // Present banners + sound even while the app is in the foreground.
        defaultPresentAlert: true,
        defaultPresentSound: true,
        defaultPresentBadge: true,
      );
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: darwinInit,
        ),
        onDidReceiveNotificationResponse: _handleLocalNotificationTap,
      );
      _localNotifReady = true;
    } catch (e) {
      debugPrint(
        '⚠️ [NotificationService] local notifications init failed '
        '(non-fatal): $e',
      );
    }

    // Fetch the token now — and again lazily whenever a sync runs without
    // one (see [syncTokenForCurrentUser]).
    await _ensureToken();

    // Warm start with an already-logged-in user → register this device.
    // No-op if AuthController isn't registered yet (login / checkAuthStatus
    // re-sync later).
    syncTokenForCurrentUser();
  }

  /// Bounded startup variant of [init] for main(): runs [init] (defaults to
  /// [this.init]) with a hard [timeout] so a native plugin that hangs — e.g.
  /// FirebaseMessaging's permission/token calls on devices with broken
  /// Google Play Services — can never block app startup. Never throws: on
  /// timeout or failure startup continues and notifications silently no-op,
  /// exactly as they already do when Firebase is unavailable. Tests inject a
  /// stub [init] with a short [timeout].
  Future<void> initBounded({
    Future<void> Function()? init,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      await (init ?? this.init)().timeout(timeout);
    } catch (_) {
      // Timed out or failed — notifications silently no-op, app continues.
    }
  }

  /// Register FCM listeners exactly once (token rotation, foreground banner,
  /// tap navigation). Safe to call repeatedly.
  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    final messaging = FirebaseMessaging.instance;

    // Token rotation → re-persist on the user row.
    messaging.onTokenRefresh.listen((newToken) {
      _token = newToken;
      syncTokenForCurrentUser();
    });

    // Foreground message → system banner (heads-up + sound), with the
    // in-app overlay banner as fallback when the system post is unavailable.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Tap on a system notification (backgrounded/terminated) → navigate.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    messaging.getInitialMessage().then(_handleMessageTap);
  }

  /// Fetch the FCM token if Firebase is ready and none is cached. Safe to
  /// call at any time: guarded against concurrent runs and tight retry
  /// loops. Once a token arrives it is immediately registered for the
  /// current user, so a token that was unavailable at startup still lands
  /// on the user row without waiting for the next login.
  Future<void> _ensureToken() async {
    if (!_firebaseReady || _fetchingToken || _token != null) return;
    _fetchingToken = true;
    try {
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) {
        debugPrint('✅ [NotificationService] FCM token acquired');
        syncTokenForCurrentUser();
      } else {
        // getToken() succeeded but returned no token yet (no exception —
        // the silent path that previously left every user's device_tokens
        // empty). The next login/registration retries.
        debugPrint('⚠️ [NotificationService] getToken returned null ' '(no token available yet — will retry)');
      }
    } catch (e) {
      // Transient failure (offline, no Play Services yet) — the next
      // login/registration (or token refresh) retries.
      debugPrint('⚠️ [NotificationService] getToken failed (will retry): $e');
      _token = null;
    } finally {
      _fetchingToken = false;
    }
  }

  // ── Device-token persistence ─────────────────────────────────────

  /// Register the current device token on [user]'s row (multi-device).
  /// Fire-and-forget: token sync must never block login/registration.
  ///
  /// If the token isn't cached yet (startup fetch failed), this triggers a
  /// lazy fetch which registers it as soon as FCM answers — so a device
  /// that was offline at launch still registers on the next login.
  void syncTokenForCurrentUser() {
    try {
      final user = Get.find<AuthController>().currentUser.value;
      if (user?.id == null || !_firebaseReady) return;
      if (_token == null) {
        unawaited(_ensureToken());
        return;
      }
      unawaited(_registerToken(user!));
    } catch (_) {
      // AuthController not registered (e.g. during early startup) — skip.
    }
  }

  /// Remove this device's token from [user]'s row (logout) so a shared
  /// device never pushes the previous user's notifications — with ONE
  /// deliberate exception: **doctor accounts keep their registration**.
  ///
  /// A doctor's phone is routinely shared with patients (a receptionist
  /// logs into the same device to book appointments). Removing the doctor's
  /// token on logout would silently silence every "New Appointment
  /// Request"/cancellation push for the clinic. The device_tokens JSONB
  /// array supports one token on many rows, so the token stays on the
  /// doctor's row (booking alerts keep arriving on this phone) while the
  /// patient's row is still cleaned up (their status-change notifications
  /// don't leak to the next user on the shared device). Stale tokens are
  /// pruned server-side when FCM reports them unregistered.
  Future<void> removeTokenForUser(UserModel user) async {
    if (user.id == null || !_firebaseReady || _token == null) return;
    // Doctor logout → keep this device registered so booking pushes still
    // reach the clinic even while a patient account is logged in here.
    if (user.isDoctor) {
      debugPrint(
        'ℹ️ [NotificationService] doctor logout — keeping device token '
        'so booking pushes still arrive',
      );
      return;
    }
    try {
      await _supabase.removeDeviceToken(user.id!, _token!);
    } catch (e) {
      debugPrint('⚠️ [NotificationService] token removal failed: $e');
    }
  }

  /// Persist the device token on [user]'s row. A short retry loop absorbs
  /// transient network blips at login/registration so the token is not
  /// silently lost (the next login / token refresh re-syncs anyway).
  Future<void> _registerToken(UserModel user) async {
    const attempts = 3;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _supabase.addDeviceToken(
          user.id!,
          _token!,
          platform: defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        );
        debugPrint(
          '✅ [NotificationService] device token registered for '
          '${user.mobile ?? user.id}',
        );
        return;
      } catch (e) {
        debugPrint(
          '⚠️ [NotificationService] token sync failed '
          '(attempt $attempt/$attempts): $e',
        );
        if (attempt < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
  }

  // ── Appointment event notifications ─────────────────────────────

  /// Notify the doctor that a patient booked an appointment. Called after a
  /// successful insert — fire-and-forget so it never blocks the booking UI.
  Future<void> notifyAppointmentBooked({
    required String appointmentId,
    required String senderMobile,
  }) async {
    await _sendEvent(
      event: 'appointment_booked',
      appointmentId: appointmentId,
      senderMobile: senderMobile,
    );
  }

  /// Notify the doctor that the patient cancelled their appointment.
  Future<void> notifyAppointmentCancelled({
    required String appointmentId,
    required String senderMobile,
  }) async {
    await _sendEvent(
      event: 'appointment_cancelled',
      appointmentId: appointmentId,
      senderMobile: senderMobile,
    );
  }

  /// Notify the doctor that the patient rescheduled their appointment to a
  /// different slot. Called after a successful patient reschedule —
  /// fire-and-forget.
  Future<void> notifyAppointmentRescheduled({
    required String appointmentId,
    required String senderMobile,
  }) async {
    await _sendEvent(
      event: 'appointment_rescheduled',
      appointmentId: appointmentId,
      senderMobile: senderMobile,
    );
  }

  /// Notify the PATIENT that the DOCTOR (clinic) moved their appointment to
  /// a different slot. Called after a successful doctor-initiated reschedule
  /// — fire-and-forget. Uses its own event (`appointment_rescheduled_by_doctor`)
  /// so the patient can tell a clinic-moved reschedule apart from their own
  /// and opt out of the two alerts independently in Notification Settings.
  Future<void> notifyAppointmentRescheduledByDoctor({
    required String appointmentId,
    required String senderMobile,
  }) async {
    await _sendEvent(
      event: 'appointment_rescheduled_by_doctor',
      appointmentId: appointmentId,
      senderMobile: senderMobile,
    );
  }

  /// Notify the patient that the doctor changed their appointment status.
  Future<void> notifyAppointmentStatusChanged({
    required String appointmentId,
    required String status,
    required String senderMobile,
  }) async {
    await _sendEvent(
      event: 'appointment_status_changed',
      appointmentId: appointmentId,
      status: status,
      senderMobile: senderMobile,
    );
  }

  Future<void> _sendEvent({
    required String event,
    required String appointmentId,
    String? status,
    required String senderMobile,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConstants.notifyFunctionUrl),
            headers: {
              'Content-Type': 'application/json',
              'x-notify-token': AppConstants.notifySharedSecret,
              'x-user-mobile': senderMobile,
            },
            body: jsonEncode({
              'event': event,
              'appointment_id': appointmentId,
              if (status != null && status.isNotEmpty) 'status': status,
              'sender_mobile': senderMobile,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ [NotificationService] $event → HTTP ${response.statusCode}: '
          '${response.body}',
        );
      }
    } catch (e) {
      // Offline / function not deployed / tests — never surface to the user.
      debugPrint('⚠️ [NotificationService] $event failed (non-fatal): $e');
    }
  }

  // ── Message handling ────────────────────────────────────────────

  /// A push arrived while the app is in the FOREGROUND. The OS does NOT show
  /// system banners for foreground FCM messages, so this posts a real system
  /// notification (heads-up + sound on the high-importance channel) — the
  /// same look as a background push — and falls back to the in-app overlay
  /// banner if the system post is unavailable (plugin missing, permission
  /// denied, …). Guarded throughout so a foreground push can never crash the
  /// app; the push is still recorded in the notification center regardless.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title;
    final body = message.notification?.body;
    if (title == null && body == null) return;

    final posted = await _showSystemNotification(
      title: title ?? 'DrsListing',
      body: body ?? '',
      data: message.data,
    );

    if (!posted) {
      try {
        InAppNotificationBanner.instance.show(
          title: title ?? 'DrsListing',
          body: body ?? '',
          type: message.data['type']?.toString() ?? '',
          onTap: () => _handleMessageTap(message),
        );
      } catch (_) {
        // No navigator/overlay context available — ignore.
      }
    }

    // The Edge Function already persisted this push as a history row —
    // reload the in-app center so the badge updates live.
    try {
      NotificationCenterController.instance.load();
    } catch (_) {
      // Not logged in / controller unavailable — the center loads on open.
    }
  }

  /// Post a REAL system notification for a foreground push on the shared
  /// `drslisting_appointments` high-importance channel (same one native
  /// background pushes use). Returns false when the plugin isn't ready or
  /// the post throws — callers fall back to the in-app banner.
  Future<bool> _showSystemNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    if (!_localNotifReady) return false;

    // If notification permission was DENIED, the plugin's show() silently
    // no-ops (returns success, nothing displays) — so bail out here and let
    // the caller fall back to the in-app overlay banner instead of showing
    // nothing at all. Android <13 reports Authorized by default, so this
    // only changes behavior on permission-denied devices.
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      final authorized = status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
      if (!authorized) {
        debugPrint(
          '⚠️ [NotificationService] notification permission denied — '
          'using in-app banner',
        );
        return false;
      }
    } catch (_) {
      // Can't read the status — let the post attempt decide.
    }

    try {
      const androidDetails = AndroidNotificationDetails(
        'drslisting_appointments',
        'Appointment Alerts',
        channelDescription: 'New appointment requests, cancellations and '
            'status updates',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      );
      await _localNotifications.show(
        // Fixed id → each foreground push replaces the previous one instead
        // of stacking notifications in the shade.
        id: 0,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: jsonEncode(data),
      );
      debugPrint('✅ [NotificationService] system banner posted (foreground)');
      return true;
    } catch (e) {
      debugPrint(
        '⚠️ [NotificationService] system banner failed '
        '(falling back to in-app): $e',
      );
      return false;
    }
  }

  /// Tap on the locally-posted foreground system notification → route like
  /// any other notification tap.
  void _handleLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      _handleDataTap(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {
      // Malformed payload — just reload the center so nothing is lost.
    }
  }

  /// Tap on a system notification (backgrounded/terminated FCM push) →
  /// route.
  void _handleMessageTap(RemoteMessage? message) {
    if (message == null) return;
    _handleDataTap(message.data);
  }

  /// Shared tap routing: reload the notification center (badge + list) and
  /// open the screen the push is about (doctor dashboard for doctors, home
  /// for patients). Never throws.
  void _handleDataTap(Map<String, dynamic> data) {
    // The pushed history row may not have been fetched yet — reload so the
    // badge + list are correct when the center is opened.
    try {
      NotificationCenterController.instance.load();
    } catch (_) {}
    try {
      final auth = Get.find<AuthController>();
      if (auth.currentUser.value?.isDoctor ?? false) {
        Get.toNamed(AppRoutes.doctorDashboard);
      } else {
        Get.toNamed(AppRoutes.home);
      }
    } catch (_) {
      // Not logged in yet or routes unavailable — fall back to default home.
      try {
        Get.toNamed(AppRoutes.home);
      } catch (_) {}
    }
  }
}
