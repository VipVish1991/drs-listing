import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/constants.dart';
import '../config/theme.dart';

/// Shows a bottom sheet for selecting the search radius (5 / 10 / 20 / 30 / 50 km).
///
/// Calls [onSelected] with the chosen km value when the user taps an option.
/// The [currentKm] value is highlighted as the active selection.
void showSearchRadiusSheet({
  required RxInt currentKm,
  required VoidCallback onSelected,
}) {
  Get.bottomSheet(
    Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.info.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.radar, color: AppColors.info, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Search Radius',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textHeading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Set how far to search for doctors near you.',
            style: TextStyle(fontSize: 14, color: AppColors.textBody),
          ),
          const SizedBox(height: 24),
          ...AppConstants.searchRadiusOptions.map((km) {
            final isSelected = km == currentKm.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    currentKm.value = km;
                    onSelected();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withAlpha(15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary.withAlpha(60)
                            : AppColors.textDisabled.withAlpha(40),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withAlpha(25)
                                : AppColors.bgSecondarySurface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            km <= 10
                                ? Icons.directions_walk
                                : km <= 20
                                    ? Icons.directions_bike
                                    : Icons.directions_car,
                            size: 18,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textCaption,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$km km',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textHeading,
                                ),
                              ),
                              Text(
                                _radiusLabel(km),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textBody,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check,
                                size: 14, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => Get.back(),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textCaption,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _radiusLabel(int km) {
  return switch (km) {
    5 => 'Nearby — walking distance',
    10 => 'Local area — quick drive',
    20 => 'City-wide coverage',
    30 => 'District-wide coverage',
    50 => 'Metro area',
    _ => '$km km radius',
  };
}
