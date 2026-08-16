import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_meet_sdk/src/utils/calendar_client.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;

/// Google Sign-In + Google Calendar wiring for Meet-backed consultations.
///
/// PATCHED vs upstream google_meet_sdk 0.0.3:
///   * The upstream version reads `clientId` / `serverClientId` from the
///     Android manifest through the unmaintained `platform_metadata`
///     package, and uses the pre-7.x `google_sign_in` API
///     (`GoogleSignIn(clientId: ...)` + `signIn()`). google_sign_in 7.x
///     removed that API in favor of a singleton
///     (`GoogleSignIn.instance.initialize(...)` + `authenticate(...)` +
///     `authorizationClient.authorizationHeaders(...)`), which this copy
///     uses. The client IDs are exposed as static fields the host app
///     sets once at startup (from its google-services.json OAuth client).
///   * The upstream `GoogleAPIClient` extends `http/io_client.dart`
///     (dart:io) which breaks any web compile of the package. This copy
///     uses a plain `http.BaseClient` wrapper so the source analyzes on
///     every platform (the host app still guards the SDK behind a
///     conditional import for web).
class GoogleAuthentication {
  GoogleAuthentication._();

  /// GCP OAuth web client ID (from google-services.json, client_type 3)
  /// used by GoogleSignIn. Set by the host app before first use.
  static String clientId = '';

  /// Optional GCP web client ID used as the OAuth2 audience when
  /// exchanging the sign-in token for a refresh token on Android.
  static String? serverClientId;

  static bool _initialized = false;

  /// Signs the user in with their Google account, requesting the Google
  /// Calendar scopes the SDK needs to create Meet-backed events.
  ///
  /// Returns the FirebaseAuth user on success, null on failure/cancel.
  static Future<User?> signInWithGoogle({required BuildContext context}) async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    User? user;
    if (clientId.isEmpty) {
      showSnackBar(
        content: 'Google Sign-In is not configured (missing clientId).',
      );
      return null;
    }
    final GoogleSignIn googleSignIn = GoogleSignIn.instance;
    try {
      if (!_initialized) {
        await googleSignIn.initialize(
          clientId: clientId,
          serverClientId: serverClientId,
        );
        _initialized = true;
      }
      final GoogleSignInAccount account = await googleSignIn.authenticate(
        scopeHint: <String>[
          cal.CalendarApi.calendarScope,
          cal.CalendarApi.calendarEventsScope,
        ],
      );
      // Authorize the Calendar scopes and grab the Bearer headers for the
      // Calendar API client. Throws GoogleSignInException on failure.
      final Map<String, String>? headers =
          await account.authorizationClient.authorizationHeaders(
        <String>[
          cal.CalendarApi.calendarScope,
          cal.CalendarApi.calendarEventsScope,
        ],
        promptIfNecessary: true,
      );
      if (headers != null) {
        CalendarClient.calendar = cal.CalendarApi(GoogleAPIClient(headers));
      }
      final String? idToken = account.authentication.idToken;
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );
      try {
        final UserCredential userCredential =
            await auth.signInWithCredential(credential);
        user = userCredential.user;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'account-exists-with-different-credential') {
          showSnackBar(
            content: 'The account already exists with a different credential',
          );
        } else if (e.code == 'invalid-credential') {
          showSnackBar(
            content: 'Error occurred while accessing credentials. Try again.',
          );
        }
      } catch (e) {
        showSnackBar(content: 'Error occurred using Google Sign In. Try again.');
      }
    } on GoogleSignInException catch (e) {
      // A canceled/interrupted picker is a normal user action — stay quiet.
      if (e.code != GoogleSignInExceptionCode.canceled &&
          e.code != GoogleSignInExceptionCode.interrupted) {
        showSnackBar(
          content: 'Google Sign-In failed: ${e.description ?? e.code.name}',
        );
      }
    }
    return user;
  }

  /// Signs the user out of both Google Sign-In and Firebase Auth.
  static Future<void> signOut({required BuildContext context}) async {
    final GoogleSignIn googleSignIn = GoogleSignIn.instance;
    try {
      if (!kIsWeb) {
        await googleSignIn.signOut();
      }
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Error signing out. Try again.');
    }
  }

  /// Shows a simple black snackbar (upstream style). PATCHED: upstream
  /// only CONSTRUCTED the SnackBar and never showed it, silently dropping
  /// every sign-in failure on device. This copy actually surfaces it via
  /// Get (falls back to a no-op when no overlay context exists, e.g. in
  /// tests).
  static void showSnackBar({required String content}) {
    debugPrint('GoogleAuthentication: $content');
    final context = Get.context;
    if (context == null) return;
    Get.snackbar(
      'Google Sign-In',
      content,
      backgroundColor: Colors.black,
      colorText: Colors.redAccent,
      duration: const Duration(seconds: 4),
    );
  }
}

/// HTTP client that injects the Google Sign-In auth headers onto every
/// request to the Calendar API. (Web-safe `http.BaseClient` wrapper —
/// upstream used `IOClient` from `package:http/io_client.dart`.)
class GoogleAPIClient extends http.BaseClient {
  final Map<String, String> _headers;

  GoogleAPIClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return request.send();
  }
}
