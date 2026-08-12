import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/doctor_model.dart';

/// Determine the display type of a [place] based on its Google Places
/// `types` list.
///
/// Returns one of `'Doctor'`, `'Hospital'`, `'Pharmacy'`, `'Physio'`, or
/// defaults to `'Clinic'`.
String getPlaceType(DoctorModel place) {
  final types = place.types.map((t) => t.toLowerCase()).toSet();

  if (types.contains('doctor')) return 'Doctor';
  if (types.contains('hospital')) return 'Hospital';
  if (types.contains('pharmacy') || types.contains('pharmacy_and_health')) {
    return 'Pharmacy';
  }
  if (types.contains('physiotherapist') || types.contains('health_services')) {
    return 'Physio';
  }
  if (types.contains('medical_clinic')) return 'Clinic';
  return 'Clinic';
}

/// Return the theme colour associated with a given place [type] string
/// returned by [getPlaceType].
Color getPlaceTypeColor(String type) {
  if (type == 'Doctor') return AppColors.primary;
  if (type == 'Hospital') return AppColors.healthHeart;
  if (type == 'Pharmacy') return AppColors.healthBrain;
  return AppColors.accent;
}

/// Return the Flutter icon for a place [type] string (as returned by
/// [getPlaceType]), used in filter chips and badges.
IconData placeTypeIcon(String type) {
  switch (type) {
    case 'Doctor':
      return Icons.person_rounded;
    case 'Hospital':
      return Icons.local_hospital_rounded;
    case 'Pharmacy':
      return Icons.medication_rounded;
    case 'Physio':
      return Icons.accessibility_new_rounded;
    default:
      return Icons.medical_services_rounded;
  }
}
