// The themed palette (Line Board world). Only these roles change between
// Light, Dark, Pitch Green and Custom. Data-state and safety colours live in
// fixed_colors.dart and never change.

import 'package:material_ui/material_ui.dart';

/// Which theme the user picked in Settings (P-13).
enum PitchyThemeMode {
  light('Light'),
  dark('Dark'),
  pitchGreen('Pitch Green'),
  custom('Custom');

  const PitchyThemeMode(this.label);
  final String label;
}

/// A colour users may pick for the Custom theme. The set is fixed so every
/// combination keeps readable contrast with white text on the shell.
@immutable
class CustomSwatch {
  const CustomSwatch(this.name, this.color);

  final String name;
  final Color color;
}

/// Fixed set for the Custom theme (provisional until confirmed with the team).
/// Each colour passes 4.5:1 against white. No reds, oranges or yellows, so a
/// themed colour can never be mistaken for a safety colour.
const customSwatches = <CustomSwatch>[
  CustomSwatch('Navy', Color(0xFF0F2540)),
  CustomSwatch('Pitch green', Color(0xFF0E3B2E)),
  CustomSwatch('Teal', Color(0xFF0E5E55)),
  CustomSwatch('Royal blue', Color(0xFF1C4FB0)),
  CustomSwatch('Violet', Color(0xFF4E3497)),
  CustomSwatch('Plum', Color(0xFF6A2C63)),
  CustomSwatch('Slate', Color(0xFF33404F)),
  CustomSwatch('Charcoal', Color(0xFF1F2328)),
];

@immutable
class PitchyPalette extends ThemeExtension<PitchyPalette> {
  const PitchyPalette({
    required this.brightness,
    required this.shell,
    required this.shellRaised,
    required this.onShell,
    required this.onShellMuted,
    required this.ground,
    required this.surface,
    required this.hairline,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.onAccent,
    required this.lines,
  });

  final Brightness brightness;

  /// Top bar, kickoff strip and navigation rail.
  final Color shell;
  final Color shellRaised;
  final Color onShell;
  final Color onShellMuted;

  /// Work area behind cards.
  final Color ground;
  final Color surface;

  /// The one rule weight's colour (1 logical pixel everywhere).
  final Color hairline;
  final Color ink;
  final Color inkMuted;

  /// Primary actions, links and selection.
  final Color accent;
  final Color onAccent;

  /// Fixed line colour per weather source id (the board's lines). Cool hues only.
  final Map<String, Color> lines;

  Color lineFor(String sourceId) => lines[sourceId] ?? inkMuted;

  static const _lightLines = {
    'open_meteo': Color(0xFF13786A),
    'pagasa_atmo': Color(0xFF5E3FB0),
    'pagasa_ecmwf': Color(0xFF2361D6),
    'dost_asti': Color(0xFF52606F),
  };

  static const _darkLines = {
    'open_meteo': Color(0xFF52C7B4),
    'pagasa_atmo': Color(0xFFB39CF5),
    'pagasa_ecmwf': Color(0xFF7FA8F5),
    'dost_asti': Color(0xFF9AA8B8),
  };

  static const light = PitchyPalette(
    brightness: Brightness.light,
    shell: Color(0xFF0F2540),
    shellRaised: Color(0xFF16304F),
    onShell: Color(0xFFFFFFFF),
    onShellMuted: Color(0xFFCAD6E4),
    ground: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    hairline: Color(0xFFD3DAE3),
    ink: Color(0xFF0F2540),
    inkMuted: Color(0xFF45556B),
    accent: Color(0xFF1F5FCC),
    onAccent: Color(0xFFFFFFFF),
    lines: _lightLines,
  );

  static const dark = PitchyPalette(
    brightness: Brightness.dark,
    shell: Color(0xFF07111F),
    shellRaised: Color(0xFF0D1B2E),
    onShell: Color(0xFFF2F5F9),
    onShellMuted: Color(0xFFAAB8CA),
    ground: Color(0xFF0B1626),
    surface: Color(0xFF122238),
    hairline: Color(0xFF2B3E58),
    ink: Color(0xFFEAF0F7),
    inkMuted: Color(0xFFAAB8CA),
    accent: Color(0xFF8CB2FF),
    onAccent: Color(0xFF07111F),
    lines: _darkLines,
  );

  static const pitchGreen = PitchyPalette(
    brightness: Brightness.light,
    shell: Color(0xFF0E3B2E),
    shellRaised: Color(0xFF15483A),
    onShell: Color(0xFFFFFFFF),
    onShellMuted: Color(0xFFC6DCD3),
    ground: Color(0xFFF2F6F3),
    surface: Color(0xFFFFFFFF),
    hairline: Color(0xFFCFDCD5),
    ink: Color(0xFF0C2A21),
    inkMuted: Color(0xFF3F5A50),
    accent: Color(0xFF0E6B52),
    onAccent: Color(0xFFFFFFFF),
    lines: _lightLines,
  );

  /// Custom theme: the user's two picks become the shell and the accent; every
  /// other role stays as in Light so contrast is guaranteed.
  factory PitchyPalette.custom({required Color shell, required Color accent}) => PitchyPalette(
    brightness: Brightness.light,
    shell: shell,
    shellRaised: Color.alphaBlend(Colors.white.withValues(alpha: 0.08), shell),
    onShell: Colors.white,
    onShellMuted: Color.alphaBlend(Colors.white.withValues(alpha: 0.78), shell),
    ground: light.ground,
    surface: light.surface,
    hairline: light.hairline,
    ink: light.ink,
    inkMuted: light.inkMuted,
    accent: accent,
    onAccent: Colors.white,
    lines: _lightLines,
  );

  @override
  PitchyPalette copyWith() => this;

  @override
  PitchyPalette lerp(PitchyPalette? other, double t) => t < 0.5 || other == null ? this : other;
}
