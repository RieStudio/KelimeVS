import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/achievement_notification_service.dart';
import '../domain/achievement_ui_manifest.dart';
import 'achievement_notification_card.dart';

/// Global overlay katmanında veya MaterialApp.builder seviyesinde çalışan
/// başarım bildirimi animasyon ve sunum bileşeni.
///
/// Özellikler:
/// - Üstten yaylanarak (overshoot, Curves.easeOutBack) iner.
/// - Giriş anında hafif haptic titreşim (HapticFeedback.lightImpact) verir.
/// - 4000 ms boyunca görünür kalır, ardından yukarı doğru kayarak (Curves.easeInCubic) kaybolur.
/// - Kullanıcı dokunduğunda veya yukarı kaydırdığında hemen kapanır.
/// - Kapanış tamamlandığında sıradaki başarıma geçmesi için servisi tetikler.
/// - Uygulama arka plana alındığında kuyruk otomatik temizlenir.
class AchievementNotificationOverlay extends ConsumerStatefulWidget {
  const AchievementNotificationOverlay({super.key});

  @override
  ConsumerState<AchievementNotificationOverlay> createState() =>
      _AchievementNotificationOverlayState();
}

class _AchievementNotificationOverlayState
    extends ConsumerState<AchievementNotificationOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animController;
  Timer? _displayTimer;
  AchievementUiItem? _activeItem;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialState = ref.read(achievementNotificationProvider);
      if (initialState.currentItem != null && _activeItem == null) {
        _showItem(initialState.currentItem!, initialState.displayDurationMs);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _displayTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _displayTimer?.cancel();
      ref.read(achievementNotificationProvider.notifier).clearQueue();
    }
  }

  void _showItem(AchievementUiItem item, int durationMs) {
    _displayTimer?.cancel();
    _isDismissing = false;
    setState(() {
      _activeItem = item;
    });

    // Girişte hafif titreşim
    HapticFeedback.lightImpact();

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      _animController.value = 1.0;
    } else {
      _animController.forward(from: 0.0);
    }

    _displayTimer = Timer(Duration(milliseconds: durationMs), () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    _displayTimer?.cancel();

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      _animController.value = 0.0;
      if (mounted) {
        setState(() {
          _activeItem = null;
        });
        ref.read(achievementNotificationProvider.notifier).dismissCurrent();
      }
    } else {
      _animController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _activeItem = null;
          });
          ref.read(achievementNotificationProvider.notifier).dismissCurrent();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AchievementNotificationState>(
      achievementNotificationProvider,
      (previous, current) {
        if (current.currentItem != null && current.token != previous?.token) {
          _showItem(current.currentItem!, current.displayDurationMs);
        } else if (current.currentItem == null && previous?.currentItem != null) {
          if (!_isDismissing) {
            _dismiss();
          }
        }
      },
    );

    if (_activeItem == null) {
      return const SizedBox.shrink();
    }

    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AchievementNotificationCard(
          item: _activeItem!,
          onDismiss: _dismiss,
        ),
      );
    }

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.0, -1.2),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _animController,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: FadeTransition(
        opacity: _animController,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AchievementNotificationCard(
            item: _activeItem!,
            onDismiss: _dismiss,
          ),
        ),
      ),
    );
  }
}
