import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';

class VoiceButton extends StatefulWidget {
  final bool isListening;
  final bool isProcessing;
  final VoidCallback onPressed;
  final VoidCallback? onStopPressed;
  final double size;

  const VoiceButton({
    super.key,
    required this.isListening,
    required this.isProcessing,
    required this.onPressed,
    this.onStopPressed,
    this.size = 72,
  });

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  // Wave bars parameters
  static const int _waveCount = 5;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isListening) {
      _animController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _animController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _animController.stop();
      _animController.reset();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isListening ? widget.onStopPressed : widget.onPressed,
      child: SizedBox(
        width: widget.size + 40,
        height: widget.size + 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Sound wave bars ──
            if (widget.isListening)
              ...List.generate(_waveCount, (index) {
                return AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    final phase = (index / _waveCount) * math.pi * 2;
                    final waveValue = math.sin(
                      _animController.value * math.pi * 2 + phase,
                    );
                    // Scale between 0.6 and 1.4
                    final scale = 0.6 + ((waveValue + 1) / 2) * 0.8;
                    final opacity = 0.3 + ((waveValue + 1) / 2) * 0.4;

                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: widget.size + 20,
                        height: widget.size + 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withAlpha(
                              (opacity * 80).round(),
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),

            // ── Expanding ripple ring (outer) ──
            if (widget.isListening)
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_animController.value * 0.4),
                    child: Opacity(
                      opacity: (1.0 - _animController.value) * 0.3,
                      child: Container(
                        width: widget.size + 20,
                        height: widget.size + 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withAlpha(30),
                        ),
                      ),
                    ),
                  );
                },
              ),

            // ── Main circle button ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: widget.isListening
                    ? const LinearGradient(
                        colors: [Color(0xFFFF7D7D), Color(0xFFF3B6D5)],
                      )
                    : widget.isProcessing
                        ? const LinearGradient(
                            colors: [Color(0xFFAFC6F8), Color(0xFFD4A5F5)],
                          )
                        : const LinearGradient(
                            colors: [AppColors.primary, Color(0xFFAFC6F8)],
                          ),
                boxShadow: [
                  BoxShadow(
                    color: (widget.isListening
                            ? const Color(0xFFFF7D7D)
                            : AppColors.primary)
                        .withAlpha((0.4 * 255).round()),
                    blurRadius: widget.isListening ? 25 : 15,
                    spreadRadius: widget.isListening ? 5 : 0,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Inner ripple (during listening)
                  if (widget.isListening)
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 1.0 + (_animController.value * 0.3),
                          child: Opacity(
                            opacity:
                                (1.0 - _animController.value).clamp(0.0, 0.25),
                            child: Container(
                              width: widget.size,
                              height: widget.size,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF7D7D),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  // Icon
                  Icon(
                    widget.isListening
                        ? Icons.mic
                        : widget.isProcessing
                            ? Icons.hourglass_top
                            : Icons.mic_none,
                    color: Colors.white,
                    size: widget.size * 0.4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
