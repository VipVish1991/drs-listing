import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/doctor_controller.dart';
import '../../controllers/notification_center_controller.dart';
import '../../models/payment_model.dart';
import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../profile/payment_history_screen.dart';
import 'doctor_dashboard_screen.dart';
import 'doctor_appointments_screen.dart';
import 'doctor_availability_screen.dart';
import 'doctor_profile_screen.dart';

/// Doctor-specific shell with custom bottom navigation bar.
/// Tab 0: Dashboard (Home)
/// Tab 1: Appointments
/// Tab 2: Slots
/// Tab 3: Payment History
/// Tab 4: Profile
class DoctorMainShell extends StatefulWidget {
  const DoctorMainShell({super.key});

  /// Appointments tab index — the doctor's booking-management surface that
  /// pushed screens (e.g. the Payment History empty state) jump back to.
  static const int appointmentsTab = 1;

  /// Switches the ACTIVE shell instance's tab from outside the shell (e.g.
  /// the doctor payment history's empty-state CTA pops back to the
  /// already-open shell and selects its Appointments tab). No-op when no
  /// shell is currently mounted.
  static void switchToTab(int index) {
    _DoctorMainShellState._active?._onTabTapped(index);
  }

  /// Observability hook for tests: the selected tab of the mounted shell,
  /// or -1 when none is mounted.
  static int get activeTabIndex => _DoctorMainShellState._active?._currentIndex ?? -1;

  @override
  State<DoctorMainShell> createState() => _DoctorMainShellState();
}

class _DoctorMainShellState extends State<DoctorMainShell>
    with WidgetsBindingObserver {
  /// The single mounted instance. Only one doctor shell exists at a time
  /// (login flows replace the stack rather than stack shells), so a static
  /// handle is unambiguous — it lets [DoctorMainShell.switchToTab] drive
  /// the shell from a pushed screen (Payment History's empty state).
  static _DoctorMainShellState? _active;

  int _currentIndex = 0;
  DateTime? _lastBackPress;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _active = this;
    WidgetsBinding.instance.addObserver(this);
    // Role guard: if the user is not a doctor, redirect to home
    final auth = Get.find<AuthController>();

    debugPrint(
      'AuthController: isDoctor=${auth.isDoctor}, isPatient=${auth.isPatient}',
    );

    if (!auth.isDoctor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed(AppRoutes.home);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only doctors can access the dashboard.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
    _screens = [
      const DoctorDashboardScreen(),
      const DoctorAppointmentsScreen(),
      _SlotsTabWrapper(),
      const _PaymentHistoryTabWrapper(),
      const DoctorProfileScreen(),
    ];

    // Start polling for new appointments when dashboard opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<DoctorController>().startPolling();
    });

    // Load the notification badge (unread push history) so the dashboard
    // bell is current the moment the shell appears. The badge is NOT
    // cleared here — booking notifications stay unread until the doctor
    // explicitly opens the Appointments tab (see _onTabTapped).
    // Foreground pushes refresh the badge live via NotificationService.
    NotificationCenterController.instance.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A push delivered while the app was backgrounded isn't surfaced by
    // onMessage — refresh the notification badge on resume so it's current
    // (mirrors the patient home screen).
    if (state == AppLifecycleState.resumed) {
      NotificationCenterController.instance.load();
    }
  }

  @override
  void dispose() {
    if (identical(_active, this)) _active = null;
    WidgetsBinding.instance.removeObserver(this);
    // Stop polling when the shell is disposed
    Get.find<DoctorController>().stopPolling();
    super.dispose();
  }

  void _onTabTapped(int index) {
    final doctorController = Get.find<DoctorController>();

    // ── When switching to Appointments tab, reset badge & refresh ──
    if (index == 1) {
      doctorController.markAppointmentsSeen();
      // The doctor is now viewing the appointments — mark the related
      // booking notifications as read too, so the bell reflects what
      // they've seen.
      NotificationCenterController.instance.markDoctorEventsRead();
    }

    // ── Start polling when on Dashboard, stop when leaving ──
    if (index == 0) {
      doctorController.startPolling();
      // Returning to the dashboard — refresh the notification badge so
      // anything received on other tabs shows up immediately.
      NotificationCenterController.instance.load();
    } else {
      doctorController.stopPolling();
    }

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
          // Double back-press to exit on the home (dashboard) tab
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
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final selectedColor = AppColors.primary;
    final unselectedColor = AppColors.textCaption;

    // Reactive badge count
    final badgeCount = Get.find<DoctorController>().unseenAppointmentCount;

    return Obx(
      () => Container(
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
                _DoctorNavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Home',
                  isSelected: _currentIndex == 0,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => _onTabTapped(0),
                ),
                _DoctorNavItem(
                  icon: Icons.calendar_month_rounded,
                  label: 'Appmts',
                  isSelected: _currentIndex == 1,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => _onTabTapped(1),
                  badge: badgeCount.value,
                ),
                _DoctorNavItem(
                  icon: Icons.schedule_rounded,
                  label: 'Slots',
                  isSelected: _currentIndex == 2,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => _onTabTapped(2),
                ),
                _DoctorNavItem(
                  icon: Icons.payments_rounded,
                  label: 'Payments',
                  isSelected: _currentIndex == 3,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => _onTabTapped(3),
                ),
                _DoctorNavItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: _currentIndex == 4,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => _onTabTapped(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrapper widget that obtains the current doctor from [DoctorController]
/// and passes it to [DoctorAvailabilityScreen].
class _SlotsTabWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final doctor = Get.find<DoctorController>().currentDoctor.value;
      if (doctor == null) {
        // The fallback notice enters with the same fade + slide family as
        // the rest of the app's empty/fallback messages.
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 48, color: AppColors.textDisabled),
              const SizedBox(height: 12),
              const Text(
                'No doctor profile loaded',
                style: TextStyle(color: AppColors.textCaption, fontSize: 14),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms, curve: Curves.easeOut)
            .slideY(begin: 0.08, end: 0, duration: 400.ms, curve: Curves.easeOut);
      }
      return DoctorAvailabilityScreen(doctor: doctor);
    });
  }
}

/// Loads the logged-in doctor's clinic payment rows for the doctor
/// payment history tab (same doctor-scoped RLS path as the appointments
/// screen).
Future<List<PaymentModel>> _loadDoctorPayments() async {
  final user = Get.find<AuthController>().currentUser.value;
  final id = user?.id;
  if (id == null) return const [];
  final rows = await SupabaseService().getPaymentsForDoctor(id);
  return rows.map((r) => PaymentModel.fromJson(r)).toList();
}

/// Wrapper widget that renders the doctor-flavoured payment history
/// screen inside the bottom-nav IndexedStack.
class _PaymentHistoryTabWrapper extends StatelessWidget {
  const _PaymentHistoryTabWrapper();

  @override
  Widget build(BuildContext context) {
    return const PaymentHistoryScreen(
      subtitle: 'Fees collected at your clinic',
      loadPayments: _loadDoctorPayments,
    );
  }
}

class _DoctorNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;
  final int badge;

  const _DoctorNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor.withAlpha(15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected ? selectedColor : unselectedColor,
                ),
                if (badge > 0)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withAlpha(100),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
