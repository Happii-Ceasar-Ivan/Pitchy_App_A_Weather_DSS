// W3 of the motion plan (P-29): validation messages that appear in place, the
// press scale on standalone buttons of the forms, settings and shared widgets,
// and the snackbar helper. Motion never changes a message's words.

import 'dart:typed_data' show Uint8List;
import 'dart:ui' show AccessibilityFeatures;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/config/donations.dart';
import 'package:pitchy/core/errors/api_failure.dart';
import 'package:pitchy/core/routing/app_router.dart';
import 'package:pitchy/core/state/loadable.dart';
import 'package:pitchy/core/theme/app_theme.dart';
import 'package:pitchy/core/theme/pitchy_palette.dart';
import 'package:pitchy/features/settings/support_screen.dart';
import 'package:pitchy/shared/widgets/pitchy_top_bar.dart';
import 'package:pitchy/shared/widgets/press_scale.dart';
import 'package:pitchy/shared/widgets/request_states.dart';

import '../app_harness.dart';
import '../helpers.dart';

class _Features implements AccessibilityFeatures {
  const _Features(this.disableAnimations);
  @override
  final bool disableAnimations;
  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}

void _reduce(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const _Features(true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Finder _pressScaleAround(Finder button) =>
    find.ancestor(of: button, matching: find.byType(PitchyPressScale));

/// The size-animating box that holds the venue error.
Finder get _venueErrorBox =>
    find.ancestor(of: find.text('Choose a venue.'), matching: find.byType(AnimatedSize)).first;

/// The error's own row: its height is the error's full height.
double _errorHeight(WidgetTester tester) => tester.getSize(find.text('Choose a venue.')).height;

Future<void> _submitEmptyForm(WidgetTester tester) async {
  await pumpPitchyApp(tester, location: Routes.matchSetup);
  await tester.scrollUntilVisible(find.text('Show conditions'), 200);
  await tester.tap(find.text('Show conditions'));
}

void main() {
  setUpAll(loadAppFonts);

  group('match setup inline errors', () {
    testWidgets('grow in with a fade when motion is on', (tester) async {
      await _submitEmptyForm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Choose a venue.'), findsOneWidget);
      final mid = tester.getSize(_venueErrorBox).height;
      await tester.pumpAndSettle();
      final full = tester.getSize(_venueErrorBox).height;
      expect(full, greaterThan(18));
      expect(mid, greaterThan(0));
      expect(mid, lessThan(full), reason: 'still growing 60 ms in');
      expect(find.text('Choose a venue.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsWidgets);
    });

    testWidgets('are instant in size when motion is reduced, words intact', (tester) async {
      _reduce(tester);
      await _submitEmptyForm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final first = _errorHeight(tester);
      expect(first, greaterThan(10), reason: 'full height straight away');
      expect(
        find.ancestor(of: find.text('Choose a venue.'), matching: find.byType(AnimatedSize)),
        findsNothing,
        reason: 'no size animation under reduced motion',
      );
      await tester.pumpAndSettle();
      expect(_errorHeight(tester), first);
      expect(find.text('Choose a venue.'), findsOneWidget);
      expect(find.text('Choose a kickoff time.'), findsOneWidget);
    });

    testWidgets('the error clears again when the venue is chosen', (tester) async {
      await _submitEmptyForm(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rizal Memorial Stadium'));
      await tester.tap(find.text('Show conditions'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a venue.'), findsNothing);
    });
  });

  group('press scale on standalone buttons', () {
    testWidgets('on the match setup submit button, not on the venue radio rows', (tester) async {
      await pumpPitchyApp(tester, location: Routes.matchSetup);
      await tester.scrollUntilVisible(find.text('Show conditions'), 200);
      expect(_pressScaleAround(find.byType(FilledButton)), findsOneWidget);
      final row = find.byType(RadioListTile<String>).first;
      expect(_pressScaleAround(row), findsNothing);
      expect(find.descendant(of: row, matching: find.byType(PitchyPressScale)), findsNothing);
    });

    testWidgets('not on Try again in the request error state (a state element)', (tester) async {
      await pumpThemed(
        tester,
        SizedBox(
          height: 400,
          child: LoadableView<String>(
            value: const Failed(NetworkFailure()),
            builder: (_, v) => Text(v),
            onRetry: () {},
          ),
        ),
      );
      expect(_pressScaleAround(find.text('Try again')), findsNothing);
    });

    testWidgets('on the top bar icon button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(PitchyPalette.light),
          home: const Scaffold(
            appBar: PitchyTopBar(title: 'Test'),
            body: SizedBox.shrink(),
          ),
        ),
      );
      final back = find.byTooltip('Back to dashboard');
      expect(back, findsOneWidget);
      expect(_pressScaleAround(back), findsOneWidget);
    });
  });

  testWidgets('support screen: the snackbar helper shows the same text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(PitchyPalette.light),
        home: SupportScreen(qr: Donations.maya!, saver: _Saver()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save QR to Photos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Couldn’t save the QR. Take a screenshot instead.'), findsOneWidget);
    expect(_pressScaleAround(find.text('Saving…')), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}

class _Saver implements QrSaver {
  @override
  Future<QrSaveResult> save(Uint8List bytes, String fileName) async => QrSaveResult.failed;
}
