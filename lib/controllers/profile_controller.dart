import 'package:get/get.dart';
import '../config/constants.dart';
import '../controllers/auth_controller.dart';
import '../controllers/voice_controller.dart';
import '../services/supabase_service.dart';
import '../services/local_storage_service.dart';
import '../models/doctor_model.dart';

class ProfileController extends GetxController {
  final AuthController _authController = Get.find<AuthController>();
  final SupabaseService _supabase = SupabaseService();
  final LocalStorageService _storage = LocalStorageService();
  final VoiceController _voiceController = Get.find<VoiceController>();

  final RxList<DoctorModel> savedDoctors = <DoctorModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString selectedLanguage = 'en'.obs;
  final RxInt searchRadiusKm = AppConstants.defaultSearchRadiusKm.obs;

  /// Reactive set of placeIds that are bookmarked locally.
  /// Used to drive the heart/bookmark icon in doctor cards and detail.
  final RxSet<String> favoriteIds = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    selectedLanguage.value = _storage.getPreferredLanguage();
    searchRadiusKm.value = _storage.getSearchRadiusKm();
    _loadLocalFavorites();
    loadSavedDoctors();
  }

  /// Load locally-stored favorite placeIds into the reactive set.
  void _loadLocalFavorites() {
    final all = _storage.getFavoriteDoctors(
      userId: _authController.userId,
    );
    favoriteIds.clear();
    favoriteIds.addAll(all.keys.toSet());
  }

  Future<void> loadSavedDoctors() async {
    // Always load local favorites first (instant, offline-capable) —
    // scoped to the logged-in user so each account only sees its own
    // saved doctors on this device.
    savedDoctors.assignAll(
      _storage
          .getFavoriteDoctorsList(userId: _authController.userId)
          .map((json) => DoctorModel.fromJson(json)),
    );

    // Then try to merge with cloud favourites (user must be logged in)
    final userId = _authController.userId;
    if (userId == null) return;

    isLoading.value = true;
    try {
      final data = await _supabase.getSavedDoctors(userId);
      final cloudDoctors = data
          .map((json) => DoctorModel.fromJson(
              json['doctor_data'] as Map<String, dynamic>))
          .toList();

      // Merge: keep local placeIds, add any cloud-only doctors
      final existingIds = savedDoctors.map((d) => d.placeId).toSet();
      for (final d in cloudDoctors) {
        if (!existingIds.contains(d.placeId)) {
          savedDoctors.add(d);
          _storage.saveFavoriteDoctor(
            d.toJson(),
            userId: userId, // sync to local under this user's key
          );
        }
      }
      // Refresh the favoriteIds set
      _loadLocalFavorites();
    } catch (_) {} finally {
      isLoading.value = false;
    }
  }

  /// Toggle a doctor as a local favorite.
  /// Returns `true` if the doctor is now favorited, `false` if removed.
  Future<bool> toggleFavorite(DoctorModel doctor) async {
    final placeId = doctor.placeId;
    final userId = _authController.userId;
    if (favoriteIds.contains(placeId)) {
      favoriteIds.remove(placeId);
      await _storage.removeFavoriteDoctor(placeId, userId: userId);
      savedDoctors.removeWhere((d) => d.placeId == placeId);

      // Also try to remove from cloud
      if (userId != null) {
        try {
          await _supabase.removeSavedDoctorByPlaceId(userId, placeId);
        } catch (_) {}
      }
      return false;
    } else {
      favoriteIds.add(placeId);
      await _storage.saveFavoriteDoctor(doctor.toJson(), userId: userId);
      savedDoctors.add(doctor);

      // Also try to save to cloud
      if (userId != null) {
        try {
          await _supabase.saveDoctor(userId, doctor.toJson());
        } catch (_) {}
      }
      return true;
    }
  }

  /// Save a doctor to favorites (legacy method, delegates to toggle).
  Future<void> saveDoctor(DoctorModel doctor) async {
    await toggleFavorite(doctor);
  }

  /// Remove a doctor from saved list.
  Future<void> removeSavedDoctor(String placeId) async {
    favoriteIds.remove(placeId);
    savedDoctors.removeWhere((d) => d.placeId == placeId);
    await _storage.removeFavoriteDoctor(
      placeId,
      userId: _authController.userId,
    );

    final userId = _authController.userId;
    if (userId != null) {
      try {
        await _supabase.removeSavedDoctorByPlaceId(userId, placeId);
      } catch (_) {}
    }
  }

  /// Drop the logged-in user's in-memory favorites — called on logout so
  /// the next user on this device never sees the previous user's saved
  /// doctors.
  void clearSession() {
    favoriteIds.clear();
    savedDoctors.clear();
  }

  /// Check if a doctor is saved by placeId (uses fast in-memory set).
  bool isDoctorSaved(String placeId) {
    // RxSet.contains() internally accesses the reactive `.value` getter,
    // which registers the dependency inside Obx contexts and triggers
    // a rebuild when the set changes (e.g. bookmark icon toggles).
    return favoriteIds.contains(placeId);
  }

  void setLanguage(String code) {
    final normalized = AppConstants.resolveLanguageCode(code);
    selectedLanguage.value = normalized;
    _voiceController.selectedLanguage.value = normalized;
    _storage.setPreferredLanguage(normalized);
  }

  void setSearchRadiusKm(int km) {
    searchRadiusKm.value = km;
    _storage.setSearchRadiusKm(km);
  }

  Future<void> logout() async {
    await _authController.logout();
  }
}
