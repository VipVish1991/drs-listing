import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/constants.dart';

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Chat history
  Future<void> saveChatHistory(List<Map<String, dynamic>> messages) async {
    final json = jsonEncode(messages);
    await _prefs?.setString('chat_history', json);
  }

  List<Map<String, dynamic>> getChatHistory() {
    final json = _prefs?.getString('chat_history');
    if (json != null) {
      try {
        return List<Map<String, dynamic>>.from(jsonDecode(json));
      } catch (_) {}
    }
    return [];
  }

  Future<void> clearChatHistory() async {
    await _prefs?.remove('chat_history');
  }

  // ── Last logged-in user (used to reset chat history per user) ──

  /// Mobile number of the user that most recently logged in on this
  /// device. When a *different* user logs in, their old chat history
  /// must not leak into the new session — callers compare this value
  /// with the incoming user's mobile and clear the chat when they differ.
  String? getLastLoggedInMobile() {
    return _prefs?.getString('last_logged_in_mobile');
  }

  Future<void> setLastLoggedInMobile(String mobile) async {
    await _prefs?.setString('last_logged_in_mobile', mobile);
  }

  // Language preference
  Future<void> setPreferredLanguage(String languageCode) async {
    await _prefs?.setString('preferred_language', languageCode);
  }

  /// Returns the stored language preference normalized to a full locale
  /// code from [AppConstants.supportedLanguages] (e.g. `'hi-IN'`). Bare
  /// codes like `'en'` written by older builds are normalized too, so the
  /// value always matches the language picker options. When the user has
  /// never picked a language, [AppConstants.defaultLanguageCode] (Hindi)
  /// is returned.
  String getPreferredLanguage() {
    final stored = _prefs?.getString('preferred_language');
    if (stored == null || stored.isEmpty) {
      return AppConstants.resolveLanguageCode(AppConstants.defaultLanguageCode);
    }
    return AppConstants.resolveLanguageCode(stored);
  }

  // ── Favorite / Bookmarked Doctors ─────────────────────────────
  // Favorites are namespaced per user id so that "each user only sees
  // their own saved doctors". When [userId] is null (no one logged in),
  // a shared anonymous key is used so pre-login bookmarks still work.

  String _favoritesKey(String? userId) {
    if (userId == null || userId.isEmpty) return 'favorite_doctors';
    return 'favorite_doctors_$userId';
  }

  /// Saves (or overwrites) a doctor in the local favorites list.
  Future<void> saveFavoriteDoctor(
    Map<String, dynamic> doctorJson, {
    String? userId,
  }) async {
    final all = getFavoriteDoctors(userId: userId);
    final placeId = doctorJson['place_id']?.toString() ?? '';
    if (placeId.isNotEmpty) {
      all[placeId] = doctorJson;
    }
    await _saveFavoritesMap(all, userId);
  }

  /// Removes a doctor from local favorites by placeId.
  Future<void> removeFavoriteDoctor(String placeId, {String? userId}) async {
    final all = getFavoriteDoctors(userId: userId);
    all.remove(placeId);
    await _saveFavoritesMap(all, userId);
  }

  /// Returns all favorite doctors as a map of placeId → doctor JSON.
  Map<String, Map<String, dynamic>> getFavoriteDoctors({String? userId}) {
    final json = _prefs?.getString(_favoritesKey(userId));
    if (json == null) return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return Map<String, Map<String, dynamic>>.from(
          decoded.map(
            (k, v) =>
                MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
          ),
        );
      }
    } catch (_) {}
    return {};
  }

  /// Returns a list of all favorite doctors for easy display.
  List<Map<String, dynamic>> getFavoriteDoctorsList({String? userId}) {
    return getFavoriteDoctors(userId: userId).values.toList();
  }

  /// Returns true if a doctor with [placeId] is in local favorites.
  bool isFavoriteDoctor(String placeId, {String? userId}) {
    return getFavoriteDoctors(userId: userId).containsKey(placeId);
  }

  /// Returns the number of locally saved favorite doctors.
  int favoriteDoctorsCount({String? userId}) =>
      getFavoriteDoctors(userId: userId).length;

  Future<void> _saveFavoritesMap(
    Map<String, Map<String, dynamic>> data,
    String? userId,
  ) async {
    await _prefs?.setString(_favoritesKey(userId), jsonEncode(data));
  }

  // ── Search radius (km) ───────────────────────────────────────

  Future<void> setSearchRadiusKm(int km) async {
    await _prefs?.setInt('search_radius_km', km);
  }

  int getSearchRadiusKm() {
    return _prefs?.getInt('search_radius_km') ??
        AppConstants.defaultSearchRadiusKm;
  }

  // ── Last known GPS location (saved on every app open) ──

  Future<void> saveLastLatLng(double lat, double lng) async {
    await _prefs?.setDouble('last_lat', lat);
    await _prefs?.setDouble('last_lng', lng);
  }

  /// Returns [latitude, longitude] of the last saved GPS fix, or null.
  List<double>? getLastLatLng() {
    final lat = _prefs?.getDouble('last_lat');
    final lng = _prefs?.getDouble('last_lng');
    if (lat == null || lng == null) return null;
    return [lat, lng];
  }

  // ── Places API response cache ───────────────────────────────────
  // Caches Google Places search results & doctor details so repeat
  // requests are served locally instead of calling the paid API again.
  // The whole cache is cleared when the app closes (frees memory).

  /// Saves a Places API response under [key] with the current timestamp.
  Future<void> savePlacesCache(String key, String jsonData) async {
    await _prefs?.setString(
      '${AppConstants.placesCachePrefix}$key',
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'data': jsonData,
      }),
    );
  }

  /// Returns the cached JSON payload for [key] if it is still fresh
  /// (within [AppConstants.placesCacheTtl]); null otherwise.
  String? getPlacesCache(String key) {
    final raw = _prefs?.getString('${AppConstants.placesCachePrefix}$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(decoded['saved_at']?.toString() ?? '');
      if (savedAt == null) return null;
      if (DateTime.now().difference(savedAt) > AppConstants.placesCacheTtl) {
        return null; // stale → treat as miss
      }
      return decoded['data']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Removes every cached Places API response (frees memory on app close).
  Future<void> clearPlacesCache() async {
    final keys = _prefs?.getKeys() ?? {};
    for (final key in keys) {
      if (key.startsWith(AppConstants.placesCachePrefix)) {
        await _prefs?.remove(key);
      }
    }
  }

  // ── Onboarding (first interaction) flag ──

  Future<void> setOnboardingDone() async {
    await _prefs?.setBool('onboarding_done', true);
  }

  bool isOnboardingDone() {
    return _prefs?.getBool('onboarding_done') ?? false;
  }

  // ── Avatar video (patient-side welcome) pause state ──
  // Persists the play/pause state of the health-assistant welcome video
  // so the next app open restores it: a paused avatar stays paused until
  // the patient taps it again ("first it plays, after it stops the state
  // is saved"). On the web build shared_preferences is backed by
  // localStorage, so this is exactly the localStorage the page mentions.

  Future<void> setAvatarVideoPaused(bool paused) async {
    await _prefs?.setBool('avatar_video_paused', paused);
  }

  /// Returns true when the patient last left the avatar video paused.
  /// Defaults to false (first open → the video auto-plays after the
  /// welcome delay).
  bool isAvatarVideoPaused() {
    return _prefs?.getBool('avatar_video_paused') ?? false;
  }

  // ── Doctor avatar video (dashboard welcome) pause state ──
  // Separate key from the patient-side avatar so pausing one never
  // affects the other.

  Future<void> setDoctorAvatarVideoPaused(bool paused) async {
    await _prefs?.setBool('doctor_avatar_video_paused', paused);
  }

  /// Returns true when the doctor last left the dashboard welcome video
  /// paused. Defaults to false (first open → the video auto-plays after
  /// the welcome delay).
  bool isDoctorAvatarVideoPaused() {
    return _prefs?.getBool('doctor_avatar_video_paused') ?? false;
  }

  // ── Auto-Play Welcome (patient home screen) toggle ──
  // Master switch for the automatic welcome (avatar video + greeting
  // audio) on the patient home screen, set from Profile → Auto-Play
  // Welcome. When off, the avatar stays paused until the patient taps it.

  Future<void> setWelcomeAutoPlayEnabled(bool enabled) async {
    await _prefs?.setBool('welcome_auto_play', enabled);
  }

  /// Returns true when the patient home screen auto-plays the welcome
  /// video + greeting. Defaults to true (the welcome is on until the
  /// patient turns it off).
  bool isWelcomeAutoPlayEnabled() {
    return _prefs?.getBool('welcome_auto_play') ?? true;
  }

  // ── Welcome greeting audio delay ──
  // When the greeting voice starts relative to the avatar video. "With
  // the video" (0 ms) is the only preset now (Profile → Auto-Play
  // Welcome); the stagger options were removed. Persisted in
  // milliseconds; validated against AppConstants.welcomeGreetingDelayOptions
  // on read so a stale value (e.g. an old 1000–3000 ms stagger from an
  // older build) falls back to the default.

  Future<void> setWelcomeGreetingDelayMs(int ms) async {
    await _prefs?.setInt('welcome_greeting_delay_ms', ms);
  }

  /// The stored greeting-audio stagger in milliseconds (0 = the voice
  /// starts together with the video). Defaults to
  /// [AppConstants.welcomeGreetingAudioDelay] when the patient has never
  /// picked a timing.
  int getWelcomeGreetingDelayMs() {
    return AppConstants.resolveWelcomeGreetingDelayMs(
      _prefs?.getInt('welcome_greeting_delay_ms'),
    );
  }

  // ── Payment history filter (range / status) ──
  // Remembers the last filter the patient or doctor left the payment
  // history screen with (a custom date range / quick preset, a status
  // pill, or "All") so reopening the screen restores it. Stored as one
  // JSON blob under a single key; the map holds 'range_start'+'range_end'
  // (ISO-8601) plus an optional 'status', and an empty map encodes
  // "All". It is a view preference (not per-user data), so it is
  // intentionally shared across roles.

  /// Persists the payment-history filter. Pass a [rangeStartIso] /
  /// [rangeEndIso] pair (ISO-8601), a [status] ('Paid' / 'Pending' — the
  /// summary pill filter, composed on top of the period), or neither to
  /// remember "All". (A legacy 'month' key from older builds is ignored
  /// on read — month chips no longer exist.)
  Future<void> savePaymentHistoryFilter({
    String? rangeStartIso,
    String? rangeEndIso,
    String? status,
  }) async {
    final data = <String, String>{};
    if (rangeStartIso != null && rangeEndIso != null) {
      data['range_start'] = rangeStartIso;
      data['range_end'] = rangeEndIso;
    }
    if (status != null) data['status'] = status;
    await _prefs?.setString('payment_history_filter', jsonEncode(data));
  }

  /// The persisted payment-history filter, or null when none was saved.
  /// An empty map means the user last left "All" selected.
  Map<String, String>? getPaymentHistoryFilter() {
    final raw = _prefs?.getString('payment_history_filter');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, String>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
    } catch (_) {}
    return null;
  }

  // ── Clear all ──
  Future<void> clearAll() async {
    await _prefs?.clear();
  }
}
