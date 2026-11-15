import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/match_request/data/match_request_messages.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';

void main() {
  group('MatchRequestMessages Serialization & Parsing', () {
    test('İstemci mesajları JSON dönüşümü', () {
      expect(const UserInboxPingMessage().toJson(), {'t': 'ping'});

      expect(
        const UserInboxPresenceMessage('busy').toJson(),
        {'t': 'presence', 'state': 'busy'},
      );

      expect(
        UserInboxSendRequestMessage(
          origin: MatchRequestOrigin.profile,
          toUid: 'target_123',
        ).toJson(),
        {
          't': 'send_match_request',
          'origin': 'profile',
          'toUid': 'target_123',
        },
      );

      expect(
        UserInboxSendRequestMessage(
          origin: MatchRequestOrigin.rematch,
          toUid: 'target_123',
          matchId: 'm_456',
        ).toJson(),
        {
          't': 'send_match_request',
          'origin': 'rematch',
          'toUid': 'target_123',
          'matchId': 'm_456',
        },
      );

      expect(
        const UserInboxAcceptRequestMessage('req_1').toJson(),
        {'t': 'accept_match_request', 'id': 'req_1'},
      );

      expect(
        const UserInboxDeclineRequestMessage('req_2').toJson(),
        {'t': 'decline_match_request', 'id': 'req_2'},
      );

      expect(
        const UserInboxCancelRequestMessage('req_3').toJson(),
        {'t': 'cancel_match_request', 'id': 'req_3'},
      );
    });

    test('Sunucu mesajları ayrıştırma: pong', () {
      final msg = parseUserInboxServerMessage('{"t":"pong"}');
      expect(msg, isA<UserInboxPongMessage>());
    });

    test('Sunucu mesajları ayrıştırma: match_request_received', () {
      final json = '''
      {
        "t": "match_request_received",
        "id": "req_100",
        "fromUid": "u_sender",
        "fromNickname": "Mehmet",
        "fromFrame": "emerald",
        "type": "ranked",
        "origin": "rematch",
        "expiresAtMs": 1728518445000
      }
      ''';
      final msg = parseUserInboxServerMessage(json);
      expect(msg, isA<UserInboxRequestReceivedMessage>());
      final received = msg as UserInboxRequestReceivedMessage;
      expect(received.id, 'req_100');
      expect(received.fromUid, 'u_sender');
      expect(received.fromNickname, 'Mehmet');
      expect(received.fromFrame, 'emerald');
      expect(received.type, MatchRequestType.ranked);
      expect(received.origin, MatchRequestOrigin.rematch);
      expect(received.expiresAtMs, 1728518445000);
    });

    test('Sunucu mesajları ayrıştırma: match_request_sent', () {
      final json = '''
      {
        "t": "match_request_sent",
        "id": "req_200",
        "toUid": "u_receiver",
        "toNickname": "Ayşe",
        "type": "friendly",
        "origin": "profile",
        "expiresAtMs": 1728518445000
      }
      ''';
      final msg = parseUserInboxServerMessage(json);
      expect(msg, isA<UserInboxRequestSentMessage>());
      final sent = msg as UserInboxRequestSentMessage;
      expect(sent.id, 'req_200');
      expect(sent.toUid, 'u_receiver');
      expect(sent.toNickname, 'Ayşe');
      expect(sent.type, MatchRequestType.friendly);
      expect(sent.origin, MatchRequestOrigin.profile);
      expect(sent.expiresAtMs, 1728518445000);
    });

    test('Sunucu mesajları ayrıştırma: match_request_status', () {
      final json1 = '{"t":"match_request_status","id":"r1","status":"declined"}';
      final msg1 = parseUserInboxServerMessage(json1) as UserInboxRequestStatusMessage;
      expect(msg1.id, 'r1');
      expect(msg1.status, MatchRequestEndStatus.declined);

      final json2 = '{"t":"match_request_status","id":"r2","status":"expired"}';
      final msg2 = parseUserInboxServerMessage(json2) as UserInboxRequestStatusMessage;
      expect(msg2.id, 'r2');
      expect(msg2.status, MatchRequestEndStatus.expired);

      final json3 = '{"t":"match_request_status","id":"r3","status":"cancelled"}';
      final msg3 = parseUserInboxServerMessage(json3) as UserInboxRequestStatusMessage;
      expect(msg3.id, 'r3');
      expect(msg3.status, MatchRequestEndStatus.cancelled);
    });

    test('Sunucu mesajları ayrıştırma: match_request_error', () {
      final json1 = '{"t":"match_request_error","code":"unavailable"}';
      final msg1 = parseUserInboxServerMessage(json1) as UserInboxRequestErrorMessage;
      expect(msg1.code, MatchRequestErrorCode.unavailable);
      expect(msg1.retryAfterSec, isNull);

      final json2 = '{"t":"match_request_error","code":"cooldown_active","retryAfterSec":35}';
      final msg2 = parseUserInboxServerMessage(json2) as UserInboxRequestErrorMessage;
      expect(msg2.code, MatchRequestErrorCode.cooldownActive);
      expect(msg2.retryAfterSec, 35);

      final json3 = '{"t":"match_request_error","code":"rate_limited","retryAfterSec":45}';
      final msg3 = parseUserInboxServerMessage(json3) as UserInboxRequestErrorMessage;
      expect(msg3.code, MatchRequestErrorCode.rateLimited);
      expect(msg3.retryAfterSec, 45);

      final jsonUnknown = '{"t":"match_request_error","code":"future_unknown_code"}';
      final msgUnknown = parseUserInboxServerMessage(jsonUnknown) as UserInboxRequestErrorMessage;
      expect(msgUnknown.code, MatchRequestErrorCode.invalid);
    });

    test('Sunucu mesajları ayrıştırma: matched', () {
      final json = '''
      {
        "t": "matched",
        "matchId": "m_new_999",
        "opponentName": "Ali",
        "opponentFrame": "gold",
        "opponentUid": "u_ali",
        "isFriendly": true
      }
      ''';
      final msg = parseUserInboxServerMessage(json) as UserInboxMatchedMessage;
      expect(msg.matchId, 'm_new_999');
      expect(msg.opponentName, 'Ali');
      expect(msg.opponentFrame, 'gold');
      expect(msg.opponentUid, 'u_ali');
      expect(msg.isFriendly, isTrue);
    });

    test('Toleranslı mesaj ayrıştırma: bozuk JSON, bilinmeyen t veya eksik alanlar', () {
      expect(parseUserInboxServerMessage(''), isNull);
      expect(parseUserInboxServerMessage('this is not json'), isNull);
      expect(parseUserInboxServerMessage('{'), isNull);
      expect(parseUserInboxServerMessage('{"random": 123}'), isNull);
      expect(parseUserInboxServerMessage('{"t": "unknown_future_type"}'), isNull);
      expect(parseUserInboxServerMessage('{"t": "match_request_received"}'), isNull); // eksik id/fromUid
      expect(parseUserInboxServerMessage('{"t": "matched"}'), isNull); // eksik matchId
    });

    test('UserInboxSendRequestMessage doğrulama: toUid boş olamaz', () {
      expect(
        () => UserInboxSendRequestMessage(
          origin: MatchRequestOrigin.profile,
          toUid: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => UserInboxSendRequestMessage(
          origin: MatchRequestOrigin.profile,
          toUid: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('UserInboxSendRequestMessage doğrulama: origin=rematch için matchId zorunludur', () {
      expect(
        () => UserInboxSendRequestMessage(
          origin: MatchRequestOrigin.rematch,
          toUid: 'target_u',
        ),
        throwsArgumentError,
      );
      expect(
        () => UserInboxSendRequestMessage(
          origin: MatchRequestOrigin.rematch,
          toUid: 'target_u',
          matchId: '',
        ),
        throwsArgumentError,
      );
    });

    test('UserInboxSendRequestMessage doğrulama: origin=profile için matchId verilemez', () {
      expect(
        () => UserInboxSendRequestMessage(
          origin: MatchRequestOrigin.profile,
          toUid: 'target_u',
          matchId: 'm_not_allowed',
        ),
        throwsArgumentError,
      );
    });

    test('Kablo Sözleşmesi Birebir Doğrulama: İstemci -> Sunucu mesaj JSON sabit alanları', () {
      // 1. ping
      final pingJson = const UserInboxPingMessage().toJson();
      expect(pingJson.keys.toList(), ['t']);
      expect(pingJson['t'], 'ping');

      // 2. presence
      final presenceIdle = const UserInboxPresenceMessage('idle').toJson();
      expect(presenceIdle.keys.toSet(), {'t', 'state'});
      expect(presenceIdle['t'], 'presence');
      expect(presenceIdle['state'], 'idle');

      final presenceBusy = const UserInboxPresenceMessage('busy').toJson();
      expect(presenceBusy.keys.toSet(), {'t', 'state'});
      expect(presenceBusy['t'], 'presence');
      expect(presenceBusy['state'], 'busy');

      // 3. send_match_request (profile) - ASLA matchId veya type içermez
      final sendProfile = UserInboxSendRequestMessage(
        origin: MatchRequestOrigin.profile,
        toUid: 'user_target_456',
      ).toJson();
      expect(sendProfile.keys.toSet(), {'t', 'origin', 'toUid'});
      expect(sendProfile['t'], 'send_match_request');
      expect(sendProfile['origin'], 'profile');
      expect(sendProfile['toUid'], 'user_target_456');
      expect(sendProfile.containsKey('matchId'), isFalse);
      expect(sendProfile.containsKey('type'), isFalse);

      // 4. send_match_request (rematch) - matchId içerir, ASLA type içermez
      final sendRematch = UserInboxSendRequestMessage(
        origin: MatchRequestOrigin.rematch,
        toUid: 'user_target_789',
        matchId: 'm_prev_123',
      ).toJson();
      expect(sendRematch.keys.toSet(), {'t', 'origin', 'toUid', 'matchId'});
      expect(sendRematch['t'], 'send_match_request');
      expect(sendRematch['origin'], 'rematch');
      expect(sendRematch['toUid'], 'user_target_789');
      expect(sendRematch['matchId'], 'm_prev_123');
      expect(sendRematch.containsKey('type'), isFalse);

      // 5. accept_match_request
      final accept = const UserInboxAcceptRequestMessage('req_abc').toJson();
      expect(accept.keys.toSet(), {'t', 'id'});
      expect(accept['t'], 'accept_match_request');
      expect(accept['id'], 'req_abc');

      // 6. decline_match_request
      final decline = const UserInboxDeclineRequestMessage('req_def').toJson();
      expect(decline.keys.toSet(), {'t', 'id'});
      expect(decline['t'], 'decline_match_request');
      expect(decline['id'], 'req_def');

      // 7. cancel_match_request
      final cancel = const UserInboxCancelRequestMessage('req_ghi').toJson();
      expect(cancel.keys.toSet(), {'t', 'id'});
      expect(cancel['t'], 'cancel_match_request');
      expect(cancel['id'], 'req_ghi');
    });

    test('Kablo Sözleşmesi Birebir Doğrulama: Bağlantıdaki Snapshot ayrıştırması (isSnapshot=true)', () {
      final snapJson = '''
      {
        "t": "match_request_received",
        "id": "req_snap_99",
        "fromUid": "u_snap_src",
        "fromNickname": "ServerSnap",
        "fromFrame": "mint",
        "type": "friendly",
        "origin": "profile",
        "expiresAtMs": 1750000000000
      }
      ''';

      final msg = parseUserInboxServerMessage(snapJson, isSnapshot: true);
      expect(msg, isA<UserInboxRequestReceivedMessage>());
      final received = msg as UserInboxRequestReceivedMessage;
      expect(received.isSnapshot, isTrue);
      expect(received.id, 'req_snap_99');
      expect(received.fromUid, 'u_snap_src');
      expect(received.fromNickname, 'ServerSnap');
      expect(received.fromFrame, 'mint');
      expect(received.type, MatchRequestType.friendly);
      expect(received.origin, MatchRequestOrigin.profile);
      expect(received.expiresAtMs, 1750000000000);
    });
  });
}
