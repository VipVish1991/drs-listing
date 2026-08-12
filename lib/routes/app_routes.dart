class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String doctorSearch = '/doctor-search';
  static const String doctorDetail = '/doctor-detail';
  static const String bookAppointment = '/book-appointment';
  static const String rescheduleAppointment = '/reschedule-appointment';
  static const String appointmentHistory = '/appointment-history';
  static const String paymentHistory = '/payment-history';
  static const String profile = '/profile';
  static const String savedDoctors = '/saved-doctors';

  // Doctor listing
  static const String nearbyDoctors = '/nearby-doctors';

  // Doctor availability / slot management
  static const String doctorAvailability = '/doctor-availability';

  // Doctor registration flow
  static const String doctorRegister = '/doctor-register';
  static const String otpVerification = '/otp-verification';

  // Doctor dashboard (3-tab shell)
  static const String doctorDashboard = '/doctor-dashboard';

  // Doctor-side clinic payment history (opened from the dashboard's
  // Payments stat card)
  static const String doctorPaymentHistory = '/doctor-payment-history';

  // Patient appointment history timeline (doctor side)
  static const String patientHistory = '/patient-history';

  // About section
  static const String notificationSettings = '/notification-settings';
  static const String notificationCenter = '/notification-center';
  static const String about = '/about';
  static const String help = '/help';
  static const String privacyPolicy = '/privacy-policy';
}
