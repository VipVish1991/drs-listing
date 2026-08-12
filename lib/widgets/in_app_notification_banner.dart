import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

/// A transient, notification-style banner shown INSIDE the app when a push
/// arrives while the app is in the foreground (`FirebaseMessaging.onMessage`
/// — the OS only renders system notifications when the app is backgrounded).
///
/// Slides in from the top edge like a real heads-up notification, auto-
/// dismisses after a few seconds, and tapping it navigates to the relevant
/// screen (the same route the system-notification tap would use).
///
/// Implementation: an [OverlayEntry] over the app's root overlay so it
/// floats above every screen without a route/dependency. The entry's Stack
/// is top-anchored to the card, so pointer events fall through to the app
/// everywhere except on the card itself (no full-screen blocker).
class InAppNotificationBanner {
  InAppNotificationBanner._();

  static final InAppNotificationBanner instance = InAppNotificationBanner._();

  OverlayEntry? _entry;
  Timer? _autoDismiss;

  bool get isShowing => _entry != null;

  /// Show a banner, replacing any banner that is currently visible.
  ///
  /// [type] is the push's `data.type` (e.g. `appointment_booked`,
  /// `appointment_cancelled`, `appointment_status_changed`) and only affects
  /// the leading icon + accent colour. Missing/unknown types fall back to a
  /// neutral bell.
  void show({
    required String title,
    required String body,
    required VoidCallback onTap,
    String type = '',
  }) {
    dismiss();

    // Root overlay via GetX's navigator key (reliable in tests and during
    // route transitions — unlike Get.overlayContext, which can be null right
    // after an offAll). Falls back to overlayContext when the key isn't
    // wired up yet.
    OverlayState? overlay;
    try {
      overlay = Get.key.currentState?.overlay ??
          (Get.overlayContext == null
              ? null
              : Overlay.maybeOf(Get.overlayContext!));
    } catch (_) {
      overlay = null;
    }
    if (overlay == null) return; // app not built yet / tests — no-op

    _entry = OverlayEntry(
      builder: (_) => _BannerView(
        title: title,
        body: body,
        type: type,
        onTap: () {
          dismiss();
          onTap();
        },
        onClose: dismiss,
      ),
    );
    overlay.insert(_entry!);
    _autoDismiss = Timer(const Duration(seconds: 5), dismiss);
  }

  /// Remove the current banner (if any). Safe to call repeatedly.
  void dismiss() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    _entry?.remove();
    _entry = null;
  }
}

/// (Type, icon, accent) mapping for the leading badge.
({IconData icon, Color color}) _badgeFor(String type) {
  switch (type) {
    case 'appointment_booked':
      return (icon: Icons.event_available, color: AppColors.primary);
    case 'appointment_cancelled':
      return (icon: Icons.event_busy, color: AppColors.error);
    case 'appointment_rescheduled':
      return (icon: Icons.event_repeat, color: AppColors.accent);
    case 'appointment_rescheduled_by_doctor':
      return (icon: Icons.event_repeat, color: AppColors.accent);
    case 'appointment_status_changed':
      return (icon: Icons.check_circle, color: AppColors.success);
    default:
      return (icon: Icons.notifications, color: AppColors.primary);
  }
}

class _BannerView extends StatefulWidget {
  const _BannerView({
    required this.title,
    required this.body,
    required this.type,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final String body;
  final String type;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badgeFor(widget.type);
    // Only the card occupies this overlay entry (top-anchored Stack), so
    // taps anywhere else fall through to the app underneath.
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _slide.value;
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -90 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Material(
                  color: AppColors.bgCard,
                  elevation: 8,
                  shadowColor: Colors.black.withAlpha(45),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: badge.color.withAlpha(26),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(badge.icon, color: badge.color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textHeading,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (widget.body.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textBody,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: widget.onClose,
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.textCaption,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
