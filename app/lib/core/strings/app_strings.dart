abstract final class AppStrings {
  // Alt Gezinme Sekmeleri
  static const String navHome = 'Ana Sayfa';
  static const String navLeaderboard = 'Sıralama';
  static const String navShop = 'Mağaza';
  static const String navProfile = 'Profil';

  // Ana Ekran
  static const String quickMatch = 'Hızlı Maç';
  static const String quickMatchSubtitle = 'Rastgele bir rakiple eşleş';
  static const String playWithFriend = 'Arkadaşınla Oyna';
  static const String playWithFriendComingSoon = 'Arkadaşınla Oyna modu yakında eklenecek.';
  static const String comingSoon = 'Yakında';
  static const String recentMatches = 'SON MAÇLARIM';
  static const String noMatchesYet = 'Henüz maç oynamadın. İlk maçını oyna!';
  static const String slogan = 'Hızlı düşün, doğru yaz!';
  static const String defaultPlayerName = 'Oyuncu';
  static const String settings = 'Ayarlar';
  static const String ok = 'Tamam';

  // Sonuç ve Durumlar
  static const String won = 'Kazandın';
  static const String lost = 'Kaybettin';
  static const String wonExclamation = 'Kazandın!';
  static const String lostExclamation = 'Kaybettin!';
  static const String roundWonTitle = 'Turu kazandın!';
  static const String roundLostTitle = 'Turu kaybettin';
  static const String roundDrawTitle = 'Tur berabere';
  static const String roundWonExclamation = 'Turu kazandın!';
  static const String roundLostExclamation = 'Turu kaybettin!';
  static const String timeUp = 'Rakibin süresi doldu';
  static const String reasonOpponentTimeout = 'Rakibin süresi doldu';
  static const String reasonMyTimeout = 'Süren doldu';
  static const String reasonExhausted = 'Tüm cevaplar söylendi';
  static const String nextRoundStartingSoonSuffix = ' birazdan başlıyor';
  static const String newRoundStartingSoon = 'Yeni tur birazdan başlıyor';
  static const String matchResultStartingSoon = 'Maç sonucu birazdan';
  static const String opponentLeftMatch = 'Rakip maçtan ayrıldı';
  static const String youLeftMatch = 'Maçı terk ettin';
  static const String coinSuffix = ' jeton';
  static const String scoreDash = ' – ';

  // Butonlar ve Eylemler
  static const String playAgain = 'Tekrar Oyna';
  static const String matchDetail = 'Maç Detayı';
  static const String cancel = 'Vazgeç';
  static const String appeal = 'İtiraz et';

  // Eşleşme
  static const String searchingOpponent = 'Rakip aranıyor…';
  static const String startingSoon = 'Birazdan başlıyoruz';
  static const String vs = 'VS';
  static const String searchTipTitle = 'İPUCU';
  static const String searchTipContent = 'Türkçe karakter kullanmasan da olur, "turkiye" yazman yeterli.';

  // Maç İçi
  static const String you = 'Sen';
  static const String opponent = 'Rakip';
  static const String inputPlaceholder = 'Cevabını yaz…';
  static const String questionMark = '?';

  // Geliştirme / Galeri / Debug / Soru Testi
  static const String componentGallery = 'Bileşen Galerisi';
  static const String firebaseUidPrefix = 'Firebase UID: ';
  static const String authErrorPrefix = 'Bağlantı hatası: ';
  static const String authSigningIn = 'Giriş yapılıyor…';
  static const String authNoUser = 'Giriş yapılmadı';
  static const String questionTest = 'Soru Testi';
  static const String questionTestTitle = 'Soru Test Sayfası';
  static const String newQuestion = 'Yeni Soru';
  static const String resultCorrect = 'Doğru!';
  static const String resultRepeated = 'Daha önce söylendi!';
  static const String resultWrong = 'Yanlış cevap!';
  static const String resultEmpty = 'Lütfen bir cevap yazın.';
  static const String resultExhausted = 'Tüm cevaplar bitti!';
  static const String remainingAnswersPrefix = 'Kalan cevap sayısı: ';
  static const String givenAnswers = 'Söylenen Cevaplar';
  static const String loadingQuestions = 'Sorular yükleniyor…';
  static const String noQuestionsFound = 'Soru bulunamadı.';
  static const String categoryPrefix = 'Kategori: ';
  static const String send = 'Gönder';

  // Maç Test Sayfası (Geçici)
  static const String matchTest = 'Maç Testi';
  static const String matchTestTitle = 'Maç Test Sayfası';
  static const String matchTestNotice = 'Bu sayfa geçicidir, sonraki adımlarda gerçek ekranlarla değiştirilecek.';
  static const String roundPrefix = 'Tur ';
  static const String roundTemplate = 'Tur {n}';
  static String round(int n) => roundTemplate.replaceAll('{n}', '$n');
  static const String timeLeftPrefix = 'Kalan Süre: ';
  static const String secondsSuffix = ' sn';
  static const String turnPrefix = 'Sıra: ';
  static const String turnMy = 'Sende';
  static const String turnOpponent = 'Rakipte';
  static const String newMatch = 'Yeni Maç';
  static const String matchFinishedTitle = 'Maç Bitti!';
  static const String winnerPrefix = 'Kazanan: ';
  static const String eventLogTitle = 'Olay Günlüğü';
  static const String scorePrefix = 'Skor: ';
  static const String nearMissExclamation = 'Çok yakın!';
  static const String leaveMatch = 'Maçtan Çık';
  static const String leaveMatchConfirmTitle = 'Maçtan çıkmak istiyor musun?';
  static const String leaveMatchConfirmMessage = 'Maçı terk edersen maçı kaybedeceksin. Devam etmek istiyor musun?';
  static const String leaveMatchConfirm = 'Çık ve Terk Et';
  static const String eventWrongAnswer = 'Yanlış cevap';
  static const String eventAlreadySaid = 'Daha önce söylendi';
  static const String eventForfeit = 'Maçı terk etti';
  static const String eventTimeout = 'Süre doldu';
  static const String eventExhausted = 'Cevaplar tükendi';

  // Maç Ekranı
  static const String matchScreen = 'Maç Ekranı';
  static const String leaveMatchPrompt = 'Maçtan çıkarsan maçı kaybedersin.';
  static const String exit = 'Çık';
  static const String turnOpponentHint = 'Sıra rakipte';
  static const String wrongAnswer = 'Yanlış cevap';
  static const String alreadySaid = 'Bu cevap söylendi';
  static const String nearMiss = 'Çok yakın!';
  static const String timeLeftLabel = 'Kalan süre';
  static const String roundEndedTitle = 'Tur bitti';
  static const String temporaryTodoNotice = 'TODO: sonraki adımda gerçek ekranla değişecek';
  static const String close = 'Kapat';

  // Maç Detayı ve İtiraz
  static const String back = 'Geri';
  static const String draw = 'Berabere';
  static const String incomplete = 'Yarım kaldı';
  static const String noAttemptsInRound = 'Bu turda deneme yok';
  static const String defaultQuestionText = 'Soru';
  static const String objectionSent = 'İtiraz gönderildi';
  static const String alreadySaidNotice = 'Bu cevap daha önce söylenmişti';
  static const String roundUpperPrefix = 'TUR ';
  static const String roundLabelWon = 'KAZANDIN';
  static const String roundLabelLost = 'KAYBETTİN';
  static const String roundLabelDraw = 'BERABERE';
  static const String roundLabelIncomplete = 'YARIM KALDI';
  static const String dotSeparator = ' · ';
  static String objectionPrompt(String text) => '“$text” kabul edilmedi. Sence doğru muydu?';

  // Sunucu Bağlantı Testi (Debug)
  static const String serverTestButton = 'Sunucu Testi';
  static const String serverTestRunning = 'Sunucu test ediliyor…';
  static const String serverTestTitle = 'Sunucu Bağlantı Testi';
  static const String serverTestSuccessSummary = 'Tüm testler başarılı!';
  static const String serverTestFailedSummary = 'Bağlantı testi başarısız oldu';

  // Ağ Tanılama (Debug)
  static const String networkDiagnosticsButton = 'Ağ Tanılama';
  static const String networkDiagnosticsRunning = 'Ağ test ediliyor…';
  static const String networkDiagnosticsTitle = 'Ağ Tanılama Sonuçları';

  // Online Protokol Testi (Debug)
  static const String onlineTestButton = 'Online test';

  // Çevrimiçi Maç Bağlantı Durumu
  static const String connectionLostNotice = 'Bağlantı koptu. Ana ekrana dönülüyor.';
}

