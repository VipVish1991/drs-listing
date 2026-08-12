import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../services/launch_service.dart';


class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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

              // ── FAQ Section ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSectionHeader(
                  icon: Icons.help_outline_rounded,
                  label: 'Frequently Asked Questions',
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _FaqTile(
                      question: 'How do I describe my symptoms?',
                      answer: 'Tap the microphone button on the home screen and speak '
                          'about your symptoms in your preferred language. You can also '
                          'type your symptoms using the text input.',
                    ),
                    const SizedBox(height: 10),
                    _FaqTile(
                      question: 'How does the AI recommend a specialist?',
                      answer: 'Our AI analyzes the symptoms you describe and matches '
                          'them with the most relevant medical specialist. For example, '
                          'chest pain may be directed to a Cardiologist, while a headache '
                          'may be directed to a Neurologist.',
                    ),
                    const SizedBox(height: 10),
                    _FaqTile(
                      question: 'How do I find a doctor near me?',
                      answer: 'Your location is used to find healthcare providers near '
                          'you. You can search by specialization, name, or browse '
                          'categories. Results are sorted by distance and rating.',
                    ),
                    const SizedBox(height: 10),
                    _FaqTile(
                      question: 'How do I book an appointment?',
                      answer: 'After finding a doctor, tap on their profile and select '
                          '"Book Appointment". Choose your preferred date and time, '
                          'enter your details, and confirm the booking.',
                    ),
                    const SizedBox(height: 10),
                    _FaqTile(
                      question: 'Can I use the app in my regional language?',
                      answer: 'Yes! DrsListing supports 12+ Indian languages '
                          'including Hindi, Marathi, Gujarati, Tamil, Telugu, Kannada, '
                          'Malayalam, Punjabi, Bengali, Odia, and Urdu. Select your '
                          'preferred language from the Profile screen.',
                    ),
                  ].animate().fadeIn(
                    duration: 400.ms,
                    delay: 100.ms,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Contact Section ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSectionHeader(
                  icon: Icons.headset_mic_rounded,
                  label: 'Contact Us',
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    children: [
                      _ContactItem(
                        icon: Icons.email_outlined,
                        label: 'Email Support',
                        value: 'support@drslisting.ai',
                        onTap: () => LaunchService.url('mailto:support@drslisting.ai'),
                      ),
                      const Divider(height: 24),
                      _ContactItem(
                        icon: Icons.chat_outlined,
                        label: 'In-App Chat',
                        value: 'Chat with our AI assistant anytime',
                        onTap: () => Get.back(),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(
                  begin: 0.1, end: 0, duration: 300.ms,
                ),
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
                'Help & Support',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Find answers and get support',
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

  Widget _buildSectionHeader({
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textHeading,
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.question,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textHeading,
                    ),
                  ),
                  trailing: AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _isExpanded ? 0.5 : 0.0,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.textCaption.withAlpha(150),
                      size: 24,
                    ),
                  ),
                ),
                if (_isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, right: 32),
                    child: Text(
                      widget.answer,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textBody,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ContactItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.primaryLight,
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textCaption.withAlpha(200),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textHeading,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textCaption.withAlpha(120),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
