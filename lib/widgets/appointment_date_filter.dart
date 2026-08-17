import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../models/appointment_model.dart';

/// Reusable date filter used by both the doctor's appointments screen and
/// the patient's appointment history screen.
///
/// Shows a compact date icon card by default. Tapping the calendar icon
/// expands a full monthly calendar grid with appointment-count badges,
/// month navigation, and a "Today" jump button — identical behaviour to
/// the doctor's dashboard date picker.
class AppointmentDateFilter extends StatefulWidget {
  /// All appointments used to compute the per-day count badges.
  final List<AppointmentModel> appointments;

  /// Currently selected date (yyyy-MM-dd).
  final String selectedDate;

  /// Called with the newly selected date (yyyy-MM-dd).
  final ValueChanged<String> onDateSelected;

  const AppointmentDateFilter({
    super.key,
    required this.appointments,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<AppointmentDateFilter> createState() => _AppointmentDateFilterState();
}

class _AppointmentDateFilterState extends State<AppointmentDateFilter> {
  /// Whether the full calendar grid is expanded.
  bool _showCalendar = false;

  /// Page controller for the horizontal month calendar.
  late final PageController _monthPageController;

  /// Start month index (0 = January of the current year).
  late final int _startMonthIndex;

  /// Currently focused month index (absolute from epoch).
  int _currentMonthIndex = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startMonthIndex = _monthIndex(now.year, now.month);
    _currentMonthIndex = _startMonthIndex;
    _monthPageController = PageController(initialPage: 12); // center page
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    super.dispose();
  }

  /// Whether the calendar is showing the current month.
  bool get _isOnCurrentMonth => _currentMonthIndex == _startMonthIndex;

  String _formatDateKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _getMonthName(int month) {
    return [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1];
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// Number of appointments on [dateKey].
  int _appointmentCountForDate(String dateKey) =>
      widget.appointments.where((a) => a.appointmentDate == dateKey).length;

  /// Convert a month and year to an absolute month index (months since
  /// epoch). 0-based month arithmetic: January is `year * 12 + 0`, so the
  /// inverse functions [_yearFromIndex]/[_monthFromIndex] round-trip
  /// correctly (a 1-based `+ month` here made the calendar always show the
  /// NEXT month).
  int _monthIndex(int year, int month) => year * 12 + (month - 1);

  /// Convert an absolute month index back to year (0-based).
  int _yearFromIndex(int index) => (index / 12).floor();

  /// Convert an absolute month index back to month (1-based).
  int _monthFromIndex(int index) => index % 12 + 1;

  /// Number of days in a given month.
  int _daysInMonth(int year, int month) {
    if (month == 12) {
      return DateTime(year + 1, 1, 0).day;
    }
    return DateTime(year, month + 1, 0).day;
  }

  /// Build a grid of day numbers for a given month.
  /// Returns a list of rows (each row is a list of 7 day values, 0 = empty).
  List<List<int>> _buildMonthGrid(int year, int month) {
    final days = _daysInMonth(year, month);
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon ... 7=Sun
    // Convert to Sunday-based: 0=Sun, 1=Mon, ..., 6=Sat
    final startOffset = firstWeekday % 7;

    final List<List<int>> grid = [];
    List<int> currentRow = List.filled(7, 0);
    int col = startOffset;

    for (int day = 1; day <= days; day++) {
      if (col == 7) {
        grid.add(currentRow);
        currentRow = List.filled(7, 0);
        col = 0;
      }
      currentRow[col] = day;
      col++;
    }
    if (currentRow.any((d) => d != 0)) {
      grid.add(currentRow);
    }
    return grid;
  }

  /// Jump the calendar back to the current month and select today's date.
  void _jumpToToday() {
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    setState(() {
      widget.onDateSelected(todayKey);
      _currentMonthIndex = _startMonthIndex;
      _showCalendar = false;
    });

    // Animate the PageView back to the center page (current month)
    _monthPageController.animateToPage(
      12, // center offset page
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _showCalendar
            ? _buildCalendarExpanded()
            : _buildCalendarCompact(),
      ),
    );
  }

  /// Compact date icon — default view. Shows selected date info
  /// and a calendar icon to expand the full calendar.
  Widget _buildCalendarCompact() {
    final selectedDate = DateTime.parse(widget.selectedDate);
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayName = dayNames[selectedDate.weekday - 1];
    final monthName = _getMonthName(selectedDate.month);
    final apptCount = _appointmentCountForDate(widget.selectedDate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          // Date icon — large day number + month
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(50),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // FittedBox scales the day + month down as a unit when the
            // system text scale grows — otherwise the fixed 52×52 box
            // overflows at large accessibility text sizes.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${selectedDate.day}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    monthName.substring(0, 3),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withAlpha(200),
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Date info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FittedBox scales the date title + Today badge down as a
                // unit on narrow screens instead of overflowing (or hiding
                // text with an ellipsis).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$dayName, $monthName ${selectedDate.day}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textHeading,
                        ),
                      ),
                      if (_isToday(selectedDate))
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 12,
                      color: AppColors.textCaption,
                    ),
                    const SizedBox(width: 4),
                    // Flexible + ellipsis: the AnimatedSize collapse
                    // animation lays the header out at shrinking widths —
                    // without this the count text overflows horizontally.
                    Flexible(
                      child: Text(
                        apptCount > 0
                            ? '$apptCount appointment${apptCount == 1 ? '' : 's'}'
                            : 'No appointments',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: apptCount > 0
                              ? AppColors.primary
                              : AppColors.textCaption,
                          fontWeight: apptCount > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Calendar toggle button
          GestureDetector(
            onTap: () => setState(() => _showCalendar = !_showCalendar),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 300),
                turns: _showCalendar ? 0.5 : 0,
                child: const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Expanded full monthly calendar grid with navigation.
  Widget _buildCalendarExpanded() {
    final totalMonths = 24;
    final centerOffset = 12;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month navigation header
          Obx(() {
            final year = _yearFromIndex(_currentMonthIndex);
            final month = _monthFromIndex(_currentMonthIndex);
            final monthName = _getMonthName(month);

            final apptsThisMonth = widget.appointments.where((a) {
              final ad = a.appointmentDate ?? '';
              return ad.startsWith('$year-${month.toString().padLeft(2, '0')}');
            }).length;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$monthName $year',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textHeading,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (apptsThisMonth > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$apptsThisMonth appts',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    if (!_isOnCurrentMonth)
                      GestureDetector(
                        onTap: _jumpToToday,
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.primary.withAlpha(60),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.today_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Today',
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
                    // Previous month
                    GestureDetector(
                      onTap: _currentMonthIndex > _startMonthIndex - 12
                          ? () => _monthPageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            )
                          : null,
                      child: _NavArrow(
                        icon: Icons.chevron_left_rounded,
                        enabled: _currentMonthIndex > _startMonthIndex - 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Next month
                    GestureDetector(
                      onTap: _currentMonthIndex < _startMonthIndex + 11
                          ? () => _monthPageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            )
                          : null,
                      child: _NavArrow(
                        icon: Icons.chevron_right_rounded,
                        enabled: _currentMonthIndex < _startMonthIndex + 11,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
          const SizedBox(height: 14),

          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((
              day,
            ) {
              return SizedBox(
                width: 36,
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textCaption,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),

          // Month grid
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: _monthPageController,
              scrollDirection: Axis.horizontal,
              onPageChanged: (page) {
                setState(() {
                  _currentMonthIndex = _startMonthIndex + (page - centerOffset);
                });
              },
              itemCount: totalMonths,
              itemBuilder: (context, pageIndex) {
                final monthIdx = _startMonthIndex + (pageIndex - centerOffset);
                final year = _yearFromIndex(monthIdx);
                final month = _monthFromIndex(monthIdx);
                final grid = _buildMonthGrid(year, month);

                return SingleChildScrollView(
                  child: Column(
                    children: grid.map((week) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: week.asMap().entries.map((entry) {
                            final day = entry.value;
                            if (day == 0) {
                              return const SizedBox(width: 36, height: 36);
                            }

                            final date = DateTime(year, month, day);
                            final dateKey = _formatDateKey(date);
                            final isSelected = dateKey == widget.selectedDate;
                            final isToday = _isToday(date);
                            final apptCount = _appointmentCountForDate(dateKey);

                            return GestureDetector(
                              onTap: () => setState(() {
                                widget.onDateSelected(dateKey);
                                _showCalendar = false;
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : isToday
                                      ? AppColors.primary.withAlpha(15)
                                      : null,
                                  shape: BoxShape.circle,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Text(
                                      '$day',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected || isToday
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : isToday
                                            ? AppColors.primary
                                            : AppColors.textHeading,
                                      ),
                                    ),
                                    if (apptCount > 0 && !isSelected)
                                      Positioned(
                                        top: -1,
                                        right: -1,
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minWidth: 16,
                                          ),
                                          height: 16,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withAlpha(
                                              220,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.error
                                                    .withAlpha(80),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              apptCount > 9
                                                  ? '9+'
                                                  : '$apptCount',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (apptCount > 0 && isSelected)
                                      Positioned(
                                        bottom: -1,
                                        right: -1,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          height: 13,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(200),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              apptCount > 9
                                                  ? '9+'
                                                  : '$apptCount',
                                              style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable navigation arrow button for month switching.
class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;

  const _NavArrow({required this.icon, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.bgSecondarySurface
            : AppColors.textDisabled.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 20,
        color: enabled ? AppColors.textBody : AppColors.textDisabled,
      ),
    );
  }
}
