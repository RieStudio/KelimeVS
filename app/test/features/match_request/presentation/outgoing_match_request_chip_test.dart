import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/presentation/widgets/outgoing_match_request_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OutgoingMatchRequestChip Widget Tests', () {
    testWidgets('giden isteği ve kalan süreyi doğru metinle gösterir', (tester) async {
      final request = OutgoingMatchRequest(
        id: 'out_1',
        toUid: 'u_target',
        toNickname: 'Bora',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        initialRemainingMs: 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OutgoingMatchRequestChip(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(
        find.text(AppStrings.matchRequestOutgoingChip('Bora', 45)),
        findsOneWidget,
      );
      expect(find.text(AppStrings.matchRequestCancel), findsOneWidget);
    });

    testWidgets('İptal butonuna basıldığında onCancel tetiklenir', (tester) async {
      bool cancelled = false;
      final request = OutgoingMatchRequest(
        id: 'out_2',
        toUid: 'u_target',
        toNickname: 'Bora',
        type: MatchRequestType.friendly,
        origin: MatchRequestOrigin.profile,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 45000,
        initialRemainingMs: 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OutgoingMatchRequestChip(
              request: request,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text(AppStrings.matchRequestCancel));
      await tester.pump();

      expect(cancelled, isTrue);
    });
  });
}
