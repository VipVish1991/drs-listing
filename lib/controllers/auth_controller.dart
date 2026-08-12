import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../models/user_model.dart';
import '../models/doctor_model.dart';
import '../services/auth_service.dart';
import '../services/places_service.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';
import '../routes/app_routes.dart';
import '../controllers/profile_controller.dart';
import '../controllers/appointment_controller.dart';
import '../controllers/doctor_controller.dart';
import '../controllers/voice_controller.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';

class AuthController extends GetxController {
  final AuthService _authService = AuthService();
  final SupabaseService _supabase = SupabaseService();

  final RxBool isLoading = false.obs;
  final RxBool isLoggedIn = false.obs;
  final Rx<UserModel?> currentUser = Rx<UserModel?>(null);
  final RxString errorMessage = ''.obs;

  /// Convenience getters for role-based access control.
  /// When no user is logged in, assumes patient role (the default).
  bool get isDoctor => currentUser.value?.isDoctor ?? false;
  bool get isPatient => currentUser.value?.isPatient ?? true;
  String? get userId => currentUser.value?.id;

  @override
  void onInit() {
    super.onInit();
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    isLoading.value = true;
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        currentUser.value = user;
        isLoggedIn.value = true;
        // Register this device for push notifications on a warm start.
        NotificationService.instance.syncTokenForCurrentUser();
        // Reload the logged-in user's own saved doctors on a warm start
        // (cold start goes through login/register) so the profile reflects
        // only this user's favorites.
        Get.find<ProfileController>().loadSavedDoctors();
      }
    } finally {
      // Always settle the flag — a session-restore failure must not leave
      // isLoading stuck true (it would hang role-gated flows like the
      // splash screen's patient-only location prompt).
      isLoading.value = false;
    }
  }

  /// Update the logged-in user's display name — persists to Supabase and
  /// refreshes the in-memory + locally cached user so every screen reading
  /// [currentUser] (e.g. the Profile header) reflects the new name.
  Future<void> updateUserName(String name) async {
    final user = currentUser.value;
    if (user == null) return;
    final updated = await _authService.updateName(user, name);
    currentUser.value = updated;
  }

  /// Navigate to the correct home based on the current user's role.
  /// Called from the splash screen after auth check completes.
  ///
  /// - Logged-in doctor → Doctor Dashboard (loads DB profile if available)
  /// - Logged-in patient → Patient Home
  /// - No user → Login screen
  Future<void> navigateToRoleBasedHome() async {
    final user = currentUser.value;
    if (user == null) {
      Get.offAllNamed(AppRoutes.login);
      return;
    }

    // ── Doctor → navigate to doctor dashboard even if DB record is
    //      missing; the dashboard shell handles empty states gracefully. ──
    if (user.isDoctor) {
      final doctorCtrl = Get.find<DoctorController>();
      final placesService = PlacesService();

      // Try to load the doctor profile, enriched with full Place Details
      // from Google Places API (phone, hours, address, etc.).
      if (user.doctorPlaceId != null) {
        // 1. Load basic data from Supabase DB — guarded so a transient
        //    DB/network error can NOT block login (it used to throw out
        //    of navigateToRoleBasedHome, leaving the user stuck on the
        //    login screen with a generic "Something went wrong").
        DoctorModel? dbDoctor;
        try {
          dbDoctor = await _supabase.getDoctorFromDb(user.doctorPlaceId!);
        } catch (_) {
          debugPrint('⚠️ getDoctorFromDb failed during login (non-fatal)');
        }

        // 2. Fetch complete details from Google Places API
        DoctorModel? doctor;
        try {
          final fullDetails = await placesService.getDoctorDetails(
            user.doctorPlaceId!,
          );
          if (fullDetails != null) {
            // Merge the Places-enriched model with the doctor-set fields
            // from the DB row (upiId, unavailableRanges, experienceYears)
            // that Google Places never returns — otherwise a re-login
            // silently drops the saved UPI ID and the profile shows
            // "Not set" even though the DB value is intact. Shares the
            // merge with DoctorController.loadDoctorFromDb so the two can
            // never drift apart.
            final enriched = DoctorController.mergeDoctorSetFields(
              fullDetails,
              dbDoctor,
              user.id,
            );
            doctor = enriched;
            // Upsert enriched data back to DB for next login
            await _supabase.saveDoctorToDb(enriched);
          }
        } catch (_) {
          // Non-fatal; fall through to DB data
        }

        // 3. Fall back to DB data if Places API failed
        doctor ??= dbDoctor;

        if (doctor != null) {
          await doctorCtrl.setDoctor(doctor);
          Get.offAllNamed(
            AppRoutes.doctorDashboard,
            arguments: {'doctor': doctor},
          );
          return;
        }
      }

      // ── Fallback: query doctors by user_id ──────────────────────
      // If doctorPlaceId wasn't saved on the user record, try to find
      // the doctor profile by the user_id column on the doctors table.
      // Guarded like above so a DB hiccup degrades to the fallback
      // dashboard instead of failing login.
      if (user.id != null) {
        List<DoctorModel> userDoctors = const [];
        try {
          userDoctors = await _supabase.getDoctorsByUserId(user.id!);
        } catch (_) {
          debugPrint('⚠️ getDoctorsByUserId failed during login (non-fatal)');
        }
        if (userDoctors.isNotEmpty) {
          final dbDoctor = userDoctors.first;

          // Try to enrich with full Place Details from Google Places API
          // (photos, reviews, hours, phone, website, etc.)
          DoctorModel? enrichedDoctor;
          if (dbDoctor.placeId.isNotEmpty) {
            try {
              final fullDetails = await placesService.getDoctorDetails(
                dbDoctor.placeId,
              );
              if (fullDetails != null) {
                // Same doctor-set field merge as the primary path — the
                // fallback must not drop the saved UPI ID / availability
                // either.
                enrichedDoctor = DoctorController.mergeDoctorSetFields(
                  fullDetails,
                  dbDoctor,
                  user.id,
                );
                // Upsert enriched data back to DB for next login
                await _supabase.saveDoctorToDb(enrichedDoctor);
              }
            } catch (_) {
              // Non-fatal; fall through to DB data
            }
          }

          final doctor = enrichedDoctor ?? dbDoctor;
          await doctorCtrl.setDoctor(doctor);
          Get.offAllNamed(
            AppRoutes.doctorDashboard,
            arguments: {'doctor': doctor},
          );
          return;
        }
      }

      // Doctor with no DB record and no user_id match — still go
      // to the dashboard. Pass a minimal doctor with the placeId and
      // userId so the route handler doesn't crash on null args.
      final fallbackDoctor = DoctorModel(
        placeId: user.doctorPlaceId ?? '',
        name: user.name ?? 'Doctor',
        userId: user.id,
      );
      Get.offAllNamed(
        AppRoutes.doctorDashboard,
        arguments: {'doctor': fallbackDoctor},
      );
      return;
    }

    // ── Default: patient home ──
    Get.offAllNamed(AppRoutes.home);
  }

  /// Logs the user in by mobile number.
  ///
  /// Returns `true` when the mobile is registered and the user is now the
  /// current user; `false` when the number isn't registered or on error
  /// (check [errorMessage] for the reason).
  ///
  /// When [redirect] is `true` (default) the controller navigates to the
  /// role-based home after a successful login, and to the register screen
  /// when the number isn't registered. Pass `redirect: false` when the
  /// caller wants to control navigation itself (e.g. the OTP screen
  /// auto-logging in an already-registered number) — only state is
  /// updated and the result is returned.
  Future<bool> login(
    String mobile, {
    DoctorModel? pendingDoctor,
    bool redirect = true,
  }) async {
    final trimmed = mobile.trim();
    if (trimmed.isEmpty) {
      errorMessage.value = 'Please enter mobile number';
      return false;
    }
    if (!_isValidMobile(trimmed)) {
      errorMessage.value = 'Please enter a valid 10-digit mobile number';
      return false;
    }

    isLoading.value = true;
    errorMessage.value = '';

    try {
      final user = await _authService.login(trimmed);
      if (user != null) {
        currentUser.value = user;
        isLoggedIn.value = true;
        // Register this device for push notifications (multi-device).
        NotificationService.instance.syncTokenForCurrentUser();
        // A new user must never inherit the previous user's chat history.
        _resetChatForNewUser(user);
        // Reload cloud-saved data after login so it survives logout/login
        Get.find<ProfileController>().loadSavedDoctors();
        Get.find<AppointmentController>().loadAppointments();

        // Caller handles navigation itself
        if (!redirect) return true;

        // If there's a pending doctor connection from NearbyDoctorsScreen,
        // complete it instead of normal role-based redirect.
        if (pendingDoctor != null) {
          final success = await completeDoctorConnection(pendingDoctor);
          if (success) {
            final controller = Get.find<DoctorController>();
            await controller.setDoctor(pendingDoctor);
            Get.offAllNamed(
              AppRoutes.doctorDashboard,
              arguments: {'doctor': pendingDoctor},
            );
          } else {
            await navigateToRoleBasedHome();
          }
          return true;
        }

        // Role-based redirect
        await navigateToRoleBasedHome();
        return true;
      }

      // User not found, redirect to register
      if (redirect) {
        Get.toNamed(
          AppRoutes.register,
          arguments: {'mobile': trimmed, 'pendingDoctor': ?pendingDoctor},
        );
      }
      return false;
    } on AuthException catch (e) {
      errorMessage.value = e.message;
      debugPrint('Login error: ${e.message}');
      return false;
    } catch (e) {
      errorMessage.value = 'Something went wrong. Please try again.';
      debugPrint('Login unexpected error: $e');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> register(
    String name,
    String mobile, {
    String role = UserModel.rolePatient,
    DoctorModel? pendingDoctor,
  }) async {
    final trimmedMobile = mobile.trim();
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      errorMessage.value = 'Please enter your name';
      return;
    }
    if (trimmedMobile.isEmpty) {
      errorMessage.value = 'Please enter mobile number';
      return;
    }
    if (!_isValidMobile(trimmedMobile)) {
      errorMessage.value = 'Please enter a valid 10-digit mobile number';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';

    try {
      final user = await _authService.register(
        trimmedName,
        trimmedMobile,
        role: role,
      );
      currentUser.value = user;
      isLoggedIn.value = true;
      // Register this device for push notifications (multi-device).
      NotificationService.instance.syncTokenForCurrentUser();
      // A newly registered account must start with a clean chat.
      _resetChatForNewUser(user);
      // Reload cloud-saved data after registration
      Get.find<ProfileController>().loadSavedDoctors();
      Get.find<AppointmentController>().loadAppointments();

      // If there's a pending doctor connection from NearbyDoctorsScreen,
      // complete it instead of normal redirect.
      if (pendingDoctor != null) {
        final success = await completeDoctorConnection(pendingDoctor);
        if (success) {
          final doctorCtrl = Get.find<DoctorController>();
          await doctorCtrl.setDoctor(pendingDoctor);
          Get.offAllNamed(
            AppRoutes.doctorDashboard,
            arguments: {'doctor': pendingDoctor},
          );
        } else {
          Get.offAllNamed(AppRoutes.home);
        }
        return;
      }

      // All registrations go to patient home by default
      Get.offAllNamed(AppRoutes.home);
    } on AuthException catch (e) {
      if (e.code == 'duplicate_mobile') {
        errorMessage.value = e.message;
        // Auto-redirect to login after a short delay so user can see the message
        Future.delayed(const Duration(seconds: 2), () {
          Get.offNamed(
            AppRoutes.login,
            arguments: {'pendingDoctor': ?pendingDoctor},
          );
        });
      } else {
        errorMessage.value = 'Registration failed. Please try again.';
        debugPrint('Registration error: ${e.message}');
      }
    } catch (e) {
      errorMessage.value =
          'Connection error. Please check your internet and try again.';
      debugPrint('Registration unexpected error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// Complete a doctor connection: save the doctor profile to the database,
  /// upgrade the user's role to 'doctor', and persist the place ID.
  ///
  /// Returns `true` on success, `false` on failure. The caller is
  /// responsible for showing any UI (alerts, navigation).
  Future<bool> completeDoctorConnection(DoctorModel doctor) async {
    try {
      // 1. Guard: user must be logged in to complete a connection
      if (currentUser.value == null) {
        debugPrint('❌ Cannot complete doctor connection: no logged-in user');
        errorMessage.value = 'Please log in first to connect a doctor.';
        return false;
      }

      // 2. Attach the user ID to the doctor record for join queries
      final doctorWithUserId = doctor.copyWith(userId: currentUser.value!.id);

      // 3. Save doctor profile to public.doctors table
      debugPrint('ℹ️ Saving doctor to DB: ${doctor.placeId} — ${doctor.name}');
      await _supabase.saveDoctorToDb(doctorWithUserId);
      debugPrint('✅ Doctor saved to DB successfully');

      // 4. Upgrade user role to 'doctor' and persist doctor_place_id
      final updatedUser = await _authService.updateRole(
        currentUser.value!,
        UserModel.roleDoctor,
        doctorPlaceId: doctor.placeId,
      );
      currentUser.value = updatedUser;

      return true;
    } catch (e) {
      debugPrint('❌ Failed to complete doctor connection: $e');
      final msg = e.toString().contains('column')
          ? 'Database column mismatch. Please run the latest migration.'
          : 'Failed to connect doctor. Please try again.';
      errorMessage.value = msg;
      return false;
    }
  }

  /// Ensure the current user's role is set to 'doctor' and the data is
  /// persisted to local storage. This is called as a safety net whenever
  /// the doctor dashboard opens.
  ///
  /// - If no user is logged in → silently returns (the guard in the shell
  ///   will redirect to login).
  /// - If the user is already a doctor → no-op.
  /// - Otherwise → delegates to [completeDoctorConnection] for the actual
  ///   save-to-DB, role-upgrade, and local-storage persistence.
  Future<void> ensureDoctorState(DoctorModel doctor) async {
    if (currentUser.value == null) return;
    if (currentUser.value!.isDoctor) return; // Already a doctor
    await completeDoctorConnection(doctor);
  }

  /// Show a styled OTP verification dialog before connecting a doctor.
  ///
  /// The entire flow (OTP entry → saving state → success) happens within
  /// a **single** dialog to eliminate the red-screen flash caused by
  /// rapidly closing and reopening multiple dialogs. The "Verify & Connect"
  /// button shows an inline spinner while saving.
  ///
  /// Flow:
  /// 1. Shows an OTP entry form with clinic info + 4-digit input.
  /// 2. On correct OTP, the button switches to a spinner (no separate
  ///    loading overlay).
  /// 3. Calls [completeDoctorConnection] to persist doctor + upgrade role.
  /// 4. Transitions the **same** dialog to a success view with
  ///    "Go to Dashboard".
  Future<void> showConnectedDialog(DoctorModel doctor) async {
    if (Get.context == null) return;

    final defaultOtp = '1111';
    final otpController = TextEditingController(text: defaultOtp);
    final focusNode = FocusNode();
    final otpError = ValueNotifier<String?>('');
    final otpValue = ValueNotifier<String>(defaultOtp);

    // ── Persistent state notifiers (live OUTSIDE the builder so values
    //     survive StatefulBuilder rebuilds; local variables get reset) ──
    final phaseNotifier = ValueNotifier<String>(
      'otp',
    ); // 'otp'|'saving'|'success'
    final resendSecsNotifier = ValueNotifier<int>(30);
    final otpResendableNotifier = ValueNotifier<bool>(false);
    Timer? resendTimer;

    void closeDialog() {
      if (Get.isDialogOpen ?? false) Get.back();
    }

    // ── Show a single dialog that transitions through 3 phases ──
    await Get.dialog(
      StatefulBuilder(
        builder: (context, setDialogState) {
          final phase = phaseNotifier.value;
          final resendSecs = resendSecsNotifier.value;
          final otpResendable = otpResendableNotifier.value;

          // ── Resend countdown timer — accepts a refresh callback so
          //     the builder rebuilds on each tick to show the countdown ──
          void startResendTimer() {
            resendTimer?.cancel();
            resendSecsNotifier.value = 30;
            otpResendableNotifier.value = false;
            resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (resendSecsNotifier.value <= 1) {
                timer.cancel();
                resendSecsNotifier.value = 0;
                otpResendableNotifier.value = true;
              } else {
                resendSecsNotifier.value--;
              }
              // Trigger builder rebuild so the countdown text updates
              setDialogState(() {});
            });
          }

          // Auto-start the countdown when the dialog first opens
          if (phase == 'otp' &&
              resendSecsNotifier.value == 30 &&
              !otpResendableNotifier.value &&
              resendTimer == null) {
            startResendTimer();
          }

          // ──────────────── PHASE 3: SUCCESS ────────────────
          if (phase == 'success') {
            return PopScope(
              canPop: false,
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: AppColors.bgMain,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Success checkmark ──
                            Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.success,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Connect Successfully!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textHeading,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You are now connected to\n${doctor.name}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textBody,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Your doctor session is saved.\nWelcome to your Doctor Dashboard!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textCaption,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () async {
                                  closeDialog();
                                  // Small delay so the dialog dismissal
                                  // renders before the route transition
                                  await Future.delayed(
                                    const Duration(milliseconds: 150),
                                  );
                                  final doctorCtrl =
                                      Get.find<DoctorController>();
                                  await doctorCtrl.setDoctor(doctor);
                                  Get.offAllNamed(
                                    AppRoutes.doctorDashboard,
                                    arguments: {'doctor': doctor},
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Go to Dashboard',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          // ──────────────── PHASE 1 & 2: OTP + SAVING ────────────────
          return PopScope(
            canPop: false,
            child: Container(
              color: Colors.black54,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppColors.bgMain,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Clinic avatar ──
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.primary,
                                  AppColors.secondary,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withAlpha(40),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _getInitials(doctor.name),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Title ──
                          Text(
                            'Verify Connection',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : AppColors.textHeading,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // ── Clinic name ──
                          Text(
                            doctor.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── OTP instruction ──
                          const Text(
                            'Enter the 4-digit code to confirm',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textBody,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── 4-digit OTP input ──
                          PinCodeTextField(
                            appContext: context,
                            controller: otpController,
                            focusNode: focusNode,
                            // The dialog owns otpController/focusNode and
                            // disposes them in the .then() cleanup below. The
                            // package's default (true) also disposes them →
                            // double-dispose assertion when the dialog closes.
                            autoDisposeControllers: false,
                            length: 4,
                            obscureText: false,
                            animationType: AnimationType.fade,
                            autoFocus: true,
                            enableActiveFill: true,
                            keyboardType: TextInputType.number,
                            pinTheme: PinTheme(
                              shape: PinCodeFieldShape.box,
                              borderRadius: BorderRadius.circular(14),
                              fieldHeight: 56,
                              fieldWidth: 48,
                              borderWidth: 1.5,
                              activeFillColor: Colors.white,
                              inactiveFillColor: Colors.white,
                              selectedFillColor: Colors.white,
                              activeColor: AppColors.primary,
                              inactiveColor: AppColors.primary.withAlpha(40),
                              selectedColor: AppColors.primary,
                              activeBorderWidth: 2,
                              inactiveBorderWidth: 1,
                              selectedBorderWidth: 2,
                            ),
                            textStyle: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textHeading,
                            ),
                            animationDuration: const Duration(
                              milliseconds: 200,
                            ),
                            enablePinAutofill: false,
                            showCursor: true,
                            cursorColor: AppColors.primary,
                            cursorWidth: 2,
                            beforeTextPaste: (text) => true,
                            onChanged: (value) {
                              otpValue.value = value;
                              otpError.value = '';
                            },
                          ),
                          const SizedBox(height: 8),

                          // ── Default OTP hint ──
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Default OTP: $defaultOtp',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.accent.withAlpha(200),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // ── Resend OTP ──
                          Center(
                            child: otpResendable
                                ? TextButton(
                                    onPressed: () {
                                      if (!otpResendable) return;
                                      otpController.text = defaultOtp;
                                      otpValue.value = defaultOtp;
                                      otpError.value = '';
                                      Get.snackbar(
                                        'Code Resent',
                                        'A new verification code has been sent.',
                                        snackPosition: SnackPosition.BOTTOM,
                                        backgroundColor: AppColors.success,
                                        colorText: Colors.white,
                                        duration: const Duration(seconds: 2),
                                      );
                                      startResendTimer();
                                      // Refresh the resend UI immediately
                                      setDialogState(() {});
                                    },
                                    child: const Text(
                                      'Resend OTP',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Resend OTP in $resendSecs'
                                    ' seconds',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textCaption.withAlpha(
                                        200,
                                      ),
                                    ),
                                  ),
                          ),

                          // ── Error message ──
                          ValueListenableBuilder<String?>(
                            valueListenable: otpError,
                            builder: (context, err, _) {
                              if (err == null || err.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withAlpha(20),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        err,
                                        style: const TextStyle(
                                          color: AppColors.error,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // ── Verify & Connect button ──
                          //     (shows inline spinner while saving)
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: phase == 'saving'
                                  ? null
                                  : () async {
                                      // Hide the keyboard so the user
                                      // sees the button switch to saving.
                                      FocusScope.of(context).unfocus();

                                      final otp = otpValue.value;
                                      if (otp.length != 4 ||
                                          !RegExp(r'^\d{4}$').hasMatch(otp)) {
                                        otpError.value =
                                            'Please enter a valid '
                                            '4-digit code';
                                        return;
                                      }
                                      if (otp != defaultOtp) {
                                        otpError.value =
                                            'Invalid code. '
                                            'Please try again.';
                                        return;
                                      }

                                      // Phase 2: saving — show
                                      // spinner on button
                                      phaseNotifier.value = 'saving';
                                      setDialogState(() {});

                                      resendTimer?.cancel();

                                      final success =
                                          await completeDoctorConnection(
                                            doctor,
                                          );

                                      if (success) {
                                        final doctorCtrl =
                                            Get.find<DoctorController>();
                                        await doctorCtrl.setDoctor(doctor);
                                        phaseNotifier.value = 'success';
                                        setDialogState(() {});
                                      } else {
                                        // Reset to OTP on error
                                        phaseNotifier.value = 'otp';
                                        otpError.value =
                                            'Connection failed. '
                                            'Please try again.';
                                        startResendTimer();
                                        setDialogState(() {});
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                disabledBackgroundColor: AppColors.primary
                                    .withAlpha(120),
                                disabledForegroundColor: Colors.white.withAlpha(
                                  200,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: phase == 'saving'
                                  ? const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Connecting...',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Verify & Connect',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ── Cancel button ──
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: phase == 'saving'
                                  ? null
                                  : () {
                                      resendTimer?.cancel();
                                      closeDialog();
                                    },
                              child: Text(
                                phase == 'saving' ? '' : 'Cancel',
                                style: const TextStyle(
                                  color: AppColors.textCaption,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
    ).then((_) {
      // Clean up after dialog closes
      resendTimer?.cancel();
      otpController.dispose();
      focusNode.dispose();
    });
  }

  /// Extract initials from a name for the avatar placeholder.
  String _getInitials(String name) {
    final parts = name
        .replaceFirst('Dr. ', '')
        .replaceFirst('Dr ', '')
        .trim()
        .split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> logout() async {
    // Stop push notifications reaching this device for the previous user —
    // best-effort, so a shared device never leaks notifications across
    // users. EXCEPTION: a doctor's device registration is deliberately
    // kept on logout (see NotificationService.removeTokenForUser) so the
    // clinic keeps receiving booking pushes even when a patient logs into
    // the same shared phone.
    final user = currentUser.value;
    if (user != null) {
      await NotificationService.instance.removeTokenForUser(user);
    }
    await _authService.logout();
    currentUser.value = null;
    isLoggedIn.value = false;
    // Drop the previous user's in-memory saved doctors so they can't
    // leak into the next session on this device.
    if (Get.isRegistered<ProfileController>()) {
      Get.find<ProfileController>().clearSession();
    }
    Get.offAllNamed(AppRoutes.login);
  }

  /// If the user logging in differs from the one that last used this
  /// device, wipe the chat history so conversations never cross users.
  /// Best-effort: storage/controller hiccups must never block login.
  void _resetChatForNewUser(UserModel user) {
    try {
      final storage = LocalStorageService();
      final lastMobile = storage.getLastLoggedInMobile();
      final currentMobile = user.mobile;
      if (lastMobile != currentMobile) {
        if (Get.isRegistered<VoiceController>()) {
          Get.find<VoiceController>().clearChat();
        }
        storage.setLastLoggedInMobile(currentMobile ?? '');
      }
    } catch (_) {
      // Non-fatal — chat is only a convenience, login must proceed.
    }
  }

  bool _isValidMobile(String mobile) {
    return mobile.length == 10 && RegExp(r'^\d{10}$').hasMatch(mobile);
  }
}
