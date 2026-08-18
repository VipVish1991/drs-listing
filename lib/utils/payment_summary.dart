import '../models/payment_model.dart';

/// Shared money-summing for payment summaries (doctor dashboard Income
/// card + the payment history screen summary). Amounts sum in integer
/// paise (×100, rounded per term) so adding many NUMERIC(10,2) doubles
/// never accumulates floating-point drift, then convert back to rupees.

/// Sums the settled (Paid) consultation amounts from [payments].
double paidIncomeOf(Iterable<PaymentModel> payments) =>
    _sumPaise(payments, (p) => p.isPaid);

/// Sums the outstanding (Pending) consultation amounts from [payments] —
/// what is still owed / not yet settled. Refunded / Failed rows are not
/// outstanding.
double pendingIncomeOf(Iterable<PaymentModel> payments) =>
    _sumPaise(payments, (p) => p.paymentStatus == 'Pending');

/// Sums the refunded consultation amounts from [payments] — the total
/// that was sent back to patients via UPI or cash.
double refundedTotalOf(Iterable<PaymentModel> payments) =>
    _sumPaise(payments, (p) => p.paymentStatus == 'Refunded');

double _sumPaise(
  Iterable<PaymentModel> payments,
  bool Function(PaymentModel) where,
) =>
    payments
            .where(where)
            .fold<int>(0, (paise, p) => paise + (p.amount * 100).round()) /
        100.0;
