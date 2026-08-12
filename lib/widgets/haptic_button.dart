import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A wrapper that adds haptic feedback + subtle scale-down animation to any
/// tappable widget.
///
/// The child scales down to [scaleEnd] (default 0.93) on press-down and
/// springs back on release / cancel.  [HapticFeedback.lightImpact] fires on
/// the [onTap] callback.
///
/// When [onTap] is null the widget renders inert (no gesture, no animation).
class HapticButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleEnd;
  final Duration animationDuration;
  final Duration hapticDelay;
  final HapticFeedbackType hapticType;

  const HapticButton({
    super.key,
    required this.child,
    this.onTap,
    this.scaleEnd = 0.93,
    this.animationDuration = const Duration(milliseconds: 120),
    this.hapticDelay = const Duration(milliseconds: 8),
    this.hapticType = HapticFeedbackType.lightImpact,
  });

  @override
  State<HapticButton> createState() => _HapticButtonState();
}

class _HapticButtonState extends State<HapticButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _anim = Tween<double>(begin: 1.0, end: widget.scaleEnd).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    _ctrl.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onTap == null) return;
    _ctrl.reverse();
  }

  void _onTapCancel() {
    if (widget.onTap == null) return;
    _ctrl.reverse();
  }

  void _onTap() {
    if (widget.onTap == null) return;
    // Fire haptic after a brief delay so the user feels it right as the
    // action begins.
    Future.delayed(widget.hapticDelay, () {
      switch (widget.hapticType) {
        case HapticFeedbackType.lightImpact:
          HapticFeedback.lightImpact();
        case HapticFeedbackType.mediumImpact:
          HapticFeedback.mediumImpact();
        case HapticFeedbackType.heavyImpact:
          HapticFeedback.heavyImpact();
        case HapticFeedbackType.selectionClick:
          HapticFeedback.selectionClick();
      }
    });
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => Transform.scale(
          scale: _anim.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// The type of haptic feedback to fire on tap.
enum HapticFeedbackType {
  /// A short, light tap (default).
  lightImpact,

  /// A medium-strength tap.
  mediumImpact,

  /// A heavy thud.
  heavyImpact,

  /// A click feeling, good for selection changes.
  selectionClick,
}
