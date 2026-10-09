# Kelime Go – Tasarım Rehberi (DESIGN.md)

> Taslak 0.1 · Tarih: 6 Ekim 2026
> Bu dosya `GDD.md` ile birlikte kodlamadan önce okunur. Arayüz kodu bu dosyayla çelişmemelidir.
> Görsel referans: `docs/design/` klasöründeki ekran görüntüleri (6 ekran). Rehber ile görüntü çelişirse görüntü kazanır.
> İşaretler: **[KARAR]** onaylı · **[VARSAYIM]** onay bekliyor

---

## 1. Tasarım dili

- **Hava:** Eğlenceli, renkli, çizgi film hissi. Kalın koyu kenarlıklar, yuvarlak köşeler, altta sert gölge ("basılabilir" butonlar).
- **Renk yönü:** Beyaz ve yeşil. Sıcak vurgu olarak tek bir sarı (jeton). Kırmızı sadece olumsuz durumlar için.
- **Maskot yok.** Kimlik tamamen tipografi ve ikonlarla kurulur.
- **Logo:** `Kelime` + `Go`. "Go" yazısı "Kelime" ile aynı boyutta ve kalınlıkta, yeşil renkte; arkasında açık nane yeşili, yuvarlatılmış, sağa bakan bir oynat (play) üçgeni durur. Üçgenin kenarlığı ve gölgesi yoktur. Logo eğik ya da döndürülmüş olmaz.

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

**Cevap balonu** – Nunito 15/800, dolgu: kendi cevabın `bright`, rakip cevabı `card`; 2 px `ink` kenarlık, köşe 14, iç boşluk 7×14, en geniş %78. Kendi cevabın sağa, rakibinki sola hizalanır. Kabul edilmeyen cevaplar (yanlış, tekrar, "çok yakın" olsa bile) listede iki oyuncuya da gösterilir; balonun kenarlığı `danger`, yazısı `dangerText`, zemini `card` olur. Kendi reddedilen cevabın sağda, rakibinki solda durur. Metin en fazla 40 karakter. Yok sayılan (hız/sayı sınırına takılan) denemeler listede görünmez.

**Giriş alanı** – Yükseklik 54, 3 px `ink` kenarlık, köşe 18, Nunito 16/700, ipucu: "Cevabını yaz…". Yanında 54×54 gönder butonu (`primary`, beyaz ok, gölge `0 4px 0 ink`). Otomatik düzeltme ve öneri kapalı; klavye "gönder" eylemiyle de gönderilir.

**Sonuç etiketi (`ResultBadge`)** – Genişlik **88 (sabit)**, yazı ortalı, Nunito 12/800, köşe 12, 2 px kenarlık. "Kazandın": `primary` zemin + beyaz yazı + `ink` kenarlık. "Kaybettin": `danger` zemin + beyaz yazı + `dangerDark` kenarlık. Sabit genişlik, listedeki skor sütununun hizalı kalması içindir; etiket metni uzarsa (başka dil) genişlik gözden geçirilir.

**Maç kartı (ana ekran listesi)** – Tüm kart tek dokunma alanı (maç detayını açar). Soldan sağa: avatar 40 · ad (Nunito 16/800) ve altında tarih (12, `muted`) · skor (Fredoka 22, sabit 56 genişlik, ortalı) · sonuç etiketi · sağ ok 16. Kenarlık: kazanılan maç `mint`, kaybedilen maç `dangerSoft`. Kartlar arası 10.

**Alt gezinme** – Beyaz, üstte 2 px `mint` çizgi, yükseklik 76 (+ güvenli alan). 4 öğe: Ana Sayfa, Sıralama, Mağaza, Profil. Etkin öğe `mint` zeminli yuvarlak dikdörtgen (köşe 16), ikon + Nunito 12/800 etiket.

**Uyarı kutusu (itiraz)** – `dangerSurface` zemin, 2 px `dangerSoft` kenarlık, köşe 16. Solda `dangerDark` metin, sağda kenarlıksız, altı çizili `dangerText` eylem bağlantısı (dokunma yüksekliği 48). Cevap balonuna benzememesi için eylem **asla** kenarlıklı/dolgulu buton olmaz.

**Bölüm etiketi** – BÜYÜK HARF, Nunito 12/800, `muted`, harf aralığı 0.08em.

**Kaydırılan liste** – Kaydırma çubuğu **gösterilmez** (mobil varsayılanı; masaüstü/web derlemesinde gizlenir). Kaydırılabilir olduğunu belli etmek için listenin son görünen kartı **yarım** görünecek biçimde ekran düzenlenir.

## 7. Ekranlar

Tüm ekranlar zemin `surface`, yan boşluk 20, üst 24.

**1) Ana ekran** – Üstte: avatar (44) + oyuncu adı + jeton hapı (`coin` daire içinde "G", sayı Fredoka 18/600, beyaz hap, 2 px `ink` kenarlık) + ayarlar ikon butonu. Logo (üstten ~36 dp boşlukla ortalı), altında "Hızlı düşün, doğru yaz!" (Nunito 17/700, `muted`). Butonlar: "Hızlı Maç" (ana, alt yazı: "Rastgele bir rakiple eşleş") ve "Arkadaşınla Oyna" (ikincil, tam genişlik). **Antrenman modu yok.** Altında "SON MAÇLARIM" etiketi ve son 10 maçın kartlı, kaydırılabilir listesi. En altta alt gezinme.

**2) Eşleşme bekleme** – Sol üstte kapat. Ortada: kendi avatarın (92) · "VS" · kesik çizgili "?" avatarı. "Rakip aranıyor…" (Fredoka 30/700), altında "Birazdan başlıyoruz". Üç noktalı yükleme göstergesi (nokta renkleri `primary`/`bright`/`mint`, sırayla yanıp söner). Altta ipucu kartı ("Türkçe karakter kullanmasan da olur…") ve "Vazgeç" butonu.

**3) Maç ekranı** – Üstte kapat ikonu + "Tur 2 / 3" hapı. İki oyuncu kartı (bkz. oyuncu kartı; sırası olan kart süre çubuğudur). Soru kartı. Cevap geçmişi (balonlar aşağıdan yukarı birikir, en yeni en altta). Doğru olmayan denemeler de aynı listede kırmızı balonla görünür. En altta giriş alanı + gönder.

**4) Tur sonu** – Üstte "Tur N / 3" hapı. Ortada 104 px yuvarlak ikon, başlık, neden ve skor kartı (Fredoka 52). Altta "Tur N+1 birazdan başlıyor" ve kısa geri sayım çubuğu (**[VARSAYIM]** yaklaşık 3 sn, otomatik geçiş). Üç varyant:
- **Kazandın:** daire `bright` zemin, 4 px `ink` kenarlık ve gölge, içinde onay. Başlık "Turu kazandın!" (`ink`). Neden: "Rakibin süresi doldu".
- **Kaybettin:** daire `dangerSoft` zemin, 4 px `dangerDark` kenarlık ve gölge, içinde `dangerText` çarpı. Başlık "Turu kaybettin" (`dangerText`). Neden: "Süren doldu".
- **Beraberlik:** daire `mint` zemin, `ink` kenarlık, içinde eşit işareti. Başlık "Tur berabere" (`ink`). Neden: "Tüm cevaplar söylendi". Alt yazı "Yeni tur birazdan başlıyor" (berabere tur sayıya dahil olmadığı için tur numarası değişmez).
- Tur sonu nedeni yalnızca iki türdür: süre dolması ya da cevapların tükenmesi (beraberlik). Maçın **son** sonuçlanan turundan sonra da bu ekran kısa süre gösterilir, alt yazı "Maç sonucu birazdan" olur; ardından maç sonucu ekranı açılır. Rakip terk ettiyse ya da oyuncu maçtan çıktıysa bu ekran atlanır.

**5) Maç sonucu** – Sol üstte kapat (ana ekrana). Ortada tur sonuyla aynı boyutta (104 px) ikon dairesi, başlık, skor ("Sen 2 – 1 Rakip"), jeton ödülü kartı. Altta "Tekrar Oyna" (ana) ve "Maç Detayı" (ikincil). Varyantlar:
- **Kazandın:** daire `bright` zemin, içinde kupa (gövdesi `coin`). Başlık "Kazandın!" (46, `ink`).
- **Kaybettin:** daire `dangerSoft` zemin, 4 px `dangerDark` kenarlık ve gölge, içinde `dangerText` "tekrar" oku. Başlık "Kaybettin" (46, `dangerText`).
- **Rakip maçı terk etti:** "Kazandın!" ve başlığın altında küçük "Rakip maçtan ayrıldı" notu. **Sen terk ettin:** "Kaybettin" ve "Maçı terk ettin" notu.
- Jeton ödülü kartı geçici içerik: ekonomi kararı verilene kadar sabit örnek değer gösterilir ve veri kaydedilmez **[VARSAYIM]**.

**6) Maç detayı** – Ana ekrandaki maç kartına ya da maç sonucu ekranındaki "Maç Detayı" butonuna dokununca açılır. Üstte geri ikon butonu + "Maç Detayı". Özet kartı: solda kendi avatarın ("Sen"), ortada skor (Fredoka 42) ve altında sonuç etiketi, sağda rakibin avatarı ve adı. Terk durumunda etiketin altında küçük not ("Rakip maçtan ayrıldı" / "Maçı terk ettin", 12, `muted`).
- Altta tur kartları (kaydırılabilir, çubuk gizli): üstte etiket satırı "TUR N · SONUÇ" (bölüm etiketi stili; sonuç metni: KAZANDIN `primary`, KAYBETTİN `dangerText`, BERABERE ve YARIM KALDI `muted`), altında soru metni (kartın tüm genişliğini kullanır), sağda ok. Turlarda ayrı sonuç rozeti yoktur; rozet yalnızca üstteki özet kartındadır. Karta dokununca açılır/kapanır (200 ms), açık kartta ok aşağı döner. Varsayılan olarak, benim kaybettiğim son tur açık gelir; kaybettiğim tur yoksa son tur açık gelir.
- Açık turda denemeler kronolojik sırayla balon olarak görünür (kendi sağda, rakip solda; doğru: `bright` / `card`; kabul edilmeyen: kırmızı balon). Denemesi olmayan turda "Bu turda deneme yok" (12, `muted`).
- Tur sonuçları: KAZANDIN / KAYBETTİN; berabere biten tur BERABERE; maçı terk etme yüzünden yarım kalan tur YARIM KALDI (terk edilen tur KAYBETTİN sayılmaz). Gerçek bir gönderimi olmayan (boş metinli) kayıtlar listede hiç gösterilmez.
- **İtiraz:** Kendi kabul edilmeyen ("yanlış" ve "çok yakın") cevap balonuna dokunmak onu seçer; varsayılan seçili olan turdaki **son** kabul edilmeyen denemendir. Seçili balonun altında uyarı kutusu çıkar (`dangerSurface`, `dangerSoft` kenarlık): "\"X\" kabul edilmedi. Sence doğru muydu?" ve altı çizili "İtiraz et" eylemi. Gönderildikten sonra eylem "İtiraz gönderildi" (`muted`, dokunulamaz) olur. Daha önce söylenmiş cevap seçilirse kutu yalnızca "Bu cevap daha önce söylenmişti" der, eylem yoktur. Rakibin cevapları için itiraz yoktur.

Henüz çizilmemiş ekranlar (giriş, sıralama, mağaza, profil, ayarlar) ilgili fazlarda bu rehberdeki bileşenlerle tasarlanır.

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
4. Giriş, sıralama, mağaza, profil, ayarlar ekranları
5. Kalan süre uyarısı eşiği (5 sn) ve renk geçişi
