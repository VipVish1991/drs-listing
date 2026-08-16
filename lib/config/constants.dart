import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static const String appName = 'DrsListing';
  static const String appTagline = 'Your AI Health Assistant';

  // API Keys — loaded from .env file at runtime via flutter_dotenv
  static String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';

  // Supabase — these are publishable values (not secrets) and are kept
  // as const so the app works even without a .env file.
  static const String supabaseUrl = 'https://qxukzqdsmlurollltrjp.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_vPRXzEGJJtwGvoRYrQC3VA_9HPIZvgP';

  // Google Places API configuration
  static const String googlePlacesBaseUrl =
      'https://maps.googleapis.com/maps/api/place';

  // Server-side proxy for Google Places API (avoids CORS on web).
  // Deployed as the `places-proxy` Supabase Edge Function; the browser can
  // call *.supabase.co/functions/v1/... (no CORS block), and the API key is
  // injected server-side instead of shipping it in the web bundle.
  static const String placesProxyUrl =
      'https://qxukzqdsmlurollltrjp.supabase.co/functions/v1/places-proxy';

  // Browser booking page — encoded into the QR code shown from the doctor
  // profile "Book" button. Patients scan it to open the booking form in
  // their browser and book an appointment.
  //
  // The form is a STATIC page (booking.html) served from free GitHub Pages;
  // its source lives in the `drsListing-web` GitHub repo
  // (github.com/VipVish1991/drsListing-web). It cannot be served from the
  // Supabase Edge Function directly: Supabase rewrites text/html GET
  // responses to text/plain on the shared *.supabase.co domain, so
  // browsers showed the raw HTML source instead of rendering the page.
  // The static page reads the placeId + shared token from the URL and
  // POSTs to the booking-page Edge Function as a JSON API.
  //
  // The booking shared secret gates the API: it is embedded in the URL and
  // replayed as the `x-booking-token` header when the form submits. It
  // must match the BOOKING_SHARED_SECRET env var set on the deployed
  // Edge Function, e.g.: supabase secrets set BOOKING_SHARED_SECRET=<value>
  //
  // Live static host serving the drsListing-web site. Every push to main
  // deploys via .github/workflows/pages.yml (Settings → Pages → Source:
  // GitHub Actions must be enabled once).
  //
  // Booking URLs point at the REAL static file (booking.html) with the
  // placeId as a ?doctor= query param — GitHub Pages has no server-side
  // rewrites, so the pretty /book/<placeId> path has no backing file and
  // would be served through 404.html with an HTTP 404 status (crawlers
  // treat that as missing). booking.html?doctor=<placeId> is a real file
  // → HTTP 200, and booking.html reads the doctor id from the query
  // string. The old /book/<placeId> QR links still render (404.html
  // fallback parses the path segment), so already-printed QRs keep
  // working.
  static const String bookingHost = 'https://VipVish1991.github.io/drsListing-web';
  static const String bookingSharedSecret = 'cAZrwHpDFJ4HaSNXowJnmvzi-0YD5rYE';

  // ── Push notifications (FCM) ─────────────────────────────────────
  // Shared secret that gates the notifications Edge Function, replayed as
  // the `x-notify-token` header — same pattern as the booking secret, but a
  // DELIBERATELY DIFFERENT value: the booking secret ships in every printed
  // QR URL, so reusing it would give the notifications endpoint no real
  // gate at all. Must match the NOTIFY_SHARED_SECRET env var set on the
  // deployed Edge Function (see supabase/deploy_notifications.py).
  static const String notifySharedSecret = 'n9Kq4Zx7Vm2Lp8Rt5Ys3Cb6Hf1Wj0AeD';

  /// Shared token that gates the places-proxy Edge Function, appended as
  /// the `token` query param on every proxy request — same pattern as the
  /// booking/notify secrets (extractable from the app, but it stops random
  /// traffic from burning the Google Maps API quota). Must match the
  /// PLACES_SHARED_SECRET env var set on the deployed Edge Function.
  static const String placesProxyToken = 'pL4sT9xKq2Wv7YmR5Hc3Nb8Fg1Jd0UeA';

  /// URL of the notifications Edge Function (FCM push sending).
  static String get notifyFunctionUrl =>
      '$supabaseUrl/functions/v1/notifications';
  static String bookingPageUrl(String placeId, {String? doctorName}) {
    // booking.html is a REAL static file on GitHub Pages (returns HTTP 200
    // to crawlers), with the placeId passed as ?doctor= — the booking page
    // reads it from the query string. This replaced the pretty
    // /book/<placeId> path, which GitHub Pages serves via 404.html with an
    // HTTP 404 status (no server-side rewrites on Pages).
    final buffer = StringBuffer(
      '$bookingHost/booking.html'
      '?doctor=${Uri.encodeComponent(placeId)}'
      '&token=$bookingSharedSecret',
    );
    if (doctorName != null && doctorName.isNotEmpty) {
      buffer.write('&name=${Uri.encodeComponent(doctorName)}');
    }
    return buffer.toString();
  }

  // ── Deep links (drslisting:// scheme) ────────────────────────────
  // Custom URL scheme registered natively on Android (intent filters in
  // AndroidManifest.xml) and iOS (CFBundleURLTypes in Info.plist). The app
  // listens via DeepLinkService and routes incoming links in-app.
  static const String deepLinkScheme = 'drslisting';

  /// `drslisting://book/<placeId>` — opens the browser booking page
  /// (AppConstants.bookingPageUrl) for the given place in-app.
  static String bookingDeepLink(String placeId) =>
      '$deepLinkScheme://book/${Uri.encodeComponent(placeId)}';

  /// `drslisting://manage-slots/<placeId>` — opens the doctor's slot
  /// management dashboard for the given place in-app.
  static String manageSlotsDeepLink(String placeId) =>
      '$deepLinkScheme://manage-slots/${Uri.encodeComponent(placeId)}';

  // ── Universal / App Links (HTTPS) ───────────────────────────────
  // Custom domain for Android App Links + iOS Universal Links. The
  // verification files (.well-known/assetlinks.json and
  // .well-known/apple-app-site-association) must be hosted on this exact
  // domain — see the drsListing-web GitHub repo (github.com/VipVish1991/
  // drsListing-web). Visiting one of
  // these HTTPS URLs opens the app when it's installed and otherwise falls
  // back to the browser (the static host serves the booking page — see
  // AppConstants.bookingPageUrl). NOTE: the booking QR code intentionally
  // encodes bookingPageUrl (the static booking page) rather than these app
  // links — it works without the app-link domain being hosted.
  static const String appLinksHost = 'drslisting.ai';

  static const int placeSearchLimit = 20;
  static const int placesSearchRadius = 5000; // meters (default 5 km)

  // Search radius options (in km) shown in the search radius sheet
  static const List<int> searchRadiusOptions = [5, 10, 20, 30, 50];
  static const int defaultSearchRadiusKm = 5;

  // Places API cache — reduces Google API calls by serving repeat
  // searches/details from local storage within this TTL. The cache is
  // cleared whenever the app is closed (see App lifecycle observer).
  static const Duration placesCacheTtl = Duration(hours: 24);
  static const String placesCachePrefix = 'places_cache_';

  // Groq (free AI API, OpenAI-compatible)
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String groqModel = 'llama-3.3-70b-versatile';

  // App Settings
  static const int splashDuration = 3; // seconds
  static const int maxChatHistoryLength = 50;
  static const String dateFormat = 'yyyy-MM-dd';
  static const String timeFormat = 'hh:mm a';
  static const String defaultLocation = 'Pune, India';

  /// Offset between the avatar video starting and the welcome greeting
  /// audio beginning (patient home screen welcome flow). The default is
  /// zero — the greeting voice starts together with the video ("With the
  /// video"). Every welcome flow (auto-welcome + avatar tap-to-resume)
  /// shares the one resolved value.
  static const Duration welcomeGreetingAudioDelay = Duration.zero;

  /// The greeting timing preset (Profile → Auto-Play Welcome). "With the
  /// video" is the ONLY option — the greeting voice always starts
  /// together with the avatar video; the stagger presets were removed.
  /// Values are milliseconds applied after the avatar video starts
  /// (0 = the voice begins together with the video).
  static const List<Map<String, Object>> welcomeGreetingDelayOptions = [
    {'label': 'With the video', 'ms': 0},
  ];

  /// Resolves a stored greeting-delay value (milliseconds) to a known
  /// preset, falling back to [welcomeGreetingAudioDelay] when null,
  /// negative or stale — keeps the settings picker's selected chip and
  /// the home screen's timer consistent even if the stored value is
  /// corrupt or from an older build.
  static int resolveWelcomeGreetingDelayMs(int? ms) {
    if (ms != null) {
      for (final option in welcomeGreetingDelayOptions) {
        if (option['ms'] == ms) return ms;
      }
    }
    return welcomeGreetingAudioDelay.inMilliseconds;
  }

  /// Zoom hint shown next to the N/M counter in every fullscreen image
  /// gallery (prescriptions, patient photos) that embeds the shared
  /// [ZoomableImage](widgets/zoomable_image.dart) — kept here so all
  /// viewers render one copy of the copy.
  static const String zoomHintText = 'Pinch or double-tap to zoom';

  // Google Maps default style
  static const double mapDefaultZoom = 15.0;

  // Supported Languages for voice input (locale codes in language-REGION format)
  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en-IN', 'name': 'English'},
    {'code': 'hi-IN', 'name': 'हिन्दी'},
    {'code': 'mr-IN', 'name': 'मराठी'},
    {'code': 'gu-IN', 'name': 'ગુજરાતી'},
  ];

  /// Default app language used until the user picks one in the Profile
  /// → Language Settings picker. Hindi is the app's target market default.
  static const String defaultLanguageCode = 'hi-IN';

  /// Normalize a stored language code to a full locale code from
  /// [supportedLanguages]. Accepts either a full locale (`'en-IN'`) or a
  /// bare language code (`'en'`) and returns the canonical locale code;
  /// falls back to `'en-IN'` when nothing matches.
  ///
  /// This keeps the persisted language consistent with the picker options
  /// (a bare `'en'` default previously never matched any option, so the
  /// language picker showed nothing selected until the user re-picked a
  /// language).
  static String resolveLanguageCode(String? code) {
    if (code != null) {
      final base = code.split('-').first;
      for (final lang in supportedLanguages) {
        if (lang['code'] == code ||
            (lang['code'] ?? '').split('-').first == base) {
          return lang['code']!;
        }
      }
    }
    return 'en-IN';
  }

  /// Display name for a stored language code. Returns the friendly name
  /// (e.g. `'English'`) or the raw code uppercased as a fallback.
  static String resolveLanguageName(String? code) {
    if (code != null) {
      for (final lang in supportedLanguages) {
        if (lang['code'] == code) return lang['name']!;
      }
    }
    return (code ?? 'en-IN').toUpperCase();
  }

  // Specialist mapping
  static const Map<String, Map<String, String>> symptomToSpecialist = {
    'chest pain': {'doctor': 'Cardiologist', 'emoji': '💔'},
    'heart': {'doctor': 'Cardiologist', 'emoji': '❤️'},
    'heart problems': {'doctor': 'Cardiologist', 'emoji': '💖'},
    'blood pressure': {'doctor': 'Cardiologist', 'emoji': '🩺'},
    'high blood pressure': {'doctor': 'Cardiologist', 'emoji': '❤️'},
    'low blood pressure': {'doctor': 'Cardiologist', 'emoji': '🩸'},
    'palpitations': {'doctor': 'Cardiologist', 'emoji': '💓'},
    'fainting': {'doctor': 'Cardiologist', 'emoji': '😰'},
    'shortness of breath': {'doctor': 'Cardiologist', 'emoji': '🫁'},
    'irregular heartbeat': {'doctor': 'Cardiologist', 'emoji': '💗'},
    'racing heart': {'doctor': 'Cardiologist', 'emoji': '💗'},
    'heart attack': {'doctor': 'Cardiologist', 'emoji': '🚑'},
    'heart palpitations': {'doctor': 'Cardiologist', 'emoji': '💓'},
    'headache': {'doctor': 'Neurologist', 'emoji': '🤕'},
    'migraine': {'doctor': 'Neurologist', 'emoji': '⚡'},
    'brain': {'doctor': 'Neurologist', 'emoji': '🧠'},
    'memory loss': {'doctor': 'Neurologist', 'emoji': '🧠'},
    'memory problems': {'doctor': 'Neurologist', 'emoji': '🧠'},
    'dizziness': {'doctor': 'Neurologist', 'emoji': '🌀'},
    'seizures': {'doctor': 'Neurologist', 'emoji': '⚠️'},
    'paralysis': {'doctor': 'Neurologist', 'emoji': '♿'},
    'numbness': {'doctor': 'Neurologist', 'emoji': '🥶'},
    'tingling': {'doctor': 'Neurologist', 'emoji': '⚡'},
    'tremors': {'doctor': 'Neurologist', 'emoji': '👐'},
    'stroke': {'doctor': 'Neurologist', 'emoji': '🧠'},
    'stroke symptoms': {'doctor': 'Neurologist', 'emoji': '🧠'},
    'slurred speech': {'doctor': 'Neurologist', 'emoji': '🗣️'},
    'fever': {'doctor': 'General Physician', 'emoji': '🤒'},
    'cold': {'doctor': 'General Physician', 'emoji': '🤧'},
    'cough': {'doctor': 'General Physician', 'emoji': '🤧'},
    'cold & cough': {'doctor': 'General Physician', 'emoji': '🤧'},
    'body pain': {'doctor': 'General Physician', 'emoji': '😣'},
    'weakness': {'doctor': 'General Physician', 'emoji': '😵'},
    'fatigue': {'doctor': 'General Physician', 'emoji': '🥱'},
    'general checkup': {'doctor': 'General Physician', 'emoji': '🩺'},
    'covid-19 symptoms': {'doctor': 'General Physician', 'emoji': '😷'},
    'dengue symptoms': {'doctor': 'General Physician', 'emoji': '🦟'},
    'malaria symptoms': {'doctor': 'General Physician', 'emoji': '🦠'},
    'typhoid symptoms': {'doctor': 'General Physician', 'emoji': '🌡️'},
    'dehydration': {'doctor': 'General Physician', 'emoji': '💧'},
    'swelling': {'doctor': 'General Physician', 'emoji': '🫧'},
    'stomach pain': {'doctor': 'Gastroenterologist', 'emoji': '🤢'},
    'acidity': {'doctor': 'Gastroenterologist', 'emoji': '🔥'},
    'indigestion': {'doctor': 'Gastroenterologist', 'emoji': '🍽️'},
    'vomiting': {'doctor': 'Gastroenterologist', 'emoji': '🤮'},
    'nausea': {'doctor': 'Gastroenterologist', 'emoji': '🤢'},
    'diarrhea': {'doctor': 'Gastroenterologist', 'emoji': '🚽'},
    'constipation': {'doctor': 'Gastroenterologist', 'emoji': '🥴'},
    'loss of appetite': {'doctor': 'Gastroenterologist', 'emoji': '🍴'},
    'liver problems': {'doctor': 'Gastroenterologist', 'emoji': '🫀'},
    'jaundice': {'doctor': 'Gastroenterologist', 'emoji': '🟡'},
    'back pain': {'doctor': 'Orthopedic', 'emoji': '🦴'},
    'neck pain': {'doctor': 'Orthopedic', 'emoji': '🧍'},
    'joint pain': {'doctor': 'Orthopedic', 'emoji': '🦵'},
    'knee pain': {'doctor': 'Orthopedic', 'emoji': '🦿'},
    'shoulder pain': {'doctor': 'Orthopedic', 'emoji': '💪'},
    'bone': {'doctor': 'Orthopedic', 'emoji': '🦴'},
    'fracture': {'doctor': 'Orthopedic', 'emoji': '🦴'},
    'injury': {'doctor': 'Orthopedic', 'emoji': '🩹'},
    'sprain': {'doctor': 'Orthopedic', 'emoji': '🤕'},
    'muscle pain': {'doctor': 'Orthopedic', 'emoji': '💪'},
    'slipped disc': {'doctor': 'Orthopedic', 'emoji': '🦴'},
    'hip pain': {'doctor': 'Orthopedic', 'emoji': '🦵'},
    'ankle pain': {'doctor': 'Orthopedic', 'emoji': '🦶'},
    'wrist pain': {'doctor': 'Orthopedic', 'emoji': '✋'},
    'burns': {'doctor': 'General Surgeon', 'emoji': '🔥'},
    'wounds': {'doctor': 'General Surgeon', 'emoji': '🩹'},
    'deep cut': {'doctor': 'General Surgeon', 'emoji': '🩹'},
    'wound infection': {'doctor': 'General Surgeon', 'emoji': '🩹'},
    'tooth pain': {'doctor': 'Dentist', 'emoji': '🦷'},
    'toothache': {'doctor': 'Dentist', 'emoji': '🦷'},
    'dental': {'doctor': 'Dentist', 'emoji': '🦷'},
    'gum pain': {'doctor': 'Dentist', 'emoji': '🦷'},
    'gum bleeding': {'doctor': 'Dentist', 'emoji': '🩸'},
    'tooth decay': {'doctor': 'Dentist', 'emoji': '🦷'},
    'skin rash': {'doctor': 'Dermatologist', 'emoji': '🔴'},
    'skin': {'doctor': 'Dermatologist', 'emoji': '🧴'},
    'allergy': {'doctor': 'Dermatologist', 'emoji': '🌸'},
    'itching': {'doctor': 'Dermatologist', 'emoji': '🖐️'},
    'acne': {'doctor': 'Dermatologist', 'emoji': '🫧'},
    'hair fall': {'doctor': 'Dermatologist', 'emoji': '💇'},
    'dandruff': {'doctor': 'Dermatologist', 'emoji': '❄️'},
    'infection': {'doctor': 'Immunologist', 'emoji': '🦠'},
    'immunity': {'doctor': 'Immunologist', 'emoji': '🛡️'},
    'low immunity': {'doctor': 'Immunologist', 'emoji': '🛡️'},
    'weak immune': {'doctor': 'Immunologist', 'emoji': '🛡️'},
    'recurring infections': {'doctor': 'Immunologist', 'emoji': '🦠'},
    'diabetes': {'doctor': 'Diabetologist', 'emoji': '🍬'},
    'blood sugar': {'doctor': 'Diabetologist', 'emoji': '🍬'},
    'high blood sugar': {'doctor': 'Diabetologist', 'emoji': '🍬'},
    'low blood sugar': {'doctor': 'Diabetologist', 'emoji': '🍬'},
    'thyroid': {'doctor': 'Endocrinologist', 'emoji': '🦋'},
    'thyroid problems': {'doctor': 'Endocrinologist', 'emoji': '🦋'},
    'hormone': {'doctor': 'Endocrinologist', 'emoji': '⚖️'},
    'weight gain': {'doctor': 'Endocrinologist', 'emoji': '🍔'},
    'weight loss': {'doctor': 'Endocrinologist', 'emoji': '⚖️'},
    'breathing': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'breathing problem': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'difficulty breathing': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'asthma': {'doctor': 'Pulmonologist', 'emoji': '🌬️'},
    'wheezing': {'doctor': 'Pulmonologist', 'emoji': '🌬️'},
    'respiratory': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'cough with mucus': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'chronic cough': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'persistent cough': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'pneumonia': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'tuberculosis': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'tuberculosis (tb)': {'doctor': 'Pulmonologist', 'emoji': '🫁'},
    'eye': {'doctor': 'Ophthalmologist', 'emoji': '👁️'},
    'eye pain': {'doctor': 'Ophthalmologist', 'emoji': '👁️'},
    'eye redness': {'doctor': 'Ophthalmologist', 'emoji': '🔴'},
    'red eyes': {'doctor': 'Ophthalmologist', 'emoji': '🔴'},
    'eye irritation': {'doctor': 'Ophthalmologist', 'emoji': '👁️'},
    'vision': {'doctor': 'Ophthalmologist', 'emoji': '👓'},
    'blurred vision': {'doctor': 'Ophthalmologist', 'emoji': '👓'},
    'ear': {'doctor': 'ENT Specialist', 'emoji': '👂'},
    'ear pain': {'doctor': 'ENT Specialist', 'emoji': '👂'},
    'hearing': {'doctor': 'ENT Specialist', 'emoji': '🔇'},
    'hearing loss': {'doctor': 'ENT Specialist', 'emoji': '🔇'},
    'throat': {'doctor': 'ENT Specialist', 'emoji': '😷'},
    'sore throat': {'doctor': 'ENT Specialist', 'emoji': '😷'},
    'sinus': {'doctor': 'ENT Specialist', 'emoji': '👃'},
    'sinus problem': {'doctor': 'ENT Specialist', 'emoji': '👃'},
    'nose bleeding': {'doctor': 'ENT Specialist', 'emoji': '🩸'},
    'snoring': {'doctor': 'ENT Specialist', 'emoji': '💤'},
    'urine': {'doctor': 'Urologist', 'emoji': '🚻'},
    'urinary infection': {'doctor': 'Urologist', 'emoji': '🚻'},
    'burning urination': {'doctor': 'Urologist', 'emoji': '🔥'},
    'frequent urination': {'doctor': 'Urologist', 'emoji': '🚽'},
    'kidney': {'doctor': 'Nephrologist', 'emoji': '🫘'},
    'kidney problems': {'doctor': 'Nephrologist', 'emoji': '🫘'},
    'pregnancy': {'doctor': 'Gynecologist', 'emoji': '🤰'},
    'pregnancy care': {'doctor': 'Gynecologist', 'emoji': '🤰'},
    'period': {'doctor': 'Gynecologist', 'emoji': '🩸'},
    'menstrual problems': {'doctor': 'Gynecologist', 'emoji': '🩸'},
    'pcos': {'doctor': 'Gynecologist', 'emoji': '🌷'},
    'infertility': {'doctor': 'Gynecologist', 'emoji': '👶'},
    'sexual health': {'doctor': 'Sexologist', 'emoji': '💕'},
    'erectile dysfunction': {'doctor': 'Sexologist', 'emoji': '🩺'},
    'mental health': {'doctor': 'Psychiatrist', 'emoji': '🧠'},
    'stress': {'doctor': 'Psychiatrist', 'emoji': '😰'},
    'anxiety': {'doctor': 'Psychiatrist', 'emoji': '😰'},
    'stress & anxiety': {'doctor': 'Psychiatrist', 'emoji': '😰'},
    'depression': {'doctor': 'Psychiatrist', 'emoji': '😔'},
    'sleep': {'doctor': 'Psychiatrist', 'emoji': '😴'},
    'sleep problems': {'doctor': 'Psychiatrist', 'emoji': '😴'},
    'insomnia': {'doctor': 'Psychiatrist', 'emoji': '😴'},
    'panic attack': {'doctor': 'Psychiatrist', 'emoji': '😰'},
    'mood swings': {'doctor': 'Psychiatrist', 'emoji': '🎭'},
    'cancer': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'cancer symptoms': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'tumor': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'lump': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'lump in neck': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'lump in breast': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'unusual lump': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'swollen lymph nodes': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'unexplained weight loss': {'doctor': 'Oncologist', 'emoji': '🎗'},
    'child': {'doctor': 'Pediatrician', 'emoji': '👶'},
    'child health': {'doctor': 'Pediatrician', 'emoji': '👶'},
    'child development': {'doctor': 'Pediatrician', 'emoji': '👶'},
    'growth issues': {'doctor': 'Pediatrician', 'emoji': '📈'},
    'baby': {'doctor': 'Pediatrician', 'emoji': '👶'},
    'vaccination': {'doctor': 'Pediatrician', 'emoji': '💉'},
  };
}
