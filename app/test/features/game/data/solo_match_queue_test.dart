import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/features/game/application/solo_match_queue_manager.dart';
import 'package:app/features/game/data/solo_match_api_client.dart';
import 'package:app/features/game/data/solo_match_queue_repository.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/domain/energy_state.dart';

class FakeSoloMatchApiClient implements SoloMatchApiClient {
  final List<SoloMatchSubmission> receivedSubmissions = [];
  SubmitSoloMatchResult Function(SoloMatchSubmission sub)? onSubmit;

  FakeSoloMatchApiClient({this.onSubmit});

  @override
  Future<SubmitSoloMatchResult> submit(SoloMatchSubmission submission) async {
    receivedSubmissions.add(submission);
    if (onSubmit != null) {
      return onSubmit!(submission);
    }
    return const SubmitSoloMatchSuccess(
      ok: true,
      counted: true,
      coins: 100,
      coinsAwarded: 20,
    );
  }
}

class FakeProfileNotifier extends ProfileNotifier {
  int updatedCoins = 0;
  EnergyState? updatedEnergy;
  int syncCalls = 0;

  @override
  Future<void> updateCoins(int coins) async {
    updatedCoins = coins;
  }

  @override
  void updateEnergy(EnergyState energy, [int? serverNowMs]) {
    updatedEnergy = energy;
  }

  @override
  Future<bool> syncWithServer({bool force = false}) async {
    syncCalls++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalSoloMatchQueueRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    final now = DateTime.now().millisecondsSinceEpoch;

    final sub1 = SoloMatchSubmission(
      matchId: 'bot:match_1',
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 2,
      durationSeconds: 15,
      endedBy: 'normal',
      submittedAtMs: now,
    );

    final sub2 = SoloMatchSubmission(
      matchId: 'bot:match_2',
      outcome: 'loss',
      myScore: 1,
      oppScore: 2,
      correctAnswers: 1,
      durationSeconds: 20,
      endedBy: 'normal',
      submittedAtMs: now,
    );

    test('enqueue ve getPendingSubmissions kuyruğu doğru saklar ve okur', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);
      await repo.enqueue(sub2);

      final list = await repo.getPendingSubmissions();
      expect(list.length, equals(2));
      expect(list[0].matchId, equals('bot:match_1'));
      expect(list[1].matchId, equals('bot:match_2'));
    });

    test('Aynı matchId zaten varsa tekrar eklenmez (idempotency)', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);
      await repo.enqueue(sub1); // Tekrar ekleme denemesi

      final list = await repo.getPendingSubmissions();
      expect(list.length, equals(1));
    });

    test('Kuyruk kapasitesi 20 ile sınırlıdır: aşılırsa en eskiler silinir', () async {
      final repo = const LocalSoloMatchQueueRepository();

      for (var i = 1; i <= 25; i++) {
        await repo.enqueue(
          SoloMatchSubmission(
            matchId: 'bot:match_$i',
            outcome: 'win',
            myScore: 2,
            oppScore: 0,
            correctAnswers: 2,
            durationSeconds: 15,
            endedBy: 'normal',
            submittedAtMs: now + i,
          ),
        );
      }

      final list = await repo.getPendingSubmissions();
      expect(list.length, equals(20));
      // En eski 5 tanesi (1..5) silinmeli, 6..25 kalmalıdır
      expect(list.first.matchId, equals('bot:match_6'));
      expect(list.last.matchId, equals('bot:match_25'));
    });

    test('24 saatten eski kayıtlar (maxAgeMs) otomatik budanır', () async {
      final now = 1000000000;
      final oldTime = now - (25 * 60 * 60 * 1000); // 25 saat önce
      final freshTime = now - (2 * 60 * 60 * 1000); // 2 saat önce

      final repo = LocalSoloMatchQueueRepository(
        clockNowMs: () => now,
      );

      await repo.enqueue(
        SoloMatchSubmission(
          matchId: 'bot:old_match',
          outcome: 'win',
          myScore: 2,
          oppScore: 0,
          correctAnswers: 2,
          durationSeconds: 15,
          endedBy: 'normal',
          submittedAtMs: oldTime,
        ),
      );

      await repo.enqueue(
        SoloMatchSubmission(
          matchId: 'bot:fresh_match',
          outcome: 'win',
          myScore: 2,
          oppScore: 0,
          correctAnswers: 2,
          durationSeconds: 15,
          endedBy: 'normal',
          submittedAtMs: freshTime,
        ),
      );

      final list = await repo.getPendingSubmissions();
      expect(list.length, equals(1));
      expect(list.first.matchId, equals('bot:fresh_match'));
    });

    test('remove belirtilen matchId yi kuyruktan siler', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);
      await repo.enqueue(sub2);

      await repo.remove(sub1.matchId);

      final list = await repo.getPendingSubmissions();
      expect(list.length, equals(1));
      expect(list.first.matchId, equals(sub2.matchId));
    });

    test('clear kuyruğu tamamen boşaltır', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);
      await repo.enqueue(sub2);

      await repo.clear();

      final list = await repo.getPendingSubmissions();
      expect(list, isEmpty);
    });
  });

  group('SoloMatchQueueManager.processQueue', () {
    late FakeProfileNotifier fakeProfile;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeProfile = FakeProfileNotifier();
      container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith(() => fakeProfile),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    final sub1 = SoloMatchSubmission(
      matchId: 'bot:match_1',
      outcome: 'win',
      myScore: 2,
      oppScore: 0,
      correctAnswers: 2,
      durationSeconds: 15,
      endedBy: 'normal',
      submittedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final sub2 = SoloMatchSubmission(
      matchId: 'bot:match_2',
      outcome: 'loss',
      myScore: 1,
      oppScore: 2,
      correctAnswers: 1,
      durationSeconds: 20,
      endedBy: 'normal',
      submittedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    test('Başarılı (counted: true) gönderimde kuyruktan kaldırılır ve profil güncellenir', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);

      final fakeApi = FakeSoloMatchApiClient(
        onSubmit: (sub) => const SubmitSoloMatchSuccess(
          ok: true,
          counted: true,
          coins: 250,
          coinsAwarded: 30,
          energy: EnergyState(enabled: true, current: 3, max: 5),
        ),
      );

      final manager = SoloMatchQueueManager(
        repository: repo,
        apiClient: fakeApi,
        ref: container.read(Provider((ref) => ref)),
      );

      await manager.processQueue();

      final list = await repo.getPendingSubmissions();
      expect(list, isEmpty);
      expect(fakeProfile.updatedCoins, equals(250));
      expect(fakeProfile.updatedEnergy?.current, equals(3));
      expect(fakeProfile.syncCalls, equals(1));
    });

    test('counted: false olduğunda kuyruktan silinir ancak profil jeton güncellemesi tetiklenmez', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);

      final fakeApi = FakeSoloMatchApiClient(
        onSubmit: (sub) => const SubmitSoloMatchSuccess(
          ok: true,
          counted: false,
          coins: 100,
          coinsAwarded: 0,
        ),
      );

      final manager = SoloMatchQueueManager(
        repository: repo,
        apiClient: fakeApi,
        ref: container.read(Provider((ref) => ref)),
      );

      await manager.processQueue();

      final list = await repo.getPendingSubmissions();
      expect(list, isEmpty);
      expect(fakeProfile.updatedCoins, equals(0));
      expect(fakeProfile.syncCalls, equals(0));
    });

    test('Kalıcı hata (400, 410) alındığında kuyruktan silinir (tekrar denenmez)', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);

      final fakeApi = FakeSoloMatchApiClient(
        onSubmit: (sub) => const SubmitSoloMatchPermanentError(statusCode: 400, error: 'bad_request'),
      );

      final manager = SoloMatchQueueManager(
        repository: repo,
        apiClient: fakeApi,
        ref: container.read(Provider((ref) => ref)),
      );

      await manager.processQueue();

      final list = await repo.getPendingSubmissions();
      expect(list, isEmpty);
    });

    test('Geçici hata (401, 5xx, ağ) alındığında kuyrukta kalır ve döngü kesilir', () async {
      final repo = const LocalSoloMatchQueueRepository();
      await repo.enqueue(sub1);
      await repo.enqueue(sub2);

      final fakeApi = FakeSoloMatchApiClient(
        onSubmit: (sub) => const SubmitSoloMatchTransientError('500 internal server error'),
      );

      final manager = SoloMatchQueueManager(
        repository: repo,
        apiClient: fakeApi,
        ref: container.read(Provider((ref) => ref)),
      );

      await manager.processQueue();

      // İkinci öğeye geçmeden ilk öğede takılır ve kuyruk korunur
      final list = await repo.getPendingSubmissions();
      expect(list.length, equals(2));
      expect(fakeApi.receivedSubmissions.length, equals(1));
    });
  });
}
