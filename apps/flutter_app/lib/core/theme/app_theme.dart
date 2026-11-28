import 'package:material_ui/material_ui.dart';

import 'fixed_colors.dart';
import 'motion.dart';
import 'pitchy_palette.dart';

/// Builds the Material 3 theme from a [PitchyPalette]. Components stay standard
/// Material; the world enters through palette, type, density and the source rail.
abstract final class AppTheme {
  /// Interface font (P-28): Switzer, bundled (fetched at build time, never at
  /// runtime). Line Board figures use [PitchyFigures].
  static const fontFamily = 'Switzer';

  /// The one rule weight (logical pixels).
  static const hairline = 1.0;

  /// Inputs, chips, menus, tooltips.
  static const radiusSm = 8.0;
  static const radiusCard = 12.0;

  /// Dialogs, the drawer's open edge, snackbars.
  static const radiusLg = 16.0;
  static const radiusPill = 999.0;
  static const radiusScrollbar = 4.0;

  /// Minimum touch target (Material: 48dp).
  static const minTarget = 48.0;

  /// Text scale from which layouts switch to their large-text form (one card
  /// per row, stacked headers), so state words and values are never cut.
  static const largeTextScale = 1.5;

  static bool isLargeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) / 10 >= largeTextScale;

  /// Elevation of things that float over the board (drawer, dialogs, menus,
  /// snackbars). Cards, bars and the rail stay flat (Flat Board Rule).
  static const overlayElevation = 6.0;

  /// The one shadow colour: navy-tinted in light themes, black in dark.
  static Color overlayShadow(PitchyPalette p) =>
      p.brightness == Brightness.dark ? const Color(0x66000000) : const Color(0x1F031A31);

  // Tabular figures on every role (Tabular Everywhere Rule). Switzer's default
  // figures are already tabular; the request is kept for any fallback font.
  static const _tnum = [FontFeature.tabularFigures()];

  /// The Material type roles in Switzer. Sizes and line heights are the
  /// existing ones, set explicitly so line boxes (and the skeletons sized from
  /// them) never depend on the font's own metrics.
  static TextTheme textTheme(PitchyPalette p) {
    final dark = p.brightness == Brightness.dark;
    // Light-on-dark text reads thinner: a touch more tracking, same box (A5).
    final body = dark ? 0.1 : 0.0;
    final label = dark ? 0.2 : 0.1;
    TextStyle s(double size, double line, FontWeight w, double tracking, [Color? color]) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: line / size,
          fontWeight: w,
          letterSpacing: tracking,
          fontFeatures: _tnum,
          color: color ?? p.ink,
          textBaseline: TextBaseline.alphabetic,
          leadingDistribution: TextLeadingDistribution.even,
        );
    const bold = FontWeight.w700;
    const semi = FontWeight.w600;
    const regular = FontWeight.w400;
    return TextTheme(
      // Large sizes tighten (about -0.015em) so values look firm (C2).
      displayLarge: s(57, 64, bold, -0.5),
      displayMedium: s(45, 52, bold, -0.5),
      displaySmall: s(36, 44, bold, -0.5),
      headlineLarge: s(32, 40, bold, -0.4),
      headlineMedium: s(28, 36, bold, -0.4),
      headlineSmall: s(24, 32, bold, -0.3),
      titleLarge: s(22, 28, semi, 0),
      titleMedium: s(16, 24, semi, 0),
      titleSmall: s(14, 20, semi, 0),
      bodyLarge: s(16, 24, regular, body),
      bodyMedium: s(14, 20, regular, body),
      bodySmall: s(12, 16, regular, body, p.inkMuted),
      labelLarge: s(14, 20, semi, label),
      labelMedium: s(12, 16, semi, label),
      labelSmall: s(11, 16, semi, label),
    );
  }

  static ThemeData build(PitchyPalette p) {
    final isDark = p.brightness == Brightness.dark;
    final safety = isDark ? SafetyColors.fixedDark : SafetyColors.fixed;
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.shell,
      onSecondary: p.onShell,
      error: safety.requestErrorInk,
      onError: safety.onRequestErrorInk,
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
      inverseSurface: isDark ? p.ink : p.shell,
      onInverseSurface: isDark ? p.shell : p.onShell,
      inversePrimary: isDark ? p.onAccent : p.onShellAccent,
      shadow: overlayShadow(p),
      scrim: const Color(0xFF000000),
      surfaceTint: Colors.transparent,
    );

    final text = textTheme(p);
    final shadow = overlayShadow(p);
    final small = BorderRadius.circular(radiusSm);
    final large = BorderRadius.circular(radiusLg);

    // Press, hover and focus layers for every control, from one rule (A2):
    // pressed 8% / hover 4% of the content colour, keyboard focus 12% accent.
    WidgetStateProperty<Color?> overlay(Color content, [Color? focus]) =>
        WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) return content.withValues(alpha: 0.08);
          if (s.contains(WidgetState.focused)) {
            return (focus ?? p.accent).withValues(alpha: 0.12);
          }
          if (s.contains(WidgetState.hovered)) return content.withValues(alpha: 0.04);
          return null;
        });
    // Focus ring: 2px accent on keyboard focus, never only a colour wash.
    BorderSide? focusRing(Set<WidgetState> s, BorderSide rest) =>
        s.contains(WidgetState.focused) ? BorderSide(color: p.accent, width: 2) : rest;
    final disabledInk = p.ink.withValues(alpha: 0.38);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      primaryTextTheme: text.apply(bodyColor: p.onAccent, displayColor: p.onAccent),
      scaffoldBackgroundColor: p.ground,
      canvasColor: p.surface,
      splashFactory: InkRipple.splashFactory,
      focusColor: p.accent.withValues(alpha: 0.12),
      hoverColor: p.ink.withValues(alpha: 0.04),
      highlightColor: Colors.transparent,
      disabledColor: disabledInk,
      shadowColor: shadow,
      extensions: [p, isDark ? StateColors.dark : StateColors.light, safety],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PitchyPageTransitionsBuilder(),
          TargetPlatform.windows: PitchyPageTransitionsBuilder(),
          TargetPlatform.linux: PitchyPageTransitionsBuilder(),
          TargetPlatform.macOS: PitchyPageTransitionsBuilder(),
          TargetPlatform.iOS: PitchyPageTransitionsBuilder(),
        },
      ),
      iconTheme: IconThemeData(color: p.ink, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: p.shell,
        foregroundColor: p.onShell,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 0,
        titleTextStyle: text.titleLarge?.copyWith(color: p.onShell),
        iconTheme: IconThemeData(color: p.onShell),
        actionsIconTheme: IconThemeData(color: p.onShell),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: p.hairline, width: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: hairline, space: hairline),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        indicatorColor: Color.alphaBlend(p.accent.withValues(alpha: 0.14), p.surface),
        surfaceTintColor: Colors.transparent,
        overlayColor: overlay(p.ink),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? p.ink : p.inkMuted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.ink : p.inkMuted),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.shell,
        elevation: 0,
        indicatorColor: p.shellRaised,
        selectedIconTheme: IconThemeData(color: p.onShellAccent),
        unselectedIconTheme: IconThemeData(color: p.onShellMuted),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: p.onShellAccent),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: p.onShellMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.inkMuted,
        textColor: p.ink,
        minVerticalPadding: 12,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: p.inkMuted),
        leadingAndTrailingTextStyle: text.labelMedium?.copyWith(color: p.inkMuted),
        selectedColor: p.accent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, minTarget)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? p.ink.withValues(alpha: 0.12) : p.accent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledInk : p.onAccent,
          ),
          overlayColor: overlay(p.onAccent, p.onAccent),
          side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused)
                ? BorderSide(color: p.ink, width: 2)
                : BorderSide.none,
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, minTarget)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledInk : p.accent,
          ),
          overlayColor: overlay(p.accent),
          side: WidgetStateProperty.resolveWith(
            (s) => focusRing(
              s,
              BorderSide(
                color: s.contains(WidgetState.disabled)
                    ? p.hairline.withValues(alpha: 0.5)
                    : p.hairline,
                width: hairline,
              ),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, minTarget)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? disabledInk : p.accent,
          ),
          overlayColor: overlay(p.accent),
          side: WidgetStateProperty.resolveWith((s) => focusRing(s, BorderSide.none)),
        ),
      ),
      switchTheme: SwitchThemeData(
        // Never the Current green (P-17): accent when on, neutral when off.
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return disabledInk;
          return s.contains(WidgetState.selected) ? p.onAccent : p.inkMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return p.hairline.withValues(alpha: 0.5);
          return s.contains(WidgetState.selected) ? p.accent : p.hairline;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.inkMuted,
        ),
        overlayColor: overlay(p.accent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return disabledInk;
          return s.contains(WidgetState.selected) ? p.accent : p.inkMuted;
        }),
        overlayColor: overlay(p.accent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return disabledInk;
          return s.contains(WidgetState.selected) ? p.accent : Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: BorderSide(color: p.inkMuted, width: 2),
        overlayColor: overlay(p.accent),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: false,
        labelStyle: text.bodyLarge?.copyWith(color: p.inkMuted),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (s) => text.bodySmall!.copyWith(
            color: s.contains(WidgetState.error)
                ? safety.requestErrorInk
                : s.contains(WidgetState.focused)
                ? p.accent
                : p.inkMuted,
          ),
        ),
        hintStyle: text.bodyLarge?.copyWith(color: p.inkMuted),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: safety.requestErrorInk),
        border: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: p.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: p.inkMuted.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: safety.requestErrorInk),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: safety.requestErrorInk, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: p.hairline.withValues(alpha: 0.5)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: Color.alphaBlend(p.accent.withValues(alpha: 0.14), p.surface),
        disabledColor: p.surface,
        side: BorderSide(color: p.hairline, width: hairline),
        shape: RoundedRectangleBorder(borderRadius: small),
        labelStyle: text.labelLarge?.copyWith(color: p.ink),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: p.ink),
        checkmarkColor: p.ink,
        iconTheme: IconThemeData(color: p.inkMuted, size: 18),
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: overlayElevation,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(borderRadius: large),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: overlayElevation,
        shadowColor: shadow,
        // Rounded on the open (trailing) edge only; the start edge meets the
        // screen edge.
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(radiusLg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: overlayElevation,
        shape: RoundedRectangleBorder(borderRadius: large),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: shadow,
        shape: RoundedRectangleBorder(
          borderRadius: small,
          side: BorderSide(color: p.hairline, width: hairline),
        ),
        textStyle: text.bodyLarge,
        labelTextStyle: WidgetStatePropertyAll(text.bodyLarge),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          shadowColor: WidgetStatePropertyAll(shadow),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: small,
              side: BorderSide(color: p.hairline, width: hairline),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? p.ink : p.shell,
          borderRadius: small,
        ),
        textStyle: text.bodySmall?.copyWith(color: isDark ? p.shell : p.onShell),
        waitDuration: const Duration(milliseconds: 500),
        showDuration: PitchyMotion.tooltipShow,
        exitDuration: PitchyMotion.tooltipExit,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.hairline,
        circularTrackColor: Colors.transparent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.inkMuted.withValues(alpha: 0.5)),
        radius: const Radius.circular(radiusScrollbar),
      ),
    );
  }
}

/// Line Board figures (P-28, plan v2 C1): IBM Plex Mono, only for the source
/// rail's time runs, the kickoff time and the trend chart's time axis and
/// readout. Everywhere else times stay Switzer with tabular figures.
abstract final class PitchyFigures {
  static const fontFamily = 'IBMPlexMono';

  /// [base] (size, line height, colour) set in Plex Mono. Weight is capped at
  /// semibold, the heaviest bundled Plex weight; tracking is the font's own.
  static TextStyle board(TextStyle base) => base.copyWith(
    fontFamily: fontFamily,
    letterSpacing: 0,
    fontWeight: (base.fontWeight?.value ?? 400) > 600 ? FontWeight.w600 : base.fontWeight,
  );

  static final _figures = RegExp(r'\d+');

  /// [text] with only its digits in Plex Mono; the colon, en dash, words,
  /// spaces, "AM"/"PM" and "PHT" stay in [base]. Plex Mono's full-cell colon
  /// and space would otherwise split "2:00 PM" into separate tokens.
  static TextSpan figureSpans(String text, TextStyle base) {
    final mono = board(base);
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in _figures.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(0), style: mono));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: base, children: spans);
  }
}

/// Shortcuts for reading the theme's extensions.
extension PitchyThemeX on BuildContext {
  PitchyPalette get palette => Theme.of(this).extension<PitchyPalette>()!;
  StateColors get stateColors => Theme.of(this).extension<StateColors>()!;
  SafetyColors get safetyColors => Theme.of(this).extension<SafetyColors>()!;
}
