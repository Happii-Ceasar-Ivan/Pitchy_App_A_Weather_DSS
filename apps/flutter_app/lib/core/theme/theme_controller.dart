import 'package:material_ui/material_ui.dart';

import 'pitchy_palette.dart';

/// Holds the user's theme choice. In memory for F0; saved on the device with the
/// other preferences once Settings is built (F1).
class ThemeController extends ChangeNotifier {
  ThemeController({CustomSwatch? customShell, CustomSwatch? customAccent})
    : _customShell = customShell ?? customSwatches[0],
      _customAccent = customAccent ?? customSwatches[3];

  PitchyThemeMode _mode = PitchyThemeMode.light;
  CustomSwatch _customShell;
  CustomSwatch _customAccent;

  PitchyThemeMode get mode => _mode;
  CustomSwatch get customShell => _customShell;
  CustomSwatch get customAccent => _customAccent;

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
    notifyListeners();
  }

  /// Only colours from [customSwatches] are accepted.
  void setCustom({CustomSwatch? shell, CustomSwatch? accent}) {
    assert(shell == null || customSwatches.contains(shell));
    assert(accent == null || customSwatches.contains(accent));
    _customShell = shell ?? _customShell;
    _customAccent = accent ?? _customAccent;
    notifyListeners();
  }
}
