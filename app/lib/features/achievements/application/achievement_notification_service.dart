import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/achievement_ui_manifest.dart';

/// Başarım bildirim katmanının durum modeli.
class AchievementNotificationState {
  /// Şu an gösterilmekte olan başarım (yoksa null).
  final AchievementUiItem? currentItem;

  /// Bildirimin ekranda kalma süresi (varsayılan: 4000 ms).
  final int displayDurationMs;

  /// Her yeni başarım gösterildiğinde artan belirteç (aynı ID ardışık gelse bile state değişikliğini tetikler).
  final int token;

  const AchievementNotificationState({
    this.currentItem,
    this.displayDurationMs = 4000,
    this.token = 0,
  });

  AchievementNotificationState copyWith({
    AchievementUiItem? currentItem,
    int? displayDurationMs,
    int? token,
  }) {
    return AchievementNotificationState(
      currentItem: currentItem ?? this.currentItem,
      displayDurationMs: displayDurationMs ?? this.displayDurationMs,
      token: token ?? this.token,
    );
  }
}

/// Başarım bildirimlerinin FIFO (ilk giren ilk çıkar) kuyruğunu ve zamanlamasını yöneten Notifier.
///
/// Kurallar:
/// - Birden fazla başarım açıldığında üst üste yığılmaz, sıralı gösterilir.
/// - Her başarım ekranda 4000 ms kalır (veya kullanıcı dokunup/kaydırıp kapatana kadar).
/// - İki başarım arasında 250 ms geçiş payı bırakılır.
/// - Uygulama arka plana geçtiğinde bekleyen kuyruk temizlenebilir.
class AchievementNotificationNotifier
    extends Notifier<AchievementNotificationState> {
  final List<AchievementUiItem> _pendingQueue = [];
  Timer? _initialDelayTimer;
  Timer? _transitionTimer;
  int _tokenCounter = 0;

  @override
  AchievementNotificationState build() {
    ref.onDispose(() {
      _initialDelayTimer?.cancel();
      _transitionTimer?.cancel();
      _pendingQueue.clear();
    });
    return const AchievementNotificationState();
  }

  /// Bekleyen kuyruktaki başarım sayısı.
  int get queueLength => _pendingQueue.length;

  /// Tek bir başarım bildirimini sıraya alır.
  void show(String achievementId, {Duration initialDelay = Duration.zero}) {
    showAll([achievementId], initialDelay: initialDelay);
  }

  /// Birden fazla başarım kimliğini sıraya alır.
  ///
  /// Tekrarlanan ID'ler listeden elenir (deduplicate).
  /// Bilinmeyen ID'ler sessizce yoksayılır (çökme olmaz).
  void showAll(
    List<String> achievementIds, {
    Duration initialDelay = Duration.zero,
  }) {
    final uniqueIds = achievementIds.toSet().toList();
    final items = uniqueIds
        .map(AchievementUiManifest.get)
        .whereType<AchievementUiItem>()
        .toList();

    if (items.isEmpty) return;

    if (initialDelay > Duration.zero) {
      _initialDelayTimer?.cancel();
      _initialDelayTimer = Timer(initialDelay, () {
        if (!ref.mounted) return;
        _enqueueItems(items);
      });
    } else {
      _enqueueItems(items);
    }
  }

  void _enqueueItems(List<AchievementUiItem> items) {
    if (state.currentItem == null) {
      final first = items.removeAt(0);
      _pendingQueue.addAll(items);
      _tokenCounter++;
      state = AchievementNotificationState(
        currentItem: first,
        token: _tokenCounter,
      );
    } else {
      _pendingQueue.addAll(items);
    }
  }

  /// Aktif bildirimi kapatıp sıradaki başarıma geçer.
  void dismissCurrent() {
    if (state.currentItem == null) return;

    _transitionTimer?.cancel();
    state = const AchievementNotificationState(currentItem: null);

    if (_pendingQueue.isNotEmpty) {
      _transitionTimer = Timer(const Duration(milliseconds: 250), () {
        if (!ref.mounted) return;
        if (_pendingQueue.isNotEmpty) {
          final next = _pendingQueue.removeAt(0);
          _tokenCounter++;
          state = AchievementNotificationState(
            currentItem: next,
            token: _tokenCounter,
          );
        }
      });
    }
  }

  /// Uygulama arka plana geçtiğinde veya kullanıcı temizlemek istediğinde
  /// bekleyen kuyruğu ve gecikme zamanlayıcılarını iptal eder.
  void clearQueue() {
    _initialDelayTimer?.cancel();
    _transitionTimer?.cancel();
    _pendingQueue.clear();
    state = const AchievementNotificationState(currentItem: null);
  }
}

/// Başarım bildirimlerinin durumunu ve kuyruğunu dinleyen Riverpod sağlayıcısı.
final achievementNotificationProvider = NotifierProvider<
    AchievementNotificationNotifier, AchievementNotificationState>(
  AchievementNotificationNotifier.new,
);
