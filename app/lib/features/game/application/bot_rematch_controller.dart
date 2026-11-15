import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'match_end_rematch_state.dart';

/// Bot maçlarında tamamen istemci tarafında rövanş akışını simüle eden durum denetleyicisi.
///
/// Sunucuya hiçbir ağ isteği göndermez.
/// - Maç normal bittiyse başlangıç durumu [MatchEndRematchIdle]'dır; aksi halde [MatchEndRematchUnavailable].
/// - [offerRematch] çağrıldığında 45 sn yerel sayaçla [MatchEndRematchPendingSent] başlar.
/// - ~%85 olasılıkla 5–10 sn arası rastgele bir beklemeden sonra [MatchEndRematchDeclined] üretir.
/// - ~%15 olasılıkla bot sessiz kalır ve 45 sn süre dolunca [MatchEndRematchExpired] durumuna geçer.
class BotRematchController extends ChangeNotifier {
  final math.Random _random;
  MatchEndRematchState _state;
  Timer? _countdownTimer;
  Timer? _botDecisionTimer;
  int _secondsRemaining = 45;

  BotRematchController({
    bool isNormalEnd = true,
    math.Random? random,
  })  : _random = random ?? math.Random(),
        _state = isNormalEnd
            ? const MatchEndRematchIdle()
            : const MatchEndRematchUnavailable();

  MatchEndRematchState get state => _state;
  int get secondsRemaining => _secondsRemaining;

  bool get isTerminal =>
      _state is MatchEndRematchDeclined ||
      _state is MatchEndRematchExpired ||
      _state is MatchEndRematchUnavailable;

  /// Oyuncu tarafından "Rövanş" teklifi gönderilmesi.
  bool offerRematch() {
    if (_state is! MatchEndRematchIdle) return false;

    _secondsRemaining = 45;
    _state = MatchEndRematchPendingSent(secondsRemaining: _secondsRemaining);
    notifyListeners();

    // 45 saniyelik yerel sayaç
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        _secondsRemaining--;
        _state = MatchEndRematchPendingSent(secondsRemaining: _secondsRemaining);
        notifyListeners();
      } else {
        _secondsRemaining = 0;
        _cancelTimers();
        if (!isTerminal) {
          _state = const MatchEndRematchExpired();
          notifyListeners();
        }
      }
    });

    // Bot tepki simülasyonu (~%85 ret, ~%15 sessiz süre aşımı)
    final willDecline = _random.nextDouble() < 0.85;
    if (willDecline) {
      // 5 ila 10 saniye arası rastgele bekleme (5 + [0..5])
      final delaySeconds = 5 + _random.nextInt(6);
      _botDecisionTimer = Timer(Duration(seconds: delaySeconds), () {
        _cancelTimers();
        _state = const MatchEndRematchDeclined();
        notifyListeners();
      });
    }

    return true;
  }

  /// Bot maçında oyuncu tekliften vazgeçerse veya iptal ederse.
  void cancelRematch() {
    _cancelTimers();
    if (!isTerminal) {
      _state = const MatchEndRematchUnavailable();
      notifyListeners();
    }
  }

  /// Geriye dönük uyumluluk / olası reddetme işlemi için.
  void declineRematch() {
    cancelRematch();
  }

  void _cancelTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _botDecisionTimer?.cancel();
    _botDecisionTimer = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }
}
