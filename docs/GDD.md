# Kelime Go – Oyun Tasarım Dokümanı (GDD)

> Taslak 0.1 (Faz 0) · Tarih: 4 Ekim 2026
> Bu dosya projenin tek doğruluk kaynağıdır. Antigravity ve diğer araçlar kodlamadan önce bunu okumalıdır.
> İşaretler: **[KARAR]** kesinleşmiş · **[VARSAYIM]** onay bekliyor · **[AÇIK]** henüz karar yok

---

## 1. Özet

Kelime Go, iki oyuncunun gerçek zamanlı eşleşip sırayla cevap verdiği bir kelime düello oyunudur. Ekranda bir kategori sorusu çıkar (örn. "B ile başlayan hayvanlar"). Oyuncular sırayla cevap yazar. Süresi içinde doğru ve daha önce söylenmemiş bir cevap veremeyen turu kaybeder.

Oyun konsepti mevcut benzer oyunlarla aynı türdendir. Arayüz, isim, ikon, karakter ve soru metinleri tamamen özgün olacaktır.

## 2. Teknoloji kararları

| Konu | Karar |
|---|---|
| İstemci | **[KARAR]** Flutter (Dart). Önce Android; iOS yaklaşık 3–4 ay sonra, bulut derlemesiyle |
| Backend | **[KARAR]** Firebase (yeni proje) |
| Canlı maç durumu | **[KARAR]** Realtime Database |
| Profil, jeton, envanter, görev, liderlik | **[KARAR]** Firestore |
| Sunucu mantığı | **[KARAR]** Cloud Functions (TypeScript) |
| İçerik (sorular) | **[KARAR]** Realtime Database, mevcut CMS paneli ile yönetilir |
| IDE | **[KARAR]** VS Code + Antigravity (eklenti) |
| iOS derleme | **[KARAR]** Bulut CI (Codemagic veya GitHub Actions macOS). Mac yok. Başlangıç: Android yayını sonrası |

## 3. Maç kuralları

1. **[KARAR]** Bir maç 3 turdur. Her turda bir soru (kategori) oynanır.
2. **[KARAR]** Oyuncular sırayla cevap yazar. Her cevap için süre **15 saniyedir**.
3. **[KARAR]** Süresi içinde cevap yazamayan, yanlış cevap veren ya da daha önce söylenmiş bir cevabı tekrar eden oyuncu o turu kaybeder. Rakip o turun puanını alır.
4. **[KARAR]** Bir turda sorunun tüm cevapları tükenirse o tur berabere sayılır, kimseye puan yazılmaz ve maç bir tur uzar. (Çok nadir bir durum, kuralın tutarlılığı için tanımlı.)
5. **[KARAR]** 3 turun sonunda skoru fazla olan maçı kazanır.
6. **[VARSAYIM]** Aynı cevap bir turda iki kez söylenemez.
7. **[VARSAYIM]** 3 tur sonunda skor eşitse (beraberlik turları nedeniyle) bir ek tur oynanır; kazanan maçı alır.
8. **[VARSAYIM]** Her turda başlayan oyuncu sırayla değişir (1. tur oyuncu A, 2. tur oyuncu B…).
9. **[VARSAYIM]** Her turun sorusu rastgele seçilir, aynı maçta aynı soru tekrar gelmez, iki oyuncu aynı soruyu görür.

### 3.1 Süre ve gecikme

- **[KARAR]** Süre ölçümü **sunucuda** yapılır. Telefondaki sayaç sadece göstergedir.
- **[VARSAYIM]** Ağ gecikmesi için 1–2 saniyelik sunucu toleransı tanınır. Değer Remote Config'ten ayarlanabilir olmalıdır.
- Her hamlede sunucu `turnDeadline` (sunucu saati) yazar. Süre dolduysa tur kaybedilmiş sayılır.

### 3.2 Bağlantı kopması

- **[AÇIK]** Oyuncu internetten çıkarsa kuralı: sırası geldiğinde süre normal işler ve turu kaybeder mi, yoksa bağlantı koptuğu anda mı kaybeder? Öneri: süre işlemeye devam eder; belli bir süre (örn. 30 sn) geri dönmezse maç kaybedilir.
- Realtime Database `onDisconnect` ile çevrimdışı durumu algılanır.

## 4. Cevap doğrulama

Doğrulama **yalnızca Cloud Functions içinde** yapılır. İstemci cevap listesini hiçbir zaman indirmez.

### 4.1 Normalizasyon (hem oyuncu girdisi hem kayıtlı cevaplar için)

1. Baştaki ve sondaki boşlukları sil, ardışık boşlukları tek boşluğa indir.
2. Türkçe kurallarıyla küçük harfe çevir (`tr-TR`): `ISPANAK` → `ıspanak`, `İSTANBUL` → `istanbul`. Büyük/küçük harf kombinasyonu fark etmez.
3. Aksan katlaması: `ç→c`, `ğ→g`, `ı→i`, `ö→o`, `ş→s`, `ü→u`. Böylece `turkiye` yazan oyuncu `türkiye` cevabını bulur.
4. Karşılaştırma katlanmış (3. adım) hâller üzerinden yapılır. Kayıtlı alias'ların katlanmış hâli önceden hesaplanıp önbelleğe alınır.

### 4.2 Eşleştirme

- Normalleştirilmiş girdi, sorunun herhangi bir cevabının alias'larından birine eşitse cevap doğrudur ve o cevabın dahili kimliği (`answerId`) kaydedilir.
- Aynı `answerId` o turda daha önce söylendiyse cevap tekrar sayılır (tur kaybedilir).
- **[KARAR]** Alias'lar (örn. "kore" → "güney kore") aynı cevabın varyantıdır, ayrı cevap sayılmaz.

### 4.3 İtiraz

- **[VARSAYIM]** Maç sonunda oyuncu "bu cevap doğruydu" diyebilir. Yoğun itiraz alan girdiler incelenmek üzere kuyruğa düşer ve CMS'ten alias olarak eklenebilir.

## 5. Veri modeli

### 5.1 İçerik (Realtime Database)

**[KARAR]** İçerik kaynağı CMS panelinin mevcut biçimidir; panelde değişiklik yapılmaz. Panelden yalnızca soru, cevap ve kategori eklenir/silinir, dışa aktarma ve içe aktarma yapılır.

```json
questions_pool: {
  "genel_kultur": {
    "q_1783868784870": {
      "question": "G20 ülkeleri",
      "acceptable_answers": {
        "güney kore": ["güney kore", "kore"],
        "suudi arabistan": ["suudi arabistan", "arabistan"]
      }
    }
  }
}
```

- Anahtar ana cevaptır; dizideki değerler o cevabın kabul edilen varyantlarıdır (alias).
- Dönüşüm **sunucuda** yapılır: Cloud Functions bu yapıyı okuyup normalleştirilmiş dahili bir dizin üretir (bölüm 4.1) ve önbelleğe alır. Her cevaba kararlı bir dahili kimlik atanır. Böylece panelin biçimi değişmeden doğrulama yapılabilir.
- Soru metnindeki fazla boşluklar da sunucu tarafında temizlenir.
- Kategori kimlikleri şimdilik mevcut haliyle kalır (`film_diz`, `bilim_teknoloji` gibi). Etiketler panelde tutulur.
- **[AÇIK]** Realtime Database anahtarlarında `. $ # [ ] /` karakterleri yasaktır. Ana cevap anahtar olduğundan bu karakterleri içeren bir cevap (örn. "dr. pepper") panelde hata verebilir. Şimdilik bu karakterlerden kaçınılır; ileride gerekirse panel kodu Antigravity ile güncellenir.
- Sunucu, içerik yüklenirken **uyarı raporu** üretir: bir cevabın varyantı başka bir cevapla çakışıyorsa ya da bir ana cevap diğerinin parçasıysa (örn. "kore" ve "güney kore") bu, içerik yöneticisine (sana) listelenir. Düzeltme gerekiyorsa soru panelden silinip doğru yapıyla yeniden eklenir ya da dışa aktarılan JSON düzenlenip içe aktarılır.

### 5.2 Canlı maç (Realtime Database)

```json
matches/{matchId}: {
  "status": "waiting | active | finished",
  "players": { "uidA": {...}, "uidB": {...} },
  "round": 1,
  "scores": { "uidA": 0, "uidB": 0 },
  "questionId": "...",
  "turnUid": "uidA",
  "turnDeadline": 1790000000000,
  "usedAnswerIds": ["a01"],
  "history": [ ... ]
}
```

- İstemciler `matches` altını **okuyabilir**, ama **doğrudan yazamaz**. Tüm hamleler `submitAnswer` adlı çağrılabilir Cloud Function üzerinden geçer.

### 5.3 Kullanıcı verisi (Firestore)

`users/{uid}`: ad, avatar, jeton, istatistikler, ayarlar. `inventory`, `quests`, `leaderboards` ayrı koleksiyonlardır. Jeton değişiklikleri yalnızca sunucudan yapılır.

## 6. Eşleştirme ve bot

- Oyuncu "Hızlı Maç" seçince eşleştirme havuzuna girer; sunucu iki oyuncuyu eşler.
- **[VARSAYIM]** Belirli bir süre (örn. 8–10 sn) eşleşme bulunamazsa bot rakip devreye girer. Başlangıçta oyuncu sayısı az olacağından bu kritiktir.
- Bot, sorunun cevap listesinden rastgele gecikmeyle (örn. 3–12 sn) ve ayarlanabilir hata olasılığıyla cevap verir.
- **[AÇIK]** Botla oynanan maçlarda kazanılan ödül normal maçtan düşük olsun mu? Bot rakip oyuncuya belirtilsin mi?

## 7. Modlar

- Hızlı maç (rastgele rakip + bot yedeği)
- Tek kişilik antrenman (bota karşı)
- Arkadaşla düello (davet kodu/bağlantı)
- Günlük meydan okuma
- Turnuva / sezon

Sürümleme ve hangi modun ne zaman çıkacağı proje sahibi tarafından belirlenir; bu dokümanda tutulmaz.

## 8. Ekonomi (taslak)

- **[AÇIK]** Jeton kazanma/harcama kuralları henüz belirlenmedi. Öneriler:
  - Maç kazanma ve günlük görevlerle jeton kazanılır, ödüllü reklamla ek jeton alınır.
  - Güçlendiriciler (ek süre, pas, harf ipucu) jetonla alınır.
  - Pay-to-win'den kaçınılır; ücretli içerik kozmetik ağırlıklı olur.
- Tüm sayısal değerler (ödül, fiyat, süre toleransı) **Remote Config**'te tutulur, kodda sabitlenmez.

## 9. Güvenlik ilkeleri

- Cevap listesi (`questions_pool`) istemci tarafından **okunamaz**; yalnızca Cloud Functions okur.
- Oyun durumu ve jeton yazma yetkisi yalnızca sunucudadır.
- Hesap silme özelliği, raporlama/engelleme mekanizması ve gizlilik politikası (KVKK/GDPR) yayın için zorunludur.
- iOS'ta başka sosyal giriş sunulursa Sign in with Apple zorunludur.
- Servis hesabı anahtarları ve gizli bilgiler asla repoya konmaz.

## 10. Platform ve yayın riskleri

| Risk | Önlem |
|---|---|
| Mac yok, iOS Windows'ta derlenemez | Bulut CI (Codemagic / GitHub Actions macOS) |
| iPhone yok | **[KARAR]** iOS aşaması ertelendi (~3–4 ay). iOS aşamasından önce bir iPhone'a erişim sağlanmalı (ödünç, ikinci el ya da TestFlight ile test edecek tanıdıklar) |
| iOS'a geç başlamanın riski: sürprizler geç görülür | Android geliştirmesi sırasında iOS ile uyumlu paketler seçilir (Android'e özel paket kullanılmaz). Hesap gerektirmeyen imzasız derleme kontrolü bulut CI'da arada çalıştırılabilir. Apple Developer hesabı iOS aşamasının başında açılır |
| Google Play yeni hesaplarda kapalı test şartı olabilir | Kuralları şimdiden kontrol et, planı buna göre kur |
| Cloud Functions ödeme planı gerektirebilir | Güncel Firebase fiyat/kota şartlarını kontrol et |
| İçerik yetersizliği (150 soru ile başlangıç) | Yayın öncesi 30–50 sağlam kategori, sonra CMS ile büyüt |

## 11. Çalışma kuralları (Antigravity ile)

1. **Faz 1 bitmeden oyun kodu yazılmaz.** `DESIGN.md` hazır olmalı.
2. Bir seferde tek ekran/özellik yaptırılır.
3. Her adım Git commit ile kaydedilir.
4. Oyun kuralı, veri modeli ve güvenlik kuralları bu dosyadan çıkarılır; bu dosyayla çelişen kod yazılmaz.
5. Süre, sıra ve cevap doğrulaması asla istemcide yapılmaz.

## 12. Açık sorular listesi

1. Bağlantı kopma kuralı (bölüm 3.2)
2. Botla oynanan maçlarda ödül ve bot bildirimi (bölüm 6)
3. Jeton ekonomisi sayıları (bölüm 8)
4. iOS aşaması için iPhone erişiminin nasıl sağlanacağı (bölüm 10)
5. Varsayımların onayı (bölüm 3, madde 6–9; bölüm 4.3; bölüm 6)
6. Cevap anahtarlarında özel karakter (`. $ # [ ] /`) sorunu (bölüm 5.1)

## 13. iOS aşaması (ertelendi)

**[KARAR]** Android ilk yayındır. iOS yaklaşık 3–4 ay sonra ele alınır. O güne kadar:

- Kodda Android'e özel çözümlerden kaçınılır; her yeni paket için iOS desteği kontrol edilir.
- Firebase projesine iOS uygulaması ve gerekli yapılandırma iOS aşamasında eklenir.
- Bildirimler (FCM), reklam (AdMob ve izleme izni isteği) ve uygulama içi satın alma iOS aşamasında ayrıca kurulur ve test edilir.
- Başka bir sosyal giriş sunulursa iOS'ta Sign in with Apple eklenmelidir; giriş yöntemleri buna göre planlanır.
- iOS aşaması başlarken: Apple Developer hesabı açılır, bulut CI kurulur, bir iPhone'da TestFlight ile test yapılır.
