import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/domain/models/online_messages.dart';

void main() {
  group('Rematch Client Message Creators', () {
    test('createRematchOfferMessage creates valid JSON', () {
      final jsonStr = createRematchOfferMessage();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(map['t'], 'rematch_offer');
    });

    test('createRematchAcceptMessage creates valid JSON', () {
      final jsonStr = createRematchAcceptMessage();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(map['t'], 'rematch_accept');
    });

    test('createRematchDeclineMessage creates valid JSON', () {
      final jsonStr = createRematchDeclineMessage();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(map['t'], 'rematch_decline');
    });

    test('createRematchLeaveMessage creates valid JSON', () {
      final jsonStr = createRematchLeaveMessage();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(map['t'], 'rematch_leave');
    });
  });

  group('FinalServerMessage with rematchAvailable', () {
    test('parses rematchAvailable: true', () {
      const json = '{"t":"final","winnerIsMe":true,"scores":{"me":3,"opponent":1},"endedBy":"normal","rematchAvailable":true}';
      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final finalMsg = msg as FinalServerMessage;
      expect(finalMsg.rematchAvailable, isTrue);
      expect(finalMsg.winnerIsMe, isTrue);
      expect(finalMsg.myScore, 3);
      expect(finalMsg.opponentScore, 1);
    });

    test('parses rematchAvailable: false', () {
      const json = '{"t":"final","winnerIsMe":false,"scores":{"me":1,"opponent":2},"endedBy":"normal","rematchAvailable":false}';
      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final finalMsg = msg as FinalServerMessage;
      expect(finalMsg.rematchAvailable, isFalse);
    });

    test('omitted rematchAvailable defaults to false', () {
      const json = '{"t":"final","winnerIsMe":null,"myScore":2,"opponentScore":2,"endedBy":"normal"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final finalMsg = msg as FinalServerMessage;
      expect(finalMsg.rematchAvailable, isFalse);
    });

    test('non-boolean rematchAvailable safely defaults to false', () {
      const json = '{"t":"final","endedBy":"normal","rematchAvailable":"yes"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<FinalServerMessage>());
      final finalMsg = msg as FinalServerMessage;
      expect(finalMsg.rematchAvailable, isFalse);
    });
  });

  group('RematchOfferedServerMessage', () {
    test('parses valid rematch_offered message', () {
      const json = '{"t":"rematch_offered","byUid":"user_abc","expiresAtMs":1760000000000}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchOfferedServerMessage>());
      final offered = msg as RematchOfferedServerMessage;
      expect(offered.byUid, 'user_abc');
      expect(offered.expiresAtMs, 1760000000000);
    });

    test('tolerates missing or invalid expiresAtMs', () {
      const json = '{"t":"rematch_offered","byUid":"user_xyz"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchOfferedServerMessage>());
      final offered = msg as RematchOfferedServerMessage;
      expect(offered.byUid, 'user_xyz');
      expect(offered.expiresAtMs, 0);
    });

    test('tolerates extra unexpected fields', () {
      const json = '{"t":"rematch_offered","byUid":"u1","expiresAtMs":100,"extra":"ignored"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchOfferedServerMessage>());
      final offered = msg as RematchOfferedServerMessage;
      expect(offered.byUid, 'u1');
    });
  });

  group('RematchStatusServerMessage', () {
    test('parses declined status', () {
      const json = '{"t":"rematch_status","status":"declined"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchStatusServerMessage>());
      final statusMsg = msg as RematchStatusServerMessage;
      expect(statusMsg.status, RematchStatusType.declined);
      expect(statusMsg.rawStatus, 'declined');
    });

    test('parses expired status', () {
      const json = '{"t":"rematch_status","status":"expired"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchStatusServerMessage>());
      final statusMsg = msg as RematchStatusServerMessage;
      expect(statusMsg.status, RematchStatusType.expired);
    });

    test('parses opponent_left status', () {
      const json = '{"t":"rematch_status","status":"opponent_left"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchStatusServerMessage>());
      final statusMsg = msg as RematchStatusServerMessage;
      expect(statusMsg.status, RematchStatusType.opponentLeft);
    });

    test('parses closed status', () {
      const json = '{"t":"rematch_status","status":"closed"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchStatusServerMessage>());
      final statusMsg = msg as RematchStatusServerMessage;
      expect(statusMsg.status, RematchStatusType.closed);
    });

    test('unknown status safely maps to unknown', () {
      const json = '{"t":"rematch_status","status":"future_new_status"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchStatusServerMessage>());
      final statusMsg = msg as RematchStatusServerMessage;
      expect(statusMsg.status, RematchStatusType.unknown);
      expect(statusMsg.rawStatus, 'future_new_status');
    });
  });

  group('RematchErrorServerMessage', () {
    test('parses all known error codes', () {
      final codeMap = {
        'no_energy': RematchErrorCode.noEnergy,
        'opponent_no_energy': RematchErrorCode.opponentNoEnergy,
        'blocked': RematchErrorCode.blocked,
        'account_deleted': RematchErrorCode.accountDeleted,
        'not_available': RematchErrorCode.notAvailable,
        'unavailable': RematchErrorCode.unavailable,
      };

      for (final entry in codeMap.entries) {
        final json = '{"t":"rematch_error","code":"${entry.key}"}';
        final msg = parseServerMessage(json);
        expect(msg, isA<RematchErrorServerMessage>());
        final errorMsg = msg as RematchErrorServerMessage;
        expect(errorMsg.code, entry.value);
        expect(errorMsg.rawCode, entry.key);
      }
    });

    test('unknown error code safely maps to unknown', () {
      const json = '{"t":"rematch_error","code":"something_new"}';
      final msg = parseServerMessage(json);
      expect(msg, isA<RematchErrorServerMessage>());
      final errorMsg = msg as RematchErrorServerMessage;
      expect(errorMsg.code, RematchErrorCode.unknown);
      expect(errorMsg.rawCode, 'something_new');
    });
  });

  group('RematchState Domain Model Tests', () {
    test('initial state and terminal states correctly classified', () {
      expect(RematchState.unavailable.canOffer, isFalse);
      expect(RematchState.unavailable.isTerminal, isFalse);

      expect(RematchState.idle.canOffer, isTrue);
      expect(RematchState.idle.isTerminal, isFalse);

      final pendingSent = RematchState.pendingSent(secondsRemaining: 45);
      expect(pendingSent.canOffer, isFalse);
      expect(pendingSent.isTerminal, isFalse);

      final pendingReceived = RematchState.pendingReceived(secondsRemaining: 45);
      expect(pendingReceived.canOffer, isFalse);
      expect(pendingReceived.isTerminal, isFalse);

      expect(RematchState.starting.isTerminal, isFalse);
      expect(RematchState.declined.isTerminal, isTrue);
      expect(RematchState.expired.isTerminal, isTrue);
      expect(RematchState.opponentLeft.isTerminal, isTrue);
      expect(RematchState.closed.isTerminal, isTrue);
      expect(RematchState.error(RematchErrorCode.noEnergy).isTerminal, isTrue);

      const matchedInfo = MatchedServerMessage(
        matchId: 'm2',
        opponentName: 'Ali',
        opponentFrame: 'mint',
        opponentUid: 'u2',
        isFriendly: false,
      );
      final matchedState = RematchState.matched(matchedInfo);
      expect(matchedState.isTerminal, isTrue);
      expect(matchedState.matchedMessage.matchId, 'm2');
    });

    test('RematchState equality works as expected', () {
      expect(RematchState.idle, equals(const RematchIdle()));
      expect(
        RematchState.pendingSent(secondsRemaining: 40),
        equals(const RematchPendingSent(secondsRemaining: 40)),
      );
      expect(
        RematchState.error(RematchErrorCode.noEnergy),
        equals(const RematchError(code: RematchErrorCode.noEnergy)),
      );
      expect(
        RematchState.error(RematchErrorCode.noEnergy),
        isNot(equals(const RematchError(code: RematchErrorCode.blocked))),
      );
    });
  });
}
