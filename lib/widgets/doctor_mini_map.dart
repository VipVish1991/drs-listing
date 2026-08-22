import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/doctor_model.dart';
import '../services/launch_service.dart';

/// An interactive mini-map showing the doctor's location with a marker.
///
/// Tapping the map opens the device's default maps app for directions.
class DoctorMiniMap extends StatefulWidget {
  final DoctorModel doctor;

  const DoctorMiniMap({super.key, required this.doctor});

  @override
  State<DoctorMiniMap> createState() => _DoctorMiniMapState();
}

class _DoctorMiniMapState extends State<DoctorMiniMap> {
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  LatLng? get _location {
    if (widget.doctor.latitude == null || widget.doctor.longitude == null) {
      return null;
    }
    return LatLng(widget.doctor.latitude!, widget.doctor.longitude!);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _openDirections() {
    LaunchService.map(widget.doctor.latitude, widget.doctor.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;

    if (location == null) {
      return const SizedBox.shrink();
    }

    final marker = Marker(
      markerId: const MarkerId('doctor_location'),
      position: location,
      infoWindow: InfoWindow(
        title: widget.doctor.name,
        snippet: widget.doctor.address ?? '',
      ),
    );

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: location,
              zoom: AppConstants.mapDefaultZoom,
            ),
            markers: {marker},
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            scrollGesturesEnabled: false,
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
            zoomGesturesEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            mapType: MapType.normal,
            padding: EdgeInsets.zero,
          ),
          // Tap overlay to open directions
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openDirections,
                borderRadius: BorderRadius.circular(16),
                child: Container(),
              ),
            ),
          ),
          // "Open in Maps" badge at bottom
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(30),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.directions,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Directions',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
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

