import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/theme/app_dimens.dart';
import 'package:app/core/widgets/app_pressable.dart';

void main() {
  group('AppPressable Widget Tests', () {
    testWidgets('1. Uzun basma (hold): basılı tutulunca kayma ve gölge kalkar, bırakınca eski haline döner ve onTap tetiklenir', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppPressable(
                pressOffset: 3.0,
                onTap: () => tapCount++,
                builder: (context, isPressed) {
                  return Container(
                    width: 120,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      boxShadow: isPressed
                          ? const []
                          : const [
                              BoxShadow(
                                color: AppColors.ink,
                                offset: Offset(0, 3),
                                blurRadius: 0,
                              ),
                            ],
                    ),
                    child: const Text('Bas'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final pressableFinder = find.byType(AppPressable);
      final containerFinder = find.descendant(
        of: pressableFinder,
        matching: find.byType(Container),
      );

      // Başlangıç durumu (basılmamış)
      final stateBefore = tester.state<AppPressableState>(pressableFinder);
      expect(stateBefore.isPressed, isFalse);
      final initialTop = tester.getTopLeft(containerFinder).dy;
      final initialDecoration =
          tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(initialDecoration.boxShadow, isNotEmpty);
      expect(initialDecoration.boxShadow!.first.offset, const Offset(0, 3));

      // Basılı tut (TapDown)
      final gesture = await tester.startGesture(tester.getCenter(pressableFinder));
      await tester.pump();
      expect(stateBefore.isPressed, isTrue);

      // 90 ms animasyon süresi sonunda tam kayma
      await tester.pump(const Duration(milliseconds: 90));
      final pressedTop = tester.getTopLeft(containerFinder).dy;
      expect(pressedTop, closeTo(initialTop + 3.0, 0.01));

      final pressedDecoration =
          tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(pressedDecoration.boxShadow, isEmpty);

      // minPressedDuration (110 ms) dolana kadar parmak basılı tutulmaya devam eder (90 + 30 = 120 ms)
      await tester.pump(const Duration(milliseconds: 30));
      expect(stateBefore.isPressed, isTrue);

      // Bırak (TapUp -> onTap) - minPressedDuration dolduğu için anında bırakılır
      await gesture.up();
      await tester.pump();
      expect(stateBefore.isPressed, isFalse);

      await tester.pump(const Duration(milliseconds: 90));
      final releasedTop = tester.getTopLeft(containerFinder).dy;
      expect(releasedTop, closeTo(initialTop, 0.01));

      final releasedDecoration =
          tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(releasedDecoration.boxShadow, isNotEmpty);
      expect(tapCount, 1);
    });

    testWidgets('2. Hızlı dokunuşta (tester.tap): basılı görünüm sonraki karelerde görünür, en az ~110 ms korunur ve onTap tam bir kez çalışır', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppPressable(
                pressOffset: 3.0,
                onTap: () => tapCount++,
                builder: (context, isPressed) {
                  return Container(
                    width: 120,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      boxShadow: isPressed
                          ? const []
                          : const [
                              BoxShadow(
                                color: AppColors.ink,
                                offset: Offset(0, 3),
                                blurRadius: 0,
                              ),
                            ],
                    ),
                    child: const Text('Hızlı Dokun'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final pressableFinder = find.byType(AppPressable);
      final containerFinder = find.descendant(
        of: pressableFinder,
        matching: find.byType(Container),
      );
      final initialTop = tester.getTopLeft(containerFinder).dy;

      // Hızlı dokun (down ve up aynı işlemde gerçekleşir)
      await tester.tap(pressableFinder);

      // İlk kare: parmak kalkmış olsa dahi minPressedDuration sayesinde isPressed true olmalıdır
      await tester.pump();
      final state = tester.state<AppPressableState>(pressableFinder);
      expect(state.isPressed, isTrue);

      final immediateDecoration =
          tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(immediateDecoration.boxShadow, isEmpty);

      // 90 ms sonra: buton aşağı kayma pozisyonuna tam ulaşmıştır
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + 3.0, 0.01));
      // 70 ms actionDelay dolduğu için onTap tetiklenmiştir
      expect(tapCount, 1);
      // Ancak 110 ms minPressedDuration dolmadığı için hâlâ basılı durumdadır
      expect(state.isPressed, isTrue);

      // 110 ms minPressedDuration dolduğunda (toplam 120 ms) basılı durum sonlanır
      await tester.pump(const Duration(milliseconds: 30));
      expect(state.isPressed, isFalse);

      // 90 ms yaylanma animasyonu tamamlanınca başlangıç pozisyonuna ve gölgesine döner
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      final finalDec =
          tester.widget<Container>(containerFinder).decoration as BoxDecoration;
      expect(finalDec.boxShadow, isNotEmpty);
      expect(tapCount, 1); // Çift tetikleme olmamalıdır
    });

    testWidgets('3. Kaydırılabilir ata (ListView) içinde hızlı dokunuşta gecikmesiz basma efekti görünür', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 50),
                AppPressable(
                  pressOffset: 3.0,
                  onTap: () => tapCount++,
                  builder: (context, isPressed) {
                    return Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        boxShadow: isPressed
                            ? const []
                            : const [
                                BoxShadow(
                                  color: AppColors.ink,
                                  offset: Offset(0, 3),
                                  blurRadius: 0,
                                ),
                              ],
                      ),
                      child: const Text('Listede Buton'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      final pressableFinder = find.byType(AppPressable);
      final containerFinder = find.descendant(
        of: pressableFinder,
        matching: find.byType(Container),
      ).first;
      final initialTop = tester.getTopLeft(containerFinder).dy;

      // ListView içinde hızlı dokun
      await tester.tap(pressableFinder);
      await tester.pump();

      // Listener onPointerDown sayesinde ListView tapTimeout gecikmesine takılmadan ilk karede basılıdır
      final state = tester.state<AppPressableState>(pressableFinder);
      expect(state.isPressed, isTrue);

      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + 3.0, 0.01));
      expect(tapCount, 1);

      await tester.pumpAndSettle();
      expect(state.isPressed, isFalse);
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
    });

    testWidgets('4. Kaydırma/parmak çıkınca (cancel) efekt eski haline döner ve onTap tetiklenmez', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppPressable(
                pressOffset: 3.0,
                onTap: () => tapCount++,
                builder: (context, isPressed) {
                  return Container(
                    width: 120,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      boxShadow: isPressed
                          ? const []
                          : const [
                              BoxShadow(
                                color: AppColors.ink,
                                offset: Offset(0, 3),
                                blurRadius: 0,
                              ),
                            ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final pressableFinder = find.byType(AppPressable);
      final containerFinder = find.descendant(
        of: pressableFinder,
        matching: find.byType(Container),
      );

      final initialTop = tester.getTopLeft(containerFinder).dy;
      final gesture = await tester.startGesture(tester.getCenter(pressableFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop + 3.0, 0.01));

      // Parmak dışarı kaydırıldı veya iptal edildi (cancel)
      await gesture.cancel();
      await tester.pump();
      final state = tester.state<AppPressableState>(pressableFinder);
      expect(state.isPressed, isFalse);

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      expect(tapCount, 0);
    });

    testWidgets('5. enablePressAnimation=false iken basma efekti çalışmaz fakat onTap gecikmesiz tetiklenir', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppPressable(
                enablePressAnimation: false,
                pressOffset: 2.0,
                onTap: () => tapCount++,
                builder: (context, isPressed) {
                  return Container(
                    width: 80,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      boxShadow: isPressed
                          ? const []
                          : const [
                              BoxShadow(
                                color: AppColors.ink,
                                offset: Offset(0, 2),
                                blurRadius: 0,
                              ),
                            ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final pressableFinder = find.byType(AppPressable);
      final containerFinder = find.descendant(
        of: pressableFinder,
        matching: find.byType(Container),
      );

      final initialTop = tester.getTopLeft(containerFinder).dy;
      await tester.tap(pressableFinder);
      await tester.pump();

      final state = tester.state<AppPressableState>(pressableFinder);
      expect(state.isPressed, isFalse);
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));
      // Devre dışıyken actionDelay işletilmez, doğrudan çalışır
      expect(tapCount, 1);
    });

    testWidgets('6. onTap=null iken buton tamamen pasiftir, basma efekti ve tıklama çalışmaz', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppPressable(
                onTap: null,
                pressOffset: 3.0,
                builder: (context, isPressed) {
                  return Container(
                    width: 100,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      boxShadow: isPressed
                          ? const []
                          : const [
                              BoxShadow(
                                color: AppColors.ink,
                                offset: Offset(0, 3),
                                blurRadius: 0,
                              ),
                            ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final pressableFinder = find.byType(AppPressable);
      final containerFinder = find.descendant(
        of: pressableFinder,
        matching: find.byType(Container),
      );

      final initialTop = tester.getTopLeft(containerFinder).dy;
      await tester.tap(pressableFinder);
      await tester.pump();

      final state = tester.state<AppPressableState>(pressableFinder);
      expect(state.isPressed, isFalse);

      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(containerFinder).dy, closeTo(initialTop, 0.01));

      await tester.pumpAndSettle();
    });

    testWidgets('7. ensureMinTouchTarget en az 48x48 dokunma alanı sağlar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppPressable(
                ensureMinTouchTarget: true,
                onTap: () {},
                builder: (context, isPressed) {
                  return Container(
                    width: 30,
                    height: 20,
                    color: AppColors.card,
                  );
                },
              ),
            ),
          ),
        ),
      );

      final constrainedFinder = find.byType(ConstrainedBox);
      expect(constrainedFinder, findsWidgets);

      final constrainedBox = tester.widget<ConstrainedBox>(
        find.ancestor(
          of: find.byType(Container),
          matching: find.byType(ConstrainedBox),
        ).first,
      );

      expect(constrainedBox.constraints.minWidth, AppDimens.minTouchTarget);
      expect(constrainedBox.constraints.minHeight, AppDimens.minTouchTarget);
    });
  });
}
