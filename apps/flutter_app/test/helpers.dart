import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';

final testNow = DateTime.utc(2026, 11, 23, 4);
final testKickoff = DateTime.utc(2026, 11, 23, 7);

/// Wraps [child] in the app theme for widget tests.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  PitchyPalette palette = PitchyPalette.light,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(palette),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}
