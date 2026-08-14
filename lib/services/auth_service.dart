import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../utils/text_capitalizer.dart';
import 'supabase_service.dart';

class AuthException implements Exception {
  final String message;
  final String? code;

  AuthException(this.message, {this.code});

  @override
  String toString() => message;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Mint a fresh OTP for [mobile] from the server (see
  /// [SupabaseService.requestOtp]). DEMO MODE: returns the code so the
  /// UI can display it. Returns null on failure.
  Future<String?> requestOtp(String mobile) => _supabase.requestOtp(mobile);

  /// Verify [otp] for [mobile] against the server (see
  /// [SupabaseService.verifyOtp]). Returns true only on server acceptance.
  Future<bool> verifyOtp(String mobile, String otp) =>
      _supabase.verifyOtp(mobile, otp);

  /// Creates an unshared instance for subclassing in tests.
  ///
  /// The default [AuthService] factory always returns the singleton, so a
  /// test double (e.g. one that counts `register`/`login` calls) must
  /// extend this class and call `super.testing()`. No platform channels
  /// are touched at construction, so it is safe to build in widget tests.
  @visibleForTesting
  AuthService.testing();

  final _storage = const FlutterSecureStorage();
  final _supabase = SupabaseService();

  static const _userKey = 'current_user';

  Future<UserModel?> login(String mobile) async {
    try {
      final userData = await _supabase.getUserByMobile(mobile);
      if (userData == null) return null;
      final user = UserModel.fromJson(userData);
      // Persisting locally is best-effort — a secure-storage hiccup must
      // NOT block login (it used to bubble up as a misleading
      // "Connection error" even though the account exists).
      try {
        await _saveUserLocally(user);
      } catch (e) {
        debugPrint('⚠️ Failed to persist user locally (non-fatal): $e');
      }
      return user;
    } catch (e) {
      throw AuthException(
        'Connection error. Please check your internet and try again.',
        code: 'network_error',
      );
    }
  }

  Future<UserModel> register(String name, String mobile,
      {String role = UserModel.rolePatient}) async {
    // Check if mobile already exists before attempting insert
    final existingUser = await _supabase.getUserByMobile(mobile);
    if (existingUser != null) {
      throw AuthException(
        'This mobile number is already registered. Please login instead.',
        code: 'duplicate_mobile',
      );
    }

    final userData = await _supabase.createUser(name, mobile, role: role);
    final user = UserModel.fromJson(userData);
    // Best-effort persistence — the account already exists in the DB;
    // failing to cache it locally shouldn't fail the registration.
    try {
      await _saveUserLocally(user);
    } catch (e) {
      debugPrint('⚠️ Failed to persist user locally (non-fatal): $e');
    }
    return user;
  }

  Future<UserModel> updateRole(
    UserModel user,
    String role, {
    String? doctorPlaceId,
  }) async {
    if (user.id != null) {
      await _supabase.updateUserRole(
        user.id!,
        user.mobile ?? '',
        role,
        doctorPlaceId: doctorPlaceId,
      );
    }
    final updated = user.copyWith(
      role: role,
      doctorPlaceId: doctorPlaceId ?? user.doctorPlaceId,
    );
    await _saveUserLocally(updated);
    return updated;
  }

  /// Update the user's display name in Supabase and refresh the locally
  /// cached session so the new name survives app restarts. Returns the
  /// updated [UserModel] (name capitalized to match the DB formatting).
  ///
  /// Throws [AuthException] when the update cannot be persisted server-side
  /// (missing id/mobile, or the PATCH affected 0 rows — e.g. an RLS denial)
  /// so callers never show a false "name updated".
  Future<UserModel> updateName(UserModel user, String name) async {
    final capitalized = capitalizeWords(name.trim());
    if (user.id == null || (user.mobile ?? '').isEmpty) {
      throw AuthException('Could not update your name. Please try again.');
    }
    final saved = await _supabase.updateUserName(
      user.id!,
      user.mobile!,
      capitalized,
    );
    if (!saved) {
      throw AuthException('Could not update your name. Please try again.');
    }
    final updated = user.copyWith(name: capitalized);
    // Best-effort persistence (same as login/register): the DB is already
    // updated, so a secure-storage hiccup must not surface as a failed
    // save — the caller still gets the updated model to refresh in memory.
    try {
      await _saveUserLocally(updated);
    } catch (e) {
      debugPrint('⚠️ Failed to persist updated name locally (non-fatal): $e');
    }
    return updated;
  }

  Future<UserModel?> getCurrentUser() async {
    try {
      final json = await _storage.read(key: _userKey);
      if (json == null) return null;
      final data = jsonDecode(json) as Map<String, dynamic>;
      return UserModel.fromJson(data);
    } catch (_) {
      // Corrupt or unreadable stored session → treat as logged out
      // instead of crashing app-start auth checks.
      return null;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _userKey);
  }

  Future<bool> isLoggedIn() async {
    final user = await getCurrentUser();
    return user != null;
  }

  Future<void> _saveUserLocally(UserModel user) async {
    await _storage.write(
      key: _userKey,
      value: jsonEncode(user.toJson()),
    );
  }
}
