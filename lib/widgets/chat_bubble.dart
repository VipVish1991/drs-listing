import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/theme.dart';
import '../models/ai_response_model.dart';
import '../models/doctor_model.dart';
import '../utils/text_sanitizer.dart';
import '../widgets/doctor_recommendation_card.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showAnimation;
  final VoidCallback? onTapSpecialist;

  /// Optional list of recommended doctors shown as compact inline cards
  /// right inside the AI bubble, so users can see and book immediately.
  final List<DoctorModel>? recommendedDoctors;

  /// Called when the user taps "Book" on a recommended doctor card.
  final ValueChanged<DoctorModel>? onBookDoctor;

  /// Called when the user taps a recommended doctor card to view profile.
  final ValueChanged<DoctorModel>? onViewDoctorProfile;

  const ChatBubble({
    super.key,
    required this.message,
    this.showAnimation = true,
    this.onTapSpecialist,
    this.recommendedDoctors,
    this.onBookDoctor,
    this.onViewDoctorProfile,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(context),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.primary
                    : isDark
                        ? Colors.white.withAlpha(10)
                        : AppColors.primaryLight,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? 20 : 8),
                  topRight: Radius.circular(isUser ? 8 : 20),
                  bottomLeft: const Radius.circular(20),
                  bottomRight: const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withAlpha(30)
                        : Colors.black.withAlpha(10),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI analysis badge
                  if (!isUser && message.analysis != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.medical_services,
                              size: 14, color: AppColors.success),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              TextSanitizer.sanitize(
                                  message.analysis!.specialist),
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Message text — sanitized at render as a final guard so
                  // a bad-UTF-16 payload can never reach the text engine.
                  Text(
                    TextSanitizer.sanitize(message.text),
                    style: TextStyle(
                      color: isUser
                          ? Colors.white
                          : isDark
                              ? Colors.white70
                              : AppColors.textBody,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),

                  // Timestamp
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isUser
                            ? Colors.white.withAlpha(150)
                            : isDark
                                ? Colors.white.withAlpha(100)
                                : AppColors.textCaption,
                      ),
                    ),
                  ),

                  // Specialist search suggestion – shown at bottom of AI responses
                  if (!isUser && message.analysis != null && onTapSpecialist != null) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onTapSpecialist,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(isDark ? 20 : 10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withAlpha(40),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: AppColors.primary.withAlpha(30),
                              ),
                              child: const Icon(
                                Icons.search,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Find ${TextSanitizer.sanitize(message.analysis!.specialist)}s near you',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : AppColors.textHeading,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Tap to search nearby clinics & hospitals',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white.withAlpha(150)
                                          : AppColors.textCaption,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 12,
                              color: isDark
                                  ? Colors.white.withAlpha(100)
                                  : AppColors.textCaption,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ── Inline doctor recommendation cards ──
                  if (!isUser && recommendedDoctors != null && recommendedDoctors!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    // Header label
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.medical_services_outlined,
                            size: 12,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Recommended ${message.analysis?.specialist ?? "Doctors"}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Doctor cards
                    ...recommendedDoctors!.map((doctor) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DoctorRecommendationCard(
                        doctor: doctor,
                        onBook: () => onBookDoctor?.call(doctor),
                        onViewProfile: () =>
                            onViewDoctorProfile?.call(doctor),

                      ),
                    )),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser) _buildUserAvatar(context),
        ],
      ),
    ).animate().fadeIn(
          duration: 300.ms,
          delay: showAnimation ? 100.ms : 0.ms,
        ).slideX(
          begin: isUser ? 0.3 : -0.3,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOut,
        );
  }

  Widget _buildAvatar(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/app_logo.png',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildUserAvatar(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.secondary,
      ),
      child: const Center(
        child: Icon(Icons.person, size: 18, color: Colors.white),
      ),
    );
  }
}
