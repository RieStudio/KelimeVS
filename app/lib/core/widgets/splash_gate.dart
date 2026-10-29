import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Splash kapısı ve süre sabitleri
class SplashConfig {
  /// Minimum splash gösterilme süresi (~1200 ms)
  static const Duration minSplashDuration = Duration(milliseconds: 1200);

  /// Geçiş animasyonu (fade-out) süresi (~250 ms)
  static const Duration fadeDuration = Duration(milliseconds: 250);

  /// Splash ekranı arka plan rengi (SİYAH #000000)
  static const Color backgroundColor = Color(0xFF000000);

  /// Sadece soğuk başlangıçta bir kez çalışması için statik durum bayrağı.
  /// Arka plandan dönünce veya sayfa geçişlerinde tekrar göstermez.
  static bool hasShownSplash = false;

  /// Test senaryolarında durumu sıfırlamak veya ayarlamak için yardımcı.
  static void resetForTest({bool hasShown = false}) {
    hasShownSplash = hasShown;
  }
}

/// Soğuk başlangıçta RieStudio beyaz logosunu siyah zemin üzerinde gösteren görsel kapı (gate).
/// Mevcut başlatma akışına dokunmadan kök widget'ın (child) önünde durur.
class SplashGate extends StatefulWidget {
  final Widget child;

  const SplashGate({
    super.key,
    required this.child,
  });

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;
  Timer? _splashTimer;
  bool _isDismissed = false;
  bool _hasFirstFrame = false;
  bool _timerElapsed = false;

  static const SystemUiOverlayStyle _splashOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: SplashConfig.backgroundColor,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static const SystemUiOverlayStyle _normalOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    if (SplashConfig.hasShownSplash) {
      _isDismissed = true;
      return;
    }

    SystemChrome.setSystemUIOverlayStyle(_splashOverlayStyle);

    final controller = AnimationController(
      vsync: this,
      duration: SplashConfig.fadeDuration,
      value: 1.0,
    );
    _fadeController = controller;

    _fadeAnimation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasFirstFrame = true;
      _checkReadyToDismiss();
    });

    _splashTimer = Timer(SplashConfig.minSplashDuration, () {
      _timerElapsed = true;
      _checkReadyToDismiss();
    });
  }

  void _checkReadyToDismiss() {
    if (!mounted || !_hasFirstFrame || !_timerElapsed || _isDismissed) {
      return;
    }

    _fadeController?.reverse().then((_) {
      if (mounted) {
        SystemChrome.setSystemUIOverlayStyle(_normalOverlayStyle);
        setState(() {
          _isDismissed = true;
        });
        SplashConfig.hasShownSplash = true;
      }
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _fadeController?.dispose();
    if (!_isDismissed && !SplashConfig.hasShownSplash) {
      SystemChrome.setSystemUIOverlayStyle(_normalOverlayStyle);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoWidth = math.min(screenWidth * 0.45, 200.0);

    return Stack(
      children: [
        widget.child,
        if (!_isDismissed && _fadeAnimation != null)
          FadeTransition(
            opacity: _fadeAnimation!,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: _splashOverlayStyle,
              child: AbsorbPointer(
                child: Container(
                  color: SplashConfig.backgroundColor,
                  width: double.infinity,
                  height: double.infinity,
                  alignment: Alignment.center,
                  child: Semantics(
                    label: AppStrings.companyName,
                    child: Image.asset(
                      'assets/images/riestudio_logo_white.png',
                      width: logoWidth,
                      fit: BoxFit.contain,
                      semanticLabel: AppStrings.companyName,
                      cacheWidth: 400,
                      errorBuilder: (context, error, stackTrace) => Text(
                        AppStrings.companyName,
                        style: AppTextStyles.screenTitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
