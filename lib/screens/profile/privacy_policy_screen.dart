import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';


class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgMain,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Gradient Header ──
              _buildGradientHeader(),

              const SizedBox(height: 24),

              // ── Content ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Last updated: July 1, 2026',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ].animate().fadeIn(duration: 400.ms, delay: 100.ms),
                ),
              ),

              const SizedBox(height: 20),

              _Section(
                title: 'Information We Collect',
                icon: Icons.info_outline_rounded,
                iconColor: AppColors.info,
                content:
                    'We collect information you provide directly, such as your name, '
                    'mobile number, and health-related information you share while '
                    'describing symptoms. We also collect location data to help find '
                    'nearby healthcare providers.',
              ).animate().fadeIn(duration: 400.ms, delay: 150.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              _Section(
                title: 'How We Use Your Information',
                icon: Icons.construction_rounded,
                iconColor: AppColors.accent,
                content:
                    'Your information is used to provide and improve our healthcare '
                    'assistant services, including:\n\n'
                    '• Analyzing symptoms using AI to recommend appropriate specialists\n'
                    '• Finding nearby doctors, clinics, and hospitals\n'
                    '• Booking appointments with healthcare providers\n'
                    '• Improving our AI models and service quality',
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              _Section(
                title: 'Location Data',
                icon: Icons.location_on_rounded,
                iconColor: AppColors.healthHeart,
                content:
                    'We use your device\'s location to show nearby healthcare providers. '
                    'Location data is not stored on our servers and is only used '
                    'in real-time for search purposes. You can disable location '
                    'access at any time from your device settings.',
              ).animate().fadeIn(duration: 400.ms, delay: 250.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              _Section(
                title: 'Data Security',
                icon: Icons.shield_rounded,
                iconColor: AppColors.primary,
                content:
                    'We implement industry-standard security measures to protect your '
                    'personal information. Your health-related conversations are '
                    'processed securely and are not shared with third parties without '
                    'your explicit consent.',
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              _Section(
                title: 'Third-Party Services',
                icon: Icons.cloud_outlined,
                iconColor: AppColors.info,
                content:
                    'We use the following third-party services to provide our features:\n\n'
                    '• Google Places API — for location-based search of healthcare providers\n'
                    '• OpenAI / Groq — for AI-powered symptom analysis\n'
                    '• Supabase — for user authentication and data storage\n\n'
                    'Each service has its own privacy policy governing data handling.',
              ).animate().fadeIn(duration: 400.ms, delay: 350.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              _Section(
                title: 'Data Retention',
                icon: Icons.storage_rounded,
                iconColor: AppColors.accent,
                content:
                    'We retain your data only as long as necessary to provide our '
                    'services. You can request deletion of your account and associated '
                    'data at any time by contacting our support team.',
              ).animate().fadeIn(duration: 400.ms, delay: 400.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              _Section(
                title: 'Your Rights',
                icon: Icons.gavel_rounded,
                iconColor: AppColors.healthBrain,
                content:
                    'You have the right to:\n\n'
                    '• Access your personal data\n'
                    '• Correct inaccurate data\n'
                    '• Delete your data\n'
                    '• Object to data processing\n'
                    '• Withdraw consent at any time\n\n'
                    'To exercise these rights, please contact us at support@drslisting.ai.',
              ).animate().fadeIn(duration: 400.ms, delay: 450.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              _Section(
                title: 'Contact Us',
                icon: Icons.mail_outline_rounded,
                iconColor: AppColors.primary,
                content:
                    'If you have any questions about this Privacy Policy, please '
                    'contact us at:\n\n'
                    'Email: support@drslisting.ai\n'
                    'Address: Pune, Maharashtra, India',
              ).animate().fadeIn(duration: 400.ms, delay: 500.ms).slideY(
                begin: 0.05, end: 0, duration: 300.ms,
              ),

              const SizedBox(height: 20),

              // ── Privacy commitment banner ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withAlpha(15),
                        AppColors.healthBrain.withAlpha(10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withAlpha(30),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 22,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Your privacy matters to us. We are committed to protecting '
                          'your personal and health information.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textBody,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 550.ms),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
            const Color(0xFF095E4C),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(80),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: Get.back,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(25),
                border: Border.all(
                  color: Colors.white.withAlpha(40),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'How we handle your data',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String content;

  const _Section({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHeading,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textBody,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
