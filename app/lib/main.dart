import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/icons/app_icons.dart';
import 'core/strings/app_strings.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_widgets.dart';
import 'features/game/application/match_providers.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/profile/application/profile_notifier.dart';
import 'features/profile/presentation/onboarding_nickname_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/store/presentation/store_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class KelimeVSApp extends StatelessWidget {
  final String? authError;

  const KelimeVSApp({super.key, this.authError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KelimeVS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
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
        _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
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
    final profile = ref.watch(profileProvider);
    if (!profile.isLoaded) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: SizedBox.shrink(),
      );
    }

    if (!profile.hasNickname) {
      return const OnboardingNicknameScreen();
    }

    final currentIndex = ref.watch(bottomNavIndexProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: IndexedStack(
        index: currentIndex,
        children: [
          const HomeScreen(),
          const _TabPlaceholder(title: AppStrings.navLeaderboard),
          const StoreScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: currentIndex,
        onTap: (index) {
          ref.read(bottomNavIndexProvider.notifier).setIndex(index);
        },
        items: _navItems,
      ),
    );
  }
}

class _TabPlaceholder extends StatelessWidget {
  final String title;

  const _TabPlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(title, style: AppTextStyles.screenTitle)),
      body: Center(child: Text(title, style: AppTextStyles.cardTitle)),
    );
  }
}
