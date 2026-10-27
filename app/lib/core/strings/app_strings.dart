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
  static const String playWithFriendComingSoon =
      'Arkadaşınla Oyna modu yakında eklenecek.';
  static const String comingSoon = 'Yakında';
  static const String recentMatches = 'SON MAÇLARIM';
  static const String noMatchesYet = 'Henüz maç oynamadın. İlk maçını oyna!';
  static const String noMatchesHistoryReset =
      'Maç geçmişi çıkış yapınca veya hesap değiştirince sıfırlanır. Yeni oynadığın maçlar burada görünecek.';
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
  static const String searchTipContent =
      'Türkçe karakter kullanmasan da olur, "turkiye" yazman yeterli.';

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
  static const String matchTestNotice =
      'Bu sayfa geçicidir, sonraki adımlarda gerçek ekranlarla değiştirilecek.';
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
  static const String leaveMatchConfirmMessage =
      'Maçı terk edersen maçı kaybedeceksin. Devam etmek istiyor musun?';
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
  static const String temporaryTodoNotice =
      'TODO: sonraki adımda gerçek ekranla değişecek';
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
  static String objectionPrompt(String text) =>
      '“$text” kabul edilmedi. Sence doğru muydu?';

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
  static const String connectionLostNotice =
      'Bağlantı koptu. Ana ekrana dönülüyor.';
  static const String connectionReconnecting =
      'Bağlantı koptu, yeniden bağlanılıyor…';
  static const String connectionRestored = 'Bağlandı';
  static const String matchReplacedNotice = 'Maçı başka bir cihazda açtın';
  static const String yourConnectionLost = 'Bağlantın koptu';
  static const String opponentConnectionLost = 'Rakibin bağlantısı koptu';
  static const String scoreBeforeDisconnectNote =
      'Skor, bağlantı kopmadan önceki duruma göredir.';

  // Global Ağ & Çevrimdışı Durumu (DESIGN.md 6b)
  static const String noInternetTitle = 'İnternet Bağlantısı Yok';
  static const String noInternetMessage =
      'KelimeVS oynamak için aktif bir internet bağlantısı gerekiyor. Lütfen bağlantını kontrol et.';
  static const String noInternetBanner =
      'İnternet bağlantısı kesildi. Yeniden bağlanılıyor…';
  static const String noInternetConnected = 'İnternet bağlantısı sağlandı';
  static const String retryConnection = 'Tekrar Dene';
  static const String noInternetActionError =
      'Bu işlem için internet bağlantısı gerekiyor.';

  // Profil ve Onboarding
  static const String welcomeTitle = 'Hoş Geldin!';
  static const String welcomePrompt = 'KelimeVS’de seni nasıl çağıralım?';
  static const String nicknameHint = 'Takma adın';
  static const String nicknameRuleHint =
      '3–16 karakter. Harf, rakam ve alt çizgi.';
  static const String continueAction = 'Devam';
  static const String profileTitle = 'Profil';
  static const String changeNickname = 'Adı Değiştir';
  static const String newNicknamePrompt = 'Yeni Takma Ad';
  static const String save = 'Kaydet';

  // Oyuncu İstatistikleri
  static const String statsTitle = 'İstatistikler';
  static const String statsPlayed = 'Oynanan Maç';
  static const String statsCorrectAnswers = 'Doğru Cevap';
  static const String statsWinRate = 'Kazanma';
  static const String statsNoData = '—';

  // Google Hesap Bağlama ve Çıkış
  static const String linkGoogle = 'Google ile Bağla';
  static const String linkedAccount = 'Bağlı Hesap';
  static const String signOut = 'Çıkış Yap';
  static const String linkConflictDialogTitle = 'Farklı Bir Hesap Bulundu';
  static const String linkConflictDialogMessage =
      'Bu Google hesabı daha önce başka bir hesaba bağlanmış. Bu hesaba geçersen şu anki anonim ilerlemen (takma ad, jeton, maç geçmişi) silinir. Devam edilsin mi?';
  static const String profileLoadErrorTitle = 'Profil yüklenemedi';
  static const String profileLoadErrorMessage =
      'Profil bilgilerin alınamadı. Lütfen internet bağlantını kontrol edip tekrar dene.';
  static const String signOutDialogTitle = 'Çıkış Yap';
  static const String signOutDialogMessage =
      'Hesabından çıkmak istediğinden emin misin?\nBulut yedeklemesi henüz bulunmadığı için çıkış yaptığında cihazındaki maç geçmişin ve takma adın silinecektir.';
  static const String networkError =
      'İnternet bağlantını kontrol edip tekrar dene.';
  static const String authGenericError =
      'İşlem gerçekleştirilemedi. Lütfen tekrar dene.';

  // Haftalık Liderlik Tablosu
  static const String leaderboardTitle = 'Haftalık Sıralama';
  static const String leaderboard = 'Sıralama';
  static const String emptyLeaderboard = 'Bu hafta henüz maç yok';
  static const String emptyLeaderboardSubtitle =
      'Hızlı Maç oynayarak haftanın ilk galibiyetini sen al!';
  static const String winsSuffix = ' galibiyet';
  static const String yourRankLabel = 'Senin Sıran';
  static String yourRank(int rank, int wins) =>
      'Senin sıran: #$rank ($wins$winsSuffix)';
  static const String notRankedYet = 'Sıralamada değilsin';
  static const String remainingTimePrefix = 'Kalan süre: ';
  static const String leaderboardLoading = 'Sıralama yükleniyor…';
  static const String leaderboardError = 'Sıralama yüklenemedi';
  static const String retry = 'Tekrar Dene';
  static const String daysUnit = 'g';
  static const String hoursUnit = 's';
  static const String minutesUnit = 'd';
  static const String timeExpired = 'Süre doldu';

  // Hesap Silme
  static const String deleteAccount = 'Hesabı Sil';
  static const String deleteAccountDialogTitle = 'Hesabı Sil';
  static const String deleteAccountDialogMessage =
      'Hesabını ve tüm verilerini kalıcı olarak silmek istediğinden emin misin?\nBu işlem geri alınamaz; takma adın, istatistiklerin, jetonların ve maç geçmişin tamamen silinecektir.';
  static const String deleteAccountConfirm = 'Evet, Hesabı Sil';
  static const String deleteAccountInProgress = 'Hesap siliniyor…';
  static const String deleteAccountSuccess = 'Hesabın başarıyla silindi.';
  static const String deleteAccountNetworkError =
      'Hesap silinirken bir bağlantı hatası oluştu. Lütfen internetini kontrol edip tekrar dene.';
  static const String accountDeletedNotice =
      'Hesabın silindiği için oturumun sonlandırıldı.';
  static const String accountDeleted = 'Hesap silinmiş';
  static const String deleteAccountGoogleReauthNote =
      'Güvenlik için Google hesabını bir kez daha seçmen istenecek.';
  static const String reauthWrongAccountError =
      'Lütfen uygulamaya bağlı Google hesabını seç.';

  // Oyuncu Bildirme ve Engelleme
  static const String reportAction = 'Bildir';
  static const String blockAction = 'Engelle';
  static const String reportedStatus = 'Bildirildi';
  static const String blockedStatus = 'Engellendi';
  static const String reportDialogTitle = 'Oyuncuyu Bildir';
  static const String reportReasonPrompt = 'Bildirme Sebebi Seç';
  static const String reasonInappropriateNickname = 'Uygunsuz takma ad';
  static const String reasonInappropriateContent = 'Hakaret / uygunsuz cevap';
  static const String reasonCheating = 'Hile veya kötüye kullanım';
  static const String reasonOther = 'Diğer';
  static const String reportSuccess = 'Bildirimin alındı. Teşekkür ederiz.';
  static const String reportAlreadyReported =
      'Bu maç için zaten bildirim yaptın.';
  static const String reportDailyLimit = 'Günlük bildirim sınırına ulaştın.';
  static const String reportMatchExpired =
      'Maç süresi dolduğu için bildirim yapılamadı.';
  static const String reportGenericError =
      'Bildirim gönderilemedi. Lütfen internetini kontrol et.';

  static const String blockDialogTitle = 'Oyuncuyu Engelle';
  static String blockDialogMessage(String nickname) =>
      ' adlı oyuncuyu engellemek istediğinden emin misin?\nBir daha bu oyuncuyla eşleştirilmeyeceksin.';
  static const String blockConfirm = 'Engelle';
  static String blockSuccess(String nickname) => ' engellendi.';
  static const String blockLimitReached =
      'En fazla 100 oyuncu engelleyebilirsin.';
  static const String blockMatchExpired =
      'Maç süresi dolduğu için engelleme yapılamadı.';
  static const String blockGenericError =
      'Engelleme işlemi gerçekleştirilemedi.';

  // Engellenen Oyuncular Ekranı (Profil)
  static const String blockedUsersTitle = 'Engellenenler';
  static const String blockedUsersTileTitle = 'Engellenen Oyuncular';
  static const String blockedUsersTileSubtitle =
      'Engellediğin oyuncularla eşleşmezsin';
  static const String emptyBlockedUsers = 'Henüz engellenen oyuncu yok';
  static const String emptyBlockedUsersSubtitle =
      'Maç sonu ekranından uygunsuz oyuncuları engelleyebilirsin.';
  static const String unblockAction = 'Kaldır';
  static const String unblockSuccess = 'Engel kaldırıldı.';
  static const String unblockGenericError =
      'Engel kaldırılırken bir hata oluştu.';
  static const String blockedUsersLoading = 'Engellenenler yükleniyor…';
  static const String blockedUsersError = 'Engellenenler yüklenemedi';

  // Arkadaşla Düello
  static const String friendDuel = 'Arkadaşla Düello';
  static const String friendDuelSubtitle =
      'Kendi odanı kur veya arkadaşının koduna katıl';
  static const String createRoom = 'Oda Kur';
  static const String createRoomSubtitle =
      'Bir davet kodu oluştur ve arkadaşına gönder';
  static const String joinRoom = 'Koda Katıl';
  static const String joinRoomSubtitle =
      'Arkadaşının paylaştığı 6 haneli kodu gir';
  static const String yourInviteCode = 'DAVET KODUN';
  static const String copyCode = 'Kodu Kopyala';
  static const String codeCopied = 'Davet kodu panoya kopyalandı!';
  static const String shareCode = 'Kodu Paylaş';
  static const String waitingForOpponent = 'Arkadaşının katılması bekleniyor…';
  static const String codeValidity = 'Kalan süre:';
  static const String cancelRoom = 'Odayı Kapat';
  static const String roomExpiredTitle = 'Süre Doldu';
  static const String roomExpiredMessage =
      'Odanın 5 dakikalık süresi doldu. Dilersen yeni bir oda kurabilirsin.';
  static const String enterInviteCode = 'Davet Kodunu Gir';
  static const String enterInviteCodeDescription =
      'Arkadaşının seninle paylaştığı 6 haneli davet kodunu gir:';
  static const String joinMatch = 'Maça Katıl';
  static const String joiningRoom = 'Odaya bağlanılıyor…';
  static const String creatingRoom = 'Oda kuruluyor…';
  static const String roomNotFound = 'Bu oda bulunamadı veya süresi dolmuş.';
  static const String roomFull = 'Bu odaya zaten başka bir oyuncu katılmış.';
  static const String cannotJoinOwnRoom =
      'Kendi oluşturduğun odaya katılamazsın.';
  static const String friendRoomUnavailable = 'Bu odaya şu anda katılınamıyor.';
  static const String friendRoomRateLimited =
      'Çok fazla hatalı deneme yaptın. Lütfen biraz bekleyip tekrar dene.';
  static const String friendRoomLobbyBusy =
      'Lobi şu anda yoğun. Lütfen birkaç dakika sonra tekrar dene.';
  static const String friendDuelBadge = 'Dostluk';
  static const String friendDuelMatchBadge =
      'Dostluk Düellosu • Jeton verilmez';

  // Güçlendiriciler (Power-ups)
  static const String extraTimePowerup = '+5 sn';
  static const String extraTimeUsed = 'Kullanıldı';
  static const String extraTimeAdded = '+5 sn eklendi!';
  static const String opponentUsedExtraTime = 'Rakip +5 sn ek süre kullandı';
  static String opponentUsedExtraTimeSec(int seconds) =>
      'Rakip +$seconds sn ek süre kullandı';
  static String notEnoughCoinsForExtraTime(int cost) =>
      'Yetersiz jeton ($cost gerekli)';
  static const String extraTimeAlreadyUsed =
      'Bu maçta ek süre hakkını zaten kullandın.';
  static const String notYourTurnPowerup =
      'Ek süre sadece kendi cevabında kullanılabilir.';
  static const String powerupGenericError =
      'Güçlendirici şu anda kullanılamıyor.';
  static const String powerupTemporaryError =
      'Şu anda kullanılamıyor, tekrar dene.';

  // İleride Play Store linki açıldığında buraya URL yazılacak:
  static const String storeShareUrl = '';

  static String friendDuelShareText(String code) {
    if (storeShareUrl.isEmpty) {
      return 'KelimeVS\'de benimle kelime düellosuna var mısın? Davet kodum: $code\nKelimeVS uygulamasını aç, "Koda Katıl" seçeneğiyle hemen maça başla!';
    }
    return 'KelimeVS\'de benimle kelime düellosuna var mısın? Davet kodum: $code\nOyunu indir ve hemen başla: $storeShareUrl';
  }

  // Mağaza & Avatar Çerçeveleri
  static const String storeTitle = 'Mağaza';
  static const String avatarFramesSection = 'AVATAR ÇERÇEVELERİ';
  static const String equipAction = 'Kuşan';
  static const String equippedStatus = 'Kuşanıldı';
  static const String buyAction = 'Satın Al';
  static const String cancelAction = 'Vazgeç';
  static const String insufficientCoins = 'Yetersiz jeton';
  static const String framePurchasedSuccess = 'Çerçeve satın alındı';
  static const String frameEquippedSuccess = 'Çerçeve kuşandı';
  static const String alreadyOwnedError = 'Bu çerçeveye zaten sahipsin.';
  static const String itemNotOwnedError = 'Bu çerçeveye henüz sahip değilsin.';
  static const String storeInvalidFrameError = 'Geçersiz çerçeve seçildi.';
  static const String storeServerError =
      'Sunucu hatası oluştu, lütfen daha sonra tekrar dene.';
  static const String storeNetworkError =
      'Bağlantı hatası. Lütfen internetini kontrol et.';
  static const String storeGenericError =
      'İşlem gerçekleştirilemedi, lütfen tekrar dene.';

  // Çerçeve adları
  static const String frameClassic = 'Klasik';
  static const String frameMint = 'Nane';
  static const String frameSunset = 'Gün Batımı';
  static const String frameOcean = 'Okyanus';
  static const String frameGold = 'Altın';
  static const String frameNeon = 'Neon';
  static const String frameRainbow = 'Gökkuşağı';
  static const String frameDiamond = 'Elmas';

  static String frameDisplayName(String frameId) {
    switch (frameId.toLowerCase()) {
      case 'mint':
        return frameMint;
      case 'sunset':
        return frameSunset;
      case 'ocean':
        return frameOcean;
      case 'gold':
        return frameGold;
      case 'neon':
        return frameNeon;
      case 'rainbow':
        return frameRainbow;
      case 'diamond':
        return frameDiamond;
      case 'classic':
      default:
        return frameClassic;
    }
  }

  static String avatarSemantics({String? name, String? frameId}) {
    final frameName = frameDisplayName(frameId ?? 'classic');
    if (name != null && name.trim().isNotEmpty) {
      return '$name, $frameName çerçeveli avatar';
    }
    return '$frameName çerçeveli avatar';
  }

  // Mağaza Sekmeleri & Enerji Sistemi (DESIGN.md 9a & 9b)
  static const String tabCoins = 'Jeton';
  static const String tabEnergy = 'Enerji';
  static const String tabFrames = 'Çerçeve';

  static const String coinsTabTitle = 'Jeton paketleri çok yakında';
  static const String coinsTabDescription =
      'Gerçek parayla jeton satın alma ve özel teklifler yakında burada olacak!';

  static const String energyTitle = 'Enerji';
  static const String energyFull = 'Tüm enerjin doldu';
  static const String energyFullButton = 'Enerjin dolu';
  static const String nextEnergyPrefix = 'Sonraki enerji: ';
  static const String energyRegenInfo = 'Her 20 dakikada 1 enerji yenilenir.';
  static const String energyPackOneTitle = '+1 Enerji';
  static const String energyPackOneDesc = 'Hemen 1 enerji doldur';
  static const String energyPackFullTitle = 'Tam Doldur';
  static const String energyPackFullDesc = 'Tüm enerjini anında 5/5 yap';
  static const String energyPackPurchased =
      'Enerji paketi başarıyla satın alındı!';
  static const String energyAlreadyFull = 'Enerjiniz zaten dolu';
  static const String energyDisabled = 'Enerji sistemi şu anda aktif değil';

  static const String energyDepletedTitle = 'Enerjin bitti';
  static const String energyDepletedSubtitle =
      'Sıralı online maç oynamak için en az 1 enerjiye ihtiyacın var.';
  static const String playWithBotEnergyFree = 'Botla Oyna';
}
