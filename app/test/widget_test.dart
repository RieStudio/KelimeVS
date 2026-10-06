import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('KelimeGoApp smoke test - verifies navigation and gallery load', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const KelimeGoApp());

    // Galerideki başlık ve alt gezinme sekmelerinin varlığını doğrula
    expect(find.text(AppStrings.componentGallery), findsOneWidget);
    expect(find.text(AppStrings.navHome), findsOneWidget);
    expect(find.text(AppStrings.navLeaderboard), findsOneWidget);
    expect(find.text(AppStrings.navShop), findsOneWidget);
    expect(find.text(AppStrings.navProfile), findsOneWidget);
  });
}
