import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesStore {
  static const _languageKey = 'preferred_language';
  static const _accountModePrefix = 'active_account_mode_';

  Future<String?> language() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_languageKey);
    return const {'en', 'fi', 'sv'}.contains(value) ? value : null;
  }

  Future<void> setLanguage(String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, languageCode);
  }

  Future<String?> accountMode(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString('$_accountModePrefix$uid');
  }

  Future<void> setAccountMode(String uid, String mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('$_accountModePrefix$uid', mode);
  }
}
