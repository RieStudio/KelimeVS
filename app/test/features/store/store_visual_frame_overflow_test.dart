import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/store/data/store_api_client.dart';
import 'package:app/features/store/domain/models/store_item.dart';
import 'package:app/features/store/presentation/widgets/purchase_bottom_sheet.dart';
import 'package:app/features/store/presentation/widgets/store_frame_card.dart';

void main() {
  Widget buildTestApp({
    required Widget child,
    Size surfaceSize = const Size(320, 640),
    double textScale = 1.5,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: surfaceSize,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: child,
          ),
        ),
      ),
    );
  }

  group('StoreFrameCard 320x640 + textScale 1.5 overflow tests', () {
    final testFrames = [
      ('vine', 'Sarmaşık', 900, 'premium', 'visual'),
      ('silver_engraved', 'Gümüş Oyma', 400, 'basic', 'visual'),
      ('bronze_engraved', 'Bronz Oyma', 250, 'basic', 'visual'),
      ('gold_leaf', 'Altın Yaprak', 600, 'medium', 'visual'),
      ('classic', 'Klasik', 0, null, 'procedural'),
      ('diamond', 'Elmas', 800, null, 'procedural'),
    ];

    for (final frame in testFrames) {
      testWidgets('StoreFrameCard renders ${frame.$1} without overflow',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final item = StoreItem(
          id: frame.$1,
          name: frame.$2,
          price: frame.$3,
          owned: false,
          isEquipped: false,
          tier: frame.$4,
          kind: frame.$5,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: SizedBox(
              width: 140, // typical 2-column card width on 320dp screen (childAspectRatio 0.72)
              height: 194,
              child: StoreFrameCard(
                item: item,
                userCoins: 1000,
                playerName: 'Çetin Öztürk',
              ),
            ),
          ),
        );

        final err = tester.takeException();
        if (err is FlutterError) {
          debugPrint(err.toStringDeep());
        }
        expect(err, isNull);
        expect(find.byType(StoreFrameCard), findsOneWidget);
      });
    }
  });

  group('PurchaseBottomSheet 320x640 + textScale 1.5 overflow tests', () {
    final testFrames = [
      ('vine', 'Sarmaşık', 900),
      ('silver_engraved', 'Gümüş Oyma', 400),
      ('bronze_engraved', 'Bronz Oyma', 250),
      ('gold_leaf', 'Altın Yaprak', 600),
    ];

    for (final frame in testFrames) {
      testWidgets('PurchaseBottomSheet renders ${frame.$1} without overflow',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final item = StoreItem(
          id: frame.$1,
          name: frame.$2,
          price: frame.$3,
          owned: false,
          isEquipped: false,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: PurchaseBottomSheet(
                  item: item,
                  userCoins: 1000,
                  playerName: 'Çetin Öztürk',
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(PurchaseBottomSheet), findsOneWidget);
      });
    }
  });

  group('StorePurchaseUnsupportedVersion test', () {
    test('carries correct error message', () {
      const result = StorePurchaseUnsupportedVersion();
      expect(result.message, equals(AppStrings.storeUnsupportedClientVersion));
      expect(result.message,
          equals('Bu çerçeveyi almak için uygulamayı güncelleyin'));

      const customResult = StorePurchaseUnsupportedVersion('Özel hata mesajı');
      expect(customResult.message, equals('Özel hata mesajı'));
    });
  });
}
