import 'package:shared_preferences/shared_preferences.dart';

mixin PreferencesMixin {
  Future<void> savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    bool saved;
    if (value is bool) {
      saved = await prefs.setBool(key, value);
    } else if (value is double) {
      saved = await prefs.setDouble(key, value);
    } else if (value is int) {
      saved = await prefs.setInt(key, value);
    } else if (value is String) {
      saved = await prefs.setString(key, value);
    } else if (value is List<String>) {
      saved = await prefs.setStringList(key, value);
    } else {
      throw ArgumentError.value(value, key, 'Unsupported preference type');
    }
    if (!saved) throw StateError('Unable to save setting: $key');
  }

  Future<T?> getPreference<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(key)) {
      if (T == bool) {
        return prefs.getBool(key) as T;
      } else if (T == double) {
        return prefs.getDouble(key) as T;
      } else if (T == int) {
        return prefs.getInt(key) as T;
      } else if (T == String) {
        return prefs.getString(key) as T;
      } else if (T == List<String>) {
        return prefs.getStringList(key) as T;
      }
    }
    return null;
  }

  Future<void> deletePreference(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(key)) {
      await prefs.remove(key);
    }
  }
}
