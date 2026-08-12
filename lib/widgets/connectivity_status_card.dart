import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../services/network_settings_service.dart';
import '../services/wifi_status_service.dart';

/// Home-screen card that appears while the app is offline and shows the
/// current connectivity status: the Wi‑Fi network name the device is
/// connected to and its signal strength (as bars + x/4), with fallbacks
/// for "Wi‑Fi is off" / "not connected" / location-denied states.
///
/// Visibility is driven by [ConnectivityService.online] (the same state
/// that drives the app-wide offline banner), so the card shows and hides
/// with the connection with no extra plumbing. The Wi‑Fi details are
/// re-read when the card becomes visible, then refreshed on a short
/// periodic timer ([autoRefresh]) and on the refresh button — signal
/// strength drifts as you move, so the card stays current.
class ConnectivityStatusCard extends StatefulWidget {
  const ConnectivityStatusCard({
    super.key,
    this.fetchStatus,
    this.autoRefresh = true,
  });

  /// Injectable status fetcher — defaults to
  /// [WifiStatusService.getWifiStatus]. Tests pass a fake so the card can
  /// be exercised without the platform channel.
  final Future<WifiStatus?> Function()? fetchStatus;

  /// When true, the Wi‑Fi details refresh on a short periodic timer while
  /// the card is visible (signal strength changes as the user moves).
  final bool autoRefresh;

  @override
  State<ConnectivityStatusCard> createState() =>
      _ConnectivityStatusCardState();
}

class _ConnectivityStatusCardState extends State<ConnectivityStatusCard> {
  static const Duration _refreshInterval = Duration(seconds: 10);

  WifiStatus? _status;
  bool _loading = false;
  Timer? _refreshTimer;

  Future<WifiStatus?> Function() get _fetcher =>
      widget.fetchStatus ?? WifiStatusService.instance.getWifiStatus;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.online.addListener(_onConnectivityChanged);
    // The card may open already offline — fetch the Wi-Fi details right
    // after the first frame (post-frame keeps setState out of initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ConnectivityService.instance.online.value) {
        _startAutoRefresh();
        _refreshStatus();
      }
    });
  }

  @override
  void dispose() {
    ConnectivityService.instance.online.removeListener(_onConnectivityChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (ConnectivityService.instance.online.value) {
      _stopAutoRefresh();
    } else {
      _startAutoRefresh();
      _refreshStatus();
    }
    if (mounted) setState(() {});
  }

  void _startAutoRefresh() {
    if (!widget.autoRefresh || _refreshTimer != null) return;
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshStatus());
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _refreshStatus() async {
    if (_loading) return;
    setState(() => _loading = true);
    WifiStatus? status;
    try {
      status = await _fetcher();
    } catch (_) {
      // Fetcher failed — keep the last known status (or the generic
      // offline message when there was none).
      status = _status;
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final online = ConnectivityService.instance.online.value;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: online
          ? const SizedBox.shrink(key: ValueKey('connectivity_online'))
          : Padding(
              key: const ValueKey('connectivity_offline'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _buildCard(context),
            ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final status = _status;

    var detail = _loading
        ? 'Checking your connection…'
        : 'Check your network connection';
    String? hint;
    int? level;

    if (status != null) {
      if (!status.wifiEnabled) {
        detail = 'Wi-Fi is turned off';
        hint = 'Turn on Wi-Fi or enable mobile data to reconnect.';
      } else if (!status.connected) {
        detail = 'Not connected to any Wi-Fi network';
        hint = 'Connect to a network or enable mobile data.';
      } else if (status.hasSsid) {
        detail = 'Connected to ${status.ssid}';
        hint = 'No internet on this network — check the router or '
            'switch to another network.';
        level = status.safeSignalLevel;
      } else if (!status.locationGranted) {
        detail = 'Connected to Wi-Fi (name hidden)';
        hint = 'Grant location access to see the network name and signal.';
      } else {
        detail = 'Connected to Wi-Fi';
        hint = 'No internet on this network — check the router.';
        level = status.safeSignalLevel;
      }
    }

    return Container(
      key: const Key('connectivity_status_card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF20242B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Wi-Fi-off badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orangeAccent.withAlpha(26),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 18,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'You\'re offline',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withAlpha(215),
                        height: 1.3,
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withAlpha(140),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (level != null) ...[
                const SizedBox(width: 10),
                _SignalBars(level: level),
                const SizedBox(width: 6),
                Text(
                  '$level/4',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withAlpha(110),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              // Manual refresh — signal strength changes as you move.
              IconButton(
                onPressed: _loading ? null : _refreshStatus,
                iconSize: 18,
                color: Colors.white.withAlpha(160),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          // Quick jump to the Wi-Fi settings — mirrors the offline
          // banner's "Settings" action.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: NetworkSettingsService.openWifiSettings,
              style: TextButton.styleFrom(
                foregroundColor: Colors.orangeAccent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(Icons.settings_rounded, size: 14),
              label: const Text('Wi-Fi settings', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four signal-strength bars (like the system Wi-Fi icon), with [level]
/// (0..4) bars filled in. Taller bars at higher indexes, so the shape
/// reads like a real signal indicator.
class _SignalBars extends StatelessWidget {
  final int level;

  const _SignalBars({required this.level});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final filled = i < level;
        return Container(
          width: 5,
          height: 7.0 + (i * 4),
          margin: EdgeInsets.only(left: i == 0 ? 0 : 2.5),
          decoration: BoxDecoration(
            color: filled ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
