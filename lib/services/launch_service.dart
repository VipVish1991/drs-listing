import 'package:url_launcher/url_launcher.dart';
import '../utils/snackbar_helpers.dart';

/// Centralized service for launching external apps (phone dialer, maps).
///
/// Eliminates duplicated _launchPhone / _launchMap methods across screens.
/// All callers show consistent error feedback via [showErrorSnackbar].
class LaunchService {
  LaunchService._();

  /// Opens the native phone dialer with [phone].
  ///
  /// Shows an error snackbar if the device can't dial the number.
  static Future<void> phone(String? phone) async {
    if (phone == null || phone.isEmpty) return;

    // Patient/doctor mobiles often contain spaces or dashes
    // (e.g. "+91 98765 43210"). Percent-encoded whitespace in a tel: URI
    // makes many dialers fail to parse the recipient, so strip everything
    // except digits and a leading '+', matching the sms()/whatsApp() paths.
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) {
      showErrorSnackbar('Unable to make a call');
      return;
    }

    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      showErrorSnackbar('Unable to make a call');
    }
  }

  /// Opens Google Maps at the given [lat], [lng] coordinates.
  ///
  /// Shows an error snackbar if maps can't be launched.
  static Future<void> map(double? lat, double? lng) async {
    if (lat == null || lng == null) return;

    final uri = Uri.parse('https://maps.google.com/maps?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      showErrorSnackbar('Unable to open maps');
    }
  }

  /// Likewise, extracts lat/lng from a [location] JSON map.
  ///
  /// Used by [AppointmentHistoryScreen] where coordinates are stored in a
  /// JSONB column (`map_location`) with `latitude` and `longitude` keys.
  static Future<void> mapFromLocation(Map<String, dynamic>? location) async {
    if (location == null) return;
    final lat = location['latitude'] as num?;
    final lng = location['longitude'] as num?;
    if (lat != null && lng != null) {
      await map(lat.toDouble(), lng.toDouble());
    }
  }

  /// Opens a URL in the default browser (or in-app if supported).
  ///
  /// Used for website and Google Maps links on the doctor detail screen.
  static Future<void> url(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final uri = Uri.tryParse(urlString);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      showErrorSnackbar('Unable to open link');
    }
  }

  /// Opens WhatsApp chat with the given [phone] number.
  ///
  /// Expects a full phone number including country code (e.g. "+919876543210").
  /// Strips non-digit characters and prefixes with country code 91 if none
  /// is detected. An optional [message] is pre-filled in the chat
  /// (wa.me/?text= — ignored when the platform's URL encoding can't
  /// represent it, which is fine).
  static Future<void> whatsApp(String? phone, {String? message}) async {
    if (phone == null || phone.isEmpty) return;

    // Strip all non-digit characters
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    // Ensure at least 10 digits; if exactly 10, assume India (+91)
    final clean = digits.length == 10 ? '91$digits' : digits;

    final uri = Uri.parse(
      'https://wa.me/$clean'
      '${message != null && message.trim().isNotEmpty ? '?text=${Uri.encodeComponent(message.trim())}' : ''}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      showErrorSnackbar('Unable to open WhatsApp');
    }
  }

  /// Opens the native SMS app with the given [phone] number pre-filled.
  ///
  /// Optionally includes a [message] body. On Android, tries `sms:` first
  /// and falls back to `smsto:` — some devices only resolve one of the two
  /// schemes, and the manifest now declares both so `canLaunchUrl` returns
  /// true on Android 11+ (package visibility).
  static Future<void> sms(String? phone, {String? message}) async {
    if (phone == null || phone.isEmpty) return;

    // Google Places phone numbers often contain spaces/dashes
    // (e.g. "+91 98765 43210"). Percent-encoded whitespace in the URI path
    // makes some Android SMS apps fail to parse the recipient, so strip
    // everything except digits and a leading '+'. This also lets
    // canLaunchUrl's intent match the manifest <queries> declarations.
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) {
      showErrorSnackbar('Unable to open SMS app');
      return;
    }

    final query = message != null && message.trim().isNotEmpty
        ? {'body': message.trim()}
        : null;

    // Try `sms:` then `smsto:`. Many Android SMS apps register
    // ACTION_SENDTO with `smsto:` but not ACTION_VIEW with `sms:`, so
    // canLaunchUrl (which checks the VIEW action) can return a false
    // negative even when the intent would resolve. Never let that block
    // the launch — fall through to a direct launch attempt at the end.
    final candidates = <Uri>[
      Uri(scheme: 'sms', path: clean, queryParameters: query),
      Uri(scheme: 'smsto', path: clean, queryParameters: query),
    ];

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {
        // canLaunchUrl itself can throw on some devices — try the next
        // scheme instead of giving up.
      }
    }

    // canLaunchUrl false-negative fallback: launch each scheme directly and
    // let the platform resolve it. A device that lied about not handling one
    // scheme still gets a chance with the other. If nothing handles either
    // intent this throws, which we surface as the usual error snackbar.
    for (final uri in candidates) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      } catch (_) {
        // Try the other scheme.
      }
    }
    showErrorSnackbar('Unable to open SMS app');
  }

  /// Opens the default email client with an optional [recipient], [subject],
  /// and [body] pre-filled.
  ///
  /// When [recipient] is null, a blank compose window is shown so the
  /// user can type the email address themselves.
  static Future<void> email({
    String? recipient,
    String? subject,
    String? body,
  }) async {
    final params = <String, String>{};
    if (subject != null) params['subject'] = subject;
    if (body != null) params['body'] = body;

    final uri = Uri(
      scheme: 'mailto',
      path: recipient ?? '',
      queryParameters: params.isNotEmpty ? params : null,
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      showErrorSnackbar('Unable to open email app');
    }
  }
}
