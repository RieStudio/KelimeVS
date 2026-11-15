import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/presentation/widgets/incoming_match_request_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IncomingMatchRequestBanner Widget Tests', () {
    testWidgets('profilden gelen dostluk maç isteğini doğru başlık ve alt başlıkla gösterir',
        (tester) async {
      final request = IncomingMatchRequest(
        id: 'req_1',
        fromUid: 'u_opponent',
        fromNickname: 'Ahmet',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.matchRequestTitleProfile('Ahmet')), findsOneWidget);
      expect(find.text(AppStrings.matchRequestSubtitleFriendly), findsOneWidget);
      expect(find.text(AppStrings.matchRequestAccept), findsOneWidget);
      expect(find.text(AppStrings.matchRequestDecline), findsOneWidget);

      // KESİNLİKLE bot rozeti veya bot metni bulunmamalı
      expect(find.textContaining('bot', findRichText: true), findsNothing);
      expect(find.textContaining('BOT', findRichText: true), findsNothing);
    });

    testWidgets('maç sonu rövanş rankli maç isteğini doğru başlık ve 1 enerji bilgisiyle gösterir',
        (tester) async {
      final request = IncomingMatchRequest(
        id: 'req_2',
        fromUid: 'u_opponent',
        fromNickname: 'Zeynep',
        fromFrame: 'gold',
        type: MatchRequestType.ranked,
        origin: MatchRequestOrigin.rematch,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.matchRequestTitleRematch('Zeynep')), findsOneWidget);
      expect(find.text(AppStrings.matchRequestSubtitleRanked), findsOneWidget);
    });

    testWidgets('Reddet butonuna basıldığında onDecline tetiklenir', (tester) async {
      bool declined = false;
      final request = IncomingMatchRequest(
        id: 'req_3',
        fromUid: 'u_1',
        fromNickname: 'Can',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () {},
              onDecline: () => declined = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text(AppStrings.matchRequestDecline));
      await tester.pump();

      expect(declined, isTrue);
    });

    testWidgets('Kabul Et butonuna basıldığında onAccept tetiklenir', (tester) async {
      bool accepted = false;
      final request = IncomingMatchRequest(
        id: 'req_4',
        fromUid: 'u_1',
        fromNickname: 'Elif',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              onAccept: () => accepted = true,
              onDecline: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text(AppStrings.matchRequestAccept));
      await tester.pump();

      expect(accepted, isTrue);
    });

    testWidgets('isAccepting true iken yükleme göstergesi açılır ve butonlara dokunulamaz',
        (tester) async {
      bool accepted = false;
      bool declined = false;
      final request = IncomingMatchRequest(
        id: 'req_5',
        fromUid: 'u_1',
        fromNickname: 'Murat',
        fromFrame: 'classic',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingMatchRequestBanner(
              request: request,
              isAccepting: true,
              onAccept: () => accepted = true,
              onDecline: () => declined = true,
            ),
          ),
        ),
      );

      // Kabul Et yazısı yerine spinner döner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Dokunulduğunda callback'ler tetiklenmemeli (çift tıklama koruması)
      await tester.tap(find.byType(CircularProgressIndicator).last);
      await tester.pump();
      expect(accepted, isFalse);

      await tester.tap(find.text(AppStrings.matchRequestDecline));
      await tester.pump();
      expect(declined, isFalse);
    });
  });
}
