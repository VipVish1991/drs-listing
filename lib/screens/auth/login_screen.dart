import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/app_button.dart';
import '../../routes/app_routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileController = TextEditingController();
  final _authController = Get.find<AuthController>();

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    // Hide the keyboard so the user sees the result of the tap.
    FocusScope.of(context).unfocus();

    // Pass pending doctor from NearbyDoctorsScreen so login can
    // complete the doctor connection after authentication.
    final args = Get.arguments;
    final pendingDoctor = args is Map ? args['pendingDoctor'] : null;
    _authController.login(_mobileController.text, pendingDoctor: pendingDoctor);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textHeading;
    final bodyColor = isDark ? const Color(0xFFCCCCCC) : AppColors.textBody;

    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: SingleChildScrollView(
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
                        Icons.person_outline,
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
                'Welcome Back!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

              const SizedBox(height: 8),
              Text(
                'Enter your mobile number to continue',
                style: TextStyle(fontSize: 16, color: bodyColor),
              ).animate().fadeIn(duration: 500.ms, delay: 300.ms),

              const SizedBox(height: 40),

              // Mobile number input
              TextField(
                    controller: _mobileController,
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
                  .fadeIn(duration: 500.ms, delay: 400.ms)
                  .slideX(begin: 0.1, end: 0, duration: 500.ms),

              const SizedBox(height: 24),

              // Error message
              Obx(
                () => _authController.errorMessage.isNotEmpty
                    ? Container(
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
                                _authController.errorMessage.value,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(),
              ),

              const SizedBox(height: 24),

              // Login button
              Obx(
                () => AppPrimaryButton(
                  label: 'Continue',
                  isLoading: _authController.isLoading.value,
                  onPressed: _handleLogin,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 500.ms),

              const SizedBox(height: 24),

              // Register link
              Center(
                child: TextButton(
                  onPressed: () {
                    // Forward pending doctor to registration screen
                    final args = Get.arguments;
                    final pendingDoctor = args is Map
                        ? args['pendingDoctor']
                        : null;
                    Get.toNamed(
                      AppRoutes.register,
                      arguments: {
                        'mobile': _mobileController.text,
                        'pendingDoctor': ?pendingDoctor,
                      },
                    );
                  },
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: bodyColor),
                      children: [
                        TextSpan(text: "Don't have an account? "),
                        const TextSpan(
                          text: 'Create Account',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

              const SizedBox(height: 8),

              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: AppColors.textCaption.withAlpha(50),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Are you a doctor?',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textCaption.withAlpha(150),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: AppColors.textCaption.withAlpha(50),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 700.ms),

              const SizedBox(height: 12),

              // Register as Doctor button — new flow via DoctorRegisterScreen
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Get.toNamed(AppRoutes.doctorRegister),
                  icon: const Icon(Icons.medical_services_outlined, size: 18),
                  label: const Text('Register as Doctor'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withAlpha(120)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 800.ms),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
