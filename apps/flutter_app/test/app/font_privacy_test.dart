// Font privacy guard (user rule, 2026-11-27, P-28): every font is bundled in
// the app, and nothing loads a font over the network at runtime, so no font
// request ever sends a user's IP address anywhere.
//
// The Fontshare download runs only at build time (tool/fetch_switzer.dart), on
// a developer PC or in CI, never on a user's device. A plain link to the
// Fontshare page on the Credits screen is fine (the user opens it in their
// browser); only the font API host is banned in lib/.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no runtime font package in the dependency lock', () {
    final lock = File('pubspec.lock').readAsStringSync();
    expect(lock, isNot(contains('google_fonts')));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('google_fonts')));
  });

  test('lib/ never loads fonts at runtime or names a font host', () {
    const banned = [
      'FontLoader',
      'loadFontFromList',
      'google_fonts',
      'fonts.googleapis',
      'fonts.gstatic',
      'api.fontshare.com',
    ];
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final b in banned) {
        if (text.contains(b)) hits.add('${f.path}: $b');
      }
    }
    expect(hits, isEmpty, reason: 'Fonts must be bundled assets only.');
  });

  test('every font family in pubspec.yaml is a bundled asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(r'^\s*- asset:\s*(\S+)', multiLine: true).allMatches(pubspec);
    for (final m in assets) {
      final path = m.group(1)!;
      expect(path.startsWith('http'), isFalse, reason: path);
    }
  });
}
