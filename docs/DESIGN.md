# Kelimeta – Tasarım Rehberi (DESIGN.md)

> Taslak 0.1 · Tarih: 6 Ekim 2026
> Bu dosya `GDD.md` ile birlikte kodlamadan önce okunur. Arayüz kodu bu dosyayla çelişmemelidir.
> Görsel referans: `docs/design/` klasöründeki ekran görüntüleri (6 ekran). Rehber ile görüntü çelişirse görüntü kazanır.
> İşaretler: **[KARAR]** onaylı · **[VARSAYIM]** onay bekliyor

---

## 1. Tasarım dili

- **Hava:** Eğlenceli, renkli, çizgi film hissi. Kalın koyu kenarlıklar, yuvarlak köşeler, altta sert gölge ("basılabilir" butonlar).
- **Renk yönü:** Beyaz ve yeşil. Sıcak vurgu olarak tek bir sarı (jeton). Kırmızı sadece olumsuz durumlar için.
- **Maskot yok.** Kimlik tamamen tipografi ve ikonlarla kurulur.
- **Logo:** `Kelimeta` tek kelime. "Kelime" `ink` renginde, "ta" `primary` renginde ve arkasında açık nane yeşili (`mint`), yuvarlatılmış, sağa bakan bir oynat (play) üçgeni rozeti durur. Aynı boyut ve kalınlıkta (Fredoka 700). Üçgenin kenarlığı ve gölgesi yoktur. Logo eğik ya da döndürülmüş olmaz. **[VARSAYIM]** Geçici çözüm; telefonda görüp netleştirilecek.

## 2. Renk jetonları

Kodda renkler **tek bir tema dosyasında** tanımlanır. Widget'larda sabit renk kodu yazılmaz.

| Jeton | Değer | Kullanım |
|---|---|---|
| `ink` | `#14532D` | Ana yazı, kenarlık, gölge, ikon |
| `primary` | `#15803D` | Ana buton, vurgulu metin, "Kazandın" etiketi |
| `bright` | `#4ADE80` | Avatar zemini, kendi cevap balonu, süre dolgusu |
| `mint` | `#BBF7D0` | Açık kenarlık, süre çubuğu zemini, logo üçgeni |
| `surface` | `#F0FDF4` | Ekran arka planı |
| `card` | `#FFFFFF` | Kart, buton, giriş alanı zemini |
| `muted` | `#166534` | İkincil yazı (tarih, etiket başlığı) |
| `coin` | `#FACC15` | Jeton simgesi, rakip avatar zemini |
| `danger` | `#DC2626` | "Kaybettin" etiketi, olumsuz durum |
| `dangerDark` | `#7F1D1D` | Kırmızı etiketin kenarlığı, hata metni |
| `dangerText` | `#B91C1C` | Kırmızı metin / bağlantı |
| `dangerSoft` | `#FECACA` | Kaybedilen maç kartı kenarlığı, uyarı kutusu kenarlığı |
| `dangerSurface` | `#FEF2F2` | Uyarı kutusu zemini |

**Kurallar**
- **Kırmızı yalnızca kayıp ve olumsuz durumlar için kullanılır** (kaybedilen tur/maç, kabul edilmeyen cevap, hata uyarısı). Başka hiçbir yerde dekoratif kırmızı yok.
- Sonuç, hiçbir zaman sadece renkle anlatılmaz. Her zaman metin de vardır ("Kazandın", "Kaybettin").
- Beyaz zemin üzerinde `bright` ile yazı yazılmaz. `bright` zemin üzerinde yazı rengi `ink` olur. `primary` ve `danger` zeminlerde yazı beyazdır.
- Yeni renk eklemeden önce bu tabloya eklenir.

## 3. Tipografi

| Rol | Font | Ağırlık |
|---|---|---|
| Başlık, rakam, buton, logo | **Fredoka** | 600–700 |
| Gövde, etiket, cevap balonu, giriş | **Nunito** | 700–800 |

**[KARAR]** Türkçe karakterleri (ç ğ ı İ ö ş ü) destekleyen Latin-ext alt kümeli sürümler kullanılır. Fontlar uygulamayla birlikte `assets/fonts/` içinde paketlenir (çevrimdışı ve ilk açılışta gecikmesiz). Paketleme yerine `google_fonts` kullanılacaksa çalışma zamanı indirmesi test edilir.

| Stil | Font | Boyut | Ağırlık |
|---|---|---|---|
| Logo | Fredoka | 64 | 700 |
| Büyük sonuç ("Kazandın!") | Fredoka | 46 | 700 |
| Tur sonucu başlığı | Fredoka | 34 | 700 |
| Skor (büyük) | Fredoka | 52 / 42 / 34 | 700 |
| Ekran başlığı | Fredoka | 22 | 600 |
| Ana buton | Fredoka | 22–28 | 600 |
| İkincil buton | Fredoka | 18–20 | 600 |
| Soru metni | Fredoka | 18 | 600 |
| Kart başlığı | Fredoka | 17 | 600 |
| Cevap balonu | Nunito | 15 | 800 |
| Giriş alanı | Nunito | 16 | 700 |
| Oyuncu adı | Nunito | 15–16 | 800 |
| İkincil metin / tarih | Nunito | 12 | 700 |
| Bölüm etiketi (BÜYÜK HARF) | Nunito | 12 | 800, harf aralığı 0.08em |

- Uzun soru ve cevap metni **alt satıra sarar**; kesilmez, küçülmez. Soru kartı ve balonlar içeriğe göre uzar.
- Büyük harfe çevirme (örn. bölüm etiketi) Türkçe kurallarına uyar (`i` → `İ`).

## 4. Ölçüler

**Boşluk:** 4 / 6 / 8 / 10 / 12 / 14 / 16 / 20 / 24. Ekran yan boşluğu **20**, üst boşluk **24** (güvenli alan eklenir). Bloklar arası boşluk 16, liste kartları arası 10, cevap balonları arası 8.

**Köşe yuvarlaklığı:** ikon buton 14 · küçük etiket 12 · cevap balonu 14 · soru kartı 18 · giriş alanı 18 · ana/ikincil buton 20–22 · liste kartı 20 · büyük kart 22–24 · avatar tam yuvarlak.

**Kenarlık:** Önemli etkileşimli öğeler (ana buton hariç) ve avatarlar `ink` renkli **2–3 px**. Dinlenme hâlindeki liste kartları `mint` renkli **2 px**.

**Gölge:** Sadece "sert, bulanıklıksız" gölge. Ana buton `0 5px 0 ink`, ikincil buton / giriş gönder butonu `0 4px 0 ink`, soru kartı `0 3px 0 ink`. Yumuşak (blur'lu) gölge **kullanılmaz**.

**Dokunma alanı:** En az **48×48 dp** (mockup'ta bazı öğeler 44 görünür, Flutter'da dokunma alanı 48'e tamamlanır).

**Referans genişlik:** 390 dp. Düzen esnek yazılır; sabit genişlik yalnızca aşağıda belirtilen yerlerde (sonuç etiketi 88, skor 56, avatar boyutları).

## 5. İkonlar

Çizgi (outline) ikonlar. Çizgi kalınlığı **2.2–2.4**, uçlar yuvarlak, rengi `ink` (koyu zemin üstünde beyaz). Mockup'taki özel çizimler `flutter_svg` ile kullanılır (24×24 görünüm kutusu):

| İkon | Yol (path) |
|---|---|
| Ana sayfa | `M3 11l9-8 9 8M5 10v10h14V10` |
| Sıralama | `M5 20V12M12 20V4M19 20V9` |
| Mağaza | `M5 8h14l-1 12H6zM9 8a3 3 0 016 0` |
| Profil | `M12 12a4 4 0 100-8 4 4 0 000 8M4 21a8 8 0 0116 0` |
| Ayarlar | `M4 7h16M4 17h16M9 4v6M15 14v6` |
| Kapat | `M6 6l12 12M18 6L6 18` |
| Geri | `M15 6l-6 6 6 6` |
| Sağ ok (gönder) | `M5 12h14M13 6l6 6-6 6` |
| Sağ ok (liste) | `M9 6l6 6-6 6` |
| Onay | `M5 12l5 5 9-10` |
| Tekrar (yenile) | `M20 12a8 8 0 11-2.3-5.7M20 4v5h-5` |
| Eşit (beraberlik) | `M5 9h14M5 15h14` |
| Kupa | gövde `M8 4h8v5a4 4 0 01-8 0z` (dolgu `coin`) + `M8 6H5v2a3 3 0 003 3M16 6h3v2a3 3 0 01-3 3M12 13v4M9 20h6M10 17h4` |

## 6. Bileşenler

**Ana buton (`PrimaryButton`)** – Zemin `primary`, yazı beyaz, Fredoka 22 (ana ekranda "Hızlı Maç" 28 ve altında 13 px alt yazı), yükseklik 60 (ana ekran 76), köşe 20–22, gölge `0 5px 0 ink`. Basılınca gölge kaybolup buton 4–5 px aşağı iner (basılma hissi, 80–100 ms).

**İkincil buton (`SecondaryButton`)** – Zemin `card`, yazı `ink`, kenarlık 3 `ink`, yükseklik 54–60, gölge `0 4px 0 ink`.

**İkon buton** – 44×44 (dokunma 48), `card` zemin, 2 px `ink` kenarlık, köşe 14.

**Avatar** – Tam yuvarlak, 3 px (liste için 2 px) `ink` kenarlık, ortada oyuncu adının baş harfi (Fredoka 700). Kendi avatarı: `primary` zemin + beyaz harf (maç içi) ya da `bright` (ana ekran); rakip: `coin` zemin; bilinmeyen rakip: beyaz zemin + kesik çizgili kenarlık + "?".

**Oyuncu kartı (maç ekranı)** – Zemin `card`, 3 px `ink` kenarlık, köşe 20. Avatar 36, ad, skor (Fredoka 34). **Sırası olan oyuncunun kartı süre göstergesidir:** kartın içinde `bright` bir dolgu soldan sağa kalan süre oranında uzanır (15 sn → %100, 0 sn → %0) ve sağdan sola azalır; ad altında "11 sn" yazar. Sırası olmayan oyuncu kartında dolgu ve süre yazısı yoktur. Kart yalnızca bir `LinearProgress` benzeri katmandır, ayrı bir sayaç öğesi yoktur.
- **[VARSAYIM]** Kalan süre 5 saniyeye indiğinde dolgu `danger` tonuna (açık kırmızı) geçer. Renk geçişi 200 ms.
- Erişilebilirlik: dolgu bir `progressbar` olarak etiketlenir ("Kalan süre").

**Soru kartı** – `card` zemin, 3 px `ink` kenarlık, köşe 18, gölge `0 3px 0 ink`, ortalı Fredoka 18/600. İçerik tek satır olmak zorunda değildir; çok satıra uzar.

**Cevap balonu** – Nunito 15/800, dolgu: kendi cevabın `bright`, rakip cevabı `card`; 2 px `ink` kenarlık, köşe 14, iç boşluk 7×14, en geniş %78. Kendi cevabın sağa, rakibinki sola hizalanır. Kabul edilmeyen cevaplar (yanlış, tekrar, "çok yakın" olsa bile) listede iki oyuncuya da gösterilir; balonun kenarlığı `danger`, yazısı `dangerText`, zemini `card` olur. Kendi reddedilen cevabın sağda, rakibinki solda durur. Metin en fazla 40 karakter. Yok sayılan (hız/sayı sınırına takılan) denemeler listede görünmez. Henüz söylenmemiş bir cevaba "çok yakın" olan denemeler tur bitene kadar rakibe gösterilmez (kopya önleme). İpucu verilen yakın deneme sahibine de balon olarak gösterilmez, yalnızca "Çok yakın!" ipucu çıkar. İpucu hakkı bitmişse sahibi onu normal yanlış deneme gibi (kırmızı balon) görür. Tur bittikten sonra ve maç detayında bütün denemeler herkese görünür.

**Giriş alanı** – Yükseklik 54, 3 px `ink` kenarlık, köşe 18, Nunito 16/700, ipucu: "Cevabını yaz…". Yanında 54×54 gönder butonu (`primary`, beyaz ok, gölge `0 4px 0 ink`). Otomatik düzeltme ve öneri kapalı; klavye "gönder" eylemiyle de gönderilir.

**Sonuç etiketi (`ResultBadge`)** – Genişlik **88 (sabit)**, yazı ortalı, Nunito 12/800, köşe 12, 2 px kenarlık. "Kazandın": `primary` zemin + beyaz yazı + `ink` kenarlık. "Kaybettin": `danger` zemin + beyaz yazı + `dangerDark` kenarlık. Sabit genişlik, listedeki skor sütununun hizalı kalması içindir; etiket metni uzarsa (başka dil) genişlik gözden geçirilir.

**Maç kartı (ana ekran listesi)** – Tüm kart tek dokunma alanı (maç detayını açar). Soldan sağa: avatar 40 · ad (Nunito 16/800, tek satır, dikey ortalı; tarih yazılmaz) · skor (Fredoka 22, sabit 56 genişlik, ortalı) · sonuç etiketi · sağ ok 16. Kenarlık: kazanılan maç `mint`, kaybedilen maç `dangerSoft`. Kartlar arası 10.

**Alt gezinme** – Beyaz, üstte 2 px `mint` çizgi, yükseklik 76 (+ güvenli alan). 4 öğe: Ana Sayfa, Sıralama, Mağaza, Profil. Etkin öğe `mint` zeminli yuvarlak dikdörtgen (köşe 16), ikon + Nunito 12/800 etiket.

**Uyarı kutusu (itiraz)** – `dangerSurface` zemin, 2 px `dangerSoft` kenarlık, köşe 16. Solda `dangerDark` metin, sağda kenarlıksız, altı çizili `dangerText` eylem bağlantısı (dokunma yüksekliği 48). Cevap balonuna benzememesi için eylem **asla** kenarlıklı/dolgulu buton olmaz.

**Bağlantı uyarısı (`ConnectionBanner`)** – Maç ekranında, kendi bağlantın koptuğunda üst çubuğun hemen altında tam genişlikte ince şerit: `dangerSurface` zemin, altında 2 px `dangerSoft` çizgi, ortalı `dangerText` yazı (Nunito 13/800): "Bağlantı koptu, yeniden bağlanılıyor…", yükseklik 32. İçeriği aşağı itmez, üstüne biner. Yeniden bağlanınca şerit 200 ms'de kaybolur ve `bright` zeminli, `ink` yazılı kısa bir "Bağlandı" hapı 1.5 sn gösterilir. **[VARSAYIM]**

**Rakip bağlantı notu** – Rakibin bağlantısı koptuğunda, kendi bağlantı uyarısıyla (`ConnectionBanner`) **aynı yerde ve aynı biçimde** şerit çıkar: üst çubuğun hemen altında tam genişlikte, `dangerSurface` zemin, 2 px `dangerSoft` alt çizgi, ortalı `dangerText` Nunito 13/800 yazı: "Rakibin bağlantısı koptu", yükseklik 32, içeriği itmez. Oyuncu kartının içine not yazılmaz. Rakip dönünce şerit 200 ms'de kaybolur ("Bağlandı" hapı gösterilmez). Kendi bağlantın da kopuksa yalnızca kendi şeridin görünür, ikisi üst üste binmez. **[VARSAYIM]**

**Bölüm etiketi** – BÜYÜK HARF, Nunito 12/800, `muted`, harf aralığı 0.08em.

**Kaydırılan liste** – Kaydırma çubuğu **gösterilmez** (mobil varsayılanı; masaüstü/web derlemesinde gizlenir). Kaydırılabilir olduğunu belli etmek için listenin son görünen kartı **yarım** görünecek biçimde ekran düzenlenir.

### 6b) Global Ağ ve Çevrimdışı (Offline) Durum Yönetimi
1. **Açılışta İnternet Yoksa:** Uygulama normal menüleriyle açılmaz; tam ekran `OfflineSplashScreen` gösterilir. Wi-Fi kapalı ikonu, `noInternetTitle` ("İnternet Bağlantısı Yok"), `noInternetMessage` ve `PrimaryButton` ile `retryConnection` ("Tekrar Dene"). Bağlantı geldiğinde ekran kendiliğinden kapanır; Firebase anonim giriş ve profil senkron adımları otomatik olarak baştan çalıştırılır. "Çevrimdışı Alıştırma Yap" seçeneği bulunmaz (KelimeVS online odaklı bir oyundur).
2. **Menülerde Bağlantı Koparsa:** `MaterialApp.builder` katmanında `GlobalOfflineBanner` şeridi (`dangerSurface` zemin, `dangerSoft` 2 px alt kenarlık, `dangerText` yazı ve mini "Tekrar Dene" butonu) içeriğin üstüne binmez; `Column` içinde içeriği aşağı iter ve üst çubuktaki buton dokunuşlarını kapatmaz (`SafeArea(bottom: false)`). Sinyal dalgalanmalarını (flapping) önlemek için kopma anında 2 sn debounce uygulanır; 2 sn'den kısa süren kopmalarda şerit gösterilmez. Bağlantı gelince şerit kendiliğinden kapanır; profil, mağaza ve sıralama yükleme çarkına düşmeden arka planda güncellenir.
3. **Maç İzolasyonu:** Aktif maç ve lobi ekranlarında (`MatchScreen`, `MatchmakingScreen`, `FriendHostScreen`, `FriendJoinScreen`) global şerit bastırılır (`isOfflineBannerSuppressed`). Online maçta mevcut `ConnectionBanner` ve sunucunun 30 sn yeniden bağlanma akışı aynen korunur; bot maçında da ekran düzeni bozulmaz.
4. **Ağ Gerektiren Eylemler:** Ağ bağlantısı yokken Hızlı Maç, Arkadaşınla Oyna (Oda Kur/Katıl), Mağaza satın alma/kuşanma, Enerji paketi alma, Hesap silme ve Engelle/Bildir gibi eylemler başlatılmaz; kullanıcıya kayan SnackBar ile `noInternetActionError` ("Bu işlem için internet bağlantısı gerekiyor.") gösterilir. Hızlı Maç internetsizken gizlice bot maçına düşürmez (yalnızca online eşleşme zaman aşımı/circuit breaker durumunda bot fallback çalışır).
5. **Sunucu Sağlık Kontrolü (`GET /health`):** Cihaz Wi-Fi/hücresel ağa bağlıyken internet çıkışı olup olmadığını (captive portal vb.) doğrulamak için sunucunun `/health` uç noktasına hafif bir probe atılır. Sürekli polling yapılmaz; yalnızca ağ geçişlerinde, kullanıcı tekrar dene butonuna bastığında ve uygulama ön plana geldiğinde (`resumed`) 5 sn throttle ile kontrol edilir. Bağlantı veya zaman aşımı hatası haricinde HTTP yanıtı (404 dahil) gelirse cihaz çevrimiçi kabul edilir.

## 7. Ekranlar

Tüm ekranlar zemin `surface`, yan boşluk 20, üst 24.

**1) Ana ekran** – Üstte solda: avatar (44, dokununca profil) + oyuncu adı. Sağda sırayla: jeton hapı (`coin` daire içinde "G", sayı Fredoka 18/600, beyaz hap, 2 px `ink` kenarlık), kupa ikon butonu (alt çubuktaki Sıralama sekmesine geçiş, 44×44) ve ayarlar ikon butonu. Logo (üstten ~36 dp boşlukla ortalı), altında "Hızlı düşün, doğru yaz!" (Nunito 17/700, `muted`). Butonlar: "Hızlı Maç" (ana, alt yazı: "Rastgele bir rakiple eşleş") ve "Arkadaşınla Oyna" (ikincil, tam genişlik). **Antrenman modu yok.** Altında "SON MAÇLARIM" etiketi ve son 10 maçın kartlı, kaydırılabilir listesi. **Sıralama mutlaka en yeni maç en üstte, yukarıdan aşağıya eskiye doğrudur** (maçın bitiş zamanına göre azalan); kartlarda tarih gösterilmez.  **Altta alt gezinme çubuğu vardır** (Ana Sayfa, Sıralama, Mağaza, Profil; ana ekranda "Ana Sayfa" etkin). Üstteki avatar, kupa ve ayarlar kısayolları da korunmuştur.

**2) Eşleşme bekleme** – Sol üstte kapat. Ortada: kendi avatarın (92) · "VS" · kesik çizgili "?" avatarı. "Rakip aranıyor…" (Fredoka 30/700), altında "Birazdan başlıyoruz". Üç noktalı yükleme göstergesi (nokta renkleri `primary`/`bright`/`mint`, sırayla yanıp söner). Altta ipucu kartı ("Türkçe karakter kullanmasan da olur…") ve "Vazgeç" butonu.

**3) Maç ekranı** – Üstte kapat ikonu + "Tur 2" hapı (paydasız: maç 2 ya da 3 tur sürebildiği için "/ 3" yazılmaz). İki oyuncu kartı (bkz. oyuncu kartı; sırası olan kart süre çubuğudur). Soru kartı. Cevap geçmişi (balonlar aşağıdan yukarı birikir, en yeni en altta). Doğru olmayan denemeler de aynı listede kırmızı balonla görünür. En altta giriş alanı + gönder.

**4) Tur sonu** – Üstte "Tur N" hapı (paydasız). Ortada 104 px yuvarlak ikon, başlık, neden ve skor kartı (Fredoka 52). Altta "Tur N+1 birazdan başlıyor" ve kısa geri sayım çubuğu (**[VARSAYIM]** yaklaşık 3 sn, otomatik geçiş). Üç varyant:
- **Kazandın:** daire `bright` zemin, 4 px `ink` kenarlık ve gölge, içinde onay. Başlık "Turu kazandın!" (`ink`). Neden: "Rakibin süresi doldu".
- **Kaybettin:** daire `dangerSoft` zemin, 4 px `dangerDark` kenarlık ve gölge, içinde `dangerText` çarpı. Başlık "Turu kaybettin" (`dangerText`). Neden: "Süren doldu".
- **Beraberlik:** daire `mint` zemin, `ink` kenarlık, içinde eşit işareti. Başlık "Tur berabere" (`ink`). Neden: "Tüm cevaplar söylendi". Alt yazı "Yeni tur birazdan başlıyor" (berabere tur sayıya dahil olmadığı için tur numarası değişmez).
- Tur sonu nedeni yalnızca iki türdür: süre dolması ya da cevapların tükenmesi (beraberlik). Maçı belirleyen turdan sonra (bir oyuncu 2. galibiyetini alınca; 2–0 ya da 2–1) da bu ekran kısa süre gösterilir, alt yazı "Maç sonucu birazdan" olur; ardından maç sonucu ekranı açılır. Rakip terk ettiyse ya da oyuncu maçtan çıktıysa bu ekran atlanır.

**5) Maç sonucu** – Sol üstte kapat (ana ekrana). Ortada tur sonuyla aynı boyutta (104 px) ikon dairesi, başlık, skor ("Sen 2 – 1 Rakip"), jeton ödülü kartı. Altta "Tekrar Oyna" (ana) ve "Maç Detayı" (ikincil). Varyantlar:
- **Kazandın:** daire `bright` zemin, içinde kupa (gövdesi `coin`). Başlık "Kazandın!" (46, `ink`).
- **Kaybettin:** daire `dangerSoft` zemin, 4 px `dangerDark` kenarlık ve gölge, içinde `dangerText` "tekrar" oku. Başlık "Kaybettin" (46, `dangerText`).
- **Rakip maçı terk etti:** "Kazandın!" ve başlığın altında küçük "Rakip maçtan ayrıldı" notu. **Sen terk ettin:** "Kaybettin" ve "Maçı terk ettin" notu.
- Jeton ödülü kartı geçici içerik: ekonomi kararı verilene kadar sabit örnek değer gösterilir ve veri kaydedilmez **[VARSAYIM]**.

**6) Maç detayı** – Ana ekrandaki maç kartına ya da maç sonucu ekranındaki "Maç Detayı" butonuna dokununca açılır. Üstte geri ikon butonu + "Maç Detayı". Özet kartı: solda kendi avatarın ("Sen"), ortada skor (Fredoka 42) ve altında sonuç etiketi, sağda rakibin avatarı ve adı. Terk ya da kopma durumunda etiketin altında küçük not (12, `muted`): "Rakip maçtan ayrıldı" / "Maçı terk ettin" / "Bağlantın koptu" / "Rakibin bağlantısı koptu". Bağlantı kopması yüzünden kesinleşmemiş kayıtlarda (sunucudan kesin sonuç alınamamışsa) bu notun altına ikinci bir satır eklenir: "Skor, bağlantı kopmadan önceki duruma göredir." (12, `muted`).
- Altta tur kartları (kaydırılabilir, çubuk gizli): üstte etiket satırı "TUR N · SONUÇ" (bölüm etiketi stili; sonuç metni: KAZANDIN `primary`, KAYBETTİN `dangerText`, BERABERE ve YARIM KALDI `muted`), altında soru metni (kartın tüm genişliğini kullanır), sağda ok. Turlarda ayrı sonuç rozeti yoktur; rozet yalnızca üstteki özet kartındadır. Karta dokununca açılır/kapanır (200 ms), açık kartta ok aşağı döner. Varsayılan olarak, benim kaybettiğim son tur açık gelir; kaybettiğim tur yoksa son tur açık gelir.
- Açık turda denemeler kronolojik sırayla balon olarak görünür (kendi sağda, rakip solda; doğru: `bright` / `card`; kabul edilmeyen: kırmızı balon). Denemesi olmayan turda "Bu turda deneme yok" (12, `muted`).
- Tur sonuçları: KAZANDIN / KAYBETTİN; berabere biten tur BERABERE; maçı terk etme yüzünden yarım kalan tur YARIM KALDI (terk edilen tur KAYBETTİN sayılmaz). Gerçek bir gönderimi olmayan (boş metinli) kayıtlar listede hiç gösterilmez.
- **İtiraz:** Kendi kabul edilmeyen ("yanlış" ve "çok yakın") cevap balonuna dokunmak onu seçer; varsayılan seçili olan turdaki **son** kabul edilmeyen denemendir. Seçili balonun altında uyarı kutusu çıkar (`dangerSurface`, `dangerSoft` kenarlık): "\"X\" kabul edilmedi. Sence doğru muydu?" ve altı çizili "İtiraz et" eylemi. Gönderildikten sonra eylem "İtiraz gönderildi" (`muted`, dokunulamaz) olur. Daha önce söylenmiş cevap seçilirse kutu yalnızca "Bu cevap daha önce söylenmişti" der, eylem yoktur. Rakibin cevapları için itiraz yoktur.

Henüz çizilmemiş ekranlar (giriş, sıralama, mağaza, profil, ayarlar) ilgili fazlarda bu rehberdeki bileşenlerle tasarlanır.

**7) Profil** – Ana ekrandaki avatara dokununca açılır. Üstte geri butonu ve "Profil" başlığı. Ortada büyük harf avatarı (takma adın ilk harfi), altında takma ad (Fredoka 22/600) ve "Adı Değiştir" ikincil butonu. Altında hesap kartı: bağlı değilse "Google ile Bağla" ikincil butonu; bağlıysa Google e-postası, onay rozeti ve `dangerSurface`/`dangerText` stilinde "Çıkış Yap". Çıkış ve hesap değiştirme onay diyalogları veri kaybı uyarısı içerir.

**8) Liderlik tablosu** – Alt gezinmedeki "Sıralama" sekmesinde ya da ana ekrandaki kupa butonuyla açılır (kupa butonu alt çubukta bu sekmeye geçer). Sekmede açıldığında geri butonu bulunmaz (yalnızca harici bir push rotasından açılırsa geri butonu görünür). Üstte "Haftalık Sıralama" başlığı. Altında "Bu hafta" ve kalan süreyi gösteren hap şeklinde şerit (kart zemini, `mint` kenarlık). Liste: ilk 50 oyuncu; satırda sıra, harf avatarı (36), takma ad ve galibiyet sayısı. İlk üç sıra için sade madalya/kupa vurgusu (1. `coin` sarısı). Kendi satırın `surface` zemin ve `mint` kenarlıkla vurgulanır. İlk 50 dışındaysan listenin altında sabit "Senin sıran" çubuğu (kart zemini, sert gölge). Boş durum: "Bu hafta henüz maç yok". Hata durumunda "Tekrar Dene" butonu. Yalnızca haftalık galibiyetler listelenir (GDD bölüm 5.4).

**9) Mağaza** – Alt gezinmedeki "Mağaza" sekmesinde açılır. Üstte "Mağaza" başlığı (Fredoka 28/700) ve sağda ana ekrandakiyle aynı jeton hapı (bakiye satın alma sonrası anında güncellenir). Başlığın altında kategori sekmeleri vardır (bkz. 9a); aşağıdaki çerçeve ızgarası **"Çerçeve" sekmesindedir**. Sekmenin içinde "AVATAR ÇERÇEVELERİ" etiketi (`muted`, etiket stili) ve ürün ızgarası: 2 sütun, aralık 12, yan boşluk 20. Her ürün bir **çerçeve kartıdır** (`card` zemin, 2 px `ink` kenarlık, köşe 20): üstte oyuncunun **kendi avatarı** (72, harfiyle) çerçeve takılı halde önizlenir, altında çerçeve adı (Nunito 15/800) ve en altta duruma göre bir alan:
- **Sahip değil, jeton yeter:** fiyat hapı (`coin` simgesi + sayı, Fredoka 16/600). Dokununca satın alma sayfası açılır.
- **Sahip değil, jeton yetmez:** fiyat hapı soluk. Dokununca "Yetersiz jeton" ipucu (SnackBar), sayfa açılmaz.
- **Sahip, kuşanılmamış:** "Kuşan" ikincil butonu (küçük, yükseklik 40).
- **Kuşanılmış:** "Kuşanıldı" etiketi (`primary` yazı, tik ikonu) ve kartın kenarlığı `primary` olur.

**Satın alma sayfası (alttan açılan sayfa):** büyük avatar önizlemesi (104), çerçeve adı, fiyat hapı, "Satın Al" (ana buton) ve "Vazgeç" (ikincil). Başarılı olunca sayfa kapanır, SnackBar ("Çerçeve satın alındı"), kart "Kuşan" durumuna geçer; otomatik kuşanma yoktur. Satın alma sunucuda yapılır, ağ hatasında anlaşılır Türkçe mesaj gösterilir ve jeton düşmez.

**Çerçeve kataloğu [VARSAYIM]:** katalog ve fiyatlar sunucuda tutulur (istemciye mesajla gelir), kodda sabit değildir. İlk liste: Klasik (ücretsiz, varsayılan: mevcut 3 px `ink` kenarlık), Nane 100, Gün Batımı 150, Okyanus 150, Altın 300, Neon 300, Gökkuşağı 500, Elmas 800. Her çerçeve avatar etrafında yalnızca renk/doku değiştirir; boyut ve okunabilirlik aynı kalır (içerideki harf her zaman `ink`/beyaz kuralına uyar). Çerçeveler yalnızca kozmetiktir, oyun dengesini etkilemez.

**Çerçevenin göründüğü yerler:** kendi avatarın (ana ekran, profil, maç kartı), maçtaki rakibin avatarı, liderlik tablosu satırı, maç detayı. Rakip kendi kuşandığı çerçeveyle görünür. Bot rakiplerde çerçeve, gerçek oyuncu dağılımına benzer şekilde (çoğunlukla Klasik, ara sıra diğerleri) rastgele atanır; böylece bot ayrıt edilemez ([KARAR] bot etiketlenmez).

**9a) Mağaza sekmeleri ve enerji [VARSAYIM]** – Mağaza başlığının altında yatay, kaydırılabilir bir **sekme şeridi** bulunur: **Jeton · Enerji · Çerçeve**. Sekmeler hap şeklindedir (yükseklik 40, köşe 20, 2 px `ink` kenarlık). Etkin sekme `primary` zemin + beyaz yazı, etkin olmayan `card` zemin + `ink` yazı (Nunito 14/800). Seçili sekme oturum içinde hatırlanır, mağaza açılışında varsayılan sekme "Çerçeve"dir. Her sekmenin içeriği ayrı kaydırılır, sekme şeridi sabit kalır.
- **Jeton sekmesi (şimdilik "Yakında"):** Gerçek parayla jeton satışı ayrı bir aşamadır (Play faturalandırma). Bu sekmede tek bir bilgi kartı bulunur: jeton simgesi, "Jeton paketleri çok yakında" başlığı (Fredoka 20/700) ve kısa açıklama. Satın alma düğmesi ya da sahte fiyat gösterilmez.
- **Enerji sekmesi:** Yalnızca sunucudaki enerji sistemi açıkken görünür; kapalıyken sekme hiç gösterilmez. Üstte büyük **enerji kartı**: yıldırım simgeli enerji hücreleri (en fazla 5; dolu hücre `coin` zemin, boş hücre `mint` kenarlık + `card` zemin), altında "3 / 5" (Fredoka 28/700) ve eksikse "Sonraki enerji: 12:30" geri sayımı (Nunito 14/700, `muted`). Altında jetonla enerji paketi kartları (bkz. 9b). Enerji doluysa paket düğmeleri pasif olur ve "Enerjin dolu" yazar.
- **Çerçeve sekmesi:** Yukarıdaki 9) Mağaza ızgarası.

**9b) Enerji kuralları ve ekranları [VARSAYIM]** – Enerji yalnızca **gerçek rakiple oynanan online hızlı maçı** sınırlar. Bot maçı ve arkadaş düellosu enerji harcamaz (zaten jeton vermezler). Değerler sunucuda ortam değişkenidir, kodda sabit değildir.
- En fazla **5** enerji; her gerçek online maç başladığında (eşleşme olduğunda) **1** enerji düşer. Eşleşme bulunamayıp bota geçilirse enerji düşmez. Maç başlar başlamaz istemcide enerji hapı ve enerji sekmesi güncellenir (sunucu güncel enerjiyi eşleşme mesajıyla bildirir). Enerji **20 dakikada 1** yenilenir (en fazla 5'e kadar, çevrimdışıyken de ilerler).
- Jetonla enerji paketleri: **1 enerji = 20 jeton**, **5 enerji (tam doldur) = 80 jeton**. Paket kartı: yıldırım ikonu, "+1 Enerji" / "Tam Doldur", fiyat hapı (`coin`). Bakiye yetmezse hap soluk ve dokununca "Yetersiz jeton" ipucu.
- **Ana ekran:** Enerji açıkken jeton hapının yanında küçük bir **enerji hapı** (yıldırım ikonu + "3", aynı 2 px `ink` kenarlıklı hap). Dokununca mağazanın "Enerji" sekmesi açılır. Enerji kapalıyken hap gösterilmez.
- **Enerjin bitti sayfası:** Enerji 0 iken "Hızlı Maç"a basılırsa alttan sayfa açılır: başlık "Enerjin bitti" (Fredoka 24/700), "Sonraki enerji: 14 dk" geri sayımı, üç buton: "1 Enerji · 20" (ana), "Botla Oyna" (ikincil) ve "Vazgeç" (metin butonu). Jetonla alım yapılırsa sayfa kapanır ve eşleşme aranmaya devam eder.
- **Eşleşme bekleme ekranı:** Enerji açıkken aramaya girerken enerji düşmez, yalnızca maç gerçekten başlayınca düşer (bu yüzden kullanıcıya "enerji harcanacak" uyarısı gösterilmez).
- **Rakip terk ederse:** Maçı terk eden (maçtan çıkan ya da bağlantısı kopup 30 saniyelik süre içinde dönmeyen, yani kopma yenilgisi alan) oyuncu enerjisini kaybeder; maçta kalan oyuncuya **1 enerji iade edilir**. Normal süre aşımı (cevap vermeme) terk sayılmaz, o durumda iade yoktur. Oyuncu kendi bağlantısını kaybedip süre içinde dönerse enerjisi düşmüş kalır, maç normal devam eder.
- **Özellik anahtarı:** Enerji sistemi sunucuda `ENERGY_ENABLED` anahtarıyla açılıp kapanır. Varsayılan **kapalı**. Kapalıyken enerji hapı, Enerji sekmesi ve "Enerjin bitti" akışı görünmez, tüm maçlar sınırsızdır.

## 8. Hareket (animasyon)

- Süreler kısa: dokunma geri bildirimi 80–100 ms, geçişler 200–250 ms, sonuç ekranı girişi 300–400 ms.
- Süre dolgusu sunucu zamanına göre **ilerler** (telefon saati değil); küçük sapmalar yumuşakça düzeltilir.
- Doğru cevap: balon aşağıdan yukarı kayarak girer (200 ms). Yanlış cevap: giriş alanı hafifçe sallanır (250 ms) ve kenarlık kısa süre `danger` olur. Yanlış ya da tekrar eden cevap turu kaybettirmez: süre akmaya devam eder, giriş alanı temizlenir ve odak korunur (klavye kapanmaz). "Çok yakın!" ipucu kısa bir geri bildirim olarak giriş alanının üstünde gösterilir (tasarımı maç ekranı adımında yapılacak).
- Hareket azaltma ayarı açıksa animasyonlar sadeleşir (kaydırma/sallanma yok, sadece geçiş).
- Ses ve titreşim: **[AÇIK]** henüz karar yok.

## 9. Metin ve dil

- Arayüz dili Türkçe. Tüm metinler tek bir dosyada toplanır (sonradan çeviri/yerelleştirme kolaylığı için); widget içinde sabit metin bırakılmaz.
- Ton: kısa, samimi, "sen" hitabı. Ünlem sadece kutlamada ("Kazandın!").

## 10. Erişilebilirlik

- Metin kontrastı en az 4.5:1 (büyük metin 3:1). Mevcut palet bunu sağlar; yeni renk eklenirse kontrol edilir.
- Sonuç, ikon ve renkle birlikte metinle de verilir.
- İkon butonlara anlamlı etiket (örn. "Maçtan çık", "Gönder").
- Sistem yazı boyutu büyütülünce düzen taşmamalı; sabit yükseklikli metin kutusu yok (sabit yükseklik sadece butonlarda).

## 11. Antigravity'ye kodlatma kuralları

1. **Her seferinde tek ekran.** Önce tema dosyası (renkler, yazı stilleri, ölçüler), sonra ortak bileşenler, sonra ekranlar.
2. Renk, boyut ve yazı stilleri yalnızca tema dosyasından gelir. Elle renk kodu yazma.
3. Her ekran bittiğinde `docs/design/` içindeki ilgili ekran görüntüsüyle yan yana karşılaştırılır; fark varsa düzeltilir.
4. Rehberde olmayan bileşen, renk veya özellik **eklenmez**. Gerekirse önce bu dosyaya eklenmesi istenir.
5. Süre, sıra ve cevap doğrulaması arayüzde yapılmaz; arayüz sunucudan gelen durumu çizer (`GDD.md` bölüm 3–5).
6. Yeni paket eklenirken iOS desteği kontrol edilir.
7. Her adım Git'e kısa, İngilizce, Conventional Commits biçiminde kaydedilir (örn. `feat(app): add match screen layout`).

## 12. Açık noktalar

1. Ses, titreşim ve oyun içi efektler
2. Koyu tema (v1'de yok, sonradan gerekirse jetonlar karşılıklarıyla eklenir)
3. Kayıp varyantları (tur sonu, maç sonucu) ve eşleşme sonrası geçiş ekranı
4. Giriş ve ayarlar ekranları (sıralama, profil ve mağaza tasarlandı)
5. Kalan süre uyarısı eşiği (5 sn) ve renk geçişi
