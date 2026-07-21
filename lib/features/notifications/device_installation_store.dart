import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceInstallationStore {
  static const _key = 'frsh_device_installation_id';

  Future<String> id() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final generated =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await preferences.setString(_key, generated);
    return generated;
  }
}
