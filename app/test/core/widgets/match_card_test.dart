import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/match_card.dart';
import 'package:app/features/game/domain/history/match_history_entry.dart';

Widget _buildCard({
  required MatchHistoryEntry entry,
  double screenWidth = 360.0,
  double textScaleFactor = 1.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 640),
          textScaler: TextScaler.linear(textScaleFactor),
        ),
        child: Center(
          child: SizedBox(
            width: screenWidth - 32, // HomeScreen kart yatay dolguları (16 soldan, 16 sağdan)
            child: MatchCard(entry: entry),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MatchCard Widget Tests', () {
    testWidgets(
      '1. 360 dp ekranda M-9999 bot adı tam görünür, asla kesilmez (didExceedMaxLines: false)',
      (tester) async {
        const entry = MatchHistoryEntry(
          id: 'test_bot_1',
          matchId: 'm_1',
          opponentName: 'M-9999',
          finishedAtMs: 12345678,
          myScore: 2,
          opponentScore: 1,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
        );

        await tester.pumpWidget(_buildCard(entry: entry, screenWidth: 360.0));
        await tester.pumpAndSettle();

        expect(find.text('M-9999'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final renderParagraph = tester.renderObject<RenderParagraph>(
          find.text('M-9999'),
        );
        expect(renderParagraph.didExceedMaxLines, isFalse);
      },
    );

    testWidgets(
      '2. 360 dp ekranda ve textScaler 1.3 altında M-9999 sıfır taşma ile çizilir ve ellipsis almaz',
      (tester) async {
        const entry = MatchHistoryEntry(
          id: 'test_bot_2',
          matchId: 'm_2',
          opponentName: 'M-9999',
          finishedAtMs: 12345678,
          myScore: 2,
          opponentScore: 0,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
        );

        await tester.pumpWidget(
          _buildCard(
            entry: entry,
            screenWidth: 360.0,
            textScaleFactor: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('M-9999'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final renderParagraph = tester.renderObject<RenderParagraph>(
          find.text('M-9999'),
        );
        expect(renderParagraph.didExceedMaxLines, isFalse);
      },
    );

    testWidgets(
      '3. Uzun kullanıcı adlarında ("Mustafa Kemalettin") FittedBox ile küçülerek sığar ve taşma olmaz',
      (tester) async {
        const entry = MatchHistoryEntry(
          id: 'test_long_1',
          matchId: 'm_3',
          opponentName: 'Mustafa Kemalettin',
          finishedAtMs: 12345678,
          myScore: 1,
          opponentScore: 2,
          result: MatchResult.lose,
          endType: MatchEndType.normal,
          roundRecords: [],
        );

        await tester.pumpWidget(
          _buildCard(
            entry: entry,
            screenWidth: 360.0,
            textScaleFactor: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mustafa Kemalettin'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '4. Aşırı uzun adlarda bile sıfır taşma oluşur',
      (tester) async {
        const entry = MatchHistoryEntry(
          id: 'test_super_long',
          matchId: 'm_4',
          opponentName: 'Çok Çok Aşırı Uzun Kullanıcı Adı Denemesi 1234567890',
          finishedAtMs: 12345678,
          myScore: 0,
          opponentScore: 2,
          result: MatchResult.lose,
          endType: MatchEndType.normal,
          roundRecords: [],
        );

        await tester.pumpWidget(
          _buildCard(
            entry: entry,
            screenWidth: 320.0,
            textScaleFactor: 1.5,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '5. Dostluk maçı olduğunda Dostluk rozeti gösterilmez, satır normal maç gibi çizilir ve taşma olmaz',
      (tester) async {
        const entry = MatchHistoryEntry(
          id: 'test_friend',
          matchId: 'm_5',
          opponentName: 'Zeynep',
          finishedAtMs: 12345678,
          myScore: 2,
          opponentScore: 1,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
          isFriendly: true,
        );

        await tester.pumpWidget(
          _buildCard(
            entry: entry,
            screenWidth: 360.0,
            textScaleFactor: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Zeynep'), findsOneWidget);
        expect(find.text('Dostluk'), findsNothing);
        expect(
          find.text('2${AppStrings.scoreDash}1'),
          findsOneWidget,
        );
        expect(find.text(AppStrings.won), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '6. Kazanılan ve kaybedilen maçlarda ResultBadge doğru variant ile çizilir',
      (tester) async {
        const winEntry = MatchHistoryEntry(
          id: 'test_win',
          matchId: 'm_6',
          opponentName: 'M-1234',
          finishedAtMs: 12345678,
          myScore: 2,
          opponentScore: 0,
          result: MatchResult.win,
          endType: MatchEndType.normal,
          roundRecords: [],
        );

        await tester.pumpWidget(_buildCard(entry: winEntry));
        expect(find.text(AppStrings.won), findsOneWidget);

        const loseEntry = MatchHistoryEntry(
          id: 'test_lose',
          matchId: 'm_7',
          opponentName: 'M-5678',
          finishedAtMs: 12345678,
          myScore: 1,
          opponentScore: 2,
          result: MatchResult.lose,
          endType: MatchEndType.normal,
          roundRecords: [],
        );

        await tester.pumpWidget(_buildCard(entry: loseEntry));
        expect(find.text(AppStrings.lost), findsOneWidget);
      },
    );
  });
}
