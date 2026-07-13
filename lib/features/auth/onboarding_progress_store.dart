import 'package:shared_preferences/shared_preferences.dart';

class OnboardingProgressStore {
  static const _prefix = 'onboarding_complete_';

  Future<bool> isComplete(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('$_prefix$uid') ?? false;
  }

  Future<void> markComplete(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_prefix$uid', true);
  }
}
