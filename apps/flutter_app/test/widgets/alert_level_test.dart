import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/shared/models/alerts.dart';
import 'package:pitchy/shared/widgets/alert_level.dart';

OfficialAlert _alert({String event = '', String subtype = '', String headline = ''}) =>
    OfficialAlert(
      issuer: 'PAGASA',
      event: event,
      subtype: subtype,
      headline: headline,
      message: '',
      issuedAt: null,
      validUntil: null,
      matchedAreas: const [],
    );

void main() {
  group('PAGASA level → fixed warning colour (P-18)', () {
    test('thunderstorm: watch yellow, advisory orange, warning red', () {
      expect(
        alertLevelOf(_alert(event: 'THUNDERSTORM', subtype: 'thunderstorm watch')),
        AlertLevel.advisory,
      );
      expect(
        alertLevelOf(_alert(event: 'THUNDERSTORM', subtype: 'thunderstorm advisory')),
        AlertLevel.warning,
      );
      expect(
        alertLevelOf(_alert(event: 'THUNDERSTORM', subtype: 'thunderstorm warning')),
        AlertLevel.danger,
      );
    });

    test('rainfall: PAGASA yellow, orange, red', () {
      AlertLevel? rain(String h) => alertLevelOf(_alert(event: 'RAINFALL', headline: h));
      expect(rain('Yellow Heavy Rainfall Warning'), AlertLevel.advisory);
      expect(rain('Orange Heavy Rainfall Warning'), AlertLevel.warning);
      expect(rain('Red Heavy Rainfall Warning'), AlertLevel.danger);
      // Whole words only: "reduced" is not "red".
      expect(rain('Rainfall advisory: reduced visibility'), isNull);
    });

    test('tropical cyclone wind signals: 1 yellow, 2–3 orange, 4–5 red', () {
      AlertLevel? signal(String h) => alertLevelOf(_alert(event: 'TROPICAL CYCLONE', headline: h));
      expect(signal('Tropical Cyclone Wind Signal No. 1'), AlertLevel.advisory);
      expect(signal('Tropical Cyclone Wind Signal No. 3'), AlertLevel.warning);
      expect(signal('Tropical Cyclone Wind Signal #5'), AlertLevel.danger);
    });

    test('unknown kinds stay neutral; the app never guesses', () {
      expect(alertLevelOf(_alert(event: 'FLOOD', subtype: 'general flood advisory')), isNull);
      expect(alertLevelOf(_alert(event: 'THUNDERSTORM', subtype: 'information')), isNull);
    });

    test('the most severe alert comes first; ties keep the backend order', () {
      final watch = _alert(event: 'THUNDERSTORM', subtype: 'thunderstorm watch', headline: 'a');
      final other = _alert(event: 'FLOOD', headline: 'b');
      final red = _alert(event: 'RAINFALL', headline: 'Red Rainfall Warning');
      final watch2 = _alert(event: 'THUNDERSTORM', subtype: 'thunderstorm watch', headline: 'c');
      expect(bySeverity([watch, other, red, watch2]), [red, watch, watch2, other]);
    });
  });
}
