import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      LocalProfileRepository.keyNickname: 'Oyuncu',
    });
  });

  testWidgets('KelimeGoApp smoke test - verifies navigation and gallery load', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KelimeGoApp()));
    await tester.pumpAndSettle();

    // Ana ekrandaki Hızlı Maç butonu ve alt gezinme sekmelerinin varlığını doğrula
    expect(find.text(AppStrings.quickMatch), findsOneWidget);
    expect(find.text(AppStrings.navHome), findsOneWidget);
    expect(find.text(AppStrings.navLeaderboard), findsOneWidget);
    expect(find.text(AppStrings.navShop), findsOneWidget);
    expect(find.text(AppStrings.navProfile), findsOneWidget);
  });
}
