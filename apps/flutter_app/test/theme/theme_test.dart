import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/core/theme/fixed_colors.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/core/theme/theme_controller.dart';
import 'package:pitchy/shared/models/weather.dart';

double _luminance(Color c) => c.computeLuminance();
double contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
}

void main() {
  final controller = ThemeController();
  final themes = {
    for (final mode in PitchyThemeMode.values)
      mode: () {
        controller.setMode(mode);
        return AppTheme.build(controller.palette);
      }(),
  };

  test('safety colours are identical in every theme (never themed)', () {
    for (final t in themes.values) {
      final s = t.extension<SafetyColors>()!;
      // Only light/dark picks the set; the theme choice never does.
      expect(
        s,
        same(t.brightness == Brightness.dark ? SafetyColors.fixedDark : SafetyColors.fixed),
      );
      // Hazard fills and the error fill are the same in both sets.
      expect(s.advisory, SafetyColors.fixed.advisory);
      expect(s.onAdvisory, SafetyColors.fixed.onAdvisory);
      expect(s.warning, SafetyColors.fixed.warning);
      expect(s.onWarning, SafetyColors.fixed.onWarning);
      expect(s.danger, SafetyColors.fixed.danger);
      expect(s.onDanger, SafetyColors.fixed.onDanger);
      expect(s.requestError, SafetyColors.fixed.requestError);
      expect(s.onRequestError, SafetyColors.fixed.onRequestError);
    }
  });

  test('request-error text and icons are readable on surface and ground (AA, user 2026-11-25)', () {
    for (final (palette, set) in [
      (PitchyPalette.light, SafetyColors.fixed),
      (PitchyPalette.pitchGreen, SafetyColors.fixed),
      (PitchyPalette.dark, SafetyColors.fixedDark),
    ]) {
      expect(contrast(set.requestErrorInk, palette.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(set.requestErrorInk, palette.ground), greaterThanOrEqualTo(4.5));
    }
    for (final t in themes.values) {
      final s = t.extension<SafetyColors>()!;
      final p = t.extension<PitchyPalette>()!;
      // Form error text uses the scheme's error colour.
      expect(t.colorScheme.error, s.requestErrorInk);
      expect(contrast(t.colorScheme.error, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(t.colorScheme.onError, t.colorScheme.error), greaterThanOrEqualTo(4.5));
    }
  });

  test('state colours only vary by light/dark, never by theme choice', () {
    for (final t in themes.values) {
      final expected = t.brightness == Brightness.dark ? StateColors.dark : StateColors.light;
      expect(t.extension<StateColors>(), same(expected));
    }
  });

  test('every state colour pair is readable (>= 4.5:1)', () {
    for (final set in [StateColors.light, StateColors.dark]) {
      for (final s in WeatherDataState.values) {
        final style = set.of(s);
        expect(
          contrast(style.foreground, style.background),
          greaterThanOrEqualTo(4.5),
          reason: s.name,
        );
      }
    }
  });

  test('every state has its own icon and label (not colour-only)', () {
    final icons = WeatherDataState.values.map((s) => StateColors.light.of(s).icon).toSet();
    final labels = WeatherDataState.values.map((s) => StateColors.light.of(s).label).toSet();
    expect(icons, hasLength(WeatherDataState.values.length));
    expect(labels, hasLength(WeatherDataState.values.length));
  });

  test('palette text roles are readable in every preset theme', () {
    for (final p in [PitchyPalette.light, PitchyPalette.dark, PitchyPalette.pitchGreen]) {
      expect(contrast(p.ink, p.surface), greaterThanOrEqualTo(7), reason: 'ink');
      expect(contrast(p.inkMuted, p.surface), greaterThanOrEqualTo(4.5), reason: 'inkMuted');
      expect(contrast(p.inkMuted, p.ground), greaterThanOrEqualTo(4.5), reason: 'inkMuted/ground');
      expect(contrast(p.onShell, p.shell), greaterThanOrEqualTo(7), reason: 'onShell');
      expect(contrast(p.onShellMuted, p.shell), greaterThanOrEqualTo(4.5), reason: 'onShellMuted');
      expect(contrast(p.accent, p.surface), greaterThanOrEqualTo(4.5), reason: 'accent');
      // Text on accent fills (buttons, the demo-data strip).
      expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: 'onAccent');
      for (final line in p.lines.values) {
        expect(contrast(line, p.surface), greaterThanOrEqualTo(3), reason: 'line colour');
      }
    }
  });

  test('redesign roles are readable (P-28, plan v1 §2)', () {
    for (final p in [PitchyPalette.light, PitchyPalette.dark, PitchyPalette.pitchGreen]) {
      final name = p == PitchyPalette.light
          ? 'light'
          : p == PitchyPalette.dark
          ? 'dark'
          : 'pitch green';
      // Glacier on the shell: rail selection, focus on navy.
      expect(contrast(p.onShellAccent, p.shell), greaterThanOrEqualTo(4.5), reason: name);
      expect(contrast(p.onShellAccent, p.shellRaised), greaterThanOrEqualTo(4.5), reason: name);
      expect(contrast(p.onShellMuted, p.shellRaised), greaterThanOrEqualTo(4.5), reason: name);
      expect(contrast(p.accent, p.ground), greaterThanOrEqualTo(4.5), reason: '$name accent');
      // Bottom-nav indicator: selected ink on the 14% accent tint.
      final indicator = Color.alphaBlend(p.accent.withValues(alpha: 0.14), p.surface);
      expect(contrast(p.ink, indicator), greaterThanOrEqualTo(7), reason: '$name indicator');
      // Snackbar (inverse surface) text and action.
      final t = AppTheme.build(p).colorScheme;
      expect(contrast(t.onInverseSurface, t.inverseSurface), greaterThanOrEqualTo(7));
      expect(contrast(t.inversePrimary, t.inverseSurface), greaterThanOrEqualTo(4.5));
    }
    // Midnight Navy and Glacier as specified.
    expect(PitchyPalette.light.shell, const Color(0xFF031A31));
    expect(PitchyPalette.light.onShellAccent, const Color(0xFF8BB9D9));
    expect(PitchyPalette.light.accent, const Color(0xFF1D5A86));
    expect(PitchyPalette.dark.accent, const Color(0xFF8BB9D9));
  });

  test('accent is never a source line colour and stays apart from them', () {
    for (final p in [PitchyPalette.light, PitchyPalette.dark]) {
      expect(p.lines.values, isNot(contains(p.accent)));
      expect(p.lineFor('unknown_source'), isNot(p.accent));
    }
  });

  test('safety calm-info (advisory) is readable and fixed in both variants', () {
    for (final s in [SafetyColors.fixed, SafetyColors.fixedDark]) {
      expect(contrast(s.onCalmInfo, s.calmInfo), greaterThanOrEqualTo(7));
      // The outline is a non-text boundary against the card surface.
      expect(contrast(s.calmInfoBorder, s.calmInfo), greaterThanOrEqualTo(1.5));
    }
  });

  test('theme type roles have explicit line heights (skeletons match text)', () {
    for (final p in [PitchyPalette.light, PitchyPalette.dark]) {
      final t = AppTheme.textTheme(p);
      for (final s in [
        t.displaySmall,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ]) {
        expect(s!.height, isNotNull);
        expect(s.fontFamily, 'Switzer');
        expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
      expect(t.bodyMedium!.fontSize! * t.bodyMedium!.height!, closeTo(20, 0.001));
      expect(t.headlineMedium!.fontSize! * t.headlineMedium!.height!, closeTo(36, 0.001));
    }
    // Dark compensates thin light-on-dark text with tracking only.
    final light = AppTheme.textTheme(PitchyPalette.light);
    final dark = AppTheme.textTheme(PitchyPalette.dark);
    expect(dark.bodyMedium!.letterSpacing, greaterThan(light.bodyMedium!.letterSpacing!));
    expect(dark.bodyMedium!.fontWeight, light.bodyMedium!.fontWeight);
  });

  test('every Custom swatch keeps white text readable', () {
    for (final s in customSwatches) {
      expect(contrast(Colors.white, s.color), greaterThanOrEqualTo(4.5), reason: s.name);
      expect(
        contrast(s.color, Colors.white),
        greaterThanOrEqualTo(4.5),
        reason: '${s.name} as accent',
      );
    }
  });

  test('Custom theme uses the two picks for shell and accent only', () {
    final c = ThemeController()
      ..setMode(PitchyThemeMode.custom)
      ..setCustom(shell: customSwatches[4], accent: customSwatches[1]);
    expect(c.palette.shell, customSwatches[4].color);
    expect(c.palette.accent, customSwatches[1].color);
    expect(c.palette.ink, PitchyPalette.light.ink);
  });
}
