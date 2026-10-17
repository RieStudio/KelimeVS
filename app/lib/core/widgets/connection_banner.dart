import 'dart:async';
import 'package:flutter/material.dart';

import '../strings/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../../features/game/application/match_ui_state.dart';

/// DESIGN.md Bölüm 6: Bağlantı uyarısı (ConnectionBanner)
///
/// Maç ekranında kendi bağlantın koptuğunda üst çubuğun hemen altında tam genişlikte ince şerit:
/// - Zemin: dangerSurface, altta 2 px dangerSoft çizgi.
/// - Yazı: ortalı dangerText (Nunito 13/800): "Bağlantı koptu, yeniden bağlanılıyor…"
/// - Yükseklik: 32 dp.
/// - İçeriği aşağı itmez, üstüne biner.
/// - Kopma 700 ms'den kısa sürerse (debounce) şerit HİÇ görünmez (ekran titremesini önleme).
/// - Yeniden bağlanınca şerit 200 ms'de kaybolur ve bright zeminli, ink yazılı kısa bir "Bağlandı"
///   hapı 1.5 sn gösterilir.
/// - Sistem hareket azaltma (disableAnimations) ayarında animasyonsuz geçiş yapılır.
class ConnectionBanner extends StatefulWidget {
  final ConnectionStatus status;
  final bool opponentConnected;
  final Duration debounceDuration;
  final Duration fadeDuration;
  final Duration pillDuration;

  const ConnectionBanner({
    super.key,
    required this.status,
    this.opponentConnected = true,
    this.debounceDuration = const Duration(milliseconds: 700),
    this.fadeDuration = const Duration(milliseconds: 200),
    this.pillDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

enum _BannerPhase {
  hidden,
  reconnecting,
  restored,
  opponentDisconnected,
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  Timer? _debounceTimer;
  Timer? _pillTimer;
  _BannerPhase _phase = _BannerPhase.hidden;

  @override
  void initState() {
    super.initState();
    _handleTransition(
      newStatus: widget.status,
      oldStatus: null,
      newOpponentConnected: widget.opponentConnected,
      oldOpponentConnected: null,
    );
  }

  @override
  void didUpdateWidget(ConnectionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
        oldWidget.opponentConnected != widget.opponentConnected) {
      _handleTransition(
        newStatus: widget.status,
        oldStatus: oldWidget.status,
        newOpponentConnected: widget.opponentConnected,
        oldOpponentConnected: oldWidget.opponentConnected,
      );
    }
  }

  void _handleTransition({
    required ConnectionStatus newStatus,
    required ConnectionStatus? oldStatus,
    required bool newOpponentConnected,
    required bool? oldOpponentConnected,
  }) {
    // 1. Kendi bağlantımız kopuksa (reconnecting) öncelik daima bizdedir
    if (newStatus == ConnectionStatus.reconnecting) {
      _pillTimer?.cancel();
      _pillTimer = null;

      if (_phase == _BannerPhase.hidden ||
          _phase == _BannerPhase.opponentDisconnected) {
        // Rakip kopuk olsa bile kendi bağlantımız koptuğu anda rakip şeridi gizlenir
        // ve kendi debounce sayacımız başlar
        _debounceTimer?.cancel();
        _debounceTimer = Timer(widget.debounceDuration, () {
          if (mounted && widget.status == ConnectionStatus.reconnecting) {
            setState(() {
              _phase = _BannerPhase.reconnecting;
            });
          }
        });
        if (_phase != _BannerPhase.hidden) {
          if (oldStatus == null && oldOpponentConnected == null) {
            _phase = _BannerPhase.hidden;
          } else {
            setState(() {
              _phase = _BannerPhase.hidden;
            });
          }
        }
      } else if (_phase == _BannerPhase.restored) {
        _phase = _BannerPhase.reconnecting;
      }
      return;
    }

    // 2. Kendi bağlantımız kalıcı koptuysa (permanentDisconnected)
    if (newStatus == ConnectionStatus.permanentDisconnected) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _pillTimer?.cancel();
      _pillTimer = null;
      if (_phase != _BannerPhase.hidden) {
        if (oldStatus == null && oldOpponentConnected == null) {
          _phase = _BannerPhase.hidden;
        } else {
          setState(() {
            _phase = _BannerPhase.hidden;
          });
        }
      }
      return;
    }

    // 3. Kendi bağlantımız bağlı (connected)
    if (newStatus == ConnectionStatus.connected) {
      // 3a. 700 ms dolmadan geri bağlandıysak (titremeyi önleme)
      if (_debounceTimer != null && _debounceTimer!.isActive) {
        _debounceTimer?.cancel();
        _debounceTimer = null;

        final targetPhase = !newOpponentConnected
            ? _BannerPhase.opponentDisconnected
            : _BannerPhase.hidden;
        if (_phase != targetPhase) {
          if (oldStatus == null && oldOpponentConnected == null) {
            _phase = targetPhase;
          } else {
            setState(() {
              _phase = targetPhase;
            });
          }
        }
        return;
      }

      // 3b. Kendi şeridimiz ekrandayken (reconnecting) geri bağlandıysak -> "Bağlandı" hapı göster
      if (_phase == _BannerPhase.reconnecting) {
        _debounceTimer = null;
        setState(() {
          _phase = _BannerPhase.restored;
        });

        _pillTimer?.cancel();
        _pillTimer = Timer(widget.pillDuration, () {
          if (mounted && _phase == _BannerPhase.restored) {
            setState(() {
              _phase = !widget.opponentConnected
                  ? _BannerPhase.opponentDisconnected
                  : _BannerPhase.hidden;
            });
          }
        });
        return;
      }

      // 3c. Şu anda "Bağlandı" hapı gösteriliyorsa (restored), hapın süresi dolana kadar bekle
      if (_phase == _BannerPhase.restored) {
        return;
      }

      // 3d. Normal durum: Kendi bağlantımız bağlı ve restored değil
      final targetPhase = !newOpponentConnected
          ? _BannerPhase.opponentDisconnected
          : _BannerPhase.hidden;

      if (_phase != targetPhase) {
        if (oldStatus == null && oldOpponentConnected == null) {
          _phase = targetPhase;
        } else {
          setState(() {
            _phase = targetPhase;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _pillTimer?.cancel();
    super.dispose();
  }

  Widget _buildDangerStrip({
    required String text,
    required Key key,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      height: 32,
      decoration: const BoxDecoration(
        color: AppColors.dangerSurface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.dangerSoft,
            width: 2,
          ),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: AppTextStyles.connectionBanner,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animDuration = disableAnimations ? Duration.zero : widget.fadeDuration;

    Widget child;
    switch (_phase) {
      case _BannerPhase.hidden:
        child = const SizedBox.shrink(key: ValueKey('banner_hidden'));
      case _BannerPhase.reconnecting:
        child = _buildDangerStrip(
          text: AppStrings.connectionReconnecting,
          key: const ValueKey('banner_reconnecting'),
        );
      case _BannerPhase.opponentDisconnected:
        child = _buildDangerStrip(
          text: AppStrings.opponentConnectionLost,
          key: const ValueKey('banner_opponent_disconnected'),
        );
      case _BannerPhase.restored:
        child = Container(
          key: const ValueKey('banner_restored'),
          width: double.infinity,
          height: 32,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space16,
              vertical: AppDimens.space4,
            ),
            decoration: BoxDecoration(
              color: AppColors.bright,
              borderRadius: AppDimens.borderRadiusFull,
              border: Border.all(
                color: AppColors.ink,
                width: AppDimens.borderThin,
              ),
            ),
            child: const Text(
              AppStrings.connectionRestored,
              style: AppTextStyles.connectionRestored,
            ),
          ),
        );
    }

    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: animDuration,
        child: child,
      ),
    );
  }
}

