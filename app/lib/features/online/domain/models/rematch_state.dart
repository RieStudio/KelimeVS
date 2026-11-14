// Saf Dart - Flutter veya harici paket bağımlılığı yoktur.

import 'online_messages.dart';

/// Rövanş hata kodları.
enum RematchErrorCode {
  noEnergy,
  opponentNoEnergy,
  blocked,
  accountDeleted,
  notAvailable,
  unavailable,
  unknown;

  static RematchErrorCode fromWire(String? value) {
    switch (value) {
      case 'no_energy':
        return RematchErrorCode.noEnergy;
      case 'opponent_no_energy':
        return RematchErrorCode.opponentNoEnergy;
      case 'blocked':
        return RematchErrorCode.blocked;
      case 'account_deleted':
        return RematchErrorCode.accountDeleted;
      case 'not_available':
        return RematchErrorCode.notAvailable;
      case 'unavailable':
        return RematchErrorCode.unavailable;
      default:
        return RematchErrorCode.unknown;
    }
  }
}

/// Rövanş durum makinesinin istemci tarafındaki tüm durumları.
sealed class RematchState {
  const RematchState();

  /// Buton gösterilmez veya devre dışıdır (terk, hükmen, kopma, void, bot veya rematchAvailable == false).
  static const RematchState unavailable = RematchUnavailable();

  /// Maç normal bitti, her iki oyuncu bağlı ve teklif gönderilebilir.
  static const RematchState idle = RematchIdle();

  /// Biz teklif gönderdik, rakibin yanıtını ve 45 sn sayacını bekliyoruz.
  static RematchPendingSent pendingSent({int secondsRemaining = 45}) =>
      RematchPendingSent(secondsRemaining: secondsRemaining);

  /// Rakip bize teklif gönderdi, Kabul / Reddet butonları ve 45 sn sayacı aktif.
  static RematchPendingReceived pendingReceived({int secondsRemaining = 45}) =>
      RematchPendingReceived(secondsRemaining: secondsRemaining);

  /// Teklif kabul edildi; sunucunun yeni maç odasını kurması ve `matched` mesajı bekleniyor.
  static const RematchState starting = RematchStarting();

  /// Teklif reddedildi (terminal).
  static const RematchState declined = RematchDeclined();

  /// Teklif süresi (45 sn) doldu (terminal).
  static const RematchState expired = RematchExpired();

  /// Rakip maç sonu ekranından ayrıldı veya bağlantısı koptu (terminal).
  static const RematchState opponentLeft = RematchOpponentLeft();

  /// Rövanş süreci kapandı (terminal).
  static const RematchState closed = RematchClosed();

  /// Sunucu hata döndürdü (no_energy, blocked vb.).
  static RematchError error(RematchErrorCode code, {String? rawCode}) =>
      RematchError(code: code, rawCode: rawCode);

  /// Yeni maç kuruldu; istemci yeni eşleşme bilgisiyle oyuna geçebilir.
  static RematchMatched matched(MatchedServerMessage matchedMessage) =>
      RematchMatched(matchedMessage);

  /// Teklif edilebilir durumda olup olmadığını belirtir.
  bool get canOffer => this is RematchIdle;

  /// Rövanş sürecinin sonlanıp sonlanmadığını belirtir.
  bool get isTerminal =>
      this is RematchDeclined ||
      this is RematchExpired ||
      this is RematchOpponentLeft ||
      this is RematchClosed ||
      this is RematchError ||
      this is RematchMatched;
}

class RematchUnavailable extends RematchState {
  const RematchUnavailable();

  @override
  String toString() => 'RematchUnavailable()';
}

class RematchIdle extends RematchState {
  const RematchIdle();

  @override
  String toString() => 'RematchIdle()';
}

class RematchPendingSent extends RematchState {
  final int secondsRemaining;

  const RematchPendingSent({required this.secondsRemaining});

  @override
  String toString() => 'RematchPendingSent(secondsRemaining: $secondsRemaining)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RematchPendingSent && other.secondsRemaining == secondsRemaining;

  @override
  int get hashCode => secondsRemaining.hashCode;
}

class RematchPendingReceived extends RematchState {
  final int secondsRemaining;

  const RematchPendingReceived({required this.secondsRemaining});

  @override
  String toString() =>
      'RematchPendingReceived(secondsRemaining: $secondsRemaining)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RematchPendingReceived &&
          other.secondsRemaining == secondsRemaining;

  @override
  int get hashCode => secondsRemaining.hashCode;
}

class RematchStarting extends RematchState {
  const RematchStarting();

  @override
  String toString() => 'RematchStarting()';
}

class RematchDeclined extends RematchState {
  const RematchDeclined();

  @override
  String toString() => 'RematchDeclined()';
}

class RematchExpired extends RematchState {
  const RematchExpired();

  @override
  String toString() => 'RematchExpired()';
}

class RematchOpponentLeft extends RematchState {
  const RematchOpponentLeft();

  @override
  String toString() => 'RematchOpponentLeft()';
}

class RematchClosed extends RematchState {
  const RematchClosed();

  @override
  String toString() => 'RematchClosed()';
}

class RematchError extends RematchState {
  final RematchErrorCode code;
  final String? rawCode;

  const RematchError({required this.code, this.rawCode});

  @override
  String toString() => 'RematchError(code: $code, rawCode: $rawCode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RematchError &&
          other.code == code &&
          other.rawCode == rawCode;

  @override
  int get hashCode => Object.hash(code, rawCode);
}

class RematchMatched extends RematchState {
  final MatchedServerMessage matchedMessage;

  const RematchMatched(this.matchedMessage);

  @override
  String toString() =>
      'RematchMatched(matchId: ${matchedMessage.matchId}, opponentName: ${matchedMessage.opponentName})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RematchMatched &&
          other.matchedMessage.matchId == matchedMessage.matchId;

  @override
  int get hashCode => matchedMessage.matchId.hashCode;
}
