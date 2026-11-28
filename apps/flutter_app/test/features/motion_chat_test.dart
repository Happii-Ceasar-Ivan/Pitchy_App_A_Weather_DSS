// W2 (P-29): Ask Pitchy motion. The welcome -> chat switch crossfades and keeps
// the role; Start chatting and Send press-scale while "Try asking" rows don't;
// the "Reply copied" snackbar sits above the composer, not over it.

import 'dart:ui' show AccessibilityFeatures;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/storage/preferences.dart';
import 'package:pitchy/features/conversational_agent/chat_screen.dart';
import 'package:pitchy/shared/widgets/pitchy_crossfade.dart';
import 'package:pitchy/shared/widgets/press_scale.dart';

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

Future<void> _open(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  await pumpPitchyApp(
    tester,
    size: size,
    location: Routes.chat,
    prefs: {...withActiveMatch(), PrefKeys.chatRole: 'coach'},
  );
}

Future<void> _start(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Start chatting'));
  await tester.tap(find.text('Start chatting'));
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pump();
  await tester.tap(find.byTooltip('Send question'));
  await tester.pumpAndSettle();
}

Finder _pressScaleAround(Finder f) => find.ancestor(of: f, matching: find.byType(PitchyPressScale));

double _maxDy(WidgetTester tester) {
  final all = find.descendant(of: find.byType(PitchyCrossfade), matching: find.byType(Transform));
  var max = 0.0;
  for (final t in tester.widgetList<Transform>(all)) {
    max = t.transform.getTranslation().y.abs() > max ? t.transform.getTranslation().y.abs() : max;
  }
  return max;
}

void main() {
  setUpAll(loadAppFonts);

  group('welcome to chat crossfade', () {
    testWidgets('motion on: both views are on screen mid-switch, then only the chat', (
      tester,
    ) async {
      _reduce(tester, false);
      await _open(tester);
      expect(find.text('Welcome to Ask Pitchy'), findsOneWidget);
      await _start(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Welcome to Ask Pitchy'), findsOneWidget, reason: 'old view still fading');
      expect(find.text('Try asking'), findsOneWidget, reason: 'new view already rising in');
      expect(_maxDy(tester), greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Ask Pitchy'), findsNothing);
      expect(find.text('Try asking'), findsOneWidget);
      expect(_maxDy(tester), 0);
    });

    testWidgets('reduced: no offset, done within 150 ms, no ticker after', (tester) async {
      _reduce(tester, true);
      await _open(tester);
      await _start(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(_maxDy(tester), 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Welcome to Ask Pitchy'), findsNothing);
      expect(find.text('Try asking'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('the chosen role and the typed text survive the switch', (tester) async {
      _reduce(tester, false);
      await _open(tester);
      await _start(tester);
      await tester.pumpAndSettle();
      // The role from the entry screen is still set: the composer is open.
      expect(find.text('Ask about this match'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Is it safe to play?');
      await tester.pump();
      expect(find.text('Is it safe to play?'), findsOneWidget);
      // Replies and later changes inside the chat don't replay the crossfade.
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Ask Pitchy'), findsNothing);
    });
  });

  group('press scale', () {
    testWidgets('Start chatting and Send carry it; Try asking rows do not', (tester) async {
      _reduce(tester, false);
      await _open(tester);
      expect(_pressScaleAround(find.text('Start chatting')), findsOneWidget);
      await _start(tester);
      await tester.pumpAndSettle();
      expect(_pressScaleAround(find.byTooltip('Send question')), findsOneWidget);
      for (final q in starterQuestions) {
        expect(find.text(q), findsOneWidget);
        expect(_pressScaleAround(find.text(q)), findsNothing, reason: 'ripple only');
      }
    });

    testWidgets('Copy reply carries it; the reply bubble does not scale', (tester) async {
      _reduce(tester, false);
      await _open(tester);
      await _start(tester);
      await tester.pumpAndSettle();
      await _ask(tester, 'Typed question');
      expect(_pressScaleAround(find.byTooltip('Copy reply')), findsOneWidget);
      expect(_pressScaleAround(find.byKey(const ValueKey('r1'))), findsNothing);
    });
  });

  group('Reply copied snackbar', () {
    Future<void> copyAndCheck(WidgetTester tester, Size size, {double keyboard = 0}) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _open(tester, size: size);
      await _start(tester);
      await tester.pumpAndSettle();
      await _ask(tester, 'Typed question');
      await tester.ensureVisible(find.byTooltip('Copy reply'));
      await tester.tap(find.byTooltip('Copy reply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (keyboard > 0) {
        // The keyboard opens while the snackbar is up: both move up together.
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Reply copied'), findsOneWidget);
      // The visible card (the SnackBar widget's own box includes its margin).
      final snack = tester.getRect(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
      );
      final composer = tester.getRect(find.byKey(const ValueKey('chat-composer')));
      expect(
        snack.bottom,
        lessThanOrEqualTo(composer.top),
        reason: 'snackbar $snack must sit above the composer $composer',
      );
      expect(snack.left, greaterThanOrEqualTo(0));
      expect(snack.right, lessThanOrEqualTo(size.width));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    testWidgets('360x640', (tester) => copyAndCheck(tester, const Size(360, 640)));
    testWidgets('390x844', (tester) => copyAndCheck(tester, const Size(390, 844)));
    testWidgets(
      '360x640 with the keyboard open',
      (tester) => copyAndCheck(tester, const Size(360, 640), keyboard: 250),
    );
  });
}
