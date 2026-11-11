import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/profile/domain/public_profile_model.dart';

void main() {
  group('PublicProfileStats Tests', () {
    test('tam ve geçerli json doğru parse edilir', () {
      final json = {
        'played': 100,
        'won': 65,
        'lost': 35,
        'winRate': 65,
      };

      final stats = PublicProfileStats.fromJson(json);

      expect(stats.played, 100);
      expect(stats.won, 65);
      expect(stats.lost, 35);
      expect(stats.winRate, 65);
      expect(stats.winRateDisplay, '%65');
    });

    test('winRate eksikse played ve won değerlerinden otomatik hesaplar', () {
      final json = {
        'played': 3,
        'won': 2,
        'lost': 1,
      };

      final stats = PublicProfileStats.fromJson(json);

      expect(stats.played, 3);
      expect(stats.won, 2);
      expect(stats.lost, 1);
      expect(stats.winRate, 67); // 2/3 = 66.66% -> 67%
      expect(stats.winRateDisplay, '%67');
    });

    test('played 0 iken winRate 0 ve winRateDisplay "—" olur', () {
      final stats = PublicProfileStats.fromJson(null);

      expect(stats.played, 0);
      expect(stats.won, 0);
      expect(stats.lost, 0);
      expect(stats.winRate, 0);
      expect(stats.winRateDisplay, '—');
    });

    test('toJson ve eşitlik (==, hashCode) doğru çalışır', () {
      const stats1 = PublicProfileStats(
        played: 10,
        won: 6,
        lost: 4,
        winRate: 60,
      );
      const stats2 = PublicProfileStats(
        played: 10,
        won: 6,
        lost: 4,
        winRate: 60,
      );
      const stats3 = PublicProfileStats(
        played: 10,
        won: 5,
        lost: 5,
        winRate: 50,
      );

      expect(stats1, equals(stats2));
      expect(stats1.hashCode, equals(stats2.hashCode));
      expect(stats1, isNot(equals(stats3)));

      final json = stats1.toJson();
      expect(json['played'], 10);
      expect(json['won'], 6);
      expect(json['lost'], 4);
      expect(json['winRate'], 60);
    });
  });

  group('PublicProfile Tests', () {
    test('tam ve geçerli json doğru parse edilir', () {
      final json = {
        'uid': 'user_123',
        'nickname': 'Sevbans',
        'equippedFrame': 'emerald',
        'stats': {
          'played': 50,
          'won': 30,
          'lost': 20,
          'winRate': 60,
        },
        'isGuest': false,
        'isBlocked': true,
        'blockId': 'blk_abc999',
      };

      final profile = PublicProfile.fromJson(json);

      expect(profile.uid, 'user_123');
      expect(profile.nickname, 'Sevbans');
      expect(profile.equippedFrame, 'emerald');
      expect(profile.stats.played, 50);
      expect(profile.stats.won, 30);
      expect(profile.stats.lost, 20);
      expect(profile.stats.winRate, 60);
      expect(profile.isGuest, false);
      expect(profile.isBlocked, true);
      expect(profile.blockId, 'blk_abc999');
    });

    test('eksik ve null alanlara karşı toleranslıdır (varsayılanlara düşer)', () {
      final json = {
        'uid': '  user_min  ',
        'nickname': '  MinUser  ',
      };

      final profile = PublicProfile.fromJson(json);

      expect(profile.uid, 'user_min');
      expect(profile.nickname, 'MinUser');
      expect(profile.equippedFrame, 'classic');
      expect(profile.stats.played, 0);
      expect(profile.isGuest, false);
      expect(profile.isBlocked, false);
      expect(profile.blockId, isNull);
    });

    test('bilinmeyen ve fazladan alanlar parse işlemini bozmaz', () {
      final json = {
        'uid': 'user_ext',
        'nickname': 'Tester',
        'equippedFrame': 'gold_leaf',
        'coins': 9999, // sunucu göndermemeli ama gelse bile güvenli parse
        'email': 'secret@example.com',
        'token': 'super_secret',
        'stats': {'played': 5, 'won': 5, 'lost': 0, 'winRate': 100},
        'extraFutureField': 'future_value',
      };

      final profile = PublicProfile.fromJson(json);

      expect(profile.uid, 'user_ext');
      expect(profile.nickname, 'Tester');
      expect(profile.equippedFrame, 'gold_leaf');
      expect(profile.stats.played, 5);
      expect(profile.stats.won, 5);
      expect(profile.stats.winRate, 100);
    });

    test('misafir kullanıcı isGuest: true olarak parse edilir', () {
      final json = {
        'uid': 'guest_123',
        'nickname': 'M-4821',
        'equippedFrame': 'classic',
        'stats': {'played': 0, 'won': 0, 'lost': 0, 'winRate': 0},
        'isGuest': true,
        'isBlocked': false,
      };

      final profile = PublicProfile.fromJson(json);

      expect(profile.isGuest, true);
      expect(profile.nickname, 'M-4821');
    });

    test('copyWith ve toJson beklenen sonuçları üretir', () {
      const profile = PublicProfile(
        uid: 'user_orig',
        nickname: 'Alice',
        equippedFrame: 'classic',
        isBlocked: false,
      );

      final updated = profile.copyWith(
        isBlocked: true,
        blockId: 'blk_new',
      );

      expect(updated.isBlocked, true);
      expect(updated.blockId, 'blk_new');
      expect(updated.nickname, 'Alice');

      final cleared = updated.copyWith(clearBlockId: true, isBlocked: false);
      expect(cleared.isBlocked, false);
      expect(cleared.blockId, isNull);

      final json = updated.toJson();
      expect(json['uid'], 'user_orig');
      expect(json['blockId'], 'blk_new');
    });

    test('eşitlik ve hashCode doğru çalışır', () {
      const p1 = PublicProfile(
        uid: 'u1',
        nickname: 'N1',
        equippedFrame: 'classic',
      );
      const p2 = PublicProfile(
        uid: 'u1',
        nickname: 'N1',
        equippedFrame: 'classic',
      );
      const p3 = PublicProfile(
        uid: 'u2',
        nickname: 'N2',
        equippedFrame: 'classic',
      );

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(p3)));
    });
  });

  group('PublicProfileException Tests', () {
    test('tüm hata tipleri ve getter yardımcıları doğrulanır', () {
      const eNotFound = PublicProfileException(
        kind: PublicProfileErrorKind.notFound,
        message: 'Bulunamadı',
        statusCode: 404,
      );
      expect(eNotFound.isNotFound, true);
      expect(eNotFound.statusCode, 404);

      const eDeleted = PublicProfileException(
        kind: PublicProfileErrorKind.deleted,
        message: 'Silinmiş',
        statusCode: 410,
      );
      expect(eDeleted.isDeleted, true);

      const eAlreadyReported = PublicProfileException(
        kind: PublicProfileErrorKind.alreadyReported,
        message: 'Zaten bildirildi',
        statusCode: 409,
      );
      expect(eAlreadyReported.isAlreadyReported, true);

      const eDailyLimit = PublicProfileException(
        kind: PublicProfileErrorKind.dailyLimit,
        message: 'Günlük limit',
        statusCode: 429,
      );
      expect(eDailyLimit.isDailyLimit, true);

      const eBlockLimit = PublicProfileException(
        kind: PublicProfileErrorKind.blockLimit,
        message: 'Blok limiti',
        statusCode: 400,
      );
      expect(eBlockLimit.isBlockLimit, true);

      const eCannotBlockSelf = PublicProfileException(
        kind: PublicProfileErrorKind.cannotBlockSelf,
        message: 'Kendini engelleyemezsin',
        statusCode: 400,
      );
      expect(eCannotBlockSelf.isCannotBlockSelf, true);

      const eUnauthorized = PublicProfileException(
        kind: PublicProfileErrorKind.unauthorized,
        message: 'Yetkisiz',
        statusCode: 401,
      );
      expect(eUnauthorized.isUnauthorized, true);

      const eNetwork = PublicProfileException(
        kind: PublicProfileErrorKind.networkOrTimeout,
        message: 'Ağ hatası',
      );
      expect(eNetwork.isNetworkOrTimeout, true);
    });
  });
}
