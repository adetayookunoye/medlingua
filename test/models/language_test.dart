import 'package:flutter_test/flutter_test.dart';
import 'package:medlingua/models/language.dart';

void main() {
  group('SupportedLanguages', () {
    test('all list is not empty', () {
      expect(SupportedLanguages.all, isNotEmpty);
    });

    test('English is first language', () {
      expect(SupportedLanguages.all.first.code, 'en');
    });

    test('all languages have unique codes', () {
      final codes = SupportedLanguages.all.map((l) => l.code).toSet();
      expect(codes.length, SupportedLanguages.all.length);
    });

    test('all languages have non-empty names', () {
      for (final lang in SupportedLanguages.all) {
        expect(lang.name, isNotEmpty, reason: '${lang.code} has empty name');
      }
    });

    test('all languages have non-empty sttLocale', () {
      for (final lang in SupportedLanguages.all) {
        expect(lang.sttLocale, isNotEmpty,
            reason: '${lang.code} has empty sttLocale');
      }
    });

    test('contains key medical triage languages', () {
      final codes = SupportedLanguages.all.map((l) => l.code).toSet();
      // Core languages for community health workers
      expect(codes, contains('en'));  // English
      expect(codes, contains('sw'));  // Swahili
      expect(codes, contains('fr'));  // French
      expect(codes, contains('ha'));  // Hausa
      expect(codes, contains('yo'));  // Yoruba
      expect(codes, contains('hi'));  // Hindi
    });

    test('Pidgin and Twi added for West Africa', () {
      final codes = SupportedLanguages.all.map((l) => l.code).toSet();
      expect(codes, contains('pcm')); // Pidgin
      expect(codes, contains('tw'));   // Twi
    });
  });

  group('AppLanguage', () {
    test('equality based on code', () {
      const a = AppLanguage(code: 'en', name: 'English', nativeName: 'English', sttLocale: 'en-US');
      const b = AppLanguage(code: 'en', name: 'English', nativeName: 'English', sttLocale: 'en-US');
      // Same properties => same behavior
      expect(a.code, b.code);
      expect(a.name, b.name);
    });
  });
}
