import 'package:flutter_test/flutter_test.dart';
import 'package:DrsListing/models/user_model.dart';

void main() {
  group('UserModel.isActive', () {
    test('defaults to true when the column is missing (legacy rows)', () {
      final user = UserModel.fromJson({
        'id': 'u1',
        'name': 'Jane',
        'mobile': '9876543210',
        'role': 'patient',
      });
      expect(user.isActive, isTrue);
    });

    test('parses is_active: true as active', () {
      final user = UserModel.fromJson({
        'id': 'u1',
        'name': 'Jane',
        'mobile': '9876543210',
        'role': 'patient',
        'is_active': true,
      });
      expect(user.isActive, isTrue);
    });

    test('parses is_active: false as inactive', () {
      final user = UserModel.fromJson({
        'id': 'u1',
        'name': 'Jane',
        'mobile': '9876543210',
        'role': 'patient',
        'is_active': false,
      });
      expect(user.isActive, isFalse);
    });

    test('constructor defaults to active', () {
      expect(UserModel().isActive, isTrue);
      expect(
        UserModel(isActive: false).isActive,
        isFalse,
      );
    });

    test('toJson round-trips is_active', () {
      final active = UserModel.fromJson({
        'id': 'u1',
        'name': 'Jane',
        'mobile': '9876543210',
        'role': 'patient',
        'is_active': true,
      });
      expect(active.toJson()['is_active'], isTrue);

      final inactive = UserModel.fromJson({
        'id': 'u1',
        'name': 'Jane',
        'mobile': '9876543210',
        'role': 'patient',
        'is_active': false,
      });
      expect(inactive.toJson()['is_active'], isFalse);
    });

    test('copyWith can toggle isActive', () {
      final user = UserModel(isActive: true);
      expect(user.copyWith(isActive: false).isActive, isFalse);
      expect(user.copyWith(isActive: false).copyWith(isActive: true).isActive,
          isTrue);
    });
  });
}
