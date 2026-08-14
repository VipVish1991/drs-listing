import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/doctor_controller.dart';
import '../../models/doctor_model.dart';
import '../../models/user_model.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../utils/otp_generator.dart';
import '../../utils/snackbar_helpers.dart';
import '../../widgets/app_button.dart';

/// OTP verification screen used for both patient and doctor registration.
///
/// Client-side OTP: the screen generates a fresh random 4-digit code via
/// [generateDemoOtp] (no server/SMS involved — the code is shown in a top
/// toast for demo/testing) and verifies the entered code locally against
/// it before registering. There is NO universal hardcoded code.
///
/// After a successful verification the user is registered with
/// [AuthService.register] and routed to the role-appropriate destination.
///
/// When [doctor] is provided (registration mode), the user picked their
/// clinic/hospital BEFORE OTP. After successful verification, the doctor
/// connection is completed and the user is taken directly to the dashboard.
///
/// When [doctor] is `null` (existing flow), the post-verification
/// destination depends on [role]:
/// - `UserModel.roleDoctor` → navigates to nearby doctors to connect
/// - `UserModel.rolePatient` → navigates to patient home
class OtpVerificationScreen extends StatefulWidget {
  final String displayName;
  final String mobile;
  final String role;
  final DoctorModel? doctor;

  /// Injectable for tests — production callers omit it and get the real
  /// [AuthService] singleton. Tests pass a counting fake to assert how
  /// many `register()` calls the verification flow makes.
  final AuthService? authService;

  /// Injectable for tests — production callers omit it and the screen
  /// generates a random code via [generateDemoOtp]. Tests pass a fixed
  /// code so they can assert the toast + local verification.
  final String Function()? otpGenerator;

  /// Delay before the OTP "arrives" (the toast shows) — feels like a real
  /// SMS send. Kept on the widget so tests can shorten it.
  final Duration otpSendDelay;

  const OtpVerificationScreen({
    super.key,
    required this.displayName,
    required this.mobile,
    this.role = UserModel.roleDoctor,
    this.doctor,
    this.authService,
    this.otpGenerator,
    this.otpSendDelay = const Duration(seconds: 3),
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  /// The client-generated OTP (demo mode — displayed to the user).
  /// Generated in [initState] (and on resend) via [generateDemoOtp].
  String? _generatedOtp;

  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  int _resendTimer = 15;
  bool _canResend = false;

  /// The server OTP is 4 digits.
  int get _pinLength => 4;

  /// Registration service used by [_verifyOtp]. Defaults to the real
  /// singleton; tests inject a fake via [OtpVerificationScreen.authService].
  late final AuthService _authService = widget.authService ?? AuthService();

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    // Mint a fresh server OTP and pre-fill it (demo mode — the code is
    // returned so the app can display it). Non-fatal: on failure the
    // screen still renders with an empty field and a friendly message.
    _loadOtp();
  }

  /// Generates a fresh OTP locally. The code is NOT pre-filled — the
  /// user reads it from the top toast and types it into the field
  /// manually. The toast is sent after a short [otpSendDelay] so the flow
  /// feels like a real SMS arriving.
  Future<void> _loadOtp() async {
    final otp = (widget.otpGenerator ?? generateDemoOtp)();
    if (!mounted) return;
    setState(() {
      _generatedOtp = otp;
      _errorMessage = null;
    });
    // "Send" the code after the delay. Deferred to after the first frame
    // — [initState] can run during the build phase, and Get.snackbar
    // inserts an overlay entry (setState on the Overlay) which would
    // throw "setState during build".
    Timer(widget.otpSendDelay, () {
      if (!mounted) return;
      showDemoOtpToast(otp);
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _canResend = false;
    _resendTimer = 15;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _resendTimer--;
        if (_resendTimer <= 0) {
          _canResend = true;
        }
      });
      return _resendTimer > 0;
    });
  }

  Future<void> _verifyOtp() async {
    // Re-entry guard: the screen previously had NO guard, so a second
    // concurrent call (auto-submit onChanged + button tap, or a double
    // tap) fired register() twice. The second INSERT then violated the
    // users.mobile UNIQUE constraint and surfaced as "Verification
    // failed" — i.e. OTP 1111 appeared "not verified".
    if (_isLoading) return;

    final otp = _pinController.text;

    if (!_isCompleteOtp(otp)) {
      setState(
        () => _errorMessage =
            'Please enter a valid $_pinLength-digit OTP',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Client-side verification — the entered code must match the code
    // the app generated for this screen.
    final verified = otp == _generatedOtp;
    if (!verified) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Invalid OTP. Please try again.';
      });
      return;
    }

    await _proceedWithVerifiedNumber();
  }

  /// True when [otp] has exactly [_pinLength] digits (the complete code).
  bool _isCompleteOtp(String otp) {
    return otp.length == _pinLength &&
        RegExp(r'^[0-9]{4}$').hasMatch(otp);
  }

  /// Fires [_verifyOtp] automatically once the entered code is complete
  /// (4 digits) — no Verify tap needed. Gated so it can never race the
  /// button.
  void _autoSubmitIfComplete() {
    // The field is never pre-filled anymore — every value here is genuine
    // user input, so any complete code auto-submits.
    if (_isLoading) return;
    final otp = _pinController.text;
    if (!_isCompleteOtp(otp)) return;
    FocusScope.of(context).unfocus();
    _verifyOtp();
  }

  /// Runs the registration / doctor-connection flow AFTER the mobile
  /// number has been verified.
  Future<void> _proceedWithVerifiedNumber() async {
    try {
      final user = await _authService.register(
        widget.displayName,
        widget.mobile,
        role: widget.role,
      );

      final authCtrl = Get.find<AuthController>();
      authCtrl.currentUser.value = user;
      authCtrl.isLoggedIn.value = true;

      // ── Doctor was pre-selected → complete connection & go to dashboard ──
      if (widget.doctor != null) {
        final success = await authCtrl.completeDoctorConnection(widget.doctor!);
        if (success) {
          final doctorCtrl = Get.find<DoctorController>();
          await doctorCtrl.setDoctor(widget.doctor!);
          if (mounted) {
            Get.offAllNamed(
              AppRoutes.doctorDashboard,
              arguments: {'doctor': widget.doctor},
            );
          }
        } else {
          // Fallback: navigate to nearby doctors if connection fails
          // (always in registration mode so an already-registered doctor
          // sees the disabled state instead of the normal Connect flow).
          if (mounted) {
            Get.offNamed(
              AppRoutes.nearbyDoctors,
              arguments: {
                'displayName': widget.displayName,
                'mobile': widget.mobile,
                'role': widget.role,
                'mode': 'register',
              },
            );
          }
        }
        return;
      }

      // ── No pre-selected doctor (original flow) ──
      if (mounted) {
        final destination = widget.role == UserModel.roleDoctor
            ? AppRoutes.nearbyDoctors
            : AppRoutes.home;
        Get.offNamed(
          destination,
          arguments: {
            'displayName': widget.displayName,
            'mobile': widget.mobile,
            // Keep the nearby list in registration mode for doctors so
            // an already-registered mobile is detected and disabled.
            if (widget.role == UserModel.roleDoctor) 'mode': 'register',
          },
        );
      }
    } on AuthException catch (e) {
      if (e.code == 'duplicate_mobile') {
        final authCtrl = Get.find<AuthController>();

        // This number is already registered → log straight in. Using
        // redirect: false means login() only populates state and does NOT
        // navigate, so THIS screen decides the single destination.
        // (Previously login() navigated to the role home AND this screen
        // navigated again from a being-disposed route → double navigation.)
        final loggedIn = await authCtrl.login(widget.mobile, redirect: false);
        if (!loggedIn || authCtrl.currentUser.value == null) {
          if (!mounted) return;
          setState(() {
            _errorMessage = authCtrl.errorMessage.value.isNotEmpty
                ? authCtrl.errorMessage.value
                : 'Login failed. Please try again.';
          });
          return;
        }
        if (!mounted) return;

        // If doctor was pre-selected, complete the connection after login
        if (widget.doctor != null) {
          final success = await authCtrl.completeDoctorConnection(
            widget.doctor!,
          );
          if (success && mounted) {
            final doctorCtrl = Get.find<DoctorController>();
            await doctorCtrl.setDoctor(widget.doctor!);
            Get.offAllNamed(
              AppRoutes.doctorDashboard,
              arguments: {'doctor': widget.doctor},
            );
            return;
          }
          // Connection failed → back to the nearby list to retry (in
          // registration mode so an already-registered doctor sees the
          // disabled state instead of the normal Connect flow).
          if (mounted) {
            Get.offNamed(
              AppRoutes.nearbyDoctors,
              arguments: {
                'displayName': widget.displayName,
                'mobile': widget.mobile,
                'role': widget.role,
                'mode': 'register',
              },
            );
          }
          return;
        }

        final destination = widget.role == UserModel.roleDoctor
            ? AppRoutes.nearbyDoctors
            : AppRoutes.home;
        Get.offNamed(
          destination,
          arguments: {
            'displayName': widget.displayName,
            'mobile': widget.mobile,
            // Keep the nearby list in registration mode for doctors so
            // an already-registered mobile is detected and disabled.
            if (widget.role == UserModel.roleDoctor) 'mode': 'register',
          },
        );
        return;
      }
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Verification failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resendOtp() {
    // Client-side flow: generate a fresh code and show it in the top
    // toast after the send delay (the user types it manually).
    setState(() => _errorMessage = null);
    _pinController.clear();
    _loadOtp();
    showSuccessSnackbar('A new verification code has been generated');
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    // Block BOTH the on-screen back button and the Android system back
    // gesture while a verification is in flight — otherwise the user can
    // pop the screen mid-register() and the completed registration still
    // fires navigation from a disposed route. PopScope only guards
    // system-initiated pops; the success path's Get.offNamed(...) is
    // unaffected.
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: AppColors.bgMain,
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                // Back button (disabled while verifying)
                AppBackButton(onPressed: _isLoading ? null : Get.back),

                const SizedBox(height: 40),

                // Illustration
                Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(40),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.smartphone_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1, 1),
                      duration: 600.ms,
                      curve: Curves.elasticOut,
                    ),

                const SizedBox(height: 40),

                // Title
                Text(
                  'Verify OTP',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

                const SizedBox(height: 8),

                // Subtitle — demo mode (no SMS), so the copy asks for the
                // code rather than claiming one was sent.
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 16, color: bodyColor),
                    children: [
                      const TextSpan(text: 'Enter the 4-digit OTP for '),
                      TextSpan(
                        text: '+91 ${widget.mobile}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 300.ms),

                const SizedBox(height: 40),

                // OTP input using PinCodeTextField
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: PinCodeTextField(
                    appContext: context,
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    // The screen owns _pinController/_pinFocusNode and disposes
                    // them itself. The package's default (true) also disposes
                    // them → double-dispose assertion when the screen closes.
                    autoDisposeControllers: false,
                    length: _pinLength,
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
                      activeFillColor: isDark
                          ? Colors.white.withAlpha(15)
                          : Colors.white,
                      inactiveFillColor: isDark
                          ? Colors.white.withAlpha(10)
                          : Colors.white,
                      selectedFillColor: isDark
                          ? Colors.white.withAlpha(20)
                          : Colors.white,
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
                      color: textColor,
                    ),
                    animationDuration: const Duration(milliseconds: 200),
                    enablePinAutofill: false,
                    showCursor: true,
                    cursorColor: AppColors.primary,
                    cursorWidth: 2,
                    beforeTextPaste: (text) => true,
                    onChanged: (value) {
                      setState(() => _errorMessage = null);
                      // Auto-submit as soon as the code is complete. Safe:
                      // [_verifyOtp] has a re-entry guard (_isLoading) that
                      // also covers the Verify button.
                      _autoSubmitIfComplete();
                    },
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 400.ms).slideY(begin: 0.1, end: 0),

                const SizedBox(height: 12),

                // Hint pill: shows the pre-filled demo OTP (no SMS is
                // sent — the code is returned by the server for display).
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Demo OTP: $_generatedOtp',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.accent.withAlpha(200),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 450.ms),

                const SizedBox(height: 24),

                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 300.ms),

                const SizedBox(height: 24),

                // Verify button
                AppPrimaryButton(
                  label: 'Verify & Continue',
                  isLoading: _isLoading,
                  onPressed: _isLoading
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          _verifyOtp();
                        },
                ).animate().fadeIn(duration: 500.ms, delay: 500.ms),

                const SizedBox(height: 20),

                // Resend OTP — re-fills the default code; the countdown is
                // a soft pacing hint only.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _resendOtp,
                        child: const Text(
                          'Resend OTP',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (!_canResend)
                        Text(
                          'You can resend in $_resendTimer s',
                          style: TextStyle(
                            fontSize: 12,
                            color: bodyColor.withAlpha(150),
                          ),
                        ),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

                const SizedBox(height: 16),

                // Doctor info card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withAlpha(30)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textHeading,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '+91 ${widget.mobile}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textBody,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 700.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
