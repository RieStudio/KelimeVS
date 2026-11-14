import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/friend_match/presentation/friend_reveal_screen.dart';
import 'package:app/features/game/application/match_providers.dart';
import 'package:app/features/game/application/match_ui_state.dart';
import 'package:app/features/online/application/online_match_session.dart';
import 'package:app/features/online/data/online_match_client.dart';
import 'package:app/features/online/domain/models/online_messages.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/domain/energy_state.dart';

class MockOnlineMatchSession extends OnlineMatchSession {
  int startOnlineMatchCallCount = 0;
  String? lastMatchId;
  String? lastOpponentName;
  String? lastOpponentUid;
  String? lastOpponentFrame;
  bool? lastIsFriendly;

  @override
  MatchUiState build() => const MatchUiState();

  @override
  Future<void> startOnlineMatch({
    required String matchId,
    required String opponentName,
    String? opponentUid,
    String opponentFrame = 'classic',
    bool isFriendly = false,
    OnlineMatchClient? client,
  }) async {
    startOnlineMatchCallCount++;
    lastMatchId = matchId;
    lastOpponentName = opponentName;
    lastOpponentUid = opponentUid;
    lastOpponentFrame = opponentFrame;
    lastIsFriendly = isFriendly;
  }
}

class MockProfileNotifier extends ProfileNotifier {
  int updateEnergyCalls = 0;
  int syncWithServerCalls = 0;
  EnergyState? lastUpdatedEnergy;
  int? lastServerNowMs;

  @override
  ProfileState build() => const ProfileState(
        nickname: 'TestUser',
        equippedFrame: 'mint',
        energy: EnergyState(enabled: true, current: 5, max: 5),
      );

  @override
  void updateEnergy(EnergyState energy, [int? serverNowMs]) {
    updateEnergyCalls++;
    lastUpdatedEnergy = energy;
    lastServerNowMs = serverNowMs;
    super.updateEnergy(energy, serverNowMs);
  }

  @override
  Future<bool> syncWithServer({bool force = false}) async {
    syncWithServerCalls++;
    return true;
  }
}

void main() {
  group('FriendMatchRevealScreen isFriendly Parameter Tests', () {
    late MockOnlineMatchSession mockOnlineSession;

    setUp(() {
      mockOnlineSession = MockOnlineMatchSession();
    });

    testWidgets('1. isFriendly: false verildiğinde süre dolunca startOnlineMatch isFriendly: false ile çağrılır', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: FriendMatchRevealScreen(
              matchId: 'm_ranked_1',
              opponentName: 'Deniz',
              opponentUid: 'u_deniz',
              opponentFrame: 'gold',
              isFriendly: false,
              revealDuration: Duration(milliseconds: 100),
            ),
          ),
        ),
      );

      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);
      expect(mockOnlineSession.startOnlineMatchCallCount, 0);

      // 100 ms reveal süresini ilerlet
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(mockOnlineSession.startOnlineMatchCallCount, 1);
      expect(mockOnlineSession.lastMatchId, 'm_ranked_1');
      expect(mockOnlineSession.lastOpponentName, 'Deniz');
      expect(mockOnlineSession.lastOpponentUid, 'u_deniz');
      expect(mockOnlineSession.lastOpponentFrame, 'gold');
      expect(mockOnlineSession.lastIsFriendly, isFalse);
    });

    testWidgets('2. isFriendly varsayılanı true kalır ve startOnlineMatch isFriendly: true ile çağrılır', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: const MaterialApp(
            home: FriendMatchRevealScreen(
              matchId: 'm_friendly_1',
              opponentName: 'Can',
              revealDuration: Duration(milliseconds: 100),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(mockOnlineSession.startOnlineMatchCallCount, 1);
      expect(mockOnlineSession.lastIsFriendly, isTrue);
    });
  });

  group('openRematchReveal Helper Function Tests', () {
    late MockProfileNotifier mockProfile;
    late MockOnlineMatchSession mockOnlineSession;

    setUp(() {
      mockProfile = MockProfileNotifier();
      mockOnlineSession = MockOnlineMatchSession();
    });

    testWidgets('3. Rankli rövanşta openRematchReveal: enerji güncellenir, sunucuyla senkronize edilir ve pushReplacement yapılır', (tester) async {
      const matchedMsg = MatchedServerMessage(
        matchId: 'm_rematch_ranked',
        opponentName: 'Ece',
        opponentFrame: 'mint',
        opponentUid: 'u_ece',
        isFriendly: false,
        energy: MatchedEnergyInfo(current: 4, max: 5, nextEnergyAtMs: 180000),
        serverNowMs: 50000,
      );

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => mockProfile),
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        openRematchReveal(
                          context,
                          capturedRef,
                          matchedMsg,
                          revealDuration: const Duration(seconds: 1),
                        );
                      },
                      child: const Text('Rövanş Aç'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Butona dokun
      await tester.tap(find.text('Rövanş Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // Geçiş animasyonunu tamamla

      // 1. FriendMatchRevealScreen açılmış olmalı
      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);
      final revealWidget = tester.widget<FriendMatchRevealScreen>(find.byType(FriendMatchRevealScreen));
      expect(revealWidget.matchId, 'm_rematch_ranked');
      expect(revealWidget.opponentName, 'Ece');
      expect(revealWidget.opponentFrame, 'mint');
      expect(revealWidget.opponentUid, 'u_ece');
      expect(revealWidget.isFriendly, isFalse);

      // 2. Enerji güncellenmiş ve sunucuyla senkron çağrısı yapılmış olmalı
      expect(mockProfile.updateEnergyCalls, 1);
      expect(mockProfile.lastUpdatedEnergy?.current, 4);
      expect(mockProfile.lastUpdatedEnergy?.max, 5);
      expect(mockProfile.lastServerNowMs, 50000);
      expect(mockProfile.syncWithServerCalls, 1);

      // 3. pushReplacement yapıldığı için geri tuşuyla önceki sayfaya dönülemez (eski sayfa silindi)
      expect(find.text('Rövanş Aç'), findsNothing);

      // Süreyi tamamla ve MatchScreen'e geçişi gözlemle
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(mockOnlineSession.startOnlineMatchCallCount, 1);
      expect(mockOnlineSession.lastIsFriendly, isFalse);
    });

    testWidgets('4. Arkadaş maçı rövanşında openRematchReveal: enerjiye DOKUNMAZ ve isFriendly: true olarak açar', (tester) async {
      const matchedMsg = MatchedServerMessage(
        matchId: 'm_rematch_friendly',
        opponentName: 'Bora',
        opponentFrame: 'classic',
        opponentUid: 'u_bora',
        isFriendly: true,
      );

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(() => mockProfile),
            onlineMatchSessionProvider.overrideWith(() => mockOnlineSession),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        openRematchReveal(
                          context,
                          capturedRef,
                          matchedMsg,
                          revealDuration: const Duration(seconds: 1),
                        );
                      },
                      child: const Text('Rövanş Aç'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Rövanş Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(FriendMatchRevealScreen), findsOneWidget);
      final revealWidget = tester.widget<FriendMatchRevealScreen>(find.byType(FriendMatchRevealScreen));
      expect(revealWidget.isFriendly, isTrue);

      // Enerji fonksiyonları çağrılmamalıdır
      expect(mockProfile.updateEnergyCalls, 0);
      expect(mockProfile.syncWithServerCalls, 0);

      // Süreyi tamamla
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(mockOnlineSession.startOnlineMatchCallCount, 1);
      expect(mockOnlineSession.lastIsFriendly, isTrue);
    });
  });
}
