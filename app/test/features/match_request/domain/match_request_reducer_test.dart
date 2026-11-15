import 'package:app/features/match_request/data/match_request_messages.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/domain/match_request_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reduceMatchRequestMessage', () {
    test('UserInboxRequestReceivedMessage gelen isteği kaydeder ve lastError temizler', () {
      final initial = const MatchRequestsState().copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.unavailable,
          retryAfterSec: 0,
        ),
      );

      const msg = UserInboxRequestReceivedMessage(
        id: 'req_100',
        fromUid: 'u_sender',
        fromNickname: 'Bob',
        fromFrame: 'frame_gold',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: 80000,
      );

      final next = reduceMatchRequestMessage(initial, msg, localNowMs: 35000);

      expect(next.incoming, isNotNull);
      expect(next.incoming!.id, 'req_100');
      expect(next.incoming!.fromUid, 'u_sender');
      expect(next.incoming!.fromNickname, 'Bob');
      expect(next.incoming!.fromFrame, 'frame_gold');
      expect(next.incoming!.type, MatchRequestType.ranked);
      expect(next.incoming!.origin, MatchRequestOrigin.rematch);
      expect(next.incoming!.expiresAtMs, 80000);
      expect(next.incoming!.initialRemainingMs, 45000);
      expect(next.incoming!.isSnapshot, isFalse);
      expect(next.lastError, isNull);
    });

    test('Yeni bir UserInboxRequestReceivedMessage gelirse önceki incoming üzerine yazar (tekil istek garantisi)', () {
      const msg1 = UserInboxRequestReceivedMessage(
        id: 'req_1',
        fromUid: 'u_1',
        fromNickname: 'One',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 50000,
      );

      final state1 = reduceMatchRequestMessage(const MatchRequestsState(), msg1, localNowMs: 5000);
      expect(state1.incoming?.id, 'req_1');

      const msg2 = UserInboxRequestReceivedMessage(
        id: 'req_2',
        fromUid: 'u_2',
        fromNickname: 'Two',
        fromFrame: 'frame_2',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: 60000,
      );

      final state2 = reduceMatchRequestMessage(state1, msg2, localNowMs: 15000);
      expect(state2.incoming?.id, 'req_2');
      expect(state2.incoming?.fromNickname, 'Two');
    });

    test('UserInboxRequestSentMessage giden isteği kaydeder ve lastError temizler', () {
      final initial = const MatchRequestsState().copyWith(
        lastError: const MatchRequestErrorInfo(
          code: MatchRequestErrorCode.rateLimited,
          retryAfterSec: 15,
        ),
      );

      const msg = UserInboxRequestSentMessage(
        id: 'req_out_1',
        toUid: 'u_target',
        toNickname: 'Alice',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 90000,
      );

      final next = reduceMatchRequestMessage(initial, msg, localNowMs: 45000);

      expect(next.outgoing, isNotNull);
      expect(next.outgoing!.id, 'req_out_1');
      expect(next.outgoing!.toUid, 'u_target');
      expect(next.outgoing!.toNickname, 'Alice');
      expect(next.outgoing!.type, MatchRequestType.friendly);
      expect(next.outgoing!.origin, MatchRequestOrigin.profile);
      expect(next.outgoing!.expiresAtMs, 90000);
      expect(next.outgoing!.initialRemainingMs, 45000);
      expect(next.outgoing!.isSnapshot, isFalse);
      expect(next.lastError, isNull);
    });

    test('UserInboxRequestStatusMessage gelen istek için (declined, expired, cancelled)', () {
      const receiveMsg = UserInboxRequestReceivedMessage(
        id: 'req_in_1',
        fromUid: 'u_1',
        fromNickname: 'One',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 50000,
      );
      final withIncoming = reduceMatchRequestMessage(const MatchRequestsState(), receiveMsg, localNowMs: 5000);
      expect(withIncoming.hasActiveIncoming, isTrue);

      const statusMsg = UserInboxRequestStatusMessage(
        id: 'req_in_1',
        status: MatchRequestEndStatus.declined,
      );
      final afterStatus = reduceMatchRequestMessage(withIncoming, statusMsg, localNowMs: 6000);

      expect(afterStatus.incoming, isNull);
      expect(afterStatus.lastEndStatus, isNotNull);
      expect(afterStatus.lastEndStatus!.id, 'req_in_1');
      expect(afterStatus.lastEndStatus!.status, MatchRequestEndStatus.declined);
      expect(afterStatus.lastEndStatus!.isOutgoing, isFalse);
    });

    test('UserInboxRequestStatusMessage giden istek için (declined, expired, cancelled)', () {
      const sentMsg = UserInboxRequestSentMessage(
        id: 'req_out_2',
        toUid: 'u_2',
        toNickname: 'Two',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: 90000,
      );
      final withOutgoing = reduceMatchRequestMessage(const MatchRequestsState(), sentMsg, localNowMs: 45000);
      expect(withOutgoing.hasActiveOutgoing, isTrue);

      const statusMsg = UserInboxRequestStatusMessage(
        id: 'req_out_2',
        status: MatchRequestEndStatus.expired,
      );
      final afterStatus = reduceMatchRequestMessage(withOutgoing, statusMsg, localNowMs: 90000);

      expect(afterStatus.outgoing, isNull);
      expect(afterStatus.lastEndStatus, isNotNull);
      expect(afterStatus.lastEndStatus!.id, 'req_out_2');
      expect(afterStatus.lastEndStatus!.status, MatchRequestEndStatus.expired);
      expect(afterStatus.lastEndStatus!.isOutgoing, isTrue);
    });

    test('UserInboxRequestErrorMessage giden isteği temizlemeden lastError alanına kaydeder', () {
      const errorMsg = UserInboxRequestErrorMessage(
        code: MatchRequestErrorCode.noEnergy,
        retryAfterSec: 0,
      );

      final next = reduceMatchRequestMessage(const MatchRequestsState(), errorMsg, localNowMs: 1000);

      expect(next.lastError, isNotNull);
      expect(next.lastError!.code, MatchRequestErrorCode.noEnergy);
      expect(next.lastError!.retryAfterSec, 0);
    });

    test('UserInboxMatchedMessage hem gelen hem giden istekleri temizler', () {
      const inMsg = UserInboxRequestReceivedMessage(
        id: 'req_in_3',
        fromUid: 'u_in',
        fromNickname: 'In',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 50000,
      );
      const outMsg = UserInboxRequestSentMessage(
        id: 'req_out_3',
        toUid: 'u_out',
        toNickname: 'Out',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: 60000,
      );

      var state = reduceMatchRequestMessage(const MatchRequestsState(), inMsg, localNowMs: 5000);
      state = reduceMatchRequestMessage(state, outMsg, localNowMs: 6000);
      expect(state.incoming, isNotNull);
      expect(state.outgoing, isNotNull);

      const matchedMsg = UserInboxMatchedMessage(
        matchId: 'm_new_123',
        opponentUid: 'u_in',
        opponentName: 'In',
        opponentFrame: 'frame_1',
        isFriendly: true,
      );

      final finalState = reduceMatchRequestMessage(state, matchedMsg, localNowMs: 7000);

      expect(finalState.incoming, isNull);
      expect(finalState.outgoing, isNull);
      expect(finalState.lastError, isNull);
    });

    test('UserInboxPongMessage durumu değiştirmez', () {
      const state = MatchRequestsState();
      const pongMsg = UserInboxPongMessage();

      final next = reduceMatchRequestMessage(state, pongMsg, localNowMs: 1000);
      expect(next, same(state));
    });

    test('isSnapshot true olan gelen istekte snapshot kalan süresi hesaplanır', () {
      const msg = UserInboxRequestReceivedMessage(
        id: 'req_snap_1',
        fromUid: 'u_snap',
        fromNickname: 'SnapUser',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 100000,
        isSnapshot: true,
      );

      final next = reduceMatchRequestMessage(
        const MatchRequestsState(),
        msg,
        nowMs: 70000, // 30 sn kalmış
      );

      expect(next.incoming, isNotNull);
      expect(next.incoming!.isSnapshot, isTrue);
      expect(next.incoming!.initialRemainingMs, 30000);
      expect(next.incoming!.calculateRemainingSeconds(), 30);
    });
  });
}
