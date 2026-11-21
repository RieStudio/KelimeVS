# Takma Ad Küfür ve Uygunsuz Kelime Filtresi (Nickname Filter)

Bu doküman, KelimeVS sisteminde takma adlarda (kullanıcı adları) küfür, hakaret, cinsel içerik ve nefret söylemini engelleyen yetkili sunucu filtre mekanizmasını, kelime listelerinin yönetimini ve normalizasyon kurallarını açıklar.

---

## 1. Mimari Genel Bakış ve Temel Prensipler

1. **Sunucu Yegane Yetkilidir (Server-Authoritative):**
   - Küfür ve filtre kelime listeleri **YALNIZCA** sunucuda (`server/src/engine/nicknameBlocklist/`) barındırılır.
   - İstemci (mobil uygulama) paketine kesinlikle kelime listesi dahil edilmez.
   - Bu sayede kelime listesi güncellemesi için App Store / Google Play uygulama güncellemesine ihtiyaç yoktur; yalnızca sunucunun deploy edilmesi (`server/` içinde `npm run deploy`) yeterlidir.

2. **Gizlilik ve Güvenlik:**
   - Filtreye takılan bir takma ad için sunucu `422 Unprocessable Entity` durum koduyla `{ "error": "nickname_blocked", "message": "Bu takma ad kullanılamaz." }` yanıtı döner.
   - Eşleşen kelimenin ne olduğu ne HTTP yanıtında ne de sunucu loglarında **asla** ifşa edilmez.
   - Reddedilen uygunsuz ad denemeleri, kullanıcının 24 saatlik kayan penceredeki başarılı ad değiştirme hakkını (sliding window kotasını) **tüketmez**.

3. **İstemci Deneyimi:**
   - İstemci hem onboarding (ilk takma ad belirleme) ekranında hem de profil takma ad değiştirme penceresinde sunucudan gelen `nickname_blocked` hatasını yakalayarak satır içi (inline) olarak **"Bu takma ad kullanılamaz"** uyarısını gösterir.
   - Ağ hataları (`ProfileUpdateNetworkError`) çevrimdışı dayanıklılık gereği yerelde saklanıp arka planda senkronizasyona bırakılırken, filtre hatası anında kullanıcıya bildirilir.

4. **Mevcut Kullanıcılar:**
   - Bu kontrol yalnızca yeni takma ad seçme veya ad değiştirme denemelerinde devreye girer. Mevcut kullanıcıların takma adlarına geriye dönük otomatik müdahale yapılmaz. (İleride gerekirse mevcut hesaplar için pasif tarama/raporlama aracı çalıştırılabilir).

---

## 2. Üç Liste Mimarisi (`server/src/engine/nicknameBlocklist/`)

Kelime listeleri yanlış pozitifleri (masum adların engellenmesi) minimumda tutmak ve kaçırma denemelerini engellemek amacıyla üç ayrı kategoriye ayrılmıştır:

| Dosya | Tür | Açıklama ve Amaç | Örnekler |
| :--- | :--- | :--- | :--- |
| `contains.ts` | **İçerme (Substring)** | Normalleştirilmiş takma adın **herhangi bir yerinde** geçerse adı engeller. Masum Türkçe veya İngilizce kelimelerde rastlanmayan güçlü kökler buraya eklenir. | `orospu`, `sikerim`, `siktir`, `yavsak`, `pezevenk`, `fuck`, `bitch`, `cunt` |
| `exact.ts` | **Tam Eşleşme (Exact)** | Yalnızca takma ad (veya sondaki rakamlar atıldıktan sonraki hali) kelimenin **tamamı** ise engeller. Kısa (2-4 harfli) ve masum kelimelerin içinde geçebilen kökler buraya eklenir. | `am`, `sik`, `pic`, `got`, `bok`, `mal`, `ass`, `dick` |
| `allow.ts` | **İzin Verilenler (Allow/Mask)** | Bilinen yanlış pozitifleri önlemek için güvenli kelime listesi. `contains` kontrolünden önce bu kelimeler metinden maskelenir (`*` ile ayrılır). | `kemal`, `cemal`, `damla`, `kamil`, `fistik`, `kasik`, `klasik`, `sarimsak`, `eksik`, `fizik`, `siklamen` |

### Neden `am`, `sik`, `mal`, `bok` gibi kökler `exact.ts` dosyasındadır?
- Eğer `am` contains listesine konsaydı; `Damla`, `Kamil`, `Samet`, `Amiral`, `Hamur`, `Tamam` gibi onlarca masum isim ve kelime engellenirdi.
- Eğer `sik` contains listesine konsaydı; `Fıstık` (fistik), `Kaşık` (kasik), `Klasik`, `Lastik`, `Eksik`, `Fizik`, `Sarımsak` gibi kelimeler engellenirdi.
- `exact.ts` sayesinde tek başına `am`, `a_m`, `am99`, `pic123`, `got_06` gibi adlar engellenirken; `Damla`, `Fıstık_99`, `Kemal` gibi adlar sorunsuz kabul edilir.

---

## 3. Normalizasyon Motoru (`normalizeForFilter`)

Kullanıcının girdiği ad ile blok listesindeki kelimeler aynı tekil normalizasyon fonksiyonundan geçirilir:

1. **Unicode NFKC:** Karakter bileşenleri standart formata indirgenir.
2. **Türkçe Farkındalıklı Küçük Harf:** `İ`, `I`, `ı`, `i` karakterlerinin tümü Türkçe kurallarına uygun olarak `i` harfine çevrilir ve `.toLowerCase()` uygulanır.
3. **Türkçe Karakter ve Aksan Sadeleştirme:** `ş->s`, `ğ->g`, `ü->u`, `ö->o`, `ç->c`, `ı->i`, `â->a`, `î->i`, `û->u` ve birleşik aksan işaretleri temizlenir.
4. **Leetspeak ve Sembol Eşleme:**
   - `0` -> `o`
   - `1` -> `i`
   - `3` -> `e`
   - `4` -> `a`
   - `5` -> `s`
   - `7` -> `t`
   - `9` -> `g`
   - `@` -> `a`
   - `$` -> `s`
   - `!` -> `i`
   - `|` -> `i`
   - `+` -> `t`
5. **Ayraç ve Görünmez Karakter Temizliği:** Boşluk, nokta (`.`), alt çizgi (`_`), tire (`-`) ve tüm sıfır genişlikli karakterler (`\u200B-\u200F`, `\uFEFF`, soft hyphen vb.) atılır.
6. **Harf Tekrarlarının İndirgenmesi (Dedup):** Üst üste tekrarlanan harfler teke indirilir (`aaa -> a`, `oo -> o`, `orooosspuuu -> orospu`).

---

## 4. Listeye Yeni Kelime Ekleme Adımları

Yeni bir kelime eklemek veya hatalı engellenen bir kelimeyi serbest bırakmak oldukça basittir:

### Adım 1: Doğru Listeyi Seçin
- Kelime güçlü, bileşik bir küfür ise (başka bir masum kelimenin parçası olamaz): `server/src/engine/nicknameBlocklist/contains.ts`
- Kelime kısa (2-4 harf) veya masum bir kelimenin içinde geçebilecek bir kök ise: `server/src/engine/nicknameBlocklist/exact.ts`
- Normalde masum olan bir isim/kelime yanlışlıkla engelleniyorsa: `server/src/engine/nicknameBlocklist/allow.ts`

### Adım 2: Kelimeyi Ekleyin
Dosyayı açıp diziye string olarak ekleyin:
```ts
export const CONTAINS_WORDS: readonly string[] = [
  ...
  'yeni_kufur',
];
```
> **İpucu:** Büyük/küçük harf, Türkçe karakter varyasyonu (ş, ğ vb.) veya leetspeak (0, 1 vb.) varyasyonlarını yazmanıza gerek yoktur. Filtre motoru girdiyi ve listeyi otomatik olarak normalize eder.

### Adım 3: Test Edin
`server/` dizininde testleri çalıştırın:
```bash
npm --prefix server test test/nicknameFilter.test.ts
```

### Adım 4: Sunucuya Dağıtın (Deploy)
```bash
npm --prefix server run deploy
```
Mobil uygulamaya güncelleme göndermenize **gerek yoktur**; tüm kullanıcılar anında yeni listeden etkilenir.

---

## 5. Maç İçi Küfür Maskeleme (In-Game Text Masker - Faz 1)

Maç içi serbest cevaplarda (özellikle yanlış cevap balonlarında) küfür ve hakaretlerin karşı oyuncuya gösterilmesini engellemek için **`server/src/engine/textMasker.ts`** devrededir.

### 5.1. Temel İlkeler ve Davranış
1. **Aynı Blok Listeleri ve Normalizasyon:**
   - Maç içi maskeleyici de aynı `server/src/engine/nicknameBlocklist/` dosyalarını (`contains.ts`, `exact.ts`, `allow.ts`) ve aynı `normalizeForFilter` fonksiyonunu kullanır. Liste tek bir merkezden yönetilir.
2. **Sözcük Bazlı Eşleştirme (Word-Boundary Matching):**
   - Takma ad filtresinden farklı olarak metindeki boşluklar toptan silinmez; cümle sözcük sınırlarına ve ayraçlara göre ayrılır.
   - Bu sayede sözlükte yer alan "tuşlu telefon", "Windows 3 1", "Perran Kutman" gibi masum birleşik kelimelerin kelime aralığı çakışmalarından dolayı yanlış pozitif (false positive) üretmesi engellenir.
3. **Aralıklı Tek Harf Yakalama:**
   - `s i k`, `s  i  k`, `o . r . o . s . p . u` gibi harfler arasına boşluk veya ayraç konularak kaçılmaya çalışılan yazımlar tespit edilip tek aday olarak denetlenir ve ilgili aralığın tamamı maskelenir.
4. **Maske Biçimi:**
   - İlk Unicode karakteri (büyük/küçük harf ve Türkçe karakter özellikleri: `Ş`, `ş`, `İ`, `ı`, `ç`, `ö`, `ü`, `ğ` vb. korunur) + kelimenin geri kalan uzunluğu kadar `*` (örn. `orospu` $\rightarrow$ `o*****`, `Şerefsiz` $\rightarrow$ `Ş*******`, `sik99` $\rightarrow$ `s****`).
5. **Oyun Mantığı ve Depolama Kesintiye Uğramaz:**
   - Oyun motoru (`engine.ts`), puanlama, tur geçişleri, veritabanı kayıtları (`MatchRoom` durumu ve `REPORT_STORE` için tutulan cevaplar) **ham metinle** çalışmaya devam eder.
   - Maskeleme yalnızca istemciye giden DTO üretim katmanında (`toClientAttempt`) ve **yalnızca karşı oyuncunun denemeleri (`mine: false`)** için uygulanır.
   - Oyuncunun kendi yazdığı cevaplar (`mine: true`) ve itiraz kutusu (`MatchDetailScreen._buildObjectionBox`) ham kalır.
6. **Dağıtım (Deployment):**
   - Liste güncellemeleri veya maskeleme kuralları için yalnızca `server/` dizininde `npm run deploy` yeterlidir; mobil uygulamaya paket güncellemesi **gerekmez**.

