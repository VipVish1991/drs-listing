import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/services/supabase_service.dart';

/// Verifies the RLS scoping contract for the `users` table.
///
/// The anon-key app must attach `x-user-mobile` (SELECT/INSERT) and
/// `x-user-id` (UPDATE) request headers so the header-scoped RLS policies
/// in supabase/migrations/20260801000001_tighten_users_rls.sql see the
/// caller's own row. These tests pin that exact header contract so a
/// future rename doesn't silently break login/registration.
void main() {
  group('usersContextHeaders', () {
    test('returns an empty map when nothing is provided', () {
      expect(usersContextHeaders(), isEmpty);
    });

    test('maps mobile to x-user-mobile only', () {
      expect(
        usersContextHeaders(mobile: '9876543210'),
        {'x-user-mobile': '9876543210'},
      );
    });

    test('maps userId to x-user-id only', () {
      expect(
        usersContextHeaders(userId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
        {'x-user-id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'},
      );
    });

    test('includes both headers when both are provided', () {
      expect(
        usersContextHeaders(mobile: '9876543210', userId: 'uuid-1'),
        {'x-user-mobile': '9876543210', 'x-user-id': 'uuid-1'},
      );
    });

    test('does not include stale values across calls', () {
      final withMobile = usersContextHeaders(mobile: '9876543210');
      expect(withMobile.containsKey('x-user-id'), isFalse);

      final withId = usersContextHeaders(userId: 'uuid-2');
      expect(withId.containsKey('x-user-mobile'), isFalse);
    });
  });
}
