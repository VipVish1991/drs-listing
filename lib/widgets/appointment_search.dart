import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/appointment_model.dart';

/// The search toggle button used in both the doctor's and patient's
/// appointment headers (top-right). Toggles the search field; while
/// searching the glyph switches to a close icon and the tile inverts to
/// white so the open state is obvious on the gradient header.
class AppointmentSearchToggle extends StatelessWidget {
  /// Key for the toggle so widget tests can find it per screen.
  final Key? toggleKey;

  final bool isSearching;

  final VoidCallback onToggle;

  const AppointmentSearchToggle({
    super.key,
    this.toggleKey,
    required this.isSearching,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: toggleKey,
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSearching ? Colors.white : Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isSearching ? Icons.close_rounded : Icons.search_rounded,
          size: 20,
          color: isSearching ? AppColors.primary : Colors.white,
        ),
      ),
    );
  }
}

/// The autofocus search field shown below the header while searching.
/// [hintText] and [onQueryChanged] are screen-specific; the styling is
/// shared so both headers look identical.
class AppointmentSearchField extends StatelessWidget {
  final TextEditingController controller;

  final String hintText;

  final ValueChanged<String> onQueryChanged;

  const AppointmentSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: onQueryChanged,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Colors.white,
          size: 20,
        ),
        filled: true,
        fillColor: Colors.white.withAlpha(22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

/// Filters [appointments] against [query] across every searchable field
/// (doctor name, patient name, phone, date, time, status, symptoms and
/// appointment id). An empty query returns the whole list unchanged.
///
/// Used while the header search is open — results span every date, so the
/// screens' date filter is hidden at the same time.
List<AppointmentModel> filterAppointmentsForSearch(
  List<AppointmentModel> appointments,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return List.of(appointments);
  return appointments.where((a) {
    final haystack = [
      a.doctorName ?? '',
      a.patientName ?? '',
      a.callNumber ?? '',
      a.appointmentDate ?? '',
      a.appointmentTime ?? '',
      a.status,
      a.symptoms ?? '',
      a.appointmentId,
    ].join(' ').toLowerCase();
    return haystack.contains(normalized);
  }).toList();
}
