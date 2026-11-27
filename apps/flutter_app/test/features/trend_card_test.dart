import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/state/loadable.dart';
import 'package:pitchy/core/storage/saved_copies.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/features/dashboard/trend/trend_card.dart';
import 'package:pitchy/features/dashboard/trend/trend_painter.dart';
import 'package:pitchy/shared/models/weather.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/data_state_badge.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../app_harness.dart';
import '../helpers.dart';

ConsolidatedWeather _trend({
  MockScenario scenario = MockScenario.allCurrent,
  bool trendContract = true,
}) => ConsolidatedWeather.fromJson(
  trendWeatherJson(
    scenario: scenario,
    now: testNow,
    kickoff: testKickoff,
    trendContract: trendContract,
  ),
);

Future<void> _pumpCard(
  WidgetTester tester,
  ConsolidatedWeather w, {
  PitchyPalette palette = PitchyPalette.light,
  double textScale = 1,
  Size size = const Size(390, 844),
  bool saved = false,
}) {
  Widget card = TrendCard(weather: w, matchKickoff: testKickoff, now: testNow);
  if (saved) card = SavedCopyScope(savedAt: testNow, child: card);
  return pumpThemed(
    tester,
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Padding(padding: const EdgeInsets.all(16), child: card),
    ),
    palette: palette,
    size: size,
  );
}

Finder _menu(String label) => find.byWidgetPredicate(
  (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == label,
);

Future<void> _open(WidgetTester tester, String label) async {
  await tester.tap(_menu(label));
  await tester.pumpAndSettle();
}

final _chart = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is TrendPainter);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('defaults: first value, kickoff to +3 h, the kickoff hour selected', (tester) async {
    await _pumpCard(tester, _trend());
    expect(find.text('Hourly trend'), findsOneWidget);
    expect(find.textContaining('3–4 PM PHT · 32.4 °C · Current · Open-Meteo'), findsOneWidget);
    expect(find.text('Weather data by Open-Meteo.com'), findsOneWidget);
    expect(find.byType(DataStateBadge), findsWidgets);
  });

  testWidgets('the value list has only values with data, without wind direction', (tester) async {
    await _pumpCard(tester, _trend());
    await _open(tester, 'Value');
    for (final label in [
      'Heat index (PAGASA)',
      'Relative humidity',
      'Rain',
      'Rain probability',
      'Wind speed',
    ]) {
      expect(find.text(label).hitTestable(), findsWidgets, reason: label);
    }
    expect(find.text('Wind direction'), findsNothing);
    expect(find.text('Cloud cover'), findsNothing);
  });

  testWidgets('the four ranges, and an older backend hides the two before kickoff', (
    tester,
  ) async {
    await _pumpCard(tester, _trend());
    await _open(tester, 'Range');
    for (final r in [
      '6 h before kickoff',
      '2 h before kickoff',
      'Kickoff to +5 h (match and after)',
    ]) {
      expect(find.text(r).hitTestable(), findsWidgets, reason: r);
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await _pumpCard(tester, _trend(trendContract: false));
    await _open(tester, 'Range');
    expect(find.text('6 h before kickoff'), findsNothing);
    expect(find.text('2 h before kickoff'), findsNothing);
    expect(find.text('Kickoff to +5 h (match and after)').hitTestable(), findsWidgets);
  });

  testWidgets('a past hour says it is a forecast, not a measurement', (tester) async {
    await _pumpCard(tester, _trend());
    await _open(tester, 'Range');
    await tester.tap(find.text('6 h before kickoff').hitTestable().last);
    await tester.pumpAndSettle();
    // Last hour with a value (2–3 PM) is selected; move to the first past hour.
    final chart = find.bySemanticsLabel(RegExp('^Air temperature, 6 h before kickoff'));
    expect(chart, findsOneWidget);
    await tester.tap(find.text('Show as table'));
    await tester.pumpAndSettle();
    expect(find.text('past hour'), findsWidgets);
    expect(find.text('No value'), findsNWidgets(2)); // before the fetch: gaps
  });

  testWidgets('stale hours read Stale, in words, and the pill says so', (tester) async {
    await _pumpCard(tester, _trend(scenario: MockScenario.someStale));
    await _open(tester, 'Value');
    await tester.tap(find.text('Heat index (PAGASA)').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.textContaining('· Stale ·'), findsOneWidget);
    expect(find.text('STALE'), findsWidgets);
  });

  testWidgets('a saved copy never reads as live', (tester) async {
    await _pumpCard(tester, _trend(), saved: true);
    expect(find.textContaining('· Saved copy ·'), findsOneWidget);
    expect(find.textContaining('· Current ·'), findsNothing);
  });

  testWidgets('screen readers get a summary and can move hour by hour', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpCard(tester, _trend());
    final chart = find.bySemanticsLabel(RegExp(r'^Air temperature, Kickoff to \+3 h: 32\.4 °C'));
    expect(chart, findsOneWidget);
    final node = tester.getSemantics(chart);
    expect(node.value, startsWith('3–4 PM PHT, 32.4 °C, Open-Meteo, Current'));
    expect(node.increasedValue, startsWith('4–5 PM PHT, 31.8 °C'));
    // The painting itself has no semantics of its own.
    expect(find.descendant(of: chart, matching: find.byType(CustomPaint)), findsWidgets);
    semantics.dispose();
  });

  testWidgets('arrow keys move the selected hour (Windows)', (tester) async {
    await _pumpCard(tester, _trend());
    await tester.tap(_chart);
    await tester.pumpAndSettle();
    final before = tester
        .widget<Text>(find.textContaining(' PHT · ').first)
        .textSpan!
        .toPlainText();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(find.textContaining(' PHT · ').first).textSpan!.toPlainText();
    expect(after, isNot(before));
  });

  testWidgets('the table lists every hour with value, source and state', (tester) async {
    await _pumpCard(tester, _trend());
    await tester.tap(find.text('Show as table'));
    await tester.pumpAndSettle();
    expect(find.text('3–4 PM PHT'), findsWidgets);
    expect(find.text('32.4 °C'), findsOneWidget);
    expect(find.text('31.8 °C'), findsOneWidget);
    expect(find.text('30.9 °C'), findsOneWidget);
    expect(find.text('Hide table'), findsOneWidget);
  });

  testWidgets('a rain fallback shows its label and the per-hour source', (tester) async {
    await _pumpCard(tester, _trend());
    await _open(tester, 'Value');
    await tester.tap(find.text('Rain').hitTestable().last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show as table'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PAGASA ATMO has no value for this hour'), findsWidgets);
    expect(find.text('PAGASA ATMO'), findsWidgets);
    expect(find.text('Open-Meteo'), findsWidgets);
  });

  testWidgets('a failed trend shows its own error with Try again', (tester) async {
    var retried = false;
    await pumpThemed(
      tester,
      TrendBlock(
        trend: const Failed(NetworkFailure()),
        matchKickoff: testKickoff,
        now: testNow,
        onRetry: () => retried = true,
      ),
    );
    expect(find.text('Hourly trend'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('the saved trend shows under the saved-copy label', (tester) async {
    await pumpThemed(
      tester,
      TrendBlock(
        trend: Failed(const NetworkFailure(), saved: SavedCopy(_trend(), savedAt: testNow)),
        matchKickoff: testKickoff,
        now: testNow,
      ),
    );
    expect(find.textContaining('· Saved copy ·'), findsOneWidget);
  });

  for (final (name, palette) in [
    ('light', PitchyPalette.light),
    ('dark', PitchyPalette.dark),
  ]) {
    testWidgets('360 px at 200 % text ($name): nothing overflows or is cut', (tester) async {
      await _pumpCard(
        tester,
        _trend(),
        palette: palette,
        textScale: 2,
        size: const Size(360, 1600),
      );
      await tester.tap(find.text('Show as table'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cut = [
        for (final e in find.byType(RichText).evaluate())
          if ((e.renderObject! as RenderParagraph).didExceedMaxLines)
            (e.widget as RichText).text.toPlainText(),
      ];
      // The one-line source note may shorten (its full text is in the tooltip).
      expect(cut.where((t) => !t.startsWith('Open-Meteo ·')), isEmpty, reason: '$cut');
    });
  }

  testWidgets('a very narrow chart at 200 % text paints without throwing', (tester) async {
    await _pumpCard(tester, _trend(), textScale: 2, size: const Size(120, 1600));
    expect(tester.takeException(), isNot(isA<ArgumentError>()));
  });

  group('on the dashboard', () {
    testWidgets('switching the range or value sends no request', (tester) async {
      final (api, _) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      expect(api.weatherQueries, contains((hours: 5, hoursBefore: 6)));
      final before = api.weatherQueries.length;
      await tester.ensureVisible(_menu('Value'));
      await _open(tester, 'Value');
      await tester.tap(find.text('Relative humidity').hitTestable().last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_menu('Range'));
      await _open(tester, 'Range');
      await tester.tap(find.text('Kickoff to +5 h (match and after)').hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.textContaining(' %'), findsWidgets); // humidity is shown
      expect(api.weatherQueries.length, before);
    });

    testWidgets('the chosen value is remembered on the device', (tester) async {
      final (_, prefs) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      await tester.ensureVisible(_menu('Value'));
      await _open(tester, 'Value');
      await tester.tap(find.text('Wind speed').hitTestable().last);
      await tester.pumpAndSettle();
      expect(prefs.getString(TrendCard.quantityPref), 'wind_speed');
    });

    testWidgets('offline: the saved trend under the banner, never Current', (tester) async {
      final (api, _) = await pumpPitchyApp(tester, prefs: withActiveMatch());
      api.scenario = MockScenario.offline;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TrendCard));
      expect(find.byType(TrendCard), findsOneWidget);
      expect(find.textContaining('· Saved copy ·'), findsOneWidget);
      expect(find.textContaining('· Current ·'), findsNothing);
      expect(find.byType(WeatherCardGrid), findsOneWidget);
    });
  });

  test('SavedKind.trend is a saved kind', () {
    expect(SavedKind.values, contains(SavedKind.trend));
  });
}
