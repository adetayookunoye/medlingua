/// Supported languages for MedLingua
class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final String sttLocale; // speech-to-text locale code

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.sttLocale,
  });
}

class SupportedLanguages {
  static const List<AppLanguage> all = [
    AppLanguage(code: 'en', name: 'English', nativeName: 'English', sttLocale: 'en-US'),
    AppLanguage(code: 'pcm', name: 'Pidgin', nativeName: 'Naija Pidgin', sttLocale: 'en-NG'),
    AppLanguage(code: 'ha', name: 'Hausa', nativeName: 'Hausa', sttLocale: 'ha-NG'),
    AppLanguage(code: 'yo', name: 'Yoruba', nativeName: 'Yorùbá', sttLocale: 'yo-NG'),
    AppLanguage(code: 'tw', name: 'Twi', nativeName: 'Akan Twi', sttLocale: 'ak-GH'),
    AppLanguage(code: 'sw', name: 'Swahili', nativeName: 'Kiswahili', sttLocale: 'sw-KE'),
    AppLanguage(code: 'fr', name: 'French', nativeName: 'Français', sttLocale: 'fr-FR'),
    AppLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', sttLocale: 'hi-IN'),
    AppLanguage(code: 'bn', name: 'Bengali', nativeName: 'বাংলা', sttLocale: 'bn-IN'),
    AppLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português', sttLocale: 'pt-BR'),
    AppLanguage(code: 'es', name: 'Spanish', nativeName: 'Español', sttLocale: 'es-ES'),
    AppLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية', sttLocale: 'ar-SA'),
  ];

  static AppLanguage getByCode(String code) {
    return all.firstWhere(
      (lang) => lang.code == code,
      orElse: () => all.first,
    );
  }
}
