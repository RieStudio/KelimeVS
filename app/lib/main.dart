import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/icons/app_icons.dart';
import 'core/network/network_status_provider.dart';
import 'core/strings/app_strings.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_dimens.dart';
import 'core/theme/app_text_styles.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/font_licenses.dart';
import 'core/widgets/app_widgets.dart';
import 'features/game/application/match_providers.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/leaderboard/application/leaderboard_providers.dart';
import 'features/leaderboard/presentation/leaderboard_screen.dart';
import 'features/profile/application/profile_notifier.dart';
import 'features/profile/presentation/onboarding_nickname_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/store/presentation/store_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  String? authError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    authError = e.toString();
  }

  runApp(ProviderScope(child: KelimeVSApp(authError: authError)));
}

class KelimeVSApp extends ConsumerWidget {
  final String? authError;

  const KelimeVSApp({super.key, this.authError});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkState = ref.watch(networkStatusProvider);
    final isSuppressed = ref.watch(isOfflineBannerSuppressedProvider);
    final showBanner =
        networkState.status == NetworkStatus.offline && !isSuppressed;

    return MaterialApp(
      title: 'KelimeVS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        if (!showBanner) {
          return child ?? const SizedBox.shrink();
        }

        // DESIGN.md 6b: Şerit içeriğin üstüne binmez, içeriği aşağı iter ve butonları kapatmaz
        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: AppColors.surface,
          body: Column(
            children: [
              GlobalOfflineBanner(
                isChecking: networkState.status == NetworkStatus.checking,
                onRetry: () =>
                    ref.read(networkStatusProvider.notifier).refresh(),
              ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
      home: MainShell(initialAuthError: authError),
    );
  }
}

class BottomNavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    state = index;
  }
}

final bottomNavIndexProvider = NotifierProvider<BottomNavIndexNotifier, int>(
  BottomNavIndexNotifier.new,
);

class MainShell extends ConsumerStatefulWidget {
  final String? initialAuthError;

  const MainShell({super.key, this.initialAuthError});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  String? _authError;
  StreamSubscription<User?>? _authSubscription;
  bool _hasVisitedLeaderboard = false;
  bool _hasInitialOnline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authError = widget.initialAuthError;
    _initAuth();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconcilePendingMatches();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(networkStatusProvider.notifier).onAppResumed();
      _reconcilePendingMatches();
      ref.read(profileProvider.notifier).retryPendingNicknameSync();
    }
  }

  void _reconcilePendingMatches() {
    ref.read(matchReconcilerProvider).reconcile();
  }

  Future<void> _initAuth() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        if (FirebaseAuth.instance.currentUser == null && _authError == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
        _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((
          _,
        ) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _authError = e.toString();
        });
      }
    }
  }

  Future<void> _retryStartupSequence() async {
    _authError = null;
    await _initAuth();
    if (mounted) {
      ref.read(profileProvider.notifier).syncWithServer();
      ref.read(matchReconcilerProvider).reconcile();
    }
  }

  void _onNetworkRestored() {
    ref.read(profileProvider.notifier).syncWithServer();
    ref.invalidate(leaderboardNotifierProvider);
    ref.read(matchReconcilerProvider).reconcile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  static const List<AppNavItem> _navItems = [
    AppNavItem(icon: AppIcons.home, label: AppStrings.navHome),
    AppNavItem(icon: AppIcons.leaderboard, label: AppStrings.navLeaderboard),
    AppNavItem(icon: AppIcons.shop, label: AppStrings.navShop),
    AppNavItem(icon: AppIcons.profile, label: AppStrings.navProfile),
  ];

  @override
  Widget build(BuildContext context) {
    final networkState = ref.watch(networkStatusProvider);

    // Ağ bağlantısı değişimlerini dinle
    ref.listen<NetworkState>(networkStatusProvider, (prev, next) {
      if (next.status == NetworkStatus.online) {
        if (!_hasInitialOnline) {
          setState(() {
            _hasInitialOnline = true;
          });
          _retryStartupSequence();
        } else if (prev?.status == NetworkStatus.offline) {
          _onNetworkRestored();
        }
      }
    });

    if (networkState.status == NetworkStatus.online && !_hasInitialOnline) {
      _hasInitialOnline = true;
    }

    // DESIGN.md 6b: Açılışta internet yoksa tam ekran OfflineSplashScreen
    if (!_hasInitialOnline && networkState.status == NetworkStatus.offline) {
      return OfflineSplashScreen(
        isChecking: networkState.status == NetworkStatus.checking,
        onRetry: () => ref.read(networkStatusProvider.notifier).refresh(),
      );
    }
    final profile = ref.watch(profileProvider);
    if (!profile.isLoaded) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (profile.syncError != null && !profile.hasNickname) {
      return Scaffold(
        key: const Key('profile_load_error_screen'),
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.screenPaddingHorizontal,
            ),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.dangerSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.dangerSoft,
                      width: AppDimens.borderThin,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 48,
                      color: AppColors.danger,
                    ),
                  ),
                ),
                const SizedBox(height: AppDimens.space24),
                Text(
                  AppStrings.profileLoadErrorTitle,
                  style: AppTextStyles.screenTitle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimens.space12),
                Text(
                  AppStrings.profileLoadErrorMessage,
                  style: AppTextStyles.bodyText.copyWith(
                    color: AppColors.muted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 3),
                PrimaryButton(
                  key: const Key('profile_load_retry_button'),
                  text: AppStrings.retry,
                  onPressed: profile.isSyncing
                      ? null
                      : () =>
                          ref.read(profileProvider.notifier).syncWithServer(),
                ),
                const SizedBox(height: AppDimens.space24),
              ],
            ),
          ),
        ),
      );
    }

    if (!profile.hasNickname) {
      return const OnboardingNicknameScreen();
    }

    ref.listen<int>(bottomNavIndexProvider, (prev, next) {
      if (next == 1 && _hasVisitedLeaderboard) {
        ref.read(leaderboardNotifierProvider.notifier).refresh();
      }
    });

    final currentIndex = ref.watch(bottomNavIndexProvider);
    if (currentIndex == 1 && !_hasVisitedLeaderboard) {
      _hasVisitedLeaderboard = true;
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: IndexedStack(
        index: currentIndex,
        children: [
          const HomeScreen(),
          _hasVisitedLeaderboard
              ? const LeaderboardScreen()
              : const SizedBox.shrink(
                  key: Key('leaderboard_unvisited_placeholder'),
                ),
          const StoreScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == 1 && currentIndex == 1 && _hasVisitedLeaderboard) {
            ref.read(leaderboardNotifierProvider.notifier).refresh();
          }
          ref.read(bottomNavIndexProvider.notifier).setIndex(index);
        },
        items: _navItems,
      ),
    );
  }
}
