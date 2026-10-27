# Kelimeta – Oyun Tasarım Dokümanı (GDD)

> Taslak 0.1 (Faz 0) · Tarih: 4 Ekim 2026
> Bu dosya projenin tek doğruluk kaynağıdır. Antigravity ve diğer araçlar kodlamadan önce bunu okumalıdır.
> İşaretler: **[KARAR]** kesinleşmiş · **[VARSAYIM]** onay bekliyor · **[AÇIK]** henüz karar yok

---

## 1. Özet

Kelimeta, iki oyuncunun gerçek zamanlı eşleşip sırayla cevap verdiği bir kelime düello oyunudur. Ekranda bir kategori sorusu çıkar (örn. "B ile başlayan hayvanlar"). Oyuncular sırayla cevap yazar. Süresi içinde doğru ve daha önce söylenmemiş bir cevap veremeyen turu kaybeder.

Oyun konsepti mevcut benzer oyunlarla aynı türdendir. Arayüz, isim, ikon, karakter ve soru metinleri tamamen özgün olacaktır.

## 2. Teknoloji kararları

| Konu | Karar |
|---|---|
| İstemci | **[KARAR]** Flutter (Dart). Önce Android; iOS yaklaşık 3–4 ay sonra, bulut derlemesiyle |
| Ücret ilkesi | **[KARAR]** Ücretli plana geçilmez; yalnızca ücretsiz planlar (Firebase Spark, Cloudflare Workers Free). Kota dolarsa online eşleşme geçici durur, botlu maç cihazda çalışmaya devam eder |
| Giriş (Auth), Remote Config, bildirim (FCM), çökme takibi | **[KARAR]** Firebase (yeni proje, Spark planı) |
| Oyun sunucusu | **[KARAR]** Cloudflare Workers + Durable Objects (TypeScript, WebSocket). Cloud Functions kullanılmaz (Blaze planı ve kart gerektirir) |
| Canlı maç durumu | **[KARAR]** Maç başına bir Durable Object; durum sunucuda tutulur, istemciler WebSocket ile bağlanır |
| Profil, jeton, envanter, görev, liderlik | **[KARAR]** Cloudflare Durable Objects (kullanıcı başına bir `UserProfile` nesnesi, SQLite; liderlik için ayrı tek bir tablo nesnesi). Firestore kullanılmaz. Jeton yazımı yalnızca sunucudan yapılır (Faz 5) |
| Maç geçmişi | **[KARAR]** Telefonda yerel saklanır; sunucu maç bitince tur kayıtlarını iki oyuncuya gönderir. Firestore'a yazılmaz |
| İçerik (sorular) | **[KARAR]** Realtime Database, mevcut CMS paneli ile yönetilir; oyun sunucusu okur |
| Profil fotoğrafı | **[KARAR]** İlk sürümde yok (harf avatar). Cloud Storage for Firebase ücretsiz planda kullanılamaz; ileride hazır avatar seti ya da Cloudinary değerlendirilir |
| IDE | **[KARAR]** VS Code + Antigravity (eklenti) |
| iOS derleme | **[KARAR]** Bulut CI (Codemagic veya GitHub Actions macOS). Mac yok. Başlangıç: Android yayını sonrası |

## 3. Maç kuralları

1. **[KARAR]** Bir maç en fazla 3 tur sürer (3 turun en iyisi). Her turda bir soru (kategori) oynanır.
2. **[KARAR]** Oyuncular sırayla cevap yazar. Her cevap için süre **15 saniyedir**.
3. **[KARAR]** Sırası gelen oyuncu, süresi dolmadan doğru ve daha önce söylenmemiş bir cevap veremezse o turu kaybeder; rakip o turun puanını alır. **Turu kaybetmenin tek koşulu süre dolmasıdır.** Yanlış ya da daha önce söylenmiş cevap turu kaybettirmez: cevap kabul edilmez, süre akmaya devam eder ve oyuncu istediği kadar yeniden deneyebilir (bölüm 4.5'teki kötüye kullanım sınırları hariç).
3b. **[KARAR]** Maçı terk eden oyuncu maçı kaybeder; rakip maçı kazanır (mevcut skordan bağımsız).
3c. **[KARAR]** Oyuncunun yaptığı her deneme (doğru, yanlış ya da tekrar eden) maç sırasında iki oyuncuya da gösterilir; rakip, oyuncunun yazdığı yanlış cevabı da görür. Yok sayılan denemeler (bölüm 4.5) gösterilmez. Kabul edilmeyen denemeler listede kırmızı balonla ayırt edilir. **İstisna:** henüz söylenmemiş bir cevaba "çok yakın" olan denemeler tur bitene kadar rakibe gösterilmez (ipucu hakkı bitmiş olsa bile); aksi halde rakip, düzeltilmiş hâlini yazarak kopya çekebilir. İpucu verilen yakın denemeler ise kimseye balon olarak gösterilmez, oyuncu yalnızca "Çok yakın!" ipucunu görür (rakibin de görüyormuş gibi yanlış anlamaması için). Online maçta sunucu bu denemeleri rakibe hiç iletmez. Tur bitince ve maç detayında herkese görünür (bölüm 4.3).
4. **[KARAR]** Bir turda sorunun tüm cevapları tükenirse o tur berabere sayılır, kimseye puan yazılmaz ve maç bir tur uzar. (Çok nadir bir durum, kuralın tutarlılığı için tanımlı.)
5. **[KARAR]** Turlardan **ikisini kazanan** maçı kazanır. Maç 2–0 biterse 3. tur oynanmaz; 1–1 ise 3. tur belirleyicidir.
6. **[VARSAYIM]** Aynı cevap bir turda iki kez söylenemez.
7. **[KARAR]** Berabere biten turlar sayıya dahil edilmez; yerine yeni bir tur oynanır. Her sonuçlanan turun bir kazananı olduğundan maç en fazla 3 sonuçlanan tur sürer ve skor eşit bitemez.
8. **[VARSAYIM]** Her turda başlayan oyuncu sırayla değişir (1. tur oyuncu A, 2. tur oyuncu B…).
9. **[VARSAYIM]** Her turun sorusu rastgele seçilir, aynı maçta aynı soru tekrar gelmez, iki oyuncu aynı soruyu görür.

### 3.1 Süre ve gecikme

- **[KARAR]** Süre ölçümü **sunucuda** yapılır. Telefondaki sayaç sadece göstergedir.
- **[VARSAYIM]** Ağ gecikmesi için 1–2 saniyelik sunucu toleransı tanınır. Değer Remote Config'ten ayarlanabilir olmalıdır.
- Her hamlede sunucu `turnDeadline` (sunucu saati) yazar. Süre dolduysa tur kaybedilmiş sayılır.

### 3.2 Bağlantı kopması

- **[KARAR]** Maçı bilerek terk eden (çıkış butonu) maçı kaybeder.
- **[KARAR]** Bağlantı kopması: oyuncunun sırası geldiğinde süre normal işlemeye devam eder; süre dolarsa turu kaybeder. Kopan oyuncu belirli bir süre (**[VARSAYIM]** 30 sn, Remote Config'ten ayarlanır) geri dönmezse maçı terk etmiş sayılır ve rakip kazanır. Geri dönen oyuncu güncel maç durumunu sunucudan alır.
- **[KARAR]** Bağlantısı 30 sn içinde dönmeyen oyuncu maçı kaybeder. Bu maç onun geçmişinde "Kaybettin" olarak ve "Bağlantın koptu" notuyla kayıtlıdır (skor, maç hangi turda kesildiyse o ana kadarki skordur; ilk tur bitmeden kesilirse 0–0). Aynı maç, rakibin geçmişinde "Kazandın" olarak ve "Rakibin bağlantısı koptu" notuyla görünür. Kayıt, maç kimliğine (matchId) göre tektir; aynı maç iki kez yazılmaz. Kopan oyuncu maçın son durumunu bilemediği için kayıt önce **geçici** yazılır (bağlantı kopmadan önceki skorla, "Skor, bağlantı kopmadan önceki duruma göredir" notuyla). Uygulama yeniden internete kavuşunca (öne alınınca ya da açılınca), sunucu maç verisini tuttuğu sürece (maç bittikten sonra yaklaşık 10 dk) istemci kesin sonucu sunucudan alıp kaydı günceller. Bu süre geçmişse kayıt geçici olarak kalır.
- **[KARAR]** Uygulama arka plana alınır ya da ekran kilitlenirse maç durmaz: süre sunucuda akmaya devam eder ve bağlantı kopmuş sayılır (yukarıdaki kural). Uygulama öne dönünce istemci hemen yeniden bağlanır ve güncel durumu sunucudan alır.
- Bağlantısı kopan oyuncu kendi ekranında bir bağlantı uyarısı görür; rakibi de karşı tarafın bağlantısının koptuğunu görür (rakip kartında küçük bir not). Geri sayım süresi gösterilmez.
- Bağlantı kopması sunucu tarafından algılanır (WebSocket kapanışı ve periyodik ping); 30 sn'lik bekleme süresi Durable Object alarmıyla sayılır.

## 4. Cevap doğrulama

Doğrulama **yalnızca oyun sunucusunda** (Cloudflare Worker / Durable Object) yapılır. İstemci cevap listesini hiçbir zaman indirmez.

### 4.1 Normalizasyon (hem oyuncu girdisi hem kayıtlı cevaplar için)

1. Baştaki ve sondaki boşlukları sil, ardışık boşlukları tek boşluğa indir.
2. Türkçe kurallarıyla küçük harfe çevir (`tr-TR`): `ISPANAK` → `ıspanak`, `İSTANBUL` → `istanbul`. Büyük/küçük harf kombinasyonu fark etmez.
3. Aksan katlaması: `ç→c`, `ğ→g`, `ı→i`, `ö→o`, `ş→s`, `ü→u`; şapkalı harfler de sadeleşir (`â→a`, `î→i`, `û→u`). Böylece `turkiye` yazan oyuncu `türkiye` cevabını bulur.
4. Harf, rakam, boşluk, `+` ve `#` dışındaki tüm karakterler (noktalama, tire, kesme işareti vb.) boşluğa çevrilir, ardışık boşluklar tek boşluğa indirilir. `+` ve `#` korunur; böylece `c`, `c++` ve `c#` birbirine karışmaz.
5. Karşılaştırma katlanmış (3. ve 4. adım) hâller üzerinden yapılır. Kayıtlı alias'ların katlanmış hâli önceden hesaplanıp önbelleğe alınır.

### 4.2 Eşleştirme

- Normalleştirilmiş girdi, sorunun herhangi bir cevabının alias'larından birine eşitse cevap doğrudur ve o cevabın dahili kimliği (`answerId`) kaydedilir.
- Aynı `answerId` o turda daha önce söylendiyse cevap tekrar sayılır: kabul edilmez, ama tur da kaybedilmez.
- **[KARAR]** Alias'lar (örn. "kore" → "güney kore") aynı cevabın varyantıdır, ayrı cevap sayılmaz.

### 4.3 "Çok yakın" geri bildirimi

- **[VARSAYIM]** Cevap hiçbir kayıtlı cevapla eşleşmezse, o turda henüz söylenmemiş cevaplar arasından en yakın olanla benzerlik hesaplanır (Damerau-Levenshtein: harf ekleme, silme, değiştirme ve komşu harflerin yer değiştirmesi 1 düzenleme sayılır; normalleştirilmiş metin üzerinde).
- Eşik cevap uzunluğuna göre değişir: çok kısa kelimelerde (3 harf ve altı) kapalı; 4+ harfte 1, 9+ harfte 2 düzenleme. Değerler Remote Config'ten ayarlanır, oyun testleriyle belirlenir.
- Yakın cevap **doğru sayılmaz**; oyuncuya yalnızca "Çok yakın!" ipucu gösterilir. Yanlış cevaplar zaten turu kaybettirmediği için bu bir ceza değil, bir yardımdır; süre akmaya devam eder.
- Cevap listesini yoklayarak öğrenmeyi önlemek için turda oyuncu başına en fazla **1** "çok yakın" ipucu verilir; sonrasında yakın cevaplar da normal yanlış cevap gibi (ipucu vermeden) reddedilir. Hangi cevaba yakın olunduğu asla söylenmez.
- **Yakın denemeler rakibe gösterilmez** (tur bitene kadar). Bu, ipucu hakkı bitmiş olsa bile geçerlidir: yakınlık her yanlış denemede ayrıca hesaplanır ve kayda "yakın" işareti düşülür. İşaret yalnızca gösterimi etkiler; ipucu hakkı ve cevabın kabulü değişmez. İpucu verilmeyen (hakkı bitmiş) yakın denemeyi oyuncu kendi listesinde normal yanlış deneme gibi görür; ipucu verilen yakın deneme listede görünmez, yalnızca ipucu çıkar.
- Hesaplama yalnızca sunucuda yapılır.
- Sık yapılan yazım hataları (örn. "maydonoz", "çedar") CMS'te alternatif cevap olarak eklenmeye devam eder ve **doğru** sayılır; "çok yakın" yalnızca listede olmayan hatalar içindir.

### 4.4 İtiraz

- **[VARSAYIM]** Maç sonunda oyuncu "bu cevap doğruydu" diyebilir. Yoğun itiraz alan girdiler incelenmek üzere kuyruğa düşer ve CMS'ten alias olarak eklenebilir.

### 4.5 Kötüye kullanım sınırları

- Yanlış cevap ceza getirmediği için, bir betik süre içinde yüzlerce kelime deneyerek cevap listesini çıkarabilir. Bunu önlemek için sunucu şu sınırları uygular:
  - **[VARSAYIM]** Aynı oyuncunun iki denemesi arasında en az 600 ms olmalıdır; daha hızlı gelen deneme yok sayılır.
  - **[VARSAYIM]** Bir oyuncu bir turdaki sırasında en fazla 25 deneme yapabilir; sonrası yok sayılır.
- Yok sayılan denemeler ceza getirmez ve geçmişe kaydedilmez; süre normal akar. Sınırlar Remote Config'ten ayarlanır.

### 4.6 Serbest metin güvenliği

Yanlış denemeler rakibe gösterildiği için oyuncunun yazdığı metin fiilen bir sohbet kanalıdır. Bu yüzden:

- **[VARSAYIM]** Deneme metni en fazla 40 karakterdir; baştaki/sondaki boşluklar silinir, ardışık boşluklar tek boşluğa iner.
- **[VARSAYIM]** Rakibe gösterilmeden önce sunucu, metni küfür/hakaret listesine karşı süzer ve eşleşen kısmı maskeler (`***`). Liste sunucuda tutulur ve güncellenebilir.
- Bir oyuncu rakibin metnini **raporlayabilir** ve rakibi **engelleyebilir**; mağazalar kullanıcı üretimli içerik için bu mekanizmaları ister (bölüm 9). Tasarımı Faz 5'te yapılır.
- Botların yanlış denemeleri kısa, zararsız bir kelime listesinden gelir.

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
- Dönüşüm **sunucuda** yapılır: Oyun sunucusu bu yapıyı Realtime Database'ten (REST, servis hesabıyla) okuyup normalleştirilmiş dahili bir dizin üretir (bölüm 4.1) ve önbelleğe alır. Her cevaba kararlı bir dahili kimlik atanır. Böylece panelin biçimi değişmeden doğrulama yapılabilir.
- Soru metnindeki fazla boşluklar da sunucu tarafında temizlenir.
- Kategori kimlikleri şimdilik mevcut haliyle kalır (`film_diz`, `bilim_teknoloji` gibi). Etiketler panelde tutulur.
- **[AÇIK]** Realtime Database anahtarlarında `. $ # [ ] /` karakterleri yasaktır. Ana cevap anahtar olduğundan bu karakterleri içeren bir cevap (örn. "dr. pepper") panelde hata verebilir. Şimdilik bu karakterlerden kaçınılır; ileride gerekirse panel kodu Antigravity ile güncellenir.
- Sunucu, içerik yüklenirken **uyarı raporu** üretir: bir cevabın varyantı başka bir cevapla çakışıyorsa ya da bir ana cevap diğerinin parçasıysa (örn. "kore" ve "güney kore") bu, içerik yöneticisine (sana) listelenir. Düzeltme gerekiyorsa soru panelden silinip doğru yapıyla yeniden eklenir ya da dışa aktarılan JSON düzenlenip içe aktarılır.

### 5.2 Canlı maç (Durable Object)

Maç durumu, maç başına bir Durable Object'in belleğinde ve SQLite deposunda tutulur:

```json
{
  "status": "waiting | active | finished",
  "players": { "uidA": {...}, "uidB": {...} },
  "round": 1,
  "scores": { "uidA": 0, "uidB": 0 },
  "questionId": "...",
  "turnUid": "uidA",
  "turnDeadline": 1790000000000,
  "usedAnswerIds": ["a01"],
  "attempts": [ ... ]
}
```

- İstemciler maça WebSocket ile bağlanır. Her istemci yalnızca **kendisine gösterilmesine izin verilen** durumu alır (yakın denemeler rakibe iletilmez, bölüm 4.3). Hamleler istemciden mesaj olarak sunucuya gönderilir; durumu yalnızca sunucu değiştirir.
- Bağlantı, Firebase kimlik jetonuyla (ID token) doğrulanır.
- Tur süresi sunucu alarmıyla (Durable Object alarm) izlenir.

### 5.3 Kullanıcı verisi (Durable Objects)

Her kullanıcının `uid`'ye bağlı bir `UserProfile` nesnesi vardır: takma ad, jeton, istatistikler (oynanan/kazanılan/kaybedilen/doğru cevap sayısı; mevcut kullanıcılarda doğru cevap sayacı güncelleme anından itibaren birikir), ayarlar. Envanter, görev ve liderlik sonraki aşamalarda eklenir. Takma ad bulutta tutulur; Google hesabıyla giriş yapılan yeni bir cihazda geri gelir. Jeton değişiklikleri yalnızca sunucudan yapılır ve her maç için en fazla bir kez uygulanır (`matchId` ile tekrar koruması). Son 10 maçın özeti (rakip, skor, sonuç) ana ekranda gösterilir. Her maçın tur ve cevap geçmişi (hangi oyuncu hangi cevabı verdi, kabul edildi mi, turu kim kazandı) **telefonda yerel** saklanır; "Maç Detayı" ekranı bunu okur. Sunucu, maç bitince tur kayıtlarını iki oyuncuya da gönderir.

### 5.4 Liderlik tablosu

- **[VARSAYIM]** Sıralama **haftalık galibiyet sayısına** göre yapılır. Hafta, Türkiye saatiyle (Europe/Istanbul) pazartesi 00:00'da başlar ve sıfırlanır. Eşitlikte sırayla: daha az mağlubiyet, sonra galibiyete daha erken ulaşan üstte.
- Tabloda ilk 50 oyuncu ve oyuncunun kendi sırası görünür. Her satırda sıra, harf avatarı, takma ad ve galibiyet sayısı bulunur.
- Yalnızca gerçek online maçlar sayılır (bot maçları sayılmaz). Bağlantı kopması nedeniyle kazanılan maç da sayılır.
- Aynı rakibe karşı bir haftada en fazla **3 galibiyet** sayılır (iki hesapla puan basmayı zorlaştırmak için). Sınırı aşan galibiyetler jetonu etkilemez, yalnızca sıralamaya yazılmaz.
- Takma adı henüz olmayan oyuncu tabloda görünmez.
- Veri tek bir `Leaderboard` Durable Object içinde tutulur; yalnızca sunucu yazar. Maç bitince `UserProfile` güncellemesiyle birlikte tabloya galibiyet bildirilir. Bildirim hata verirse maç sonu etkilenmez, sonra tekrar denenir.
- Geçmiş haftaların tablosu ve haftalık ödüller şimdilik yoktur (sonraki aşama).

## 6. Eşleştirme ve bot

- Oyuncu "Hızlı Maç" seçince sunucudaki eşleştirme havuzuna (Durable Object) girer; sunucu iki oyuncuyu eşler.
- **[VARSAYIM]** Belirli bir süre (örn. 8–10 sn) eşleşme bulunamazsa bot rakip devreye girer. Bot **cihazda** çalışır (sunucuya hiç gitmez), böylece sunucu kotası harcanmaz. Başlangıçta oyuncu sayısı az olacağından bu kritiktir.
- Bot, sorunun cevap listesinden rastgele gecikmeyle (örn. 3–12 sn) ve ayarlanabilir hata olasılığıyla cevap verir.
- **[KARAR]** Bot rakip için ayrı bir etiket gösterilmez; bot adı normal bir oyuncu adı gibi görünür. Maç geçmişi kaydına iç bilgi olarak "botla oynandı" işareti düşülür (arayüzde gösterilmez; ileride ekonomi ve istatistik kararları için). **[AÇIK]** Botla oynanan maçlarda jeton ödülünün normalden düşük olup olmayacağı (ekonomi kararı).

## 7. Modlar

- Hızlı maç (rastgele rakip + bot yedeği)
- Arkadaşla düello (davet kodu/bağlantı)
- Günlük meydan okuma
- Turnuva / sezon

Sürümleme ve hangi modun ne zaman çıkacağı proje sahibi tarafından belirlenir; bu dokümanda tutulmaz.

## 8. Ekonomi (taslak)

- **[VARSAYIM]** İlk sürüm değerleri (sunucu ortam değişkeni olarak ayarlanır, kodda sabit değildir): başlangıç bakiyesi 100; maç kazanma +30; maç kaybetme +5; rakibin bağlantısı kopup kazanılan maç +30; bağlantısı kopup kaybedilen maç +0; günlük maç ödülü üst sınırı 300 jeton; botla oynanan maçlar jeton vermez (bot maçı istemcide oynandığı için sunucu doğrulayamaz).
- Ödüller yalnızca sunucuda canlı maç bitince verilir; istemcinin "şu kadar jeton kazandım" demesine güvenilmez.
- Harcama (güçlendirici, kozmetik) ve ödüllü reklam sonraki aşamadadır.
- **[AÇIK]** Jeton kazanma/harcama kuralları henüz tam belirlenmedi. Öneriler:
  - Maç kazanma ve günlük görevlerle jeton kazanılır, ödüllü reklamla ek jeton alınır.
  - Güçlendiriciler (ek süre, pas, harf ipucu) jetonla alınır.
  - Pay-to-win'den kaçınılır; ücretli içerik kozmetik ağırlıklı olur.
- Tüm sayısal değerler kodda sabitlenmez. İstemciyi ilgilendirenler (fiyat gösterimi vb.) Remote Config'te, sunucuyu ilgilendirenler (ödül miktarı, günlük sınır) Worker ortam değişkenlerinde tutulur.

## 9. Güvenlik ilkeleri

- Cevap listesi (`questions_pool`) istemci tarafından **okunamaz**; yalnızca oyun sunucusu okur (servis hesabıyla). Sunucu, her bağlantıda Firebase kimlik jetonunu doğrular.
- Oyun durumu ve jeton yazma yetkisi yalnızca sunucudadır.
- Hesap silme özelliği, raporlama/engelleme mekanizması ve gizlilik politikası (KVKK/GDPR) yayın için zorunludur.
- iOS'ta başka sosyal giriş sunulursa Sign in with Apple zorunludur.
- Servis hesabı anahtarları ve gizli bilgiler asla repoya konmaz; sunucu tarafında Cloudflare gizli değişkenleri (`wrangler secret`) kullanılır.

## 10. Platform ve yayın riskleri

| Risk | Önlem |
|---|---|
| Mac yok, iOS Windows'ta derlenemez | Bulut CI (Codemagic / GitHub Actions macOS) |
| iPhone yok | **[KARAR]** iOS aşaması ertelendi (~3–4 ay). iOS aşamasından önce bir iPhone'a erişim sağlanmalı (ödünç, ikinci el ya da TestFlight ile test edecek tanıdıklar) |
| iOS'a geç başlamanın riski: sürprizler geç görülür | Android geliştirmesi sırasında iOS ile uyumlu paketler seçilir (Android'e özel paket kullanılmaz). Hesap gerektirmeyen imzasız derleme kontrolü bulut CI'da arada çalıştırılabilir. Apple Developer hesabı iOS aşamasının başında açılır |
| Google Play yeni hesaplarda kapalı test şartı olabilir | Kuralları şimdiden kontrol et, planı buna göre kur |
| Ücretsiz plan kotaları dolabilir (Firebase Spark, Cloudflare Free) | Kullanım izlenir. Kota aşımı otomatik ücret doğurmaz; online eşleşme geçici durur, botlu maç çalışmaya devam eder |
| Cloudflare ücretsiz plan koşulları değişebilir | Maç motoru taşınabilir TypeScript, protokol sade tutulur; gerekirse başka bir sunucuya taşınır |
| İçerik yetersizliği (150 soru ile başlangıç) | Yayın öncesi 30–50 sağlam kategori, sonra CMS ile büyüt |

## 11. Çalışma kuralları (Antigravity ile)

1. **Faz 1 bitmeden oyun kodu yazılmaz.** `DESIGN.md` hazır olmalı.
2. Bir seferde tek ekran/özellik yaptırılır.
3. Her adım Git commit ile kaydedilir.
4. Oyun kuralı, veri modeli ve güvenlik kuralları bu dosyadan çıkarılır; bu dosyayla çelişen kod yazılmaz.
5. Süre, sıra ve cevap doğrulaması asla istemcide yapılmaz.

## 12. Açık sorular listesi

1. Bağlantı kopması bekleme süresinin (30 sn) netleşmesi (bölüm 3.2)
2. Botla oynanan maçlarda ödül ve bot bildirimi (bölüm 6)
3. Jeton ekonomisi sayılarının onayı ve harcama kuralları (bölüm 8)
4. iOS aşaması için iPhone erişiminin nasıl sağlanacağı (bölüm 10)
5. Varsayımların onayı (bölüm 3, madde 6–9; bölüm 4.3 ve 4.4; bölüm 6)
6. Cevap anahtarlarında özel karakter (`. $ # [ ] /`) sorunu (bölüm 5.1)

## 13. iOS aşaması (ertelendi)

**[KARAR]** Android ilk yayındır. iOS yaklaşık 3–4 ay sonra ele alınır. O güne kadar:

- Kodda Android'e özel çözümlerden kaçınılır; her yeni paket için iOS desteği kontrol edilir.
- Firebase projesine iOS uygulaması ve gerekli yapılandırma iOS aşamasında eklenir.
- Bildirimler (FCM), reklam (AdMob ve izleme izni isteği) ve uygulama içi satın alma iOS aşamasında ayrıca kurulur ve test edilir.
- Başka bir sosyal giriş sunulursa iOS'ta Sign in with Apple eklenmelidir; giriş yöntemleri buna göre planlanır.
- iOS aşaması başlarken: Apple Developer hesabı açılır, bulut CI kurulur, bir iPhone'da TestFlight ile test yapılır.

## 14. Notlar ve ileriye dönük bilgiler

- **Alan adı:** `riestudio.com.tr` proje sahibine aittir. İleride şunlar için kullanılabilir: kayıt/doğrulama e-postalarının gönderen adresi, mağazalar için gerekli gizlilik politikası ve destek sayfası, "Arkadaşınla Oyna" davet bağlantıları.
- **[AÇIK]** Kayıt doğrulaması: e-posta ile doğrulama kodu isteniyorsa, Firebase Authentication'ın yerleşik e-posta doğrulaması bağlantı tabanlıdır; kod (OTP) göndermek için ayrı bir e-posta servisi ya da farklı bir Firebase Authentication yapılandırması gerekebilir. Güncel seçenekler Faz 4 öncesinde kontrol edilir.
- **İçerik alışkanlığı:** CMS'te doğru cevabın yaygın kısaltma, alternatif ad ve yazım hataları ("abd", "amerika birleşik devletleri", "maydonoz", "çedar") alternatif cevap olarak girilir; eşleştirici bunları ilgili ana cevabın varyantı sayar.
