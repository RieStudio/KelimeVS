import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/match_request_messages.dart';
import '../data/user_inbox_client.dart';

/// Kullanıcı varlık durumu (presence).
enum UserPresenceState {
  idle,
  busy;

  String toWireString() => this == UserPresenceState.busy ? 'busy' : 'idle';
}

/// Referans sayaçlı varlık (presence) yöneticisi.
/// Ekranlar ve oturumlar `acquireBusy(reason)` / `releaseBusy(reason)` çağrıları ile
/// kullanıcının meşgul olduğunu bildirir.
class PresenceController extends Notifier<UserPresenceState> {
  final Set<String> _busyTokens = <String>{};
  UserPresenceState? _lastSentState;
  UserInboxClient? _client;
  bool _isDisposed = false;

  @override
  UserPresenceState build() {
    _busyTokens.clear();
    _lastSentState = null;
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });
    return UserPresenceState.idle;
  }

  void attachClient(UserInboxClient? client) {
    _client = client;
    // İstemci yeni bağlandığında veya değiştiğinde son durumu gönder
    _sendPresenceIfNeeded(force: true);
  }

  /// Aktif meşguliyet belirteçleri listesi (hata ayıklama ve testler için).
  Set<String> get activeTokens => Set.unmodifiable(_busyTokens);

  /// Kullanıcıyı belirtilen gerekçe ile meşgul (busy) olarak işaretler.
  void acquireBusy(String reason) {
    if (reason.trim().isEmpty) return;
    _busyTokens.add(reason);
    _updateState();
  }

  /// Belirtilen gerekçeyi kaldırır. Sayaç 0 olduğunda durum `idle` olur.
  void releaseBusy(String reason) {
    _busyTokens.remove(reason);
    _updateState();
  }

  /// Sayaç kaçağına karşı güvenlik ağı (Safety Net):
  /// Tüm meşguliyet belirteçlerini temizler ve durumu zorla `idle` yapar.
  void forceReset() {
    _busyTokens.clear();
    _updateState();
  }

  void _updateState() {
    if (_isDisposed) return;
    final newState =
        _busyTokens.isNotEmpty ? UserPresenceState.busy : UserPresenceState.idle;
    if (state != newState) {
      // Widget ağacı inşa edilirken (initState gibi) state değiştirilirse Riverpod assertion atar.
      // scheduleMicrotask ile microtask kuyruğuna erteleyerek güvenli ve temiz geçiş sağlıyoruz.
      scheduleMicrotask(() {
        if (_isDisposed) return;
        final currentTarget =
            _busyTokens.isNotEmpty ? UserPresenceState.busy : UserPresenceState.idle;
        if (state != currentTarget) {
          state = currentTarget;
          _sendPresenceIfNeeded();
        }
      });
    }
  }

  void _sendPresenceIfNeeded({bool force = false}) {
    final client = _client;
    if (client == null || !client.isConnected) return;

    if (!force && _lastSentState == state) {
      return; // Aynı durum mükerrer olarak tekrar gönderilmez
    }

    final sent = client.send(UserInboxPresenceMessage(state.toWireString()));
    if (sent) {
      _lastSentState = state;
    }
  }

  /// Yeniden bağlanma sonrası sokete mevcut durumu aktarmak için kullanılır.
  void onConnected() {
    _sendPresenceIfNeeded(force: true);
  }
}

final presenceControllerProvider =
    NotifierProvider<PresenceController, UserPresenceState>(
  PresenceController.new,
);
