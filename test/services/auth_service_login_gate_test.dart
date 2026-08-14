import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/services/auth_service.dart';
import 'package:DrsListing/services/supabase_service.dart';

/// Test double for SupabaseService: returns a canned users row for
/// [getUserByMobile] without touching any platform channel.
class _FakeSupabaseService extends SupabaseService {
  _FakeSupabaseService(this.row) : super.testing();

  final Map<String, dynamic>? row;

  @override
  Future<Map<String, dynamic>?> getUserByMobile(String mobile) async => row;
}

void main() {
  group('AuthService.login inactive-account gate', () {
    test('blocks login with the support message when is_active is false',
        () async {
      final service = AuthService.testing(
        supabase: _FakeSupabaseService({
          'id': 'user_inactive',
          'name': 'Blocked User',
          'mobile': '9876543210',
          'role': 'patient',
          'is_active': false,
        }),
      );

      await expectLater(
        service.login('9876543210'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.code, 'code', 'account_inactive')
              .having(
                (e) => e.message,
                'message',
                AuthService.inactiveMessage,
              ),
        ),
      );
    });

    test('allows login when is_active is true', () async {
      final service = AuthService.testing(
        supabase: _FakeSupabaseService({
          'id': 'user_active',
          'name': 'Active User',
          'mobile': '9876543210',
          'role': 'patient',
          'is_active': true,
        }),
      );

      final user = await service.login('9876543210');
      expect(user, isNotNull);
      expect(user!.id, 'user_active');
      expect(user.isActive, isTrue);
    });

    test('returns null when the mobile is not registered', () async {
      final service = AuthService.testing(
        supabase: _FakeSupabaseService(null),
      );
      expect(await service.login('9999999999'), isNull);
    });
  });
}
