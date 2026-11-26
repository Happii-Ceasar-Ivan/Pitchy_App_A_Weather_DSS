import 'package:material_ui/material_ui.dart';

/// A decorative icon for a consolidated weather quantity (P-27 task B), shown
/// beside the tile label and in the chart's value list. Never a state or
/// safety colour, and never read out: the label says what the value is.
///
/// Null for quantities this app version doesn't know, so an unknown value gets
/// no icon rather than a misleading one. CAPE deliberately has no storm or bolt
/// icon, so it can't be read as a lightning warning.
IconData? weatherIconFor(String quantity) => switch (quantity) {
  'air_temperature' => Icons.thermostat,
  'heat_index' => Icons.device_thermostat,
  'dew_point' => Icons.water_drop_outlined,
  'relative_humidity' => Icons.opacity,
  'rain' => Icons.grain,
  'rain_probability' => Icons.umbrella_outlined,
  'wind_speed' || 'wind_gusts' => Icons.air,
  // Static on purpose: a rotated arrow could be misread as "from" or "to".
  'wind_direction' => Icons.explore_outlined,
  'cloud_cover' => Icons.cloud_outlined,
  'shortwave_radiation' ||
  'direct_normal_irradiance' ||
  'diffuse_radiation' => Icons.wb_sunny_outlined,
  'cape' => Icons.stacked_line_chart,
  _ => null,
};

/// The icon for a label in [style], scaled with the text like the label is.
class WeatherQuantityIcon extends StatelessWidget {
  const WeatherQuantityIcon({super.key, required this.quantity, required this.style, this.color});

  final String quantity;
  final TextStyle? style;
  final Color? color;

  /// Icon size for [style]: the font size, scaled like the text.
  static double sizeFor(BuildContext context, TextStyle? style) =>
      MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) * 1.4;

  @override
  Widget build(BuildContext context) {
    final icon = weatherIconFor(quantity);
    if (icon == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: Icon(icon, size: sizeFor(context, style), color: color ?? style?.color),
    );
  }
}
