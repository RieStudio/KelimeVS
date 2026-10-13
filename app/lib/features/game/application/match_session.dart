import 'match_ui_state.dart';

/// Aktif maç oturumu modu (yerel bot veya çevrimiçi sunucu).
enum MatchSessionMode {
  bot,
  online,
}

/// Maç ekranlarının (MatchScreen, RoundEndView, MatchEndView) bağımlı olduğu
/// ortak maç oturumu arayüzü.
abstract interface class MatchSession {
  /// Güncel maç arayüz durumu.
  MatchUiState get state;

  /// Kullanıcının cevap denemesini gönderir.
  void submit(String text);

  /// Kullanıcının maçı terk etmesini sağlar.
  void leaveMatch();

  /// Oturum kaynaklarını ve zamanlayıcıları temizler.
  void dispose();
}

