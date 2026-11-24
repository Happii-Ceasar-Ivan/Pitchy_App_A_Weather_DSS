import 'package:material_ui/material_ui.dart';

import '../storage/preferences.dart';
import 'pitchy_palette.dart';

/// Holds the user's theme choice and saves it on the device (P-13, P-17).
///
/// The Quick Settings switch toggles between the "light family" (Light, Pitch
/// Green or Custom) and Dark; switching back to light returns to whichever
/// light-family theme was last active.
class ThemeController extends ChangeNotifier {
  ThemeController({Preferences? preferences}) : _prefs = preferences {
    final p = _prefs;
    if (p == null) return;
    _mode = _modeNamed(p.getString(PrefKeys.themeMode)) ?? _mode;
    final last = _modeNamed(p.getString(PrefKeys.lastLightMode));
    if (last != null && last != PitchyThemeMode.dark) _lastLight = last;
    _customShell = _swatchNamed(p.getString(PrefKeys.customShell)) ?? _customShell;
    _customAccent = _swatchNamed(p.getString(PrefKeys.customAccent)) ?? _customAccent;
  }

  final Preferences? _prefs;

  PitchyThemeMode _mode = PitchyThemeMode.light;
  PitchyThemeMode _lastLight = PitchyThemeMode.light;
  CustomSwatch _customShell = customSwatches[0];
  CustomSwatch _customAccent = customSwatches[3];

  PitchyThemeMode get mode => _mode;
  CustomSwatch get customShell => _customShell;
  CustomSwatch get customAccent => _customAccent;
  bool get isDark => _mode == PitchyThemeMode.dark;

  /// The light-family theme the switch returns to.
  PitchyThemeMode get lastLight => _lastLight;

  PitchyPalette get palette => switch (_mode) {
    PitchyThemeMode.light => PitchyPalette.light,
    PitchyThemeMode.dark => PitchyPalette.dark,
    PitchyThemeMode.pitchGreen => PitchyPalette.pitchGreen,
    PitchyThemeMode.custom => PitchyPalette.custom(
      shell: _customShell.color,
      accent: _customAccent.color,
    ),
  };

  void setMode(PitchyThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    if (mode != PitchyThemeMode.dark) _lastLight = mode;
    _save();
    notifyListeners();
  }

  /// The Quick Settings switch (P-17).
  void setDark(bool dark) => setMode(dark ? PitchyThemeMode.dark : _lastLight);

  /// Only colours from [customSwatches] are accepted.
  void setCustom({CustomSwatch? shell, CustomSwatch? accent}) {
    assert(shell == null || customSwatches.contains(shell));
    assert(accent == null || customSwatches.contains(accent));
    _customShell = shell ?? _customShell;
    _customAccent = accent ?? _customAccent;
    _save();
    notifyListeners();
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    // Fire and forget: a failed write only loses the preference, never data.
    p.setString(PrefKeys.themeMode, _mode.name);
    p.setString(PrefKeys.lastLightMode, _lastLight.name);
    p.setString(PrefKeys.customShell, _customShell.name);
    p.setString(PrefKeys.customAccent, _customAccent.name);
  }

  static PitchyThemeMode? _modeNamed(String? name) {
    for (final m in PitchyThemeMode.values) {
      if (m.name == name) return m;
    }
    return null;
  }

  static CustomSwatch? _swatchNamed(String? name) {
    for (final s in customSwatches) {
      if (s.name == name) return s;
    }
    return null;
  }
}
