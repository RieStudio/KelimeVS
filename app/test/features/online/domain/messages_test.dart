import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/domain/models/online_match_state.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

void main() {
  group('Client Message Creators & Sanitization', () {
    test('createQueueMessage sanitizes name and limits to 20 chars', () {
      final msg1 = createQueueMessage('   Ahmet   Yılmaz   ');
      final map1 = jsonDecode(msg1) as Map<String, dynamic>;
      expect(map1['t'], 'queue');
      expect(map1['name'], 'Ahmet Yılmaz');

      final msg2 = createQueueMessage('1234567890123456789012345');
      final map2 = jsonDecode(msg2) as Map<String, dynamic>;
      expect(map2['name'], '12345678901234567890');
      expect(map2['name'].length, 20);

      final msg3 = createQueueMessage('   ');
      final map3 = jsonDecode(msg3) as Map<String, dynamic>;
      expect(map3['name'], 'Oyuncu');
    });

    test('createCancelMessage creates valid JSON', () {
      final msg = createCancelMessage();
      final map = jsonDecode(msg) as Map<String, dynamic>;
      expect(map['t'], 'cancel');
    });

    test('createSubmitMessage sanitizes text and limits to 40 chars', () {
      final msg1 = createSubmitMessage('   ankara   başkent   ');
      final map1 = jsonDecode(msg1) as Map<String, dynamic>;
      expect(map1['t'], 'submit');
      expect(map1['text'], 'ankara başkent');

      final longText = 'a' * 50;
      final msg2 = createSubmitMessage(longText);
      final map2 = jsonDecode(msg2) as Map<String, dynamic>;
      expect(map2['text'], 'a' * 40);
      expect((map2['text'] as String).length, 40);
    });

    test('createLeaveMessage and createSyncMessage create valid JSON', () {
      final leave = jsonDecode(createLeaveMessage()) as Map<String, dynamic>;
      expect(leave['t'], 'leave');

      final sync = jsonDecode(createSyncMessage()) as Map<String, dynamic>;
      expect(sync['t'], 'sync');
    });
  });

  group('Server Message Parsers', () {
    test('parses queued message', () {
      final msg = parseServerMessage('{"t":"queued"}');
      expect(msg, isA<QueuedServerMessage>());
    });

    test('parses cancelled message', () {
      final msg = parseServerMessage('{"t":"cancelled"}');
      expect(msg, isA<CancelledServerMessage>());
    });

    test('parses matched message', () {
      final json = '{"t":"matched","matchId":"m_123","opponentName":"Mehmet"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<MatchedServerMessage>());
      final matched = msg as MatchedServerMessage;
      expect(matched.matchId, 'm_123');
      expect(matched.opponentName, 'Mehmet');
    });

    test('parses error message', () {
      final json = '{"t":"error","code":"content_unavailable"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<ErrorServerMessage>());
      expect((msg as ErrorServerMessage).code, 'content_unavailable');
    });

    test('parses state message and calculates clock offset & kalanSureMs', () {
      final json = jsonEncode({
        't': 'state',
        'serverNowMs': 10000,
        'phase': 'roundActive',
        'roundNumber': 2,
        'scores': {'me': 1, 'opponent': 0},
        'question': {'id': 'q1', 'text': 'Soru 1'},
        'turnIsMine': true,
        'deadlineMs': 25000,
        'myHintsLeft': 1,
        'attempts': [
          {'mine': true, 'text': 'ankara', 'result': 'wrong', 'hintShown': false},
          {'mine': false, 'text': 'izmir', 'result': 'correct'}
        ],
        'opponentName': 'Rakip',
        'opponentConnected': true,
        'nextRoundAtMs': 30000,
      });

      // Yerel saat: 8000 ms.
      // Offset: serverNowMs(10000) - receivedLocalMs(8000) = +2000 ms.
      final msg = parseServerMessage(json, receivedLocalMs: 8000);
      expect(msg, isA<StateServerMessage>());
      final state = (msg as StateServerMessage).state;

      expect(state.phase, OnlineMatchPhase.roundActive);
      expect(state.roundNumber, 2);
      expect(state.myScore, 1);
      expect(state.opponentScore, 0);
      expect(state.question?.id, 'q1');
      expect(state.turnIsMine, isTrue);
      expect(state.deadlineMs, 25000);
      expect(state.myHintsLeft, 1);
      expect(state.attempts.length, 2);
      expect(state.opponentName, 'Rakip');
      expect(state.opponentConnected, isTrue);
      expect(state.clockOffsetMs, 2000);

      // Yerel saat 11000 olduğunda:
      // Tahmini sunucu saati = 11000 + 2000 = 13000 ms.
      // Kalan süre = 25000 - 13000 = 12000 ms.
      expect(state.kalanSureMs(11000), 12000);

      // Yerel saat 24000 olduğunda:
      // Tahmini sunucu saati = 24000 + 2000 = 26000 ms. (deadline 25000 aşıldı)
      // Kalan süre = 0 ms.
      expect(state.kalanSureMs(24000), 0);
    });

    test('parses feedback message', () {
      final json = '{"t":"feedback","kind":"nearMiss","reason":"cooldown"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<FeedbackServerMessage>());
      final fb = msg as FeedbackServerMessage;
      expect(fb.kind, 'nearMiss');
      expect(fb.reason, 'cooldown');
    });

    test('parses final message', () {
      final json = jsonEncode({
        't': 'final',
        'rounds': [
          {
            'questionId': 'q1',
            'attempts': [
              {'mine': true, 'text': 'ankara', 'result': 'correct'}
            ],
            'winnerIsMe': true,
            'reason': 'normal'
          }
        ],
        'scores': {'me': 2, 'opponent': 0},
        'winnerIsMe': true,
        'endedBy': 'normal'
      });

      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final fin = msg as FinalServerMessage;
      expect(fin.rounds.length, 1);
      expect(fin.rounds.first.questionId, 'q1');
      expect(fin.myScore, 2);
      expect(fin.opponentScore, 0);
      expect(fin.winnerIsMe, isTrue);
      expect(fin.endedBy, 'normal');
    });

    test('parses voided message', () {
      final json = '{"t":"voided","reason":"opponent_absent"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<VoidedServerMessage>());
      expect((msg as VoidedServerMessage).reason, 'opponent_absent');
    });

    test('handles malformed and unknown messages safely without throwing', () {
      expect(parseServerMessage(null), isA<UnknownServerMessage>());
      expect(parseServerMessage(''), isA<UnknownServerMessage>());
      expect(parseServerMessage('invalid json {['), isA<UnknownServerMessage>());
      expect(parseServerMessage('{"t":"unknown_type"}'), isA<UnknownServerMessage>());
      expect(parseServerMessage('{"t":"matched"}'), isA<UnknownServerMessage>());
      expect(parseServerMessage(12345), isA<UnknownServerMessage>());
      expect(parseServerMessage(['list']), isA<UnknownServerMessage>());
    });
  });
}
