import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/app_button.dart';
import '../../models/user_model.dart';
import '../../routes/app_routes.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();

  /// Focus nodes so the keyboard's "next" action on the name field moves
  /// focus straight to the mobile field (instead of being a no-op).
  final _nameFocusNode = FocusNode();
  final _mobileFocusNode = FocusNode();

  final _authController = Get.find<AuthController>();

  @override
  void initState() {
    super.initState();
    // Get mobile from arguments if available
    final args = Get.arguments;
    if (args is Map && args.containsKey('mobile')) {
      _mobileController.text = args['mobile'];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _nameFocusNode.dispose();
    _mobileFocusNode.dispose();
    super.dispose();
  }

  void _handleRegister() {
    // Hide the keyboard so the user sees the result of the tap.
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();

    if (name.isEmpty) {
      _authController.errorMessage.value = 'Please enter your name';
      return;
    }
    if (mobile.isEmpty || mobile.length != 10) {
      _authController.errorMessage.value =
          'Please enter a valid 10-digit mobile number';
      return;
    }

    // Navigate to OTP verification screen for 4-digit code entry
    Get.toNamed(
      AppRoutes.otpVerification,
      arguments: {
        'displayName': name,
        'mobile': mobile,
        'role': UserModel.rolePatient,
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
                      ),
                      child: const Icon(
                        Icons.person_add,
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
                'Create Account',
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

              const SizedBox(height: 24),

              // Full Name input
              TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _mobileFocusNode.requestFocus(),
                    decoration: const InputDecoration(
                      hintText: 'Full Name',
                      prefixIcon: Icon(
                        Icons.person_outline,
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

              // Register button
              Obx(
                () => AppPrimaryButton(
                  label: 'Create Account',
                  isLoading: _authController.isLoading.value,
                  onPressed: _handleRegister,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

              const SizedBox(height: 24),

              // Login link
              Center(
                child: TextButton(
                  onPressed: () => Get.toNamed(AppRoutes.login),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14, color: bodyColor),
                      children: [
                        TextSpan(text: 'Already have an account? '),
                        const TextSpan(
                          text: 'Login',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 700.ms),
            ],
          ),
        ),
      ),
    );
  }
}
