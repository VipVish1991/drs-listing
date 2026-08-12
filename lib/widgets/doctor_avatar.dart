import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/doctor_model.dart';
import '../services/places_service.dart';

/// Shape variant for the avatar.
enum AvatarShape { circle, roundedRect }

/// A reusable doctor avatar that loads the Google Places photo with a
/// gradient initial-letter fallback.
///
/// Supports:
/// - Circle or rounded-rect shape
/// - Configurable size (defaults: circle 64, rounded-rect 52)
/// - Optional open/closed status dot (bottom-right)
/// - Smart initial-letter computation (strips "Dr." prefix, uses first + last)
///
/// Usage:
/// ```dart
/// DoctorAvatar.circle(doctor: doctor, size: 68, showStatusDot: true)
/// DoctorAvatar.roundedRect(doctor: doctor, size: 52, borderRadius: 14)
/// ```
class DoctorAvatar extends StatelessWidget {
  final DoctorModel doctor;
  final double size;
  final AvatarShape shape;
  final double borderRadius;
  final bool showStatusDot;

  const DoctorAvatar({
    super.key,
    required this.doctor,
    this.size = 64,
    this.shape = AvatarShape.circle,
    this.borderRadius = 14,
    this.showStatusDot = false,
  });

  /// Convenience constructor for a circle avatar.
  const DoctorAvatar.circle({
    super.key,
    required this.doctor,
    this.size = 64,
    this.showStatusDot = false,
  })  : shape = AvatarShape.circle,
        borderRadius = 14;

  /// Convenience constructor for a rounded-rect avatar.
  const DoctorAvatar.roundedRect({
    super.key,
    required this.doctor,
    this.size = 52,
    this.borderRadius = 14,
    this.showStatusDot = false,
  }) : shape = AvatarShape.roundedRect;

  /// Compute smart initials: strips "Dr." prefix, uses first letter
  /// of first and last name. Falls back to '?' if name is empty.
  String get _initials {
    if (doctor.name.isEmpty) return '?';
    final parts = doctor.name
        .replaceFirst('Dr. ', '')
        .replaceFirst('Dr ', '')
        .trim()
        .split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Determine fallback font size proportionally to the avatar size.
  double get _fallbackFontSize => size * 0.35;

  /// Build the gradient fallback with initials.
  Widget _buildGradientFallback() {
    Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: shape == AvatarShape.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            shape == AvatarShape.roundedRect ? BorderRadius.circular(borderRadius) : null,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.accent],
        ),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: _fallbackFontSize,
          ),
        ),
      ),
    );

    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = doctor.photos.isNotEmpty;
    final photoUrl = hasPhoto
        ? PlacesService().getPhotoUrl(doctor.photos.first, maxWidth: 200)
        : null;

    Widget avatar;
    if (photoUrl != null) {
      // Build the photo with proper clip shape
      Widget photoArea;
      if (shape == AvatarShape.circle) {
        photoArea = Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildGradientFallback(),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return _buildGradientFallback();
            },
          ),
        );
      } else {
        photoArea = ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: SizedBox(
            width: size,
            height: size,
            child: Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _buildGradientFallback(),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return _buildGradientFallback();
              },
            ),
          ),
        );
      }
      avatar = photoArea;
    } else {
      avatar = _buildGradientFallback();
    }

    // Wrap in Stack if a status dot is requested
    if (showStatusDot) {
      return Stack(
        children: [
          avatar,
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: size * 0.24,
              height: size * 0.24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: doctor.isOpen == true ? Colors.green : Colors.grey,
                border: Border.all(
                  color: AppColors.bgCard,
                  width: 2.5,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return avatar;
  }
}
