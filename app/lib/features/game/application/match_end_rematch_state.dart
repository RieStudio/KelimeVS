// Saf Dart - Flutter UI bileşeni veya sunucu soketi bağımlılığı yoktur.

import '../../match_request/domain/match_request_models.dart';

/// Maç Sonu ekranında gösterilen rövanş görünüm durumları.
/// Hem insan hem bot rakipler bu durum modelini paylaşır.
sealed class MatchEndRematchState {
  const MatchEndRematchState();
}

/// Rövanş bu maç için uygun değil (final rematchAvailable == false, terk, void,
/// opponentUid yok veya kullanıcı/rakip rövanş sürecini sonlandırdı).
/// Yalnızca "Ana Sayfa" butonu gösterilir, üstte ek mesaj yer almaz.
class MatchEndRematchUnavailable extends MatchEndRematchState {
  const MatchEndRematchUnavailable();

  @override
  String toString() => 'MatchEndRematchUnavailable()';
}

/// Rövanş teklif edilebilir durumda.
/// "Rövanş" PrimaryButton gösterilir.
class MatchEndRematchIdle extends MatchEndRematchState {
  const MatchEndRematchIdle();

  @override
  String toString() => 'MatchEndRematchIdle()';
}

/// Gönderilen rövanş teklifi yanıt bekliyor.
/// "Rövanş bekleniyor · $secondsRemaining sn" metni ve "İptal" SecondaryButton gösterilir.
class MatchEndRematchPendingSent extends MatchEndRematchState {
  final int secondsRemaining;
  final String? requestId;

  const MatchEndRematchPendingSent({
    required this.secondsRemaining,
    this.requestId,
  });

  @override
  String toString() =>
      'MatchEndRematchPendingSent(secondsRemaining: $secondsRemaining, requestId: $requestId)';
}

/// Karşı taraftan bu maça yönelik rövanş teklifi geldi.
/// "`<Rakip>` rövanş istiyor!" metni ve satır içi "Kabul Et (NN)" / "Reddet" butonları gösterilir.
class MatchEndRematchPendingReceived extends MatchEndRematchState {
  final int secondsRemaining;
  final String requestId;

  const MatchEndRematchPendingReceived({
    required this.secondsRemaining,
    required this.requestId,
  });

  @override
  String toString() =>
      'MatchEndRematchPendingReceived(secondsRemaining: $secondsRemaining, requestId: $requestId)';
}

/// Rövanş kabul edildi, sunucudan eşleşme ve oda kurulumu bekleniyor.
/// "Rövanş başlıyor..." devre dışı butonu gösterilir.
class MatchEndRematchStarting extends MatchEndRematchState {
  const MatchEndRematchStarting();

  @override
  String toString() => 'MatchEndRematchStarting()';
}

/// Rövanş teklifi reddedildi (terminal).
/// "Rövanş reddedildi" KIRMIZI metin (AppColors.dangerText) ve "Ana Sayfa" butonu gösterilir.
class MatchEndRematchDeclined extends MatchEndRematchState {
  const MatchEndRematchDeclined();

  @override
  String toString() => 'MatchEndRematchDeclined()';
}

/// Rövanş teklifinin süresi doldu (terminal).
/// "Süre doldu" (AppColors.muted) metin ve "Ana Sayfa" butonu gösterilir.
class MatchEndRematchExpired extends MatchEndRematchState {
  const MatchEndRematchExpired();

  @override
  String toString() => 'MatchEndRematchExpired()';
}

/// Rakip şu an müsait değil (çevrimdışı, meşgul veya maç istekleri kapalı).
/// "Rakip şu an müsait değil" (AppColors.muted) metin ve "Ana Sayfa" butonu gösterilir.
class MatchEndRematchUnavailableReason extends MatchEndRematchState {
  const MatchEndRematchUnavailableReason();

  @override
  String toString() => 'MatchEndRematchUnavailableReason()';
}

/// Enerji yetersizliği vb. hata durumu (terminal).
class MatchEndRematchError extends MatchEndRematchState {
  final MatchRequestErrorCode code;

  const MatchEndRematchError(this.code);

  @override
  String toString() => 'MatchEndRematchError(code: $code)';
}
