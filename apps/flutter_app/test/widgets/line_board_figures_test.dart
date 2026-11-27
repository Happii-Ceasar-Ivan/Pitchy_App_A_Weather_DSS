import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/shared/models/match.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/kickoff_strip.dart';
import 'package:pitchy/shared/widgets/source_rail.dart';

import '../helpers.dart';

/// Every (text, family) leaf run in the paragraphs matching [test].
List<(String, String?)> _runs(WidgetTester tester, bool Function(String) test) {
  final out = <(String, String?)>[];
  for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    if (!test(p.text.toPlainText())) continue;
    p.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        out.add((span.text!, span.style?.fontFamily));
      }
      return true;
    });
  }
  return out;
}

void main() {
  setUpAll(loadAppFonts);

  WeatherStatus fourSources(MockScenario s) {
    final json = weatherStatusJson(s, now: testNow, kickoff: testKickoff);
    final list = (json['sources']! as List).cast<Map<String, Object?>>();
    json['sources'] = [
      ...list,
      {...list.first, 'source_id': 'open_meteo_2', 'source_name': 'Open-Meteo second model'},
    ];
    return WeatherStatus.fromJson(json);
  }

  Widget rail(WeatherStatus st) => SourceRail(
    sources: st.sources,
    checkedAt: st.checkedAt,
    coverage: st.coverage,
    kickoff: testKickoff,
    now: testNow,
    initiallyExpanded: true,
  );

  testWidgets('source rail: the time run is mono, the words are not', (tester) async {
    await pumpThemed(tester, rail(fourSources(MockScenario.someStale)));
    final runs = _runs(tester, (t) => t.startsWith('Current until') || t.startsWith('Fetched'));
    expect(runs, isNotEmpty);
    final mono = runs.where((r) => r.$2 == PitchyFigures.fontFamily).map((r) => r.$1);
    // Only the figures are mono; "h", "AM"/"PM" and "PHT" stay Switzer.
    expect(mono, contains('9'));
    expect(mono.where((r) => r.contains(RegExp(r'\D'))), isEmpty);
    for (final (text, family) in runs) {
      if (family == PitchyFigures.fontFamily) continue;
      expect(RegExp(r'\d{1,2}:\d{2} [AP]M').hasMatch(text), isFalse, reason: text);
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('source rail with four sources fits 360x780 at ${scale}x text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpThemed(
        tester,
        rail(fourSources(MockScenario.someStale)),
        size: const Size(360, 780),
      );
      expect(tester.takeException(), isNull);
      await pumpThemed(
        tester,
        SourceRail(
          sources: fourSources(MockScenario.allCurrent).sources,
          checkedAt: testNow,
          coverage: fourSources(MockScenario.allCurrent).coverage,
          kickoff: testKickoff,
          now: testNow,
        ),
        size: const Size(360, 780),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('kickoff strip: the kickoff time is mono', (tester) async {
    final match = MatchContext.fromJson(matchContextJson(kickoff: testKickoff, created: testNow));
    await pumpThemed(tester, KickoffStrip(match: match));
    final runs = _runs(tester, (t) => t.startsWith('Kickoff'));
    final mono = runs.where((r) => r.$2 == PitchyFigures.fontFamily).map((r) => r.$1).toList();
    expect(mono, ['3', '00']);
    expect(tester.takeException(), isNull);
  });
}
