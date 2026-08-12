import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/home_controller.dart';
import 'home/home_screen.dart';
import 'appointment/appointment_history_screen.dart';
import 'profile/saved_doctors_screen.dart';
import 'profile/profile_screen.dart';

/// Main shell with custom bottom navigation bar.
/// Tab 0: HomeScreen
/// Tab 1: AppointmentHistoryScreen
/// Tab 2: SavedDoctorsScreen
/// Tab 3: ProfileScreen
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  DateTime? _lastBackPress;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // The location/GPS/mic permission prompts belong to the PATIENT side:
    // the HomeController (home screen location fetch, GPS-off popup,
    // top-doctors section) is created here — when a patient actually opens
    // their dashboard — instead of globally in main(). The doctor dashboard
    // never creates it, so a doctor is never asked for location permission.
    //
    // NOTE for tests: any test pumping MainShell MUST pre-register its own
    // (test) HomeController — otherwise this creates the REAL controller,
    // whose onInit starts a 60s periodic location timer that fails the test
    // with a pending-timer assertion at teardown.
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }

    _screens = [
      HomeScreen(),
      const AppointmentHistoryScreen(),
      const SavedDoctorsScreen(),
      ProfileScreen(),
    ];
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_currentIndex != 0) {
          _onTabTapped(0);
        } else {
          // Double back-press to exit on the home tab
          final now = DateTime.now();
          if (_lastBackPress != null &&
              now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
            SystemNavigator.pop();
          } else {
            _lastBackPress = now;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Press back again to exit'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bgMain,
        body: _screens[_currentIndex],
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Soft white nav to sit cleanly under the pink Talk-with-bot home screen
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    // All tabs use the same teal-green primary color when selected
    final selectedColor = AppColors.primary;
    final unselectedColor = AppColors.textCaption;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                isSelected: _currentIndex == 0,
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                onTap: () => _onTabTapped(0),
              ),
              _NavItem(
                icon: Icons.calendar_month_rounded,
                label: 'Appointments',
                isSelected: _currentIndex == 1,
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                onTap: () => _onTabTapped(1),
              ),
              _NavItem(
                icon: Icons.favorite_rounded,
                label: 'Saved',
                isSelected: _currentIndex == 2,
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                onTap: () => _onTabTapped(2),
              ),
              _NavItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                isSelected: _currentIndex == 3,
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                onTap: () => _onTabTapped(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor.withAlpha(15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? selectedColor : unselectedColor,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? selectedColor : unselectedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
