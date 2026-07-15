import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OnboardingDraftStore {
  static const _prefix = 'frsh_onboarding_draft_v1_';

  Future<Map<String, dynamic>?> load(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_prefix$uid');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      await preferences.remove('$_prefix$uid');
      return null;
    }
  }

  Future<void> save(String uid, Map<String, dynamic> draft) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_prefix$uid',
      jsonEncode({
        ...draft,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> clear(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_prefix$uid');
  }
}
