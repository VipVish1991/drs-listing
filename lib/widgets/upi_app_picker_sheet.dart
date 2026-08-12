import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:upi_india/upi_india.dart';

import '../config/theme.dart';

/// Bottom sheet listing the installed UPI apps so the patient can pick which
/// one to pay with.
///
/// Shows EVERY installed UPI app the device reports (each with its real app
/// icon) in a scrollable list so a phone with many UPI apps never overflows
/// the sheet.
class UpiAppPickerSheet extends StatelessWidget {
  const UpiAppPickerSheet({
    super.key,
    required this.apps,
    this.payeeUpiId,
    this.payeeName,
  });

  /// The discovered UPI apps to offer (usually from
  /// `UpiPaymentService.getInstalledUpiApps`).
  final List<UpiApp> apps;

  /// The UPI VPA the payment will be sent to, shown in the header so the
  /// patient can verify they're paying the right account.
  final String? payeeUpiId;

  /// The doctor/clinic name receiving the payment.
  final String? payeeName;

  /// Shows the picker as a modal bottom sheet and resolves with the chosen
  /// app, or null when dismissed.
  static Future<UpiApp?> show(
    BuildContext context,
    List<UpiApp> apps, {
    String? payeeUpiId,
    String? payeeName,
  }) {
    return Get.bottomSheet<UpiApp>(
      UpiAppPickerSheet(
        apps: apps,
        payeeUpiId: payeeUpiId,
        payeeName: payeeName,
      ),
      isScrollControlled: true,
    );
  }

  /// The app's real icon, or a generic UPI placeholder when the platform
  /// icon isn't available.
  ///
  /// `UpiApp.icon` only carries bytes when the app was built by the
  /// platform (via `fromMap` or the native fallback); test-constructed
  /// apps never assign it, so the placeholder keeps the picker usable on
  /// every platform.
  Widget _appIcon(UpiApp app) {
    try {
      return Image.memory(
        app.icon,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
      );
    } catch (_) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.currency_rupee_rounded,
          color: AppColors.primary,
          size: 21,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF1C1C30)
        : const Color(0xFFF7F8FA);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pay with',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHeading,
                  ),
                ),
              ),
              // How many UPI apps were found on this device.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${apps.length} ${apps.length == 1 ? 'app' : 'apps'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          // Show the payee UPI ID so the patient can verify the
          // recipient before choosing an app.
          if (payeeUpiId != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    payeeName != null
                        ? '$payeeName ($payeeUpiId)'
                        : payeeUpiId!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Scrollable app list — every installed UPI app fits on screen.
          // Flexible (not a fixed cap) so the sheet can never overflow on
          // short/landscape viewports: the list scrolls only when needed.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: apps
                    .map(
                      (app) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PaymentMethodTile(
                          leading: _appIcon(app),
                          title: app.name,
                          subtitle: 'Pay with ${app.name}',
                          color: AppColors.primary,
                          onTap: () => Get.back(result: app),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Get.back(result: null),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable payment row used by the UPI app picker and the Online/Offline
/// payment-method sheet.
class PaymentMethodTile extends StatelessWidget {
  final IconData? icon;

  /// Optional custom leading widget (e.g. the UPI app's real icon image)
  /// rendered in place of the icon box.
  final Widget? leading;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const PaymentMethodTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  }) : assert(icon != null || leading != null,
            'either icon or leading must be provided');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(45), width: 1.2),
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withAlpha(14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon ?? Icons.currency_rupee_rounded,
                    color: color,
                    size: 21,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHeading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textCaption,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withAlpha(160)),
            ],
          ),
        ),
      ),
    );
  }
}
