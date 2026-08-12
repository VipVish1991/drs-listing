import 'dart:async';

import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Full-width primary button used for confirmation steps (e.g. the
/// nearby-clinic "Confirm & Continue" dialog). When tapped it swaps its
/// arrow icon for a small loading spinner and disables itself, giving
/// immediate visual feedback that the tap was registered.
///
/// The spinner stays visible until [onPressed] completes — so real async
/// work (e.g. an OTP verification call) drives its duration — and for at
/// least [minimumSpinnerDuration] so the loading state is perceptible
/// even when the action is synchronous and fast.
class ConfirmContinueButton extends StatefulWidget {
  const ConfirmContinueButton({
    super.key,
    required this.onPressed,
    this.label = 'Confirm & Continue',
    this.loadingLabel = 'Confirming…',
    this.minimumSpinnerDuration = const Duration(milliseconds: 200),
  });

  /// May return a [Future] — the spinner is held until it completes.
  final FutureOr<void> Function() onPressed;
  final String label;
  final String loadingLabel;
  final Duration minimumSpinnerDuration;

  @override
  State<ConfirmContinueButton> createState() => _ConfirmContinueButtonState();
}

class _ConfirmContinueButtonState extends State<ConfirmContinueButton> {
  bool _isLoading = false;

  Future<void> _handleTap() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final stopwatch = Stopwatch()..start();
    try {
      // Real work drives the spinner: hold until onPressed resolves.
      await widget.onPressed();
    } finally {
      // Keep the spinner up for at least the minimum so a fast action
      // is still perceptible, then restore the idle label.
      final remaining = widget.minimumSpinnerDuration - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _handleTap,
        icon: _isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.arrow_forward_rounded, size: 20),
        label: Text(
          _isLoading ? widget.loadingLabel : widget.label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          // Keep the primary green while loading so the white spinner pops.
          disabledBackgroundColor: AppColors.primary,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
