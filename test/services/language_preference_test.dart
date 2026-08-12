import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:DrsListing/config/constants.dart';
import 'package:DrsListing/services/local_storage_service.dart';

/// Guards the language-preferences fix: the stored language code must be
/// normalized to a full locale code from [AppConstants.supportedLanguages]
/// (a bare `'en'` default previously never matched the picker's `'en-IN'`
/// option, so the language picker showed nothing selected on first launch).
void main() {
  group('LocalStorageService.getPreferredLanguage', () {
    late LocalStorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = LocalStorageService();
      await storage.init();
    });

    test('returns the Hindi default (hi-IN) when nothing has been stored yet',
        () {
      expect(storage.getPreferredLanguage(), 'hi-IN');
    });

    test('normalizes a bare en code to the full en-IN locale', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preferred_language', 'en');

      expect(storage.getPreferredLanguage(), 'en-IN');
    });

    test('returns the stored full locale code unchanged', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preferred_language', 'hi-IN');

      expect(storage.getPreferredLanguage(), 'hi-IN');
    });
  });

  group('AppConstants.resolveLanguageCode', () {
    test('matches a bare language code to its full locale', () {
      expect(AppConstants.resolveLanguageCode('en'), 'en-IN');
      expect(AppConstants.resolveLanguageCode('hi'), 'hi-IN');
      expect(AppConstants.resolveLanguageCode('mr'), 'mr-IN');
      expect(AppConstants.resolveLanguageCode('gu'), 'gu-IN');
    });

    test('returns full locale codes unchanged', () {
      expect(AppConstants.resolveLanguageCode('en-IN'), 'en-IN');
      expect(AppConstants.resolveLanguageCode('hi-IN'), 'hi-IN');
    });

    test('falls back to en-IN for unknown or empty codes', () {
      expect(AppConstants.resolveLanguageCode('fr'), 'en-IN');
      expect(AppConstants.resolveLanguageCode('xx-XX'), 'en-IN');
      expect(AppConstants.resolveLanguageCode(''), 'en-IN');
      expect(AppConstants.resolveLanguageCode(null), 'en-IN');
    });

    test('every supported language resolves to itself', () {
      for (final lang in AppConstants.supportedLanguages) {
        expect(
          AppConstants.resolveLanguageCode(lang['code']),
          lang['code'],
          reason: '${lang['code']} should resolve to itself',
        );
      }
    });
  });

  group('AppConstants.resolveLanguageName', () {
    test('returns the friendly name for stored locale codes', () {
      expect(AppConstants.resolveLanguageName('en-IN'), 'English');
      expect(AppConstants.resolveLanguageName('hi-IN'), 'हिन्दी');
    });

    test('falls back to the uppercased raw code for unknown values', () {
      expect(AppConstants.resolveLanguageName('fr'), 'FR');
      expect(AppConstants.resolveLanguageName(null), 'EN-IN');
    });
  });
}
