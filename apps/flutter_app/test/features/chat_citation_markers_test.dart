// Citation labels ([A], [D1]..) are for the backend's answer check; on screen
// they read as unfinished text, so the app hides them (user, 2026-11-25). The
// rest of the answer is shown exactly as sent, and "Based on" still lists the
// sources.

import 'package:flutter_test/flutter_test.dart';
import 'package:pitchy/features/conversational_agent/chat_reply.dart';
import 'package:pitchy/shared/models/conversation.dart';
import 'package:pitchy/shared/services/mock/fixtures.dart';

final _now = DateTime.utc(2026, 11, 23, 4);

void main() {
  group('hideCitationMarkers', () {
    for (final (input, shown) in [
      (
        'The match management team decides on cooling breaks [A][D1].',
        'The match management team decides on cooling breaks.',
      ),
      (
        'Cooling breaks are used at 32 °C or more [D1].',
        'Cooling breaks are used at 32 °C or more.',
      ),
      ('Heat is high [A], so drink often [D2][D3].', 'Heat is high, so drink often.'),
      ('[A] No level is set.', 'No level is set.'),
      ('Line one [D1].\nLine two [A].', 'Line one.\nLine two.'),
      ('Labels in one bracket [A, D1] too.', 'Labels in one bracket too.'),
      ('Up to [D12] documents.', 'Up to documents.'),
    ]) {
      test('"$input"', () => expect(hideCitationMarkers(input), shown));
    }

    for (final kept in [
      'Plain text with no labels.',
      'Brackets that are not labels stay: [see note], [B], [d1], [D], [AB].',
      '**bold** <b>tag</b>',
    ]) {
      test('kept as sent: "$kept"', () => expect(hideCitationMarkers(kept), kept));
    }
  });

  test('an answer shows without labels; the references are unchanged', () {
    final json = conversationJson(now: _now, role: 'coach');
    json['answer'] = 'Officials decide on cooling breaks [A][D1].';
    final r = ConversationResponse.fromJson(json);
    final v = ChatReplyView.of(r);
    expect(v.text, 'Officials decide on cooling breaks.');
    expect(v.references, isNotEmpty);
  });

  test('a reply that is only labels falls back to the no-answer text', () {
    final json = conversationJson(now: _now, role: 'coach');
    json['answer'] = '[A][D1]';
    final v = ChatReplyView.of(ConversationResponse.fromJson(json));
    expect(v.isAnswer, isFalse);
  });
}
