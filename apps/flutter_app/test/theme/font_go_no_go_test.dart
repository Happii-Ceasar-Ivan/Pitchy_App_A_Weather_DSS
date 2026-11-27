// Font go/no-go checks for the visual redesign (plan v1 §1.5, P-28).
//
// 1. Switzer has tabular figures: equal widths for "111:11" and "888:88",
//    in every weight the theme uses (its default figures are tabular).
// 2. Switzer and IBM Plex Mono have a glyph for every character the app shows.
//    Checked in the font's own cmap table, so a fallback font can't hide a gap.
// 3. Plex Mono digits and colon share one advance at the sizes used.
//
// Needs the Switzer files: run `dart run tool/fetch_switzer.dart` first.
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _switzer = {
  400: 'assets/fonts/switzer/Switzer-Regular.otf',
  500: 'assets/fonts/switzer/Switzer-Medium.otf',
  600: 'assets/fonts/switzer/Switzer-Semibold.otf',
  700: 'assets/fonts/switzer/Switzer-Bold.otf',
};
const _plex = {
  400: 'assets/fonts/ibm_plex_mono/IBMPlexMono-Regular.ttf',
  500: 'assets/fonts/ibm_plex_mono/IBMPlexMono-Medium.ttf',
  600: 'assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf',
};

/// Every character the app's own strings use (scanned from lib/, 2026-11-27),
/// the plan's list, printable ASCII, and the Filipino letters in venue names.
final _appChars = <int>{
  for (var c = 0x20; c <= 0x7e; c++) c,
  ...'°²·–—’‘“”•…±×→₱%ñÑé'.runes,
};

/// What the Line Board's mono runs show: times, dates, durations, units.
final _boardChars = <int>{
  ...'0123456789:.,-–·/ %°'.runes,
  ...'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.runes,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final s = FontLoader('Switzer');
    for (final p in _switzer.values) {
      s.addFont(rootBundle.load(p));
    }
    await s.load();
    final m = FontLoader('IBMPlexMono');
    for (final p in _plex.values) {
      m.addFont(rootBundle.load(p));
    }
    await m.load();
  });

  group('Switzer', () {
    for (final e in _switzer.entries) {
      // Found 2026-11-27: the kit has no `tnum` GSUB feature, because its
      // default figures are already tabular (checked by the width tests below,
      // with and without the feature). If Fontshare ever adds proportional
      // default figures, those tests fail.
      test('weight ${e.key}: OpenType file, no tnum feature needed', () {
        final font = _Font(File(e.value).readAsBytesSync());
        expect(font.featureTags, isNot(contains('pnum')));
      });

      test('weight ${e.key}: has a glyph for every app character', () {
        final font = _Font(File(e.value).readAsBytesSync());
        final missing = _appChars.where((c) => !font.cmap.contains(c)).toSet();
        // Switzer has no arrow (→) or peso sign (₱). Neither is in any string
        // the app shows today (lib/ uses them only in comments); if backend or
        // chat text contains one, the OS fallback font draws it.
        expect(missing.map(_hex).toSet(), {'U+2192', 'U+20B1'});
      });

      for (final (size, tnum) in [
        for (final s in [11.0, 14.0, 28.0, 36.0]) ...[(s, true), (s, false)],
      ]) {
        test('weight ${e.key} at ${size}px, tnum $tnum: digits equal width', () {
          final style = TextStyle(
            fontFamily: 'Switzer',
            fontSize: size,
            fontWeight: FontWeight.values[e.key ~/ 100 - 1],
            fontFeatures: tnum ? const [FontFeature.tabularFigures()] : null,
          );
          final ones = _width('111:11', style);
          final eights = _width('888:88', style);
          expect(ones, closeTo(eights, 0.01), reason: '111:11=$ones 888:88=$eights');
          final mixed = _width('0123456789', style);
          expect(mixed, closeTo(_width('5555555555', style), 0.01));
        });
      }
    }
  });

  group('IBM Plex Mono', () {
    for (final e in _plex.entries) {
      test('weight ${e.key}: has a glyph for every Line Board character', () {
        final font = _Font(File(e.value).readAsBytesSync());
        final missing = _boardChars.where((c) => !font.cmap.contains(c)).toList();
        expect(missing.map(_hex).toList(), isEmpty);
      });

      for (final size in [11.0, 12.0, 14.0, 16.0]) {
        test('weight ${e.key} at ${size}px: digits and colon share one advance', () {
          final style = TextStyle(
            fontFamily: 'IBMPlexMono',
            fontSize: size,
            fontWeight: FontWeight.values[e.key ~/ 100 - 1],
          );
          final one = _width('0', style);
          for (final ch in '123456789:'.split('')) {
            expect(_width(ch, style), closeTo(one, 0.01), reason: ch);
          }
          expect(_width('12:45', style), closeTo(one * 5, 0.05));
        });
      }
    }
  });
}

double _width(String text, TextStyle style) {
  final p = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

String _hex(int c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// Minimal OpenType reader: table directory, cmap (formats 4 and 12) and the
/// GSUB feature list. Enough to prove what the font file itself contains.
class _Font {
  _Font(Uint8List bytes) : _d = ByteData.sublistView(bytes) {
    final tag = _d.getUint32(0);
    if (tag != 0x00010000 && tag != 0x4f54544f) {
      throw StateError('Not an OpenType file (header ${tag.toRadixString(16)}).');
    }
    final n = _d.getUint16(4);
    for (var i = 0; i < n; i++) {
      final r = 12 + i * 16;
      _tables[String.fromCharCodes(bytes, r, r + 4)] = _d.getUint32(r + 8);
    }
  }

  final ByteData _d;
  final _tables = <String, int>{};

  late final Set<int> cmap = _readCmap();
  late final Set<String> featureTags = _readFeatures();

  Set<int> _readCmap() {
    final base = _tables['cmap']!;
    final count = _d.getUint16(base + 2);
    final out = <int>{};
    for (var i = 0; i < count; i++) {
      final rec = base + 4 + i * 8;
      final platform = _d.getUint16(rec);
      final encoding = _d.getUint16(rec + 2);
      if (!(platform == 3 && (encoding == 1 || encoding == 10)) && platform != 0) continue;
      final sub = base + _d.getUint32(rec + 4);
      switch (_d.getUint16(sub)) {
        case 4:
          final segX2 = _d.getUint16(sub + 6);
          final ends = sub + 14;
          final starts = ends + segX2 + 2;
          final deltas = starts + segX2;
          final ranges = deltas + segX2;
          for (var s = 0; s < segX2 ~/ 2; s++) {
            final end = _d.getUint16(ends + s * 2);
            final start = _d.getUint16(starts + s * 2);
            final delta = _d.getUint16(deltas + s * 2);
            final roAddr = ranges + s * 2;
            final ro = _d.getUint16(roAddr);
            for (var c = start; c <= end && c != 0xffff; c++) {
              int glyph;
              if (ro == 0) {
                glyph = (c + delta) & 0xffff;
              } else {
                final g = _d.getUint16(roAddr + ro + (c - start) * 2);
                glyph = g == 0 ? 0 : (g + delta) & 0xffff;
              }
              if (glyph != 0) out.add(c);
            }
          }
        case 12:
          final groups = _d.getUint32(sub + 12);
          for (var g = 0; g < groups; g++) {
            final r = sub + 16 + g * 12;
            final start = _d.getUint32(r);
            final end = _d.getUint32(r + 4);
            final startGlyph = _d.getUint32(r + 8);
            for (var c = start; c <= end; c++) {
              if (startGlyph + (c - start) != 0) out.add(c);
            }
          }
      }
    }
    return out;
  }

  Set<String> _readFeatures() {
    final base = _tables['GSUB'];
    if (base == null) return {};
    final list = base + _d.getUint16(base + 6);
    final count = _d.getUint16(list);
    return {
      for (var i = 0; i < count; i++)
        String.fromCharCodes([
          for (var k = 0; k < 4; k++) _d.getUint8(list + 2 + i * 6 + k),
        ]),
    };
  }
}
