import 'dart:async';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Position? _currentPosition;
  String? _currentAddress;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;

  /// Check if location services are enabled on the device
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Request location permission. Returns detailed status.
  /// Handles deniedForever by opening app settings on Android/iOS.
  Future<LocationPermissionStatus> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // Open app settings so user can manually grant permission
      await openAppSettings();
      return LocationPermissionStatus.deniedForever;
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionStatus.denied;
    }

    return LocationPermissionStatus.granted;
  }

  /// Get current position with a 10-second timeout to prevent infinite loading.
  /// Resets stale state before fetching fresh location.
  Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      final permissionStatus = await requestPermission();
      if (permissionStatus == LocationPermissionStatus.denied ||
          permissionStatus == LocationPermissionStatus.deniedForever) {
        return null;
      }

      _currentPosition = null;
      _currentAddress = null;

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _currentPosition;
    } on TimeoutException {
      try {
        _currentPosition = await Geolocator.getLastKnownPosition();
        return _currentPosition;
      } catch (_) {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks[0];

        // Build a clean address: Area, City, State
        final area = placemark.subLocality ?? '';
        final city = placemark.locality ?? '';
        final state = placemark.administrativeArea ?? '';
        final address = [area, city, state]
            .where((s) => s.isNotEmpty)
            .join(', ');

        if (address.isNotEmpty) {
          _currentAddress = address;
          return _currentAddress;
        }

        // Fallback: use postalCode + country if nothing else is available
        final postal = placemark.postalCode ?? '';
        final country = placemark.country ?? '';
        final fallback = [postal, country]
            .where((s) => s.isNotEmpty)
            .join(', ');
        if (fallback.isNotEmpty) {
          _currentAddress = fallback;
          return _currentAddress;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Complete location fetch: position + reverse geocode.
  /// Returns a [LocationResult] with detailed success/failure info.
  Future<LocationResult> fetchLocation() async {
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult(
        success: false,
        reason: LocationFailureReason.serviceDisabled,
      );
    }

    final permissionStatus = await requestPermission();
    if (permissionStatus == LocationPermissionStatus.deniedForever) {
      return LocationResult(
        success: false,
        reason: LocationFailureReason.permissionDeniedForever,
      );
    }
    if (permissionStatus == LocationPermissionStatus.denied) {
      return LocationResult(
        success: false,
        reason: LocationFailureReason.permissionDenied,
      );
    }

    _currentPosition = null;
    _currentAddress = null;

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } on TimeoutException {
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    } catch (e) {
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    if (position == null) {
      return LocationResult(
        success: false,
        reason: LocationFailureReason.positionUnavailable,
      );
    }

    _currentPosition = position;

    final address = await getAddressFromLatLng(
      position.latitude,
      position.longitude,
    );
    if (address == null) {
      _currentAddress = AppConstants.defaultLocation;
    }

    return LocationResult(
      success: true,
      position: _currentPosition,
      address: _currentAddress,
    );
  }

  String get displayAddress {
    return _currentAddress ?? AppConstants.defaultLocation;
  }
}

/// Result of a location fetch operation with detailed failure reason.
class LocationResult {
  final bool success;
  final LocationFailureReason? reason;
  final Position? position;
  final String? address;

  LocationResult({
    required this.success,
    this.reason,
    this.position,
    this.address,
  });
}

/// Detailed reasons for location failure.
enum LocationFailureReason {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  positionUnavailable,
  geocodingFailed,
  timeout,
}

/// Permission status wrapper for clarity.
enum LocationPermissionStatus { granted, denied, deniedForever }
