import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/theme.dart';

class NurseAvatar extends StatefulWidget {
  final double size;
  final bool isListening;
  final bool isProcessing;

  const NurseAvatar({
    super.key,
    this.size = 120,
    this.isListening = false,
    this.isProcessing = false,
  });

  @override
  State<NurseAvatar> createState() => _NurseAvatarState();
}

class _NurseAvatarState extends State<NurseAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size + 40,
      height: widget.size + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          if (widget.isListening || widget.isProcessing)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: widget.size + 40 + (_pulseController.value * 20),
                  height: widget.size + 40 + (_pulseController.value * 20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        if (widget.isListening)
                          AppColors.primary.withAlpha(100)
                        else
                          AppColors.secondary.withAlpha(100),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),

          // Main circle — uses the app icon image
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(80),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.size / 2),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B8A6F), Color(0xFF076B55)],
                  ),
                ),
                child: Icon(
                  Icons.health_and_safety,
                  color: Colors.white,
                  size: widget.size * 0.5,
                ),
              ),
            ),
          ),

          // Listening/Processing indicator badge (positioned at the
          // bottom edge of the circle). The outer SizedBox is 40 px
          // taller than the circle, so bottom: 28 = 20 (centering) + 8.
          if (widget.isListening || widget.isProcessing)
            Positioned(
              bottom: 28,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.isListening ? '🎤' : '🤔',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).scale(
          begin: const Offset(0.8, 0.8),
          end: const Offset(1.0, 1.0),
          duration: 600.ms,
          curve: Curves.elasticOut,
        );
  }

}
