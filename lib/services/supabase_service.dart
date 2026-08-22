import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/constants.dart';
import '../models/appointment_model.dart';
import '../models/doctor_model.dart';
import '../models/doctor_slot_model.dart';
import '../models/unavailable_range.dart';
import '../utils/text_capitalizer.dart';

/// Request headers that scope the anon-key RLS policies on the `users`
/// table to the caller's own row.
///
/// The QR web booking page writes to `users` with the **service role**
/// (RLS bypassed), but the mobile app talks to PostgREST with the anon
/// key, so it must prove ownership of every row it touches:
///
///   * `x-user-mobile` → SELECT / INSERT — the app only knows the typed
///     mobile number at lookup/registration time
///   * `x-user-id` + `x-user-mobile` → UPDATE — the app knows the row UUID
///     once the account exists, but the mobile header MUST ride along too:
///     supabase-dart requests `return=representation`, and PostgREST
///     materializes the affected rows through the SELECT policy, so with
///     only `x-user-id` the UPDATE silently affects 0 rows (HTTP 200, no
///     error — verified against the live project).
///
/// Null values are omitted so callers can build partial contexts.
Map<String, String> usersContextHeaders({String? mobile, String? userId}) {
  return {'x-user-mobile': ?mobile, 'x-user-id': ?userId};
}

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  /// Creates an unshared instance for subclassing in tests (mirrors
  /// [AuthService.testing]) or for injection into other services. No
  /// platform channels are touched at construction.
  SupabaseService.testing();

  SupabaseClient get client => Supabase.instance.client;

  Future<void> init() async {
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        publishableKey: AppConstants.supabaseAnonKey,
      );
    } catch (e) {
      // If Supabase fails to initialize (e.g. on first launch without
      // network, or on devices without Google Play Services), the app
      // should still start.  Individual services that depend on Supabase
      // will handle null/error states downstream.
      debugPrint('Supabase init error (non-fatal): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Users table
  // ═══════════════════════════════════════════════════════════════
  /// Runs [action] with [contextHeaders] attached to the Supabase REST
  /// client, restoring the previous headers afterwards.
  ///
  /// supabase-dart propagates headers to PostgREST only through the
  /// `client.headers` **setter**, so we snapshot → set → run → restore.
  /// The app's user flows are sequential (login → register → become a
  /// doctor), so this is race-free in practice.
  Future<T> _withUsersContext<T>(
    Map<String, String> contextHeaders,
    Future<T> Function() action,
  ) async {
    if (contextHeaders.isEmpty) return action();
    final supabase = Supabase.instance;
    final original = Map<String, String>.of(supabase.client.headers);
    supabase.client.headers = {...original, ...contextHeaders};
    try {
      return await action();
    } finally {
      supabase.client.headers = original;
    }
  }

  Future<Map<String, dynamic>?> getUserByMobile(String mobile) async {
    return _withUsersContext(usersContextHeaders(mobile: mobile), () async {
      final response = await client
          .from('users')
          .select()
          .eq('mobile', mobile)
          .maybeSingle();
      return response;
    });
  }

  Future<Map<String, dynamic>> createUser(
    String name,
    String mobile, {
    String? role,
  }) async {
    return _withUsersContext(usersContextHeaders(mobile: mobile), () async {
      final data = <String, dynamic>{
        'name': capitalizeWords(name),
        'mobile': mobile,
      };
      if (role != null) {
        data['role'] = role;
      }
      final response = await client
          .from('users')
          .insert(data)
          .select()
          .single();
      return response;
    });
  }

  /// Register (or refresh) an FCM device token on the caller's own row.
  /// Single-token: the add_device_token RPC replaces any existing token
  /// with the new one (the array always contains exactly one entry).
  /// Runs with the x-user-id header context so the SECURITY DEFINER
  /// function can verify ownership.
  Future<void> addDeviceToken(
    String userId,
    String token, {
    String platform = 'android',
  }) async {
    await _withUsersContext(usersContextHeaders(userId: userId), () async {
      await client.rpc('add_device_token', params: {
        'p_token': token,
        'p_platform': platform,
      });
    });
  }

  /// Remove an FCM device token from the caller's own row (logout).
  Future<void> removeDeviceToken(String userId, String token) async {
    await _withUsersContext(usersContextHeaders(userId: userId), () async {
      await client.rpc('remove_device_token', params: {'p_token': token});
    });
  }

  /// Load the caller's push-notification preferences. The users SELECT RLS
  /// policy is scoped to the `x-user-mobile` header, so [mobile] must be the
  /// caller's own number. Returns the raw map (event name → bool) or `null`
  /// when the row/column can't be read (e.g. migration not yet applied).
  Future<Map<String, dynamic>?> getUserNotificationPrefs(
    String userId,
    String mobile,
  ) async {
    return _withUsersContext(
      usersContextHeaders(mobile: mobile),
      () async {
        final response = await client
            .from('users')
            .select('notification_prefs')
            .eq('id', userId)
            .maybeSingle();
        return response?['notification_prefs'] as Map<String, dynamic>?;
      },
    );
  }

  /// Persist the caller's push-notification preferences. Requires BOTH
  /// context headers: the UPDATE policy is scoped on `x-user-id`, but
  /// supabase-dart requests `return=representation`, so PostgREST
  /// materializes the affected row through the SELECT policy — without
  /// `x-user-mobile` the UPDATE silently affects 0 rows (same contract as
  /// [updateUserName], verified against the live project).
  Future<void> saveUserNotificationPrefs(
    String userId,
    String mobile,
    Map<String, bool> prefs,
  ) async {
    await _withUsersContext(
      usersContextHeaders(userId: userId, mobile: mobile),
      () async {
        await client.from('users').update({
          'notification_prefs': prefs,
        }).eq('id', userId);
      },
    );
  }

  /// Update the caller's own display name. Requires BOTH context headers
  /// (see [saveUserNotificationPrefs]); names are capitalized for
  /// consistent DB formatting, matching [createUser]. Returns `true` only
  /// when the row actually came back — a silent RLS denial (0 rows) is
  /// reported as `false` so callers never show a false "name updated".
  ///
  /// NOTE: `.select()` (list) instead of `.select().maybeSingle()` —
  /// postgrest only unwraps a single-row response for GET requests; on a
  /// PATCH the maybeSingle unwrap is skipped and parsing a `[{...}]`
  /// response crashes (verified against postgrest 2.7.2).
  Future<bool> updateUserName(
    String userId,
    String mobile,
    String name,
  ) async {
    final rows = await _withUsersContext(
      usersContextHeaders(userId: userId, mobile: mobile),
      () async {
        return client
            .from('users')
            .update({'name': capitalizeWords(name)})
            .eq('id', userId)
            .select();
      },
    );
    return rows.isNotEmpty;
  }

  Future<void> updateUserRole(
    String userId,
    String mobile,
    String role, {
    String? doctorPlaceId,
  }) async {
    try {
      await _withUsersContext(
        usersContextHeaders(userId: userId, mobile: mobile),
        () async {
          final updateData = <String, dynamic>{'role': role};
          if (doctorPlaceId != null) {
            updateData['doctor_place_id'] = doctorPlaceId;
          }
          await client.from('users').update(updateData).eq('id', userId);
        },
      );
    } catch (e) {
      // Role/doctor_place_id column may not exist in the DB yet if the
      // migration hasn't been applied.  The role is always saved locally
      // in AuthService, so this is non-fatal.
      debugPrint('⚠️ updateUserRole failed (column may not exist): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Notifications (in-app push history)
  // ═══════════════════════════════════════════════════════════════

  /// All notifications for a user, newest first — powers the in-app
  /// notification center. The notifications SELECT RLS policy is scoped to
  /// the `x-user-id` header.
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    return _withUsersContext(usersContextHeaders(userId: userId), () async {
      final response = await client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return response;
    });
  }

  /// Mark a single notification as read (notifications UPDATE RLS policy is
  /// scoped to the `x-user-id` header).
  Future<void> markNotificationRead(String userId, String id) async {
    await _withUsersContext(usersContextHeaders(userId: userId), () async {
      await client
          .from('notifications')
          .update({'read': true})
          .eq('id', id)
          .eq('user_id', userId);
    });
  }

  /// Mark every unread notification of a user as read (used by the
  /// "Mark all as read" action).
  Future<void> markAllNotificationsRead(String userId) async {
    await _withUsersContext(usersContextHeaders(userId: userId), () async {
      await client
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .eq('read', false);
    });
  }

  /// Mark every unread DOCTOR-event notification as read — the new-booking,
  /// patient-cancel and patient-reschedule alerts tied to appointments
  /// (`appointment_booked` / `appointment_cancelled` /
  /// `appointment_rescheduled`). Called when the doctor opens the app or
  /// views the appointments, so the bell badge reflects what they've already
  /// seen while patient-scoped notifications stay untouched.
  Future<void> markDoctorNotificationsRead(String userId) async {
    await _withUsersContext(usersContextHeaders(userId: userId), () async {
      await client
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .inFilter('type', [
            'appointment_booked',
            'appointment_cancelled',
            'appointment_rescheduled',
          ])
          .eq('read', false);
    });
  }

  /// Mark every unread notification for ONE appointment as read — used when
  /// the doctor acts on the booking (confirm / cancel / complete) so the bell
  /// reflects it was seen and handled. The row's `data` JSONB carries
  /// `appointment_id`, matched here (same `->>` filter style as the doctor
  /// `doctor_data->>place_id` lookups).
  Future<void> markAppointmentNotificationsRead(
    String userId,
    String appointmentId,
  ) async {
    await _withUsersContext(usersContextHeaders(userId: userId), () async {
      await client
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .filter('data->>appointment_id', 'eq', appointmentId)
          .eq('read', false);
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Payments table (consultation fees — UPI online / offline)
  // ═══════════════════════════════════════════════════════════════

  /// Insert a payment row for a booked appointment. Runs with the
  /// `x-user-id` header context so the payments INSERT RLS policy
  /// (patient_id = x-user-id) accepts it — same convention as
  /// [addDeviceToken].
  Future<void> createPayment(
    String patientUserId,
    Map<String, dynamic> paymentData,
  ) async {
    await _withUsersContext(usersContextHeaders(userId: patientUserId), () async {
      await client.from('payments').insert(paymentData);
    });
  }

  /// All payment rows for a patient, newest first — powers the payment
  /// history. The payments SELECT RLS policy is scoped to the `x-user-id`
  /// header.
  Future<List<Map<String, dynamic>>> getPaymentsForUser(
    String userId,
  ) async {
    return _withUsersContext(usersContextHeaders(userId: userId), () async {
      final response = await client
          .from('payments')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return response;
    });
  }

  /// All payment rows for the clinics the CALLER owns (doctor side), newest
  /// first — powers the payment line + Mark Paid/Refund actions on the
  /// doctor appointments screen AND the doctor payment history screen. The
  /// payments SELECT RLS policy for doctors matches the caller's
  /// `x-user-id` against the `doctors` table (owned clinic place ids) and
  /// then against `payments.doctor_place_id`.
  ///
  /// Also embeds the appointment's `patient_name` (via the
  /// payments.appointment_id → appointments FK) so the doctor-facing list
  /// can lead with who the payment belongs to.
  Future<List<Map<String, dynamic>>> getPaymentsForDoctor(
    String userId,
  ) async {
    return _withUsersContext(usersContextHeaders(userId: userId), () async {
      final response = await client
          .from('payments')
          .select('*, appointments(patient_name)')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return response;
    });
  }

  /// Flip a payment's status (e.g. an offline 'Pending' → 'Paid' /
  /// 'Refunded', or a 'Paid' row → 'Refunded'). Runs with the `x-user-id`
  /// header; the payments UPDATE RLS policy for doctors (owned clinic)
  /// permits only `payment_status` / `paid_at` / `updated_at` and the
  /// refund columns to be written. [refundMethod] / [refundedAt] /
  /// [refundUpiId] / [refundTransactionId] / [refundRawResponse] record
  /// HOW an online/cash refund was given back (see the refund_details
  /// migration). Returns `true` only when the row actually came back — a
  /// silent RLS denial (0 rows) is reported as `false` so the UI never
  /// claims a payment was settled that wasn't (same contract as
  /// [updateUserName]).
  Future<bool> updatePaymentStatus(
    String userId,
    String paymentId, {
    required String status,
    DateTime? paidAt,
    String? refundMethod,
    DateTime? refundedAt,
    String? refundUpiId,
    String? refundTransactionId,
    String? refundRawResponse,
  }) async {
    final rows = await _withUsersContext(
      usersContextHeaders(userId: userId),
      () async {
        return client.from('payments').update({
          'payment_status': status,
          'paid_at': ?paidAt?.toUtc().toIso8601String(),
          'refund_method': ?refundMethod,
          'refunded_at': ?refundedAt?.toUtc().toIso8601String(),
          'refund_upi_id': ?refundUpiId,
          'refund_transaction_id': ?refundTransactionId,
          'refund_raw_response': ?refundRawResponse,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', paymentId).select();
      },
    );
    return rows.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════
  // Appointments table
  // ═══════════════════════════════════════════════════════════════
  /// The caller's appointments (patient). Runs with the `x-user-id`
  /// header so the owner-scoped appointments SELECT policy returns only
  /// the caller's own rows.
  Future<List<Map<String, dynamic>>> getUserAppointments(String userId) async {
    final response = await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('appointments')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10)),
    );
    return response;
  }

  /// Create an appointment on the caller's own behalf. Runs with the
  /// `x-user-id` header (from `data['user_id']`) so the owner-scoped
  /// INSERT policy accepts it.
  Future<Map<String, dynamic>> createAppointment(
    Map<String, dynamic> data,
  ) async {
    final response = await _withUsersContext(
      usersContextHeaders(userId: data['user_id']?.toString()),
      () => client
          .from('appointments')
          .insert(data)
          .select()
          .single(),
    );
    return response;
  }

  /// Flip an appointment's status. Runs with the `x-user-id` header —
  /// both the patient (own cancel) and the clinic (Confirm/Complete/
  /// Cancel) pass their own user id, which the owner-scoped UPDATE
  /// policy matches against the appointment's patient or the clinic's
  /// doctors row.
  Future<void> updateAppointmentStatus(
    String appointmentId,
    String status, {
    required String userId,
  }) async {
    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('appointments')
          .update({'status': status})
          .eq('appointment_id', appointmentId),
    );
  }

  // ── Web user registration (browser-only booking) ──────────────────

  /// Find an existing user row by mobile number. Returns the row
  /// or null if no match.
  Future<Map<String, dynamic>?> findUserByMobile(String mobile) async {
    try {
      final rows = await client
          .from('users')
          .select('id, name, mobile')
          .eq('mobile', mobile)
          .limit(1);
      return rows.isNotEmpty ? rows.first : null;
    } catch (_) {
      return null;
    }
  }

  /// Create a minimal web user row (name + mobile) for the browser
  /// booking flow. Returns the created row with `id`.
  Future<Map<String, dynamic>> createWebUser({
    required String name,
    required String mobile,
  }) async {
    final response = await client
        .from('users')
        .insert({
          'name': name,
          'mobile': mobile,
          'role': 'patient',
        })
        .select('id, name, mobile')
        .single();
    return response;
  }

  /// Save (or clear, when [link] is null/empty) the shared Google Meet URL
  /// for a video/tele consultation. Runs with the `x-user-id` header — the
  /// appointments UPDATE policy lets both the owning patient and the
  /// clinic write it. Returns `true` only when the row actually came back
  /// (a silent RLS denial is reported as `false`, same contract as
  /// [updateUserName]).
  Future<bool> updateAppointmentMeetLink(
    String appointmentId,
    String? link, {
    required String userId,
  }) async {
    try {
      final value = (link ?? '').trim().isEmpty ? null : link!.trim();
      final rows = await _withUsersContext(
        usersContextHeaders(userId: userId),
        () => client
            .from('appointments')
            .update({'meet_link': value})
            .eq('appointment_id', appointmentId)
            .select(),
      );
      return rows.isNotEmpty;
    } catch (e) {
      // The meet_link column may not exist yet if the migration hasn't
      // been applied — never crash the video-call flow over it.
      debugPrint('⚠️ [updateAppointmentMeetLink] failed: $e');
      return false;
    }
  }

  /// Move an appointment to a new date/time slot (patient reschedule).
  ///
  /// Updates only the slot-defining columns: `appointment_date`,
  /// `appointment_time` and `consultation_type` (the schedule type of the
  /// NEW slot, so Tele/Video/In-Clinic stays in sync with the slot the
  /// patient picked).
  ///
  /// **Owner scoping:** the UPDATE is filtered by BOTH `appointment_id`
  /// and the caller's `user_id`, so the app never even attempts to move
  /// someone else's appointment (defense-in-depth on top of the
  /// appointments RLS policies).
  ///
  /// **Slot conflict safety:** the DB trigger `enforce_slot_booking_rule`
  /// fires on UPDATE of `appointment_date`/`appointment_time` and REJECTS
  /// the move when the new slot is already occupied by another
  /// non-Cancelled appointment (it excludes the appointment being moved
  /// itself, so keeping the same slot is a harmless no-op). Returns
  /// `false` on rejection or silent RLS denial (0 rows) so the UI can
  /// tell the patient the slot was just taken — never crashes.
  Future<bool> rescheduleAppointment(
    String appointmentId, {
    required String userId,
    required String date,
    required String time,
    String? consultationType,
  }) async {
    try {
      final rows = await _withUsersContext(
        usersContextHeaders(userId: userId),
        () => client
            .from('appointments')
            .update({
              'appointment_date': date,
              'appointment_time': time,
              if (consultationType != null && consultationType.isNotEmpty)
                'consultation_type': consultationType,
            })
            .eq('appointment_id', appointmentId)
            .eq('user_id', userId)
            .select(),
      );
      return rows.isNotEmpty;
    } catch (e) {
      // The slot-rule trigger raised appointments_slot_occupied (or any
      // other rejection) — report the reschedule as failed so the screen
      // can show the friendly "slot was just booked" message.
      debugPrint('⚠️ [rescheduleAppointment] rejected: $e');
      return false;
    }
  }

  /// Move an appointment to a new date/time slot as the CLINIC
  /// (doctor-initiated reschedule).
  ///
  /// Identical to [rescheduleAppointment] but deliberately does NOT scope
  /// the UPDATE to a `user_id` — the doctor is not the row's owner (the
  /// patient is), and the appointments UPDATE policy lets the clinic move
  /// its own bookings the same way it changes their status
  /// ([updateAppointmentStatus] follows the same no-owner-scope pattern).
  /// The DB trigger `enforce_slot_booking_rule` still guards the new slot
  /// (a just-taken slot rejects the move). Returns `false` on rejection or
  /// a silent 0-row update so the UI can tell the doctor the slot was
  /// taken — never crashes.
  Future<bool> rescheduleAppointmentAsDoctor(
    String appointmentId, {
    required String userId,
    required String date,
    required String time,
    String? consultationType,
  }) async {
    try {
      final rows = await _withUsersContext(
        usersContextHeaders(userId: userId),
        () => client
            .from('appointments')
            .update({
              'appointment_date': date,
              'appointment_time': time,
              if (consultationType != null && consultationType.isNotEmpty)
                'consultation_type': consultationType,
            })
            .eq('appointment_id', appointmentId)
            .select(),
      );
      return rows.isNotEmpty;
    } catch (e) {
      // The slot-rule trigger raised appointments_slot_occupied (or any
      // other rejection) — report the reschedule as failed so the screen
      // can show the friendly "slot was just booked" message.
      debugPrint('⚠️ [rescheduleAppointmentAsDoctor] rejected: $e');
      return false;
    }
  }

  /// Append one or more prescription photo URLs to an appointment's
  /// `upload_prescription` array (the doctor-side gallery grows over
  /// time). Combined with [updateAppointmentStatus] by the controller.
  Future<void> addPrescriptionUrls(
    String appointmentId,
    List<String> urls, {
    required String userId,
  }) async {
    if (urls.isEmpty) return;
    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('appointments')
          .update({'upload_prescription': urls})
          .eq('appointment_id', appointmentId),
    );
  }

  /// Upload a prescription photo to the booking-page Edge Function, which
  /// resizes + compresses it server-side (max 2560px, JPEG q92 + light
  /// sharpen) BEFORE writing it to the public `prescriptions` bucket,
  /// then returns the public URL to store on the appointment.
  ///
  /// [bytes] must be a JPEG/PNG the server can decode — image_picker
  /// already re-encodes to JPEG (with EXIF orientation baked into the
  /// pixels) when imageQuality/maxWidth is set, so camera photos arrive
  /// correctly oriented. The function URL is derived from the project's
  /// supabaseUrl and gated with the same booking shared secret the QR
  /// booking flow uses. Returns null on failure.
  Future<String?> uploadPrescriptionImage(
    String appointmentId, {
    required String doctorPlaceId,
    required Uint8List bytes,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppConstants.supabaseUrl}/functions/v1/booking-page'
        '?doctor=${Uri.encodeComponent(doctorPlaceId)}'
        '&action=prescription'
        '&appointment=${Uri.encodeComponent(appointmentId)}',
      );
      final response = await http
          .post(
            uri,
            headers: {
              'x-booking-token': AppConstants.bookingSharedSecret,
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ [uploadPrescriptionImage] HTTP ${response.statusCode}: '
          '${response.body}',
        );
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['url'] as String?;
    } catch (e) {
      debugPrint('⚠️ [uploadPrescriptionImage] failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Saved doctors (user favorites)
  // ═══════════════════════════════════════════════════════════════
  Future<void> saveDoctor(
    String userId,
    Map<String, dynamic> doctorData,
  ) async {
    // Capitalise text fields for consistent DB formatting
    if (doctorData['name'] is String) {
      doctorData['name'] = capitalizeWords(doctorData['name']);
    }
    if (doctorData['address'] is String) {
      doctorData['address'] = capitalizeWords(doctorData['address']);
    }
    if (doctorData['specialization'] is String) {
      doctorData['specialization'] = capitalizeWords(
        doctorData['specialization'],
      );
    }
    if (doctorData['hospital_name'] is String) {
      doctorData['hospital_name'] = capitalizeWords(
        doctorData['hospital_name'],
      );
    }

    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client.from('saved_doctors').insert({
        'user_id': userId,
        'doctor_data': doctorData,
      }),
    );
  }

  Future<List<Map<String, dynamic>>> getSavedDoctors(String userId) async {
    final response = await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('saved_doctors')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    );
    return response;
  }

  Future<void> removeSavedDoctorByPlaceId(String userId, String placeId) async {
    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('saved_doctors')
          .delete()
          .eq('user_id', userId)
          .filter('doctor_data->>place_id', 'eq', placeId),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Doctors table (canonical doctor profile)
  // ═══════════════════════════════════════════════════════════════

  /// Save (upsert) a doctor's full profile from Places API into
  /// the public.doctors table. Returns the saved record.
  ///
  /// **Null-value filtering:** Columns that the doctor does not have
  /// (e.g. `userId == null`) are removed from the payload so the upsert
  /// doesn't reset existing DB values to `null`.
  ///
  /// **Owner scoping:** runs with the `x-user-id` header so the
  /// owner-scoped doctors INSERT/UPDATE policies accept the write — the
  /// caller must be the user connected to this clinic (or the first
  /// connector adopting a legacy NULL-user_id row).
  Future<Map<String, dynamic>> saveDoctorToDb(DoctorModel doctor) async {
    final data = doctor.toJson();
    data.remove('distance');
    // `unavailable_ranges` is doctor-set state that a Places-API-enriched
    // save must NEVER overwrite — it lives in its own column and is only
    // written via [saveDoctorUnavailableRanges].
    data.remove('unavailable_ranges');

    // Capitalise text fields for consistent DB formatting
    if (data['name'] is String) {
      data['name'] = capitalizeWords(data['name']);
    }
    if (data['address'] is String) {
      data['address'] = capitalizeWords(data['address']);
    }
    if (data['specialization'] is String) {
      data['specialization'] = capitalizeWords(data['specialization']);
    }
    if (data['hospital_name'] is String) {
      data['hospital_name'] = capitalizeWords(data['hospital_name']);
    }

    // Remove fields whose values are null to avoid overwriting existing
    // DB data with nulls on upsert.
    data.removeWhere((_, v) => v == null);

    final response = await _withUsersContext(
      usersContextHeaders(userId: doctor.userId),
      () => client
          .from('doctors')
          .upsert(data, onConflict: 'place_id')
          .select()
          .single(),
    );
    return response;
  }

  /// Get a single doctor by their Google Place ID.
  Future<DoctorModel?> getDoctorFromDb(String placeId) async {
    final response = await client
        .from('doctors')
        .select()
        .eq('place_id', placeId)
        .maybeSingle();
    if (response == null) return null;
    return DoctorModel.fromJson(response);
  }

  /// Returns the Google Place IDs of every clinic/hospital/doctor already
  /// registered in the `doctors` table. Registration mode uses this to
  /// disable the nearby-Google-result card for any place that is already
  /// registered (you can't claim a clinic someone else manages). SELECT on
  /// `doctors` stays open, so this works without any ownership headers.
  Future<List<String>> getRegisteredDoctorPlaceIds() async {
    final rows = await client.from('doctors').select('place_id');
    return rows
        .map((r) => r['place_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  /// Persist a doctor's unavailable date ranges (leave / holiday) without
  /// touching any other column. Deliberately separate from the generic
  /// profile upsert ([saveDoctorToDb]) so Places-enriched saves never wipe
  /// the ranges. Owner-scoped via [userId] (the connected clinic user).
  Future<void> saveDoctorUnavailableRanges(
    String doctorPlaceId,
    List<UnavailableRange> ranges, {
    String? userId,
  }) async {
    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('doctors')
          .update({'unavailable_ranges': ranges.map((r) => r.toJson()).toList()})
          .eq('place_id', doctorPlaceId),
    );
  }

  /// Persist the doctor's UPI VPA (the address that receives online
  /// consultation fees) without touching any other column. A null/empty
  /// [upiId] clears it. Mirrors [saveDoctorUnavailableRanges] so
  /// Places-enriched saves never wipe doctor-set payment details.
  /// Owner-scoped via [userId] (the connected clinic user).
  Future<void> saveDoctorUpiId(
    String doctorPlaceId,
    String? upiId, {
    String? userId,
  }) async {
    final value = (upiId ?? '').trim().isEmpty ? null : upiId!.trim();
    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('doctors')
          .update({'upi_id': value})
          .eq('place_id', doctorPlaceId),
    );
  }

  /// Get all doctors linked to a specific user by [userId].
  /// Useful for the doctor dashboard / profile to list all clinics
  /// a doctor user has connected.
  Future<List<DoctorModel>> getDoctorsByUserId(String userId) async {
    final response = await client
        .from('doctors')
        .select()
        .eq('user_id', userId)
        .order('name');
    return (response as List)
        .map((json) => DoctorModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════
  // Doctor Slots table (weekly availability)
  // ═══════════════════════════════════════════════════════════════

  /// Get all slots for a user by filtering on [userId].
  /// Returns all slot rows across all doctors this user owns.
  Future<List<DoctorSlot>> getDoctorSlotsByUserId(String userId) async {
    final response = await client
        .from('doctor_slots')
        .select()
        .eq('user_id', userId)
        .order('day_of_week')
        .order('schedule_type');
    return (response as List)
        .map((json) => DoctorSlot.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get all slots for a doctor, ordered by day and type.
  Future<List<DoctorSlot>> getDoctorSlots(String doctorPlaceId) async {
    final response = await client
        .from('doctor_slots')
        .select()
        .eq('doctor_place_id', doctorPlaceId)
        .order('day_of_week')
        .order('schedule_type');
    return (response as List)
        .map((json) => DoctorSlot.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Save (upsert) a single slot row for a doctor.
  /// Uses the unique constraint `doctor_slots_unique_key` on
  /// (doctor_place_id, day_of_week, schedule_type).
  ///
  /// If the unique constraint does not exist in the database (migration
  /// not yet applied), falls back to delete + insert.
  Future<DoctorSlot> saveDoctorSlot(DoctorSlot slot) async {
    try {
      final response = await _withUsersContext(
        usersContextHeaders(userId: slot.userId),
        () => client
            .from('doctor_slots')
            .upsert(
              slot.toJson(),
              onConflict: 'doctor_place_id,day_of_week,schedule_type',
            )
            .select()
            .single(),
      );
      return DoctorSlot.fromJson(response);
    } catch (e) {
      // If the upsert fails (e.g. constraint doesn't exist), fall back
      // to explicit delete + insert.
      debugPrint('⚠️ [saveDoctorSlot] Upsert failed, trying delete+insert: $e');
      await _withUsersContext(
        usersContextHeaders(userId: slot.userId),
        () => client
            .from('doctor_slots')
            .delete()
            .eq('doctor_place_id', slot.doctorPlaceId)
            .eq('day_of_week', slot.dayOfWeek)
            .eq('schedule_type', slot.scheduleType),
      );
      final response = await _withUsersContext(
        usersContextHeaders(userId: slot.userId),
        () => client
            .from('doctor_slots')
            .insert(slot.toJson())
            .select()
            .single(),
      );
      return DoctorSlot.fromJson(response);
    }
  }

  /// Save all weekly schedule rows for a doctor in one batch.
  /// Each slot row in the list is upserted individually.
  ///
  /// **Error handling:** A single failing slot does not abort the rest.
  /// Returns the number of successfully saved rows.
  Future<int> saveWeeklySchedule(
    String doctorPlaceId,
    List<DoctorSlot> slots,
  ) async {
    int savedCount = 0;
    for (final slot in slots) {
      try {
        await saveDoctorSlot(slot);
        savedCount++;
      } catch (e) {
        debugPrint(
          '⚠️ [saveWeeklySchedule] Failed for '
          '(${slot.dayOfWeek}, ${slot.scheduleType}): $e',
        );
      }
    }
    return savedCount;
  }

  /// Delete a single slot row by its UUID.
  Future<void> deleteDoctorSlot(String slotId, {String? userId}) async {
    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client.from('doctor_slots').delete().eq('id', slotId),
    );
  }

  /// Delete all slots for a doctor (e.g. before re-saving the whole week).
  Future<void> deleteAllDoctorSlots(
    String doctorPlaceId, {
    String? userId,
  }) async {
    await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('doctor_slots')
          .delete()
          .eq('doctor_place_id', doctorPlaceId),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Doctor-specific appointments (for the doctor dashboard)
  // ═══════════════════════════════════════════════════════════════

  /// Get all appointments for a doctor by filtering on the indexed
  /// `doctor_place_id` column (faster than JSONB traversal).
  /// Falls back to JSONB `doctor_details->>place_id` filtering for rows
  /// created before the migration was applied.
  /// Get all appointments for a doctor by filtering on the indexed
  /// `doctor_place_id` column (faster than JSONB traversal).
  ///
  /// Runs with the `x-user-id` header — the owner-scoped appointments
  /// SELECT policy lets the CLINIC (a doctors row whose user_id is the
  /// caller) read its own bookings, so [userId] must be the connected
  /// clinic owner's user id.
  ///
  /// ⚠️ NOT for the patient booking screen: it needs only which slots are
  /// taken (not other patients' rows) — use [getBookedSlotKeys] instead.
  Future<List<Map<String, dynamic>>> getDoctorAppointments(
    String doctorPlaceId, {
    required String userId,
  }) async {
    final response = await _withUsersContext(
      usersContextHeaders(userId: userId),
      () => client
          .from('appointments')
          .select()
          .or(
            'doctor_place_id.eq.$doctorPlaceId,'
            'doctor_details->>place_id.eq.$doctorPlaceId',
          )
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10)),
    );
    return response;
  }

  /// The booking screen's single allowed peek into a clinic's bookings:
  /// returns ONLY the `date|time` keys of non-Cancelled appointments for
  /// [doctorPlaceId] (no patient data). Backed by the SECURITY DEFINER
  /// `get_booked_slot_keys` RPC so the owner-scoped appointments SELECT
  /// never leaks other patients' rows to the booking flow.
  Future<Set<String>> getBookedSlotKeys(String doctorPlaceId) async {
    try {
      final result = await client.rpc('get_booked_slot_keys', params: {
        'p_doctor_place_id': doctorPlaceId,
      });
      final keys = result as List<dynamic>? ?? const [];
      return keys.map((k) => k.toString()).toSet();
    } catch (e) {
      debugPrint('⚠️ [getBookedSlotKeys] failed: $e');
      return <String>{};
    }
  }

  /// Get a summary of appointments for a doctor (today's count, total,
  /// completed, cancelled). Returns counts as a map.
  ///
  /// Slot-occupancy rule (shared with the booking screen, see
  /// [AppointmentStatus.occupiesSlot]): a slot stays booked until the
  /// appointment is Cancelled — so `today` and `upcoming` count every
  /// appointment (Pending / Upcoming / Completed / …) except Cancelled
  /// ones, and only a Cancelled appointment frees its slot.
  Future<Map<String, int>> getDoctorAppointmentStats(
    String doctorPlaceId, {
    required String userId,
  }) async {
    final all = await getDoctorAppointments(doctorPlaceId, userId: userId);

    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    int total = 0, today = 0, completed = 0, cancelled = 0, upcoming = 0;
    for (final apt in all) {
      final status = apt['status']?.toString() ?? '';
      total++;
      if (status == 'Completed') completed++;
      if (status == 'Cancelled') cancelled++;
      // A slot stays booked until the appointment is Cancelled — every
      // other status (Pending / Upcoming / Completed / …) is a booked
      // slot, so it counts toward today's and the overall booked counts.
      if (AppointmentStatus.occupiesSlot(status)) {
        upcoming++;
        final date = apt['appointment_date']?.toString() ?? '';
        if (date == todayKey) today++;
      }
    }

    return {
      'total': total,
      'today': today,
      'completed': completed,
      'cancelled': cancelled,
      'upcoming': upcoming,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // API usage tracking (daily Google Places call counters)
  // ═══════════════════════════════════════════════════════════════

  /// Increment today's counter for [endpoint] (e.g. `text_search`,
  /// `place_details`) in the `api_usage_count` table.
  ///
  /// **Do not call this for normal searches** — the places-proxy Edge
  /// Function (the app's single choke point for Google Places calls)
  /// already records every call it relays, and calling this too would
  /// double-count. It exists for parity with the DB contract and for
  /// tests/manual backfill.
  Future<void> incrementApiUsage(String endpoint) async {
    await client.rpc('increment_api_usage', params: {'p_endpoint': endpoint});
  }

  /// Total Google Places API calls recorded today (sum of every
  /// endpoint's counter row for the current `usage_date`). Returns 0
  /// when nothing has been counted yet.
  ///
  /// The `usage_date` column is set by the DB with `CURRENT_DATE`
  /// (Supabase server = UTC), so the day key is derived from UTC —
  /// using local time would read the wrong day in timezones ahead of
  /// UTC between midnight and sunrise.
  Future<int> getApiUsageToday() async {
    final today = _dateKey(DateTime.now().toUtc());
    final rows = await client
        .from('api_usage_count')
        .select('count')
        .eq('usage_date', today)
        .timeout(const Duration(seconds: 10));
    return rows.fold<int>(
      0,
      (sum, r) => sum + ((r['count'] as num?)?.toInt() ?? 0),
    );
  }

  /// Calls recorded for [endpoint] on [date] (0 when no counter row
  /// exists for that day + endpoint).
  Future<int> getApiUsageForDate(DateTime date, String endpoint) async {
    final row = await client
        .from('api_usage_count')
        .select('count')
        .eq('usage_date', _dateKey(date))
        .eq('endpoint', endpoint)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    return (row?['count'] as num?)?.toInt() ?? 0;
  }

  /// Local helper: `usage_date` column key in YYYY-MM-DD (lexicographic
  /// order == chronological, matches the DB DATE format).
  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';
}
