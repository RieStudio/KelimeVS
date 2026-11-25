import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/primary_button.dart';
import 'package:app/core/widgets/secondary_button.dart';
import 'package:app/features/achievements/domain/user_achievement.dart';
import 'package:app/features/achievements/presentation/widgets/achievement_badges_row.dart';
import 'package:app/features/achievements/presentation/widgets/achievement_detail_sheet.dart';
import 'package:app/features/auth/application/auth_notifier.dart';
import 'package:app/features/auth/data/auth_repository.dart';
import 'package:app/features/profile/application/profile_notifier.dart';
import 'package:app/features/profile/data/profile_repository.dart';
import 'package:app/features/profile/presentation/profile_screen.dart';

class _ProfileTestAuthRepo implements AuthRepository {
  @override
  bool get isAuthenticated => true;
  @override
  bool get isGoogleLinked => true;
  @override
  String? get linkedEmail => 'test@google.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAuthNotifier extends AuthNotifier {
  final bool isGoogleLinked;
  _TestAuthNotifier({this.isGoogleLinked = true});

  @override
  AuthUiState build() => AuthUiState(
        isAuthenticated: true,
        isGoogleLinked: isGoogleLinked,
        linkedEmail: isGoogleLinked ? 'test@google.com' : null,
      );
}

class _TestProfileNotifier extends ProfileNotifier {
  final ProfileState _state;
  _TestProfileNotifier(this._state);

  @override
  ProfileState build() => _state;

  @override
  Future<bool> syncWithServer({bool force = false}) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      LocalProfileRepository.keyNickname: 'Mehmet',
    });
  });

  Widget buildTestScreen({bool isGoogleLinked = true}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_ProfileTestAuthRepo()),
        authNotifierProvider.overrideWith(() => _TestAuthNotifier(isGoogleLinked: isGoogleLinked)),
      ],
      child: const MaterialApp(
        home: ProfileScreen(),
      ),
    );
  }

  testWidgets('1. Profil ekranı: Başlık, mevcut takma ad ve Adı Değiştir butonu görüntülenir', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profileTitle), findsOneWidget);
    expect(find.text('Mehmet'), findsOneWidget);
    expect(find.text('M'), findsOneWidget); // Avatar initial
    expect(find.text(AppStrings.changeNickname), findsOneWidget);
  });

  testWidgets('2. "Adı Değiştir" butonuna basılınca diyalog açılır ve yeni geçerli ad kaydedilir', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SecondaryButton, AppStrings.changeNickname));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.newNicknamePrompt), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Geçersiz ad gir (küfür)
    await tester.enterText(find.byType(TextField), 'salak');
    await tester.pumpAndSettle();

    expect(find.text('Bu takma ad uygunsuz ifadeler içeriyor.'), findsOneWidget);
    var saveButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.save),
    );
    expect(saveButton.onPressed, isNull);

    // Geçerli yeni ad gir
    await tester.enterText(find.byType(TextField), 'Baris_34');
    await tester.pumpAndSettle();

    saveButton = tester.widget<PrimaryButton>(
      find.widgetWithText(PrimaryButton, AppStrings.save),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(PrimaryButton, AppStrings.save));
    await tester.pumpAndSettle();

    // Diyalog kapanmalı ve ekranda yeni ad görünmeli
    expect(find.text(AppStrings.newNicknamePrompt), findsNothing);
    expect(find.text('Baris_34'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    // Depoyu doğrula
    const repo = LocalProfileRepository();
    final updated = await repo.getNickname();
    expect(updated, 'Baris_34');
  });

  testWidgets('3. Bağlı hesap kartında account_linked_game.svg ikonu (renkli, check olmadan) gösterilir', (tester) async {
    await tester.pumpWidget(buildTestScreen(isGoogleLinked: true));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.linkedAccount), findsOneWidget);
    expect(find.text('test@google.com'), findsOneWidget);

    final svgFinder = find.byWidgetPredicate(
      (w) =>
          w is SvgPicture &&
          w.bytesLoader is SvgAssetLoader &&
          (w.bytesLoader as SvgAssetLoader).assetName ==
              'assets/icons/account_linked_game.svg',
    );
    expect(svgFinder, findsOneWidget);
    final svg = tester.widget<SvgPicture>(svgFinder);
    expect(svg.width, 44);
    expect(svg.height, 44);
    expect(svg.colorFilter, isNull);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('4. Kendi profilinde başarım yoksa rozet satırı hiç çizilmez', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_ProfileTestAuthRepo()),
          authNotifierProvider.overrideWith(() => _TestAuthNotifier()),
          profileProvider.overrideWith(
            () => _TestProfileNotifier(
              const ProfileState(
                nickname: 'Mehmet',
                isLoaded: true,
                achievements: [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AchievementBadgesRow), findsNothing);
  });

  testWidgets('5. Kendi profilinde 5 rozette kaydırma+solma görünür ve dokununca detay sheet açılır', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_ProfileTestAuthRepo()),
          authNotifierProvider.overrideWith(() => _TestAuthNotifier()),
          profileProvider.overrideWith(
            () => _TestProfileNotifier(
              const ProfileState(
                nickname: 'Mehmet',
                isLoaded: true,
                achievements: [
                  UserAchievement(id: 'first_match', unlockedAt: 1700000000000),
                  UserAchievement(id: 'first_win', unlockedAt: 1700000100000),
                  UserAchievement(id: 'matches_10', unlockedAt: 1700000200000),
                  UserAchievement(id: 'streak_3', unlockedAt: 1700000300000, count: 4),
                  UserAchievement(id: 'wins_10', unlockedAt: 1700000400000),
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AchievementBadgesRow), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.text('x4'), findsOneWidget);

    // Satır ekran genişliğinde (360 dp) olmalı ve ilk rozet soldan 20 px içeride başlamalı
    expect(tester.getSize(find.byType(AchievementBadgesRow)).width, 360.0);
    final firstBadge = find.bySemanticsLabel(
      AppStrings.achievementBadgeSemantic('Yükselen Yıldız', 1),
    );
    expect(tester.getTopLeft(firstBadge).dx, 20.0);

    // En sağa kaydırınca ofset sıfırlanmamalı
    final rowScrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(AchievementBadgesRow),
        matching: find.byType(Scrollable),
      ),
    );
    final maxExtent = rowScrollable.position.maxScrollExtent;
    expect(maxExtent, greaterThan(0.0));
    await tester.drag(
      find.descendant(
        of: find.byType(AchievementBadgesRow),
        matching: find.byType(ListView),
      ),
      Offset(-maxExtent - 50, 0),
    );
    await tester.pumpAndSettle();
    expect(rowScrollable.position.pixels, closeTo(maxExtent, 1.0));

    await tester.tap(find.bySemanticsLabel(AppStrings.achievementBadgeSemantic('Üçlü Seri', 4)));
    await tester.pumpAndSettle();

    expect(find.byType(AchievementDetailSheet), findsOneWidget);
    expect(find.text('Üçlü Seri'), findsOneWidget);
    expect(find.text('x4 kez kazanıldı'), findsOneWidget);
  });
}
