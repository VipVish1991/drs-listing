import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_button.dart';

/// First step of the doctor registration flow.
///
/// Collects the doctor's name (with a placeholder hint) and mobile
/// number, then shows a 1-second loading animation followed by the
/// nearby clinics & hospitals list where the user picks their clinic.
class DoctorRegisterScreen extends StatefulWidget {
  const DoctorRegisterScreen({super.key});

  @override
  State<DoctorRegisterScreen> createState() => _DoctorRegisterScreenState();
}

class _DoctorRegisterScreenState extends State<DoctorRegisterScreen> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();

  /// Focus nodes so the keyboard's "next" action on the name field moves
  /// focus straight to the mobile field (instead of being a no-op).
  final _nameFocusNode = FocusNode();
  final _mobileFocusNode = FocusNode();

  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _nameFocusNode.dispose();
    _mobileFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    // Hide the keyboard so the user sees the result of the tap.
    FocusScope.of(context).unfocus();

    setState(() => _errorMessage = null);

    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }
    if (mobile.isEmpty) {
      setState(() => _errorMessage = 'Please enter your mobile number');
      return;
    }
    if (mobile.length != 10 || !RegExp(r'^\d{10}$').hasMatch(mobile)) {
      setState(
        () => _errorMessage = 'Please enter a valid 10-digit mobile number',
      );
      return;
    }

    // Show loading overlay for 1 second
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _isLoading = false);

    // Navigate to nearby clinics with registration data
    Get.toNamed(
      AppRoutes.nearbyDoctors,
      arguments: {
        'displayName': name,
        'mobile': mobile,
        'role': UserModel.roleDoctor,
        'mode': 'register',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),

                  // Back button
                  AppBackButton(onPressed: Get.back),

                  const SizedBox(height: 40),

                  // Illustration
                  Center(
                        child: Container(
                          width: 120,
                          height: 120,
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
                            Icons.medical_services_rounded,
                            size: 56,
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
                    'Doctor Registration',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

                  const SizedBox(height: 8),
                  Text(
                    'Enter your details to get started',
                    style: TextStyle(fontSize: 16, color: bodyColor),
                  ).animate().fadeIn(duration: 500.ms, delay: 300.ms),

                  const SizedBox(height: 32),

                  // Name input
                  TextField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _mobileFocusNode.requestFocus(),
                        decoration: const InputDecoration(
                          hintText: 'Doctor name, Clinic name, Hospital name',
                          hintStyle: TextStyle(fontSize: 13),
                          prefixIcon: Icon(
                            Icons.badge_outlined,
                            color: AppColors.textCaption,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 400.ms)
                      .slideX(begin: 0.1, end: 0, duration: 500.ms),

                  const SizedBox(height: 20),

                  // Mobile number input
                  TextField(
                        controller: _mobileController,
                        focusNode: _mobileFocusNode,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        maxLength: 10,
                        decoration: const InputDecoration(
                          hintText: 'Mobile Number',
                          prefixIcon: Icon(
                            Icons.phone_android,
                            color: AppColors.textCaption,
                          ),
                          counterText: '',
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 500.ms)
                      .slideX(begin: 0.1, end: 0, duration: 500.ms),

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

                  // Continue button
                  AppPrimaryButton(
                    label: 'Continue',
                    onPressed: _handleContinue,
                  ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

                  const SizedBox(height: 24),

                  // Info text
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: AppColors.primary.withAlpha(200),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Select your clinic after continuing to nearby healthcare places.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primary.withAlpha(200),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(duration: 500.ms, delay: 700.ms),
                ],
              ),
            ),

            // ── Loading overlay ──
            if (_isLoading)
              Container(
                color: AppColors.bgMain.withAlpha(240),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(60),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Finding nearby clinics...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textHeading,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Looking for hospitals and clinics near you',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textBody.withAlpha(200),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 200.ms),
          ],
        ),
      ),
    );
  }
}
