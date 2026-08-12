import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// hide AuthException: gotrue (re-exported by supabase_flutter) defines its
// own, which would clash with the app's AuthException from auth_service.dart.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import 'package:DrsListing/services/auth_service.dart';
import 'package:DrsListing/services/supabase_service.dart';

import '../helpers/test_data.dart';

/// Guards the profile name-edit chain:
///
/// * [SupabaseService.updateUserName] must PATCH the caller's own `users`
///   row (scoped by `id`) with the **capitalized** name and BOTH RLS
///   context headers (`x-user-id` + `x-user-mobile`), then restore the
///   client headers. Returns `false` when the PATCH affects 0 rows — the
///   silent RLS denial that used to show a false "Name updated".
/// * [AuthService.updateName] must trim + capitalize, persist the updated
///   session locally (so a restart sees the new name), and throw
///   [AuthException] when the update cannot land server-side instead of
///   silently pretending success.
///
/// The real Supabase client is initialized with an injected [MockClient]
/// that records every request, so the full PostgREST path (header attach
/// via `_withUsersContext`, PATCH construction, response handling) runs
/// for real without any network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every HTTP request the mocked Supabase client makes, in order.
  final requests = <http.Request>[];

  /// When true, the next PATCH to /users returns `[]` — simulating the
  /// RLS denial where PostgREST silently affects 0 rows.
  var failNextPatch = false;

  /// Same for the next PATCH to /payments (doctor-side status flip).
  var failNextPaymentPatch = false;

  late SupabaseService supabase;
  late AuthService auth;

  setUpAll(() async {
    // supabase_flutter's auth persistence uses shared_preferences, and
    // AuthService's session cache uses flutter_secure_storage — mock both
    // before initializing so no platform channels are touched.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    final client = MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      // Attach the incoming request to every response: postgrest reads
      // `response.request!.method`, and MockClient only copies whatever
      // `request` field the returned Response carries.
      http.Response respond(String body, {int status = 200}) => http.Response(
        body,
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
        request: request,
      );
      if (path.endsWith('/auth/v1/settings')) {
        return respond(
          jsonEncode({
            'external': {'enabled': false},
            'mailer': {'enabled': false},
            'phone': {'enabled': false},
            'sms': {'enabled': false},
            'mfa': {'enabled': false},
            'password': {'enabled': false},
            'sessions': {'enabled': false},
          }),
        );
      }
      if (path.contains('/rest/v1/users')) {
        if (request.method == 'PATCH') {
          if (failNextPatch) {
            failNextPatch = false;
            return respond('[]');
          }
          // A successful PATCH returns the updated row — echo the
          // (already-capitalized) name from the request body.
          final name =
              (jsonDecode(request.body) as Map<String, dynamic>)['name'];
          return respond(
            jsonEncode([
              {'id': 'user_123', 'name': name, 'mobile': '9876543210'},
            ]),
          );
        }
        return respond('[]');
      }
      if (path.contains('/rest/v1/payments')) {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return respond(jsonEncode([body]));
        }
        if (request.method == 'PATCH') {
          if (failNextPaymentPatch) {
            failNextPaymentPatch = false;
            return respond('[]');
          }
          // A successful PATCH returns the updated row — PostgREST
          // materializes it through the doctor SELECT policy.
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return respond(jsonEncode([{'id': 'pay_abc', ...body}]));
        }
        return respond('[]');
      }
      return respond('{}');
    });

    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-anon-key',
      httpClient: client,
    );

    supabase = SupabaseService();
    auth = AuthService();
  });

  setUp(() {
    requests.clear();
    failNextPatch = false;
    failNextPaymentPatch = false;
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SupabaseService.updateUserName', () {
    test('PATCHes the users row with the capitalized name and BOTH RLS '
        'headers', () async {
      final ok = await supabase.updateUserName(
        'user_123',
        '9876543210',
        'rahul sharma',
      );
      expect(ok, isTrue);

      final patch = requests.singleWhere(
        (r) => r.method == 'PATCH' && r.url.path.contains('/rest/v1/users'),
      );

      // RLS scoping: the row is addressed by id. BOTH headers are
      // required — supabase-dart requests return=representation, so
      // PostgREST materializes the row through the SELECT policy and an
      // x-user-id-only PATCH silently affects 0 rows.
      expect(patch.url.queryParameters['id'], 'eq.user_123');
      expect(patch.headers['x-user-id'], 'user_123');
      expect(patch.headers['x-user-mobile'], '9876543210');

      // The name is capitalized before it reaches the DB.
      expect(jsonDecode(patch.body), {'name': 'Rahul Sharma'});
    });

    test('returns false when the PATCH affects 0 rows (RLS denial)', () async {
      failNextPatch = true;
      final ok = await supabase.updateUserName(
        'user_123',
        '9876543210',
        'rahul sharma',
      );
      expect(ok, isFalse);
    });

    test('restores the original client headers after the call', () async {
      await supabase.updateUserName('user_123', '9876543210', 'rahul sharma');

      // No stale RLS context may leak onto later requests.
      expect(
        Supabase.instance.client.headers.containsKey('x-user-id'),
        isFalse,
      );
      expect(
        Supabase.instance.client.headers.containsKey('x-user-mobile'),
        isFalse,
      );
    });
  });

  group('sibling users-table UPDATEs (same RLS bug class)', () {
    test('saveUserNotificationPrefs sends BOTH RLS headers so the prefs '
        'update lands', () async {
      await supabase.saveUserNotificationPrefs(
        'user_123',
        '9876543210',
        {'appointment_booked': false},
      );

      final patch = requests.singleWhere(
        (r) => r.method == 'PATCH' && r.url.path.contains('/rest/v1/users'),
      );
      expect(patch.headers['x-user-id'], 'user_123');
      expect(patch.headers['x-user-mobile'], '9876543210');
      expect(
        jsonDecode(patch.body),
        {'notification_prefs': {'appointment_booked': false}},
      );
    });

    test('updateUserRole sends BOTH RLS headers so the role update lands',
        () async {
      await supabase.updateUserRole(
        'user_123',
        '9876543210',
        'doctor',
        doctorPlaceId: 'place_9',
      );

      final patch = requests.singleWhere(
        (r) => r.method == 'PATCH' && r.url.path.contains('/rest/v1/users'),
      );
      expect(patch.headers['x-user-id'], 'user_123');
      expect(patch.headers['x-user-mobile'], '9876543210');
      expect(
        jsonDecode(patch.body),
        {'role': 'doctor', 'doctor_place_id': 'place_9'},
      );
    });
  });

  group('SupabaseService.createPayment (payments RLS header contract)', () {
    test('sends the x-user-id header so the payments INSERT policy accepts '
        'it', () async {
      await supabase.createPayment('user_123', {
        'appointment_id': 'APT123',
        'patient_id': 'user_123',
        'payment_status': 'Paid',
        'payment_method': 'online',
        'amount': 800,
      });

      final insert = requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.contains('/rest/v1/payments'),
      );
      expect(insert.headers['x-user-id'], 'user_123');
      expect(jsonDecode(insert.body), {
        'appointment_id': 'APT123',
        'patient_id': 'user_123',
        'payment_status': 'Paid',
        'payment_method': 'online',
        'amount': 800,
      });
    });

    test('restores the client headers so no x-user-id leaks onto later '
        'requests', () async {
      await supabase.createPayment('user_123', {
        'appointment_id': 'APT123',
        'patient_id': 'user_123',
      });

      expect(
        Supabase.instance.client.headers.containsKey('x-user-id'),
        isFalse,
      );
    });

    test('getPaymentsForUser reads with the x-user-id header', () async {
      final rows = await supabase.getPaymentsForUser('user_123');
      expect(rows, isEmpty);

      final select = requests.singleWhere(
        (r) => r.method == 'GET' && r.url.path.contains('/rest/v1/payments'),
      );
      expect(select.headers['x-user-id'], 'user_123');
    });
  });

  group('SupabaseService doctor payment actions (payments doctor RLS)', () {
    test('updatePaymentStatus PATCHes the payment with the x-user-id header '
        'and the app payload (status + paid_at + updated_at)', () async {
      final ok = await supabase.updatePaymentStatus(
        'user_123',
        'pay_abc',
        status: 'Paid',
        paidAt: DateTime.utc(2026, 8, 9, 12),
      );
      expect(ok, isTrue);

      final patch = requests.singleWhere(
        (r) => r.method == 'PATCH' && r.url.path.contains('/rest/v1/payments'),
      );
      // The doctor UPDATE RLS policy is scoped to the x-user-id header.
      expect(patch.headers['x-user-id'], 'user_123');
      expect(patch.url.queryParameters['id'], 'eq.pay_abc');
      final body = jsonDecode(patch.body) as Map<String, dynamic>;
      expect(body['payment_status'], 'Paid');
      expect(body['paid_at'], '2026-08-09T12:00:00.000Z');
      expect(body.containsKey('updated_at'), isTrue);
    });

    test('updatePaymentStatus omits paid_at for non-Paid statuses', () async {
      final ok = await supabase.updatePaymentStatus(
        'user_123',
        'pay_abc',
        status: 'Refunded',
      );
      expect(ok, isTrue);

      final patch = requests.singleWhere(
        (r) => r.method == 'PATCH' && r.url.path.contains('/rest/v1/payments'),
      );
      final body = jsonDecode(patch.body) as Map<String, dynamic>;
      expect(body['payment_status'], 'Refunded');
      expect(body.containsKey('paid_at'), isFalse);
    });

    test('updatePaymentStatus returns false when the PATCH affects 0 rows '
        '(RLS denial)', () async {
      failNextPaymentPatch = true;
      final ok = await supabase.updatePaymentStatus(
        'user_123',
        'pay_abc',
        status: 'Paid',
      );
      expect(ok, isFalse);
    });

    test('getPaymentsForDoctor reads payments with the x-user-id header',
        () async {
      final rows = await supabase.getPaymentsForDoctor('user_123');
      expect(rows, isEmpty);

      final select = requests.singleWhere(
        (r) => r.method == 'GET' && r.url.path.contains('/rest/v1/payments'),
      );
      // The doctor SELECT RLS policy scopes by the same header.
      expect(select.headers['x-user-id'], 'user_123');
    });
  });

  group('AuthService.updateName', () {
    test('trims + capitalizes the name and returns the updated model', () async {
      final updated = await auth.updateName(
        userPatient(id: 'user_123', name: 'old name'),
        '  rahul   sharma  ',
      );

      expect(updated.id, 'user_123');
      expect(updated.mobile, '9876543210');
      expect(updated.name, 'Rahul Sharma');
    });

    test('persists the updated session locally so a restart sees the new '
        'name', () async {
      await auth.updateName(userPatient(id: 'user_123'), 'dr. rahul sharma');

      // A fresh service reads from the same mocked secure storage.
      final reloaded = await AuthService().getCurrentUser();
      expect(reloaded?.id, 'user_123');
      expect(reloaded?.name, 'Dr. Rahul Sharma');
    });

    test('still sends the RLS-scoped, capitalized update to Supabase with '
        'both headers', () async {
      await auth.updateName(
        userPatient(id: 'user_123', name: 'old'),
        'rahul sharma',
      );

      final patch = requests.singleWhere(
        (r) => r.method == 'PATCH' && r.url.path.contains('/rest/v1/users'),
      );
      expect(patch.headers['x-user-id'], 'user_123');
      expect(patch.headers['x-user-mobile'], '9876543210');
      expect(jsonDecode(patch.body), {'name': 'Rahul Sharma'});
    });

    test('throws when the DB update does not land (RLS denial) so the UI '
        'never claims success', () async {
      failNextPatch = true;
      expect(
        () => auth.updateName(
          userPatient(id: 'user_123', name: 'old'),
          'rahul sharma',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('throws when the user has no id instead of silently skipping the '
        'DB', () async {
      expect(
        () => auth.updateName(
          userPatient(id: null, name: 'x'),
          '  john   doe  ',
        ),
        throwsA(isA<AuthException>()),
      );
      // No PATCH was attempted.
      expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
    });
  });
}
