// Fixed colours: data-state colours and the safety ramp. These are NEVER themed
// (P-13): Light, Dark, Pitch Green and Custom all use exactly these values, with
// only a light/dark variant for contrast. Every state also carries an icon and a
// word, so colour is never the only signal.

import 'package:material_ui/material_ui.dart';

import '../../shared/models/weather.dart';

@immutable
class StateStyle {
  const StateStyle({
    required this.foreground,
    required this.background,
    required this.icon,
    required this.label,
    this.dashed = false,
  });

  final Color foreground;
  final Color background;
  final IconData icon;
  final String label;

  /// Stale is "stamped": drawn with a dashed outline so it reads differently from
  /// Current even without colour.
  final bool dashed;
}

/// Data-state colours (P-05 vocabulary). Contrast of foreground on background
/// is at least 4.5:1 in both variants.
@immutable
class StateColors extends ThemeExtension<StateColors> {
  const StateColors._(this._styles);

  static const light = StateColors._({
    WeatherDataState.current: StateStyle(
      foreground: Color(0xFF0B5C43),
      background: Color(0xFFE1F3EC),
      icon: Icons.check_circle,
      label: 'Current',
    ),
    WeatherDataState.stale: StateStyle(
      foreground: Color(0xFF6E4300),
      background: Color(0xFFFFF0D2),
      icon: Icons.history,
      label: 'Stale',
      dashed: true,
    ),
    WeatherDataState.updating: StateStyle(
      foreground: Color(0xFF1A4FA8),
      background: Color(0xFFE3ECFB),
      icon: Icons.sync,
      label: 'Updating',
    ),
    WeatherDataState.missing: StateStyle(
      foreground: Color(0xFF3F4C5E),
      background: Color(0xFFECEFF3),
      icon: Icons.help_outline,
      label: 'Missing',
    ),
    WeatherDataState.unavailable: StateStyle(
      foreground: Color(0xFF2E3440),
      background: Color(0xFFE2E5EA),
      icon: Icons.cloud_off,
      label: 'Unavailable',
    ),
  });

  static const dark = StateColors._({
    WeatherDataState.current: StateStyle(
      foreground: Color(0xFF8BE0C0),
      background: Color(0xFF113A2E),
      icon: Icons.check_circle,
      label: 'Current',
    ),
    WeatherDataState.stale: StateStyle(
      foreground: Color(0xFFE3BF95),
      background: Color(0xFF3D2A07),
      icon: Icons.history,
      label: 'Stale',
      dashed: true,
    ),
    WeatherDataState.updating: StateStyle(
      foreground: Color(0xFFA9C7FF),
      background: Color(0xFF14284D),
      icon: Icons.sync,
      label: 'Updating',
    ),
    WeatherDataState.missing: StateStyle(
      foreground: Color(0xFFC3CDD9),
      background: Color(0xFF243246),
      icon: Icons.help_outline,
      label: 'Missing',
    ),
    WeatherDataState.unavailable: StateStyle(
      foreground: Color(0xFFE3E7ED),
      background: Color(0xFF39424F),
      icon: Icons.cloud_off,
      label: 'Unavailable',
    ),
  });

  final Map<WeatherDataState, StateStyle> _styles;

  StateStyle of(WeatherDataState state) => _styles[state]!;

  @override
  StateColors copyWith() => this;

  @override
  StateColors lerp(StateColors? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Safety ramp for backend-provided warnings and official alerts. Fixed in every
/// theme. Which level applies is always decided by the backend or the issuing
/// agency, never by the app.
@immutable
class SafetyColors extends ThemeExtension<SafetyColors> {
  const SafetyColors({
    required this.advisory,
    required this.onAdvisory,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.calmInfo,
    required this.calmInfoBorder,
    required this.onCalmInfo,
    required this.requestError,
    required this.onRequestError,
    required this.requestErrorInk,
    required this.onRequestErrorInk,
  });

  /// Light themes.
  static const fixed = SafetyColors(
    advisory: Color(0xFFF2C200),
    onAdvisory: Color(0xFF1A1400),
    warning: Color(0xFFE8710A),
    onWarning: Color(0xFF1A0B00),
    danger: Color(0xFFC62828),
    onDanger: Color(0xFFFFFFFF),
    calmInfo: Color(0xFFE4EBF0),
    calmInfoBorder: Color(0xFF8EADC3),
    onCalmInfo: Color(0xFF031A31),
    requestError: Color(0xFF9F1D1D),
    onRequestError: Color(0xFFFFFFFF),
    requestErrorInk: Color(0xFF9F1D1D),
    onRequestErrorInk: Color(0xFFFFFFFF),
  );

  /// Dark themes: the same fills; only the request-error text/icon colour is
  /// lighter, because #9F1D1D is 2.03:1 on the dark surface (user, 2026-11-25).
  static const fixedDark = SafetyColors(
    advisory: Color(0xFFF2C200),
    onAdvisory: Color(0xFF1A1400),
    warning: Color(0xFFE8710A),
    onWarning: Color(0xFF1A0B00),
    danger: Color(0xFFC62828),
    onDanger: Color(0xFFFFFFFF),
    calmInfo: Color(0xFF1A344D),
    calmInfoBorder: Color(0xFF4B6E8C),
    onCalmInfo: Color(0xFFEAF0F7),
    requestError: Color(0xFF9F1D1D),
    onRequestError: Color(0xFFFFFFFF),
    requestErrorInk: Color(0xFFFF8A80),
    onRequestErrorInk: Color(0xFF07111F),
  );

  final Color advisory;
  final Color onAdvisory;
  final Color warning;
  final Color onWarning;
  final Color danger;
  final Color onDanger;

  /// The safety "advisory" level (P-19: a calm info style, not amber, e.g.
  /// "below the cooling-break level"). Fixed like the rest of the ramp, so no
  /// theme or Custom pick can change how a hazard level looks (P-13, Q6).
  /// Official alerts' advisory stays [advisory] yellow (P-18).
  final Color calmInfo;
  final Color calmInfoBorder;
  final Color onCalmInfo;

  /// A failed request (not a hazard): the filled banner colour.
  final Color requestError;
  final Color onRequestError;

  /// A failed request as text or an icon on the page or a card (form errors,
  /// error icons). Same as [requestError] in light themes; lighter in dark.
  final Color requestErrorInk;

  /// Text on a fill of [requestErrorInk] (the scheme's `onError`).
  final Color onRequestErrorInk;

  @override
  SafetyColors copyWith() => this;

  @override
  SafetyColors lerp(SafetyColors? other, double t) => this;
}
