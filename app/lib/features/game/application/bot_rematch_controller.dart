import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../online/domain/models/rematch_state.dart';

/// Bot maçlarında tamamen istemci tarafında rövanş akışını simüle eden durum denetleyicisi.
///
/// Sunucuya hiçbir ağ isteği göndermez.
/// - Maç normal bittiyse başlangıç durumu [RematchState.idle]'dır; aksi halde [RematchState.unavailable].
/// - [offerRematch] çağrıldığında 45 sn yerel sayaçla [RematchState.pendingSent] başlar.
/// - ~%85 olasılıkla 5–10 sn arası rastgele bir beklemeden sonra [RematchState.declined] üretir.
/// - ~%15 olasılıkla bot sessiz kalır ve 45 sn süre dolunca [RematchState.expired] durumuna geçer.
class BotRematchController extends ChangeNotifier {
  final math.Random _random;
  RematchState _state;
  Timer? _countdownTimer;
  Timer? _botDecisionTimer;
  int _secondsRemaining = 45;

  BotRematchController({
    bool isNormalEnd = true,
    math.Random? random,
  })  : _random = random ?? math.Random(),
        _state = isNormalEnd ? RematchState.idle : RematchState.unavailable;

  RematchState get state => _state;
  int get secondsRemaining => _secondsRemaining;

  /// Oyuncu tarafından "Rövanş" teklifi gönderilmesi.
  bool offerRematch() {
    if (_state is! RematchIdle) return false;

    _secondsRemaining = 45;
    _state = RematchState.pendingSent(secondsRemaining: _secondsRemaining);
    notifyListeners();

    // 45 saniyelik yerel sayaç
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        _secondsRemaining--;
        _state = RematchState.pendingSent(secondsRemaining: _secondsRemaining);
        notifyListeners();
      } else {
        _secondsRemaining = 0;
        _cancelTimers();
        if (!_state.isTerminal) {
          _state = RematchState.expired;
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
        _state = RematchState.declined;
        notifyListeners();
      });
    }

    return true;
  }

  /// Bot maçında oyuncu tekliften vazgeçerse veya olası reddetme işlemi için.
  void declineRematch() {
    _cancelTimers();
    if (!_state.isTerminal) {
      _state = RematchState.declined;
      notifyListeners();
    }
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
