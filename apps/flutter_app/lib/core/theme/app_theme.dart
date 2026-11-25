import 'package:material_ui/material_ui.dart';

import 'fixed_colors.dart';
import 'pitchy_palette.dart';

/// Builds the Material 3 theme from a [PitchyPalette]. Components stay standard
/// Material; the world enters through palette, type, density and the source rail.
abstract final class AppTheme {
  static const fontFamily = 'Roboto';

  /// The one rule weight (logical pixels).
  static const hairline = 1.0;

  static const radiusCard = 12.0;
  static const radiusPill = 999.0;

  /// Minimum touch target (Material: 48dp).
  static const minTarget = 48.0;

  /// Text scale from which layouts switch to their large-text form (one card
  /// per row, stacked headers), so state words and values are never cut.
  static const largeTextScale = 1.5;

  static bool isLargeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) / 10 >= largeTextScale;

  static ThemeData build(PitchyPalette p) {
    final isDark = p.brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.shell,
      onSecondary: p.onShell,
      error: SafetyColors.fixed.requestError,
      onError: SafetyColors.fixed.onRequestError,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.inkMuted,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.ground,
      surfaceContainer: p.ground,
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.surface,
      outline: p.inkMuted,
      outlineVariant: p.hairline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: p.ground,
      extensions: [p, isDark ? StateColors.dark : StateColors.light, SafetyColors.fixed],
    );

    // Tabular figures everywhere so values line up and don't jitter on update.
    const tnum = [FontFeature.tabularFigures()];
    final text = base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink);
    TextStyle? t(TextStyle? s, {FontWeight? w}) => s?.copyWith(fontFeatures: tnum, fontWeight: w);

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: t(text.displaySmall, w: FontWeight.w700),
        headlineMedium: t(text.headlineMedium, w: FontWeight.w700),
        headlineSmall: t(text.headlineSmall, w: FontWeight.w700),
        titleLarge: t(text.titleLarge, w: FontWeight.w700),
        titleMedium: t(text.titleMedium, w: FontWeight.w700),
        titleSmall: t(text.titleSmall, w: FontWeight.w700),
        bodyLarge: t(text.bodyLarge),
        bodyMedium: t(text.bodyMedium),
        bodySmall: t(text.bodySmall)?.copyWith(color: p.inkMuted),
        labelLarge: t(text.labelLarge, w: FontWeight.w700),
        labelMedium: t(text.labelMedium, w: FontWeight.w700),
        labelSmall: t(text.labelSmall, w: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.shell,
        foregroundColor: p.onShell,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        titleTextStyle: text.titleLarge?.copyWith(color: p.onShell, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: p.hairline, width: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: hairline, space: hairline),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: Color.alphaBlend(p.accent.withValues(alpha: 0.16), p.surface),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? p.ink : p.inkMuted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.ink : p.inkMuted),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.shell,
        indicatorColor: p.shellRaised,
        selectedIconTheme: IconThemeData(color: p.onShell),
        unselectedIconTheme: IconThemeData(color: p.onShellMuted),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: p.onShell,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: p.onShellMuted),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.inkMuted,
        textColor: p.ink,
        minVerticalPadding: 12,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, minTarget)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, minTarget),
          side: BorderSide(color: p.hairline, width: hairline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, minTarget)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.inkMuted.withValues(alpha: 0.5)),
        radius: const Radius.circular(4),
      ),
      focusColor: p.accent.withValues(alpha: 0.24),
    );
  }
}

/// Shortcuts for reading the theme's extensions.
extension PitchyThemeX on BuildContext {
  PitchyPalette get palette => Theme.of(this).extension<PitchyPalette>()!;
  StateColors get stateColors => Theme.of(this).extension<StateColors>()!;
  SafetyColors get safetyColors => Theme.of(this).extension<SafetyColors>()!;
}
