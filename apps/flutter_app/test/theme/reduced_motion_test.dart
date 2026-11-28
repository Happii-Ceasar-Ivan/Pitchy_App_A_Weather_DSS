// Reduced motion (Android "Remove animations"): expanders are instant, pushed
// routes are opacity-only and short, and the new-reply cue loses its rise.

import 'dart:async';
import 'dart:ui' show AccessibilityFeatures;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/state/loadable.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/core/theme/motion.dart';
import 'package:pitchy/shared/models/alerts.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';
import 'package:pitchy/shared/widgets/alerts_panel.dart';
import 'package:pitchy/shared/widgets/weather_value_card.dart';

import '../app_harness.dart';
import '../helpers.dart';

class _Features implements AccessibilityFeatures {
  const _Features(this.disableAnimations);
  @override
  final bool disableAnimations;
  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}

void _reduce(WidgetTester tester, bool on) {
  tester.platformDispatcher.accessibilityFeaturesTestValue = _Features(on);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Finder _arrival(int id) => find.byKey(ValueKey('arrive$id'));

double _opacity(WidgetTester tester, int id) => tester
    .widget<FadeTransition>(
      find.descendant(of: _arrival(id), matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

double _dy(WidgetTester tester, int id) => tester
    .widget<Transform>(find.descendant(of: _arrival(id), matching: find.byType(Transform)).first)
    .transform
    .getTranslation()
    .y;

Future<void> _openChatAndAsk(WidgetTester tester, String q) async {
  await pumpPitchyApp(
    tester,
    prefs: {...withActiveMatch(), PrefKeys.chatRole: 'coach'},
    location: Routes.chat,
    size: const Size(390, 1600),
  );
  await tester.tap(find.text('Start chatting'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('r1')), findsNothing, reason: 'nothing on open');
  await _ask(tester, q);
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pump();
  await tester.tap(find.byTooltip('Send question'));
  await tester.pump(); // reply lands
  await tester.pump(const Duration(milliseconds: 1)); // cue's first frame
}

void main() {
  setUpAll(loadAppFonts);

  group('weather value card expand', () {
    double detailsHeight(WidgetTester tester) {
      final open = find.byWidgetPredicate((w) => w is WeatherValueCard && w.expanded);
      return tester.getSize(find.descendant(of: open, matching: find.byType(AnimatedSize))).height;
    }

    Future<(double, double)> heights(WidgetTester tester) async {
      await pumpPitchyApp(tester, prefs: withActiveMatch(), size: const Size(390, 2400));
      await tester.tap(find.byType(WeatherValueCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final early = detailsHeight(tester);
      await tester.pumpAndSettle();
      final full = detailsHeight(tester);
      expect(full, greaterThan(0));
      return (early, full);
    }

    testWidgets('motion on: expands over 220 ms', (tester) async {
      _reduce(tester, false);
      await heights(tester);
      final size = find.descendant(
        of: find.byWidgetPredicate((w) => w is WeatherValueCard && w.expanded),
        matching: find.byType(AnimatedSize),
      );
      expect(tester.widget<AnimatedSize>(size).duration, PitchyMotion.expand);
    });

    testWidgets('reduced: fully open after one pump, no running ticker', (tester) async {
      _reduce(tester, true);
      final (early, full) = await heights(tester);
      expect(early, full);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('page transitions', () {
    Future<void> pumpRoutes(WidgetTester tester, bool reduced) async {
      _reduce(tester, reduced);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: PitchyPageTransitionsBuilder(),
                TargetPlatform.windows: PitchyPageTransitionsBuilder(),
              },
            ),
          ),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );
      unawaited(
        Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('pushed'))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    testWidgets('reduced: fade only, finished within 150 ms', (tester) async {
      await pumpRoutes(tester, true);
      Finder above(Type t) => find.ancestor(
        of: find.text('pushed', skipOffstage: false),
        matching: find.byType(t, skipOffstage: false),
      );
      expect(above(FadeTransition), findsWidgets);
      expect(above(SlideTransition), findsNothing);
      expect(
        tester
            .widgetList<Transform>(above(Transform))
            .where((w) => w.transform.getTranslation().y != 0),
        isEmpty,
        reason: 'no rise when reduced',
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('motion on: fade and a 4 px rise, 200 ms', (tester) async {
      await pumpRoutes(tester, false);
      await tester.pump(const Duration(milliseconds: 20)); // the transition's first built frame
      final pushed = find.ancestor(
        of: find.text('pushed', skipOffstage: false),
        matching: find.byType(Transform, skipOffstage: false),
      );
      final rise = tester
          .widgetList<Transform>(pushed)
          .map((w) => w.transform.getTranslation().y)
          .fold<double>(0, (a, b) => b > a ? b : a);
      expect(rise, greaterThan(0));
      expect(rise, lessThanOrEqualTo(4), reason: 'a fixed 4 px, not a share of the page');
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('new reply cue', () {
    testWidgets('motion on: fades in with a rise; earlier replies stay put', (tester) async {
      _reduce(tester, false);
      await _openChatAndAsk(tester, 'Do we need cooling breaks?');
      expect(_opacity(tester, 1), lessThan(1));
      expect(_dy(tester, 1), greaterThan(0));
      expect(_dy(tester, 1), lessThanOrEqualTo(4));
      await tester.pumpAndSettle();
      expect(_opacity(tester, 1), 1);
      expect(_dy(tester, 1), 0);
      await _ask(tester, 'And hydration?');
      expect(_opacity(tester, 1), 1, reason: 'the first reply does not replay');
      expect(_opacity(tester, 3), lessThan(1));
      await tester.pumpAndSettle();
    });

    testWidgets('reduced: opacity only, no offset, within 150 ms', (tester) async {
      _reduce(tester, true);
      await _openChatAndAsk(tester, 'Do we need cooling breaks?');
      expect(_opacity(tester, 1), lessThan(1));
      expect(_dy(tester, 1), 0);
      await tester.pump(PitchyMotion.quick);
      expect(_opacity(tester, 1), 1);
      expect(_dy(tester, 1), 0);
    });
  });

  group('other expanders under reduced motion (P-29 review)', () {
    testWidgets('Safety "How this was worked out": open after one pump, no ticker', (
      tester,
    ) async {
      _reduce(tester, true);
      await pumpPitchyApp(
        tester,
        prefs: withActiveMatch(),
        location: Routes.safety,
        size: const Size(390, 2400),
      );
      await tester.tap(find.text('How this was worked out').first);
      await tester.pump();
      expect(find.text('Measurement times'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final early = tester.getSize(
        find
            .ancestor(of: find.text('Measurement times'), matching: find.byType(AnimatedSize))
            .first,
      );
      await tester.pumpAndSettle(); // the tap's ripple is the only thing still running
      expect(
        tester.getSize(
          find
              .ancestor(of: find.text('Measurement times'), matching: find.byType(AnimatedSize))
              .first,
        ),
        early,
        reason: 'already full size',
      );
      await tester.tap(find.text('How this was worked out').first);
      await tester.pump();
      expect(find.text('Measurement times'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('alert details: open after one pump, no ticker', (tester) async {
      _reduce(tester, true);
      await pumpThemed(
        tester,
        AlertsPanel(
          alerts: Loaded(VenueAlerts.fromJson(alertsJson(now: testNow, withAlert: true))),
        ),
      );
      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(find.text('Hide'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final early = tester.getSize(find.byType(AnimatedSize));
      await tester.pumpAndSettle(); // the tap's ripple is the only thing still running
      expect(tester.getSize(find.byType(AnimatedSize)), early, reason: 'already full size');
      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.text('Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
