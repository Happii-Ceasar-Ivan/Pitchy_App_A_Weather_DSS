// P-29 foundations: the press scale on standalone buttons, the crossfade for
// step and view changes, the snackbar helper, the spring token, tooltips and
// the instant theme switch.

import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pitchy/core/theme/motion.dart';
import 'package:pitchy/shared/widgets/pitchy_crossfade.dart';
import 'package:pitchy/shared/widgets/pitchy_snack_bar.dart';
import 'package:pitchy/shared/widgets/press_scale.dart';

import '../app_harness.dart';
import '../helpers.dart';

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced, size: const Size(400, 800)),
    child: Scaffold(body: Center(child: child)),
  ),
);

double _scale(WidgetTester tester) {
  final t = find.descendant(of: find.byType(PitchyPressScale), matching: find.byType(Transform));
  if (t.evaluate().isEmpty) return 1;
  return tester.widget<Transform>(t.first).transform.storage[0]; // x scale
}

Widget _button({bool enabled = true, VoidCallback? onPressed}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    const SizedBox(key: ValueKey('left'), width: 20, height: 20),
    PitchyPressScale(
      enabled: enabled,
      child: FilledButton(
        key: const ValueKey('btn'),
        onPressed: enabled ? (onPressed ?? () {}) : null,
        child: const Text('Update'),
      ),
    ),
    const SizedBox(key: ValueKey('right'), width: 20, height: 20),
  ],
);

void main() {
  setUpAll(loadAppFonts);

  group('press scale', () {
    testWidgets('shrinks to 0.97 while held and returns on release', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(_button(onPressed: () => taps++)));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('btn'))),
      );
      await tester.pump(); // the press starts on this frame
      await tester.pump(PitchyMotion.press);
      expect(_scale(tester), closeTo(PitchyMotion.pressScale, 0.001));
      await gesture.up();
      await tester.pump();
      await tester.pump(PitchyMotion.release);
      expect(_scale(tester), closeTo(1, 0.001));
      expect(taps, 1, reason: 'the wrapper never takes the tap');
      await tester.pumpAndSettle();
    });

    testWidgets('no layout shift: the button and its neighbours keep their boxes', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_button()));
      Rect box(String k) => tester.getRect(find.byKey(ValueKey(k)));
      final before = [box('left'), box('right')];
      final size = tester.getSize(find.byType(PitchyPressScale));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('btn'))),
      );
      await tester.pump(PitchyMotion.press);
      expect([box('left'), box('right')], before);
      expect(tester.getSize(find.byType(PitchyPressScale)), size);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('disabled button stays still', (tester) async {
      await tester.pumpWidget(_host(_button(enabled: false)));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('btn'))),
      );
      await tester.pump(PitchyMotion.press);
      expect(_scale(tester), 1);
      await gesture.up();
    });

    testWidgets('reduced motion: no scale and no running ticker after one pump', (tester) async {
      // A plain child, so the button's own ripple ticker doesn't count.
      await tester.pumpWidget(
        _host(
          const PitchyPressScale(
            child: SizedBox(
              key: ValueKey('btn'),
              width: 80,
              height: 40,
              child: ColoredBox(color: Colors.blue),
            ),
          ),
          reduced: true,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('btn'))),
      );
      await tester.pump();
      expect(_scale(tester), 1);
      expect(
        find.descendant(of: find.byType(PitchyPressScale), matching: find.byType(Transform)),
        findsNothing,
      );
      expect(tester.binding.transientCallbackCount, 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('crossfade', () {
    Widget view(String k, {bool reduced = false}) => _host(
      PitchyCrossfade(child: Text(k, key: ValueKey(k))),
      reduced: reduced,
    );

    testWidgets('motion on: fade in with a rise over 200 ms, old view out in 150 ms', (
      tester,
    ) async {
      await tester.pumpWidget(view('a'));
      await tester.pumpWidget(view('b'));
      await tester.pump(); // the switch starts on this frame
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('a'), findsOneWidget);
      final rise = tester
          .widget<Transform>(
            find.ancestor(of: find.text('b'), matching: find.byType(Transform)).first,
          )
          .transform
          .getTranslation()
          .y;
      expect(rise, greaterThan(0));
      expect(rise, lessThanOrEqualTo(4));
      final out = tester
          .widget<FadeTransition>(
            find.ancestor(of: find.text('a'), matching: find.byType(FadeTransition)).first,
          )
          .opacity
          .value;
      expect(out, lessThan(0.8), reason: 'the old view fades fast at first (ease-out)');
      await tester.pump(const Duration(milliseconds: 125));
      expect(find.text('a'), findsNothing, reason: 'exit finished by 150 ms (+1 frame)');
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced: opacity only, done within 150 ms', (tester) async {
      await tester.pumpWidget(view('a', reduced: true));
      await tester.pumpWidget(view('b', reduced: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        find.ancestor(of: find.text('b'), matching: find.byType(Transform)),
        findsNothing,
        reason: 'no movement',
      );
      expect(
        find.ancestor(of: find.text('b'), matching: find.byType(FadeTransition)),
        findsWidgets,
      );
      await tester.pump(PitchyMotion.quick);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.text('a'), findsNothing);
    });
  });

  group('tokens', () {
    test('spring is critically damped and never overshoots past 2 %', () {
      final sim = SpringSimulation(PitchyMotion.spring, 0, 1, 0);
      var max = 0.0;
      for (var t = 0.0; t < 1; t += 0.005) {
        max = sim.x(t) > max ? sim.x(t) : max;
      }
      expect(max, lessThanOrEqualTo(1.02));
      expect(sim.x(0.4), closeTo(1, 0.01), reason: 'settled well inside 400 ms');
    });

    test('reduced spec: no scale, no spring, fades within 150 ms', () {
      const r = PitchyMotionSpec(reduced: true);
      expect(r.pressScale, 1);
      expect(r.spring, isFalse);
      expect(r.rise, 0);
      for (final d in [r.switchIn, r.switchOut, r.message, r.fade, r.snackBar.duration!]) {
        expect(d, lessThanOrEqualTo(PitchyMotion.quick));
      }
      const m = PitchyMotionSpec(reduced: false);
      expect(m.switchOut, lessThan(m.switchIn), reason: 'exits beat entrances');
      expect(m.snackBar.reverseDuration!, lessThan(m.snackBar.duration!));
    });
  });

  testWidgets('snackbar helper replaces the current snackbar', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    showPitchySnackBar(ctx, const SnackBar(content: Text('one')));
    await tester.pumpAndSettle();
    showPitchySnackBar(ctx, const SnackBar(content: Text('two')));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('theme and light/dark switches are instant (P-29)', (tester) async {
    await pumpPitchyApp(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeAnimationStyle, AnimationStyle.noAnimation);
  });
}
