import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../models/payment_model.dart';
import '../services/supabase_service.dart';
import '../utils/payment_summary.dart';

/// Powers the patient Payment History screen: loads the current user's
/// consultation-fee payment rows (the `payments` table) via
/// [SupabaseService.getPaymentsForUser] — newest first, scoped to the
/// caller's own rows by the `x-user-id` header (payments SELECT RLS).
///
/// Mirrors [NotificationCenterController]'s load/state contract.
class PaymentHistoryController extends GetxController {
  static PaymentHistoryController get instance =>
      Get.isRegistered<PaymentHistoryController>()
          ? Get.find<PaymentHistoryController>()
          : Get.put(PaymentHistoryController());

  final SupabaseService _supabase = SupabaseService();

  final RxList<PaymentModel> payments = <PaymentModel>[].obs;
  final RxBool isLoading = false.obs;

  /// Settled total — the sum of **Paid** amounts (paise-rounded, shared
  /// helper). Reactive through [payments], so the summary section on the
  /// screen updates as the list loads.
  double get paidTotal => paidIncomeOf(payments);

  /// Outstanding total — the sum of **Pending** amounts (what has not been
  /// settled yet).
  double get pendingTotal => pendingIncomeOf(payments);

  /// Load the current user's payments (newest first). Non-fatal: offline
  /// / not logged in keeps the current list.
  Future<void> load() async {
    final user = Get.find<AuthController>().currentUser.value;
    if (user?.id == null) return;
    isLoading.value = true;
    try {
      final rows = await _supabase.getPaymentsForUser(user!.id!);
      payments.value = rows.map((r) => PaymentModel.fromJson(r)).toList()
        // Defensive re-sort: the service already orders by created_at
        // desc, but this keeps seeded/test lists ordered too.
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
    } catch (_) {
      // Non-fatal — keep whatever we already have.
    } finally {
      isLoading.value = false;
    }
  }
}
