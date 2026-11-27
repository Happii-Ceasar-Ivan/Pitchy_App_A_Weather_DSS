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

/// Fixed set for the Custom theme (approved by the team, P-16).
/// Each colour passes 4.5:1 against white. No reds, oranges or yellows, so a
/// themed colour can never be mistaken for a safety colour.
const customSwatches = <CustomSwatch>[
  // Midnight Navy, the default theme's shell (P-16 update, P-28, 2026-11-27).
  CustomSwatch('Navy', Color(0xFF031A31)),
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
    required this.onShellAccent,
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

  /// Selection and focus on the shell (rail indicator icon and label, focus
  /// ring on navy). Glacier in Light and Dark; plain onShell elsewhere.
  final Color onShellAccent;

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

  /// Midnight Navy and Glacier (P-28). Glacier is 2.09:1 on white, so light
  /// surfaces use Glacier Deep, a darker tone of the same hue (7.35:1).
  static const light = PitchyPalette(
    brightness: Brightness.light,
    shell: Color(0xFF031A31),
    shellRaised: Color(0xFF0B2742),
    onShell: Color(0xFFFFFFFF),
    onShellMuted: Color(0xFFC3D3E2),
    onShellAccent: Color(0xFF8BB9D9),
    ground: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    hairline: Color(0xFFD3DAE3),
    ink: Color(0xFF031A31),
    inkMuted: Color(0xFF45556B),
    accent: Color(0xFF1D5A86),
    onAccent: Color(0xFFFFFFFF),
    lines: _lightLines,
  );

  static const dark = PitchyPalette(
    brightness: Brightness.dark,
    shell: Color(0xFF020F1E),
    shellRaised: Color(0xFF0A1F36),
    onShell: Color(0xFFF2F5F9),
    onShellMuted: Color(0xFFA6B6C8),
    onShellAccent: Color(0xFF8BB9D9),
    ground: Color(0xFF041426),
    surface: Color(0xFF0B223A),
    hairline: Color(0xFF1E3754),
    ink: Color(0xFFEAF0F7),
    inkMuted: Color(0xFFA6B6C8),
    accent: Color(0xFF8BB9D9),
    onAccent: Color(0xFF031A31),
    lines: _darkLines,
  );

  static const pitchGreen = PitchyPalette(
    brightness: Brightness.light,
    shell: Color(0xFF0E3B2E),
    shellRaised: Color(0xFF15483A),
    onShell: Color(0xFFFFFFFF),
    onShellMuted: Color(0xFFC6DCD3),
    onShellAccent: Color(0xFFFFFFFF),
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
    onShellAccent: Colors.white,
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

  /// Colours blend during the short theme switch; brightness and the fixed
  /// source lines snap at the midpoint (they never blend into another hue).
  @override
  PitchyPalette lerp(PitchyPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    final snap = t < 0.5 ? this : other;
    return PitchyPalette(
      brightness: snap.brightness,
      shell: c(shell, other.shell),
      shellRaised: c(shellRaised, other.shellRaised),
      onShell: c(onShell, other.onShell),
      onShellMuted: c(onShellMuted, other.onShellMuted),
      onShellAccent: c(onShellAccent, other.onShellAccent),
      ground: c(ground, other.ground),
      surface: c(surface, other.surface),
      hairline: c(hairline, other.hairline),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      lines: snap.lines,
    );
  }
}
