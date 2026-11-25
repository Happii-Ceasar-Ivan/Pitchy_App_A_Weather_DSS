import 'package:shared_preferences/shared_preferences.dart';

/// Small on-device preferences: theme choice, the active match, the match
/// setup draft and the Ask Pitchy role. Never secrets (the chat session token
/// lives in memory only, F4) and never weather data (that is the DEC-13 saved
/// copy, F5).
abstract interface class Preferences {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// Keys, in one place so nothing collides.
abstract final class PrefKeys {
  static const themeMode = 'theme.mode';
  static const lastLightMode = 'theme.lastLight';
  static const customShell = 'theme.customShell';
  static const customAccent = 'theme.customAccent';
  static const activeMatchId = 'match.activeId';
  static const matchDraft = 'match.draft';

  /// The Ask Pitchy role (P-03). A conversational context, not an account.
  static const chatRole = 'chat.role';
}

class SharedPreferencesStore implements Preferences {
  SharedPreferencesStore(this._prefs);

  static Future<SharedPreferencesStore> open() async =>
      SharedPreferencesStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// In-memory preferences for tests and previews.
class MemoryPreferences implements Preferences {
  MemoryPreferences([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
