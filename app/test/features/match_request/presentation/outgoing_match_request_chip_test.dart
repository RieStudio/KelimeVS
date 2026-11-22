import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/match_request/domain/match_request_models.dart';
import 'package:app/features/match_request/presentation/widgets/outgoing_match_request_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
      expect(find.byType(SvgPicture), findsOneWidget);
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 20.0);
      expect(svg.height, 20.0);
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

    testWidgets('İptal butonu tehlike çerçeveli stildedir (card zemin, danger 1.5 kenarlık, dangerText yazı)', (tester) async {
      final request = OutgoingMatchRequest(
        id: 'out_3',
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

      // İptal butonunu kapsayan Container
      final cancelTextFinder = find.text(AppStrings.matchRequestCancel);
      final cancelContainerFinder = find.ancestor(
        of: cancelTextFinder,
        matching: find.byType(Container),
      ).first;

      final cancelContainer = tester.widget<Container>(cancelContainerFinder);
      final decoration = cancelContainer.decoration as BoxDecoration;

      // Zemin: card (beyaz), KIRMIZI DOLGU YOK
      expect(decoration.color, AppColors.card);

      // Kenarlık: kırmızı (AppColors.danger), kalınlık 1.5
      final border = decoration.border as Border;
      expect(border.top.color, AppColors.danger);
      expect(border.top.width, 1.5);

      // Yazı: AppColors.dangerText ve TextDecoration.none (sarı alt çizgi yok)
      final textWidget = tester.widget<Text>(cancelTextFinder);
      expect(textWidget.style?.color, AppColors.dangerText);
      expect(textWidget.style?.decoration, TextDecoration.none);
    });
  });
}
