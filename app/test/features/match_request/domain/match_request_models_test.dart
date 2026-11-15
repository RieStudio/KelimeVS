import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/domain/match_request_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchRequest Enums', () {
    test('MatchRequestType string parsing and wire representation', () {
      expect(MatchRequestType.fromString('ranked'), MatchRequestType.ranked);
      expect(MatchRequestType.fromString('friendly'), MatchRequestType.friendly);
      expect(MatchRequestType.fromString('unknown'), MatchRequestType.friendly);

      expect(MatchRequestType.ranked.toWireString(), 'ranked');
      expect(MatchRequestType.friendly.toWireString(), 'friendly');
    });

    test('MatchRequestOrigin string parsing and wire representation', () {
      expect(MatchRequestOrigin.fromString('rematch'), MatchRequestOrigin.rematch);
      expect(MatchRequestOrigin.fromString('profile'), MatchRequestOrigin.profile);
      expect(MatchRequestOrigin.fromString('unknown'), MatchRequestOrigin.profile);

      expect(MatchRequestOrigin.rematch.toWireString(), 'rematch');
      expect(MatchRequestOrigin.profile.toWireString(), 'profile');
    });

    test('MatchRequestErrorCode string parsing and wire representation', () {
      expect(MatchRequestErrorCode.fromString('unavailable'), MatchRequestErrorCode.unavailable);
      expect(MatchRequestErrorCode.fromString('cooldown_active'), MatchRequestErrorCode.cooldownActive);
      expect(MatchRequestErrorCode.fromString('rate_limited'), MatchRequestErrorCode.rateLimited);
      expect(MatchRequestErrorCode.fromString('no_energy'), MatchRequestErrorCode.noEnergy);
      expect(MatchRequestErrorCode.fromString('opponent_no_energy'), MatchRequestErrorCode.opponentNoEnergy);
      expect(MatchRequestErrorCode.fromString('invalid'), MatchRequestErrorCode.invalid);
      expect(MatchRequestErrorCode.fromString('unknown_future_error'), MatchRequestErrorCode.invalid);

      expect(MatchRequestErrorCode.unavailable.toWireString(), 'unavailable');
      expect(MatchRequestErrorCode.cooldownActive.toWireString(), 'cooldown_active');
      expect(MatchRequestErrorCode.rateLimited.toWireString(), 'rate_limited');
      expect(MatchRequestErrorCode.noEnergy.toWireString(), 'no_energy');
      expect(MatchRequestErrorCode.opponentNoEnergy.toWireString(), 'opponent_no_energy');
      expect(MatchRequestErrorCode.invalid.toWireString(), 'invalid');
    });

    test('MatchRequestEndStatus string parsing and wire representation', () {
      expect(MatchRequestEndStatus.fromString('declined'), MatchRequestEndStatus.declined);
      expect(MatchRequestEndStatus.fromString('expired'), MatchRequestEndStatus.expired);
      expect(MatchRequestEndStatus.fromString('cancelled'), MatchRequestEndStatus.cancelled);
      expect(MatchRequestEndStatus.fromString('unknown_status'), MatchRequestEndStatus.cancelled);

      expect(MatchRequestEndStatus.declined.toWireString(), 'declined');
      expect(MatchRequestEndStatus.expired.toWireString(), 'expired');
      expect(MatchRequestEndStatus.cancelled.toWireString(), 'cancelled');
    });
  });

  group('IncomingMatchRequest & calculateRemainingSeconds', () {
    test('canlı istek: cihaz saati 5 dk ileri olsa bile kalan süre ~45 sn başlar', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Cihaz saati sunucudan 5 dk (300,000 ms) ileride
      final expiresAt = now - 255000; // Eski hesapta negatif/0 çıkardı

      final req = IncomingMatchRequest.live(
        id: 'req_live_ahead',
        fromUid: 'u_alice',
        fromNickname: 'Alice',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: expiresAt,
      );

      // Alım anında cihaz saatinden bağımsız olarak 45 saniyedir
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 0), 45);
      // 10 sn monotonik süre geçince 35 sn
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 10000), 35);
    });

    test('canlı istek: cihaz saati 5 dk geri olsa bile kalan süre ~45 sn başlar', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Cihaz saati sunucudan 5 dk geride
      final expiresAt = now + 345000;

      final req = IncomingMatchRequest.live(
        id: 'req_live_behind',
        fromUid: 'u_bob',
        fromNickname: 'Bob',
        fromFrame: 'frame_2',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: expiresAt,
      );

      // Alım anında 45 saniyedir
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 0), 45);
      // 20 sn geçince 25 sn
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 20000), 25);
    });

    test('canlı istek: saat doğru ve monotonik süre ilerliyor', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final req = IncomingMatchRequest.live(
        id: 'req_live_exact',
        fromUid: 'u_charlie',
        fromNickname: 'Charlie',
        fromFrame: 'frame_3',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: now + 45000,
      );

      expect(req.calculateRemainingSeconds(elapsedMsOverride: 0), 45);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 10000), 35);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 44500), 1);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 45000), 0);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 50000), 0);
    });

    test('snapshot istek: alım anında expiresAtMs - nowMs [0, 45] olarak hesaplanır ve monotonik sayar', () {
      const now = 100000;
      const expiresAt = 130000; // 30 sn kalmış

      final req = IncomingMatchRequest.snapshot(
        id: 'req_snap_1',
        fromUid: 'u_david',
        fromNickname: 'David',
        fromFrame: 'frame_4',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: expiresAt,
        nowMs: now,
      );

      expect(req.isSnapshot, isTrue);
      // Alım anında kalan süre: 30 sn
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 0), 30);
      // 10 sn sonra: 20 sn
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 10000), 20);
      // 30 sn sonra: 0 sn
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 30000), 0);
      // 35 sn sonra: 0 sn (negatife düşmez)
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 35000), 0);
    });

    test('snapshot istek: süresi dolmuş veya aşırı büyük expiresAtMs sınırlandırılır', () {
      const now = 100000;

      // Süresi geçmiş (expired)
      final reqExpired = IncomingMatchRequest.snapshot(
        id: 'req_snap_exp',
        fromUid: 'u_e',
        fromNickname: 'Eva',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 90000,
        nowMs: now,
      );
      expect(reqExpired.calculateRemainingSeconds(elapsedMsOverride: 0), 0);

      // 45 saniyeden fazla
      final reqLarge = IncomingMatchRequest.snapshot(
        id: 'req_snap_large',
        fromUid: 'u_f',
        fromNickname: 'Frank',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 200000,
        nowMs: now,
      );
      expect(reqLarge.calculateRemainingSeconds(elapsedMsOverride: 0), 45);
    });
  });

  group('OutgoingMatchRequest & calculateRemainingSeconds', () {
    test('canlı giden istek kalan süre hesaplama', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final req = OutgoingMatchRequest.live(
        id: 'req_out_live',
        toUid: 'u_target',
        toNickname: 'Target',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: now + 45000,
      );

      expect(req.calculateRemainingSeconds(elapsedMsOverride: 0), 45);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 20000), 25);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 45000), 0);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 50000), 0);
    });

    test('snapshot giden istek kalan süre hesaplama', () {
      const now = 50000;
      final req = OutgoingMatchRequest.snapshot(
        id: 'req_out_snap',
        toUid: 'u_target_snap',
        toNickname: 'TargetSnap',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 75000, // 25 sn kalmış
        nowMs: now,
      );

      expect(req.isSnapshot, isTrue);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 0), 25);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 10000), 15);
      expect(req.calculateRemainingSeconds(elapsedMsOverride: 30000), 0);
    });
  });

  group('MatchRequestsState copyWith & equality', () {
    test('durum kopyalama ve eşitlik', () {
      const state1 = MatchRequestsState();
      expect(state1.incoming, isNull);
      expect(state1.outgoing, isNull);
      expect(state1.connectionState, UserInboxConnectionState.disconnected);

      final incoming = IncomingMatchRequest(
        id: 'req_in',
        fromUid: 'u_1',
        fromNickname: 'One',
        fromFrame: 'frame_1',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: 50000,
      );

      final state2 = state1.copyWith(
        incoming: incoming,
        connectionState: UserInboxConnectionState.connected,
      );

      expect(state2.incoming, incoming);
      expect(state2.connectionState, UserInboxConnectionState.connected);
      expect(state2.hasActiveIncoming, isTrue);

      final state3 = state2.copyWith(clearIncoming: true);
      expect(state3.incoming, isNull);
    });
  });
}
