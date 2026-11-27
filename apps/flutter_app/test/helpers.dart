import 'dart:io';

import 'package:flutter/services.dart';
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

/// Loads the app's bundled Switzer and IBM Plex Mono and the Material icon font, so layout tests
/// measure real glyph widths instead of the wide square test font.
Future<void> loadAppFonts() async {
  final switzer = FontLoader('Switzer');
  for (final w in ['Regular', 'Medium', 'Semibold', 'Bold']) {
    switzer.addFont(rootBundle.load('assets/fonts/switzer/Switzer-$w.otf'));
  }
  await switzer.load();
  final plex = FontLoader('IBMPlexMono');
  for (final w in ['Regular', 'Medium', 'SemiBold']) {
    plex.addFont(rootBundle.load('assets/fonts/ibm_plex_mono/IBMPlexMono-$w.ttf'));
  }
  await plex.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final icons = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (!icons.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await loader.load();
}
