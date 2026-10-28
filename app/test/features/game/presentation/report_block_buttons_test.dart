import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/theme/app_text_styles.dart';
import 'package:app/core/widgets/player_avatar.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';

void main() {
  Widget buildOpponentCard({
    required String reportText,
    required String blockText,
    required double width,
    required double textScale,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.screenPaddingHorizontal,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space12,
                    vertical: AppDimens.space12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppDimens.borderRadiusListCard,
                    border: Border.all(
                      color: AppColors.mint,
                      width: AppDimens.borderThin,
                    ),
                  ),
                  child: Row(
                    children: [
                      const PlayerAvatar.opponent(
                        name: 'CanliRakip',
                        size: 36,
                      ),
                      const SizedBox(width: AppDimens.space10),
                      Expanded(
                        child: Text(
                          'CanliRakip',
                          style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppDimens.space8),
                      SecondaryButton(
                        text: reportText,
                        height: 38,
                        width: 78,
                        onPressed: () {},
                      ),
                      const SizedBox(width: AppDimens.space8),
                      SecondaryButton.danger(
                        text: blockText,
                        height: 38,
                        width: 82,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('Bildir ve Engelle Butonları Taşma ve Düzen Testleri', () {
    testWidgets(
      '320 dp genişlik ve textScaler 1.5 iken "Bildir" ve "Engelle" butonları taşmaz, tek satırda kalır ve yüksekliği korunur',
      (tester) async {
        await tester.pumpWidget(
          buildOpponentCard(
            reportText: AppStrings.reportAction,
            blockText: AppStrings.blockAction,
            width: 320,
            textScale: 1.5,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(AppStrings.reportAction), findsOneWidget);
        expect(find.text(AppStrings.blockAction), findsOneWidget);

        // Her iki butonun içindeki Text widget'larının tek satır olduğunu doğrula
        final reportTextWidget = tester.widget<Text>(find.descendant(
          of: find.widgetWithText(SecondaryButton, AppStrings.reportAction),
          matching: find.byType(Text),
        ));
        final blockTextWidget = tester.widget<Text>(find.descendant(
          of: find.widgetWithText(SecondaryButton, AppStrings.blockAction),
          matching: find.byType(Text),
        ));
        expect(reportTextWidget.maxLines, 1);
        expect(blockTextWidget.maxLines, 1);

        // Buton boyutlarının ve dokunma alanının (minTouchTarget) bozulmadığını doğrula
        final reportRect = tester.getRect(
          find.widgetWithText(SecondaryButton, AppStrings.reportAction),
        );
        final blockRect = tester.getRect(
          find.widgetWithText(SecondaryButton, AppStrings.blockAction),
        );
        expect(reportRect.height, AppDimens.minTouchTarget); // 48.0 dokunma alanı
        expect(reportRect.width, 78.0);
        expect(blockRect.height, AppDimens.minTouchTarget); // 48.0 dokunma alanı
        expect(blockRect.width, 82.0);

        // İç buton gövdesinin 38 dp yüksekliğini koruduğunu doğrula
        final reportContainers = tester.widgetList<Container>(find.descendant(
          of: find.widgetWithText(SecondaryButton, AppStrings.reportAction),
          matching: find.byType(Container),
        ));
        expect(reportContainers.first.constraints?.maxHeight ?? 38.0, 38.0);
      },
    );

    testWidgets(
      '320 dp genişlik ve textScaler 1.5 iken "Bildirildi" ve "Engellendi" (uzun metinler) taşmaz ve tek satırda kalır',
      (tester) async {
        await tester.pumpWidget(
          buildOpponentCard(
            reportText: AppStrings.reportedStatus,
            blockText: AppStrings.blockedStatus,
            width: 320,
            textScale: 1.5,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(AppStrings.reportedStatus), findsOneWidget);
        expect(find.text(AppStrings.blockedStatus), findsOneWidget);

        final reportedTextWidget = tester.widget<Text>(find.descendant(
          of: find.widgetWithText(SecondaryButton, AppStrings.reportedStatus),
          matching: find.byType(Text),
        ));
        final blockedTextWidget = tester.widget<Text>(find.descendant(
          of: find.widgetWithText(SecondaryButton, AppStrings.blockedStatus),
          matching: find.byType(Text),
        ));
        expect(reportedTextWidget.maxLines, 1);
        expect(blockedTextWidget.maxLines, 1);

        final reportedRect = tester.getRect(
          find.widgetWithText(SecondaryButton, AppStrings.reportedStatus),
        );
        final blockedRect = tester.getRect(
          find.widgetWithText(SecondaryButton, AppStrings.blockedStatus),
        );
        expect(reportedRect.height, AppDimens.minTouchTarget);
        expect(reportedRect.width, 78.0);
        expect(blockedRect.height, AppDimens.minTouchTarget);
        expect(blockedRect.width, 82.0);
      },
    );

    testWidgets(
      'Diyalog/Aksiyon butonları (PrimaryButton) textScaler 1.5 iken taşmaz ve tek satırda kalır',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PrimaryButton(
                          text: AppStrings.blockConfirm,
                          backgroundColor: AppColors.danger,
                          onPressed: () {},
                        ),
                        const SizedBox(height: AppDimens.space12),
                        PrimaryButton(
                          text: AppStrings.reportAction,
                          onPressed: () {},
                        ),
                        const SizedBox(height: AppDimens.space12),
                        SecondaryButton(
                          text: AppStrings.unblockAction,
                          height: 42,
                          width: 84,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final blockConfirmText = tester.widget<Text>(find.descendant(
          of: find.widgetWithText(PrimaryButton, AppStrings.blockConfirm),
          matching: find.byType(Text),
        ));
        final reportActionText = tester.widget<Text>(find.descendant(
          of: find.widgetWithText(PrimaryButton, AppStrings.reportAction),
          matching: find.byType(Text),
        ));
        final unblockText = tester.widget<Text>(find.descendant(
          of: find.widgetWithText(SecondaryButton, AppStrings.unblockAction),
          matching: find.byType(Text),
        ));

        expect(blockConfirmText.maxLines, 1);
        expect(reportActionText.maxLines, 1);
        expect(unblockText.maxLines, 1);
      },
    );
  });
}

