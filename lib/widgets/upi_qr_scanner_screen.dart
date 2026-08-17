import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera scanner for the patient's UPI QR code (refund flow).
///
/// Pops with the RAW scanned text (`Navigator.pop(context, raw)`), which
/// the caller parses with [extractVpaFromQr]. Pops with null when the
/// doctor backs out without a scan.
class UpiQrScannerScreen extends StatefulWidget {
  const UpiQrScannerScreen({super.key});

  @override
  State<UpiQrScannerScreen> createState() => _UpiQrScannerScreenState();
}

class _UpiQrScannerScreenState extends State<UpiQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // Only UPI QR codes are expected — no need to scan other barcode
    // types (and restricting the formats speeds up detection).
    formats: const [BarcodeFormat.qrCode],
  );

  /// Guards against double-detection (the detector can fire several
  /// frames for the same code while the pop is in flight).
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _handled = true;
    _controller.stop();
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Dark vignette so the scan frame stands out on the live feed.
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.15,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(150),
                  ],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
          ),
          // ── Scan frame + instructions ──
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Point at the patient\'s UPI QR code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The UPI ID will be filled in automatically',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          // ── Top bar: close + torch ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _RoundIconBtn(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _RoundIconBtn(
                    icon: Icons.flashlight_on_rounded,
                    onTap: () => _controller.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(120),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
