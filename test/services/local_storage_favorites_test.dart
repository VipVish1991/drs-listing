import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:DrsListing/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().init();
  });

  test('favorites are isolated per user id', () async {
    final storage = LocalStorageService();

    await storage.saveFavoriteDoctor(
      {'place_id': 'doc_a', 'name': 'Doc A'},
      userId: 'user_a',
    );
    await storage.saveFavoriteDoctor(
      {'place_id': 'doc_b', 'name': 'Doc B'},
      userId: 'user_b',
    );

    // Each user sees exactly their own saved doctor.
    final userAList = storage.getFavoriteDoctorsList(userId: 'user_a');
    expect(userAList.length, 1);
    expect(userAList.single['place_id'], 'doc_a');

    final userBList = storage.getFavoriteDoctorsList(userId: 'user_b');
    expect(userBList.length, 1);
    expect(userBList.single['place_id'], 'doc_b');

    // The anonymous (logged-out) bucket stays untouched.
    expect(storage.getFavoriteDoctorsList(), isEmpty);
  });

  test('same user accumulates; removing only affects that user', () async {
    final storage = LocalStorageService();

    await storage.saveFavoriteDoctor({'place_id': 'doc_x'}, userId: 'u1');
    await storage.saveFavoriteDoctor({'place_id': 'doc_y'}, userId: 'u1');
    expect(storage.favoriteDoctorsCount(userId: 'u1'), 2);

    await storage.removeFavoriteDoctor('doc_x', userId: 'u1');
    expect(storage.favoriteDoctorsCount(userId: 'u1'), 1);
    expect(storage.getFavoriteDoctors(userId: 'u1').containsKey('doc_y'), isTrue);

    // Removing under user u1 doesn't touch user u2's list.
    await storage.saveFavoriteDoctor({'place_id': 'doc_z'}, userId: 'u2');
    expect(storage.favoriteDoctorsCount(userId: 'u2'), 1);
    expect(storage.favoriteDoctorsCount(userId: 'u1'), 1);
  });

  test('last logged-in mobile round-trips', () async {
    final storage = LocalStorageService();
    expect(storage.getLastLoggedInMobile(), isNull);

    await storage.setLastLoggedInMobile('9876543210');
    expect(storage.getLastLoggedInMobile(), '9876543210');
  });
}
