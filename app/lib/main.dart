import 'package:flutter/material.dart';
import 'core/icons/app_icons.dart';
import 'core/strings/app_strings.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_widgets.dart';
import 'gallery/component_gallery.dart';

void main() {
  runApp(const KelimeGoApp());
}

class KelimeGoApp extends StatelessWidget {
  const KelimeGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kelime Go',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<AppNavItem> _navItems = [
    AppNavItem(
      icon: AppIcons.home,
      label: AppStrings.navHome,
    ),
    AppNavItem(
      icon: AppIcons.leaderboard,
      label: AppStrings.navLeaderboard,
    ),
    AppNavItem(
      icon: AppIcons.shop,
      label: AppStrings.navShop,
    ),
    AppNavItem(
      icon: AppIcons.profile,
      label: AppStrings.navProfile,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          ComponentGallery(),
          _TabPlaceholder(title: AppStrings.navLeaderboard),
          _TabPlaceholder(title: AppStrings.navShop),
          _TabPlaceholder(title: AppStrings.navProfile),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
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
      appBar: AppBar(
        title: Text(title, style: AppTextStyles.screenTitle),
      ),
      body: Center(
        child: Text(
          title,
          style: AppTextStyles.cardTitle,
        ),
      ),
    );
  }
}
