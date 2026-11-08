# KelimeGo Eşleştirme ve Canlı Maç Sunucusu

Bu sunucu, Cloudflare Workers ve Durable Objects (SQLite depolamalı) üzerinde çalışan, KelimeGo çok oyunculu kelime oyununun eşleştirme (matchmaking) ve canlı maç yönetimi motorudur.

---

## 🚀 Başlangıç ve Kurulum

### Gereksinimler
- Node.js >= 20.x (Node.js 24 önerilir)
- npm >= 9.x

### Bağımlılıkların Yüklenmesi
```bash
cd server
npm install
```

---

## ⚙️ Yapılandırma (`.dev.vars` & `wrangler.jsonc`)

Yerel geliştirme ortamında gizli anahtarlar ve geliştirme bayrakları `.dev.vars` dosyasında tutulur (`.gitignore` ile versiyon kontrolü dışındadır).

Örnek `server/.dev.vars`:
```env
ALLOW_DEV_AUTH=true
FAST_TIMERS=true
FIREBASE_PROJECT_ID=kelimegov2
CONTENT_SOURCE=dev
FIREBASE_DATABASE_URL=https://kelimegov2-default-rtdb.europe-west1.firebasedatabase.app
CONTENT_TTL_SECONDS=3600
FIREBASE_SERVICE_ACCOUNT_B64=<base64-encoded-service-account-json>
```

- **`ALLOW_DEV_AUTH=true`**: Geliştirme ortamında `dev:<uid>` biçimindeki test token'larının kabul edilmesini sağlar (Örn: `dev:alice` veya `?token=dev:alice`). Üretim yapılandırmasında (`wrangler.jsonc`) asla yer almaz.
- **`FAST_TIMERS=true`**: Testleri ve E2E akışlarını saniyeler içinde tamamlamak üzere hamle süresini (15s -> 3s), tur geçişini (2s -> 500ms) ve bağlantı kopma süresini (30s -> 3s) hızlandırır.
- **`CONTENT_SOURCE`**: Yalnızca `"dev"` değeri alabilir ve YALNIZCA `ALLOW_DEV_AUTH=true` iken dikkate alınır (bu durumda yerel `DevContentProvider` çalışır, E2E testleri internetsiz çalışabilir). Aksi halde veya üretimde her zaman `RealtimeDbContentProvider` kullanılır.
- **`FIREBASE_DATABASE_URL`**: Firebase Realtime Database kök adresi.
- **`CONTENT_TTL_SECONDS`**: Bellek içi soru havuzu önbellek süresi (saniye cinsinden, varsayılan 3600).
- **`FIREBASE_SERVICE_ACCOUNT_B64`**: Sunucunun Realtime Database REST API'sine erişmek için kullandığı Google servis hesabı JSON dosyasının Base64 hali.
- **`LEADERBOARD_PAIR_WIN_CAP`**: Sıralama tablosunda aynı rakibe karşı haftada en fazla kaç galibiyetin sayılabileceğini (anti-farming) belirler. Belirtilmezse veya geçersizse varsayılan **20**'dir. Değer olarak **0** veya negatif bir sayı verildiğinde sınır kaldırılır (sınırsız, yerel testler için uygundur). Yerelde test ederken `server/.dev.vars` içine `LEADERBOARD_PAIR_WIN_CAP=0` veya istenen sınır yazılarak ayarlanabilir.
- **`EXTRA_TIME_COST`**: Ek süre (+5 sn) güçlendiricisinin jeton maliyeti (varsayılan: **30**).
- **`EXTRA_TIME_SECONDS`**: Ek süre güçlendiricisinin sağladığı süre (saniye cinsinden, varsayılan: **5**).
- **`GIVE_ANSWER_COST`**: "Cevap Ver" güçlendiricisinin jeton maliyeti (varsayılan: **50**). Maç başına 1 kullanım sınırı bulunur ve sorunun henüz kullanılmamış doğru cevaplarından birini otomatik oynar.

### 🔐 Canlı Ortam Gizli Değişkenleri (Cloudflare Secrets)

Depo herkese açık (public) olduğu için hassas bilgiler, yönetici anahtarları ve kişisel test UID'leri ASLA `wrangler.jsonc` içine yazılmaz ve versiyon kontrolüne dahil edilmez. Canlı ortamda bu değişkenler Cloudflare Secrets olarak yapılandırılır:

1. **`ENERGY_TEST_UIDS`**: Canlı ortamda genel enerji anahtarı kapalıyken (`ENERGY_ENABLED="false"`), enerji akışını yalnızca kendi test hesabınızda denemek için virgülle ayrılmış Firebase UID listesi gizli değişken olarak verilir:
   ```bash
   npx wrangler secret put ENERGY_TEST_UIDS
   # İstendiğinde virgülle ayrılmış UID listesini girin (örn: uid1,uid2)
   ```
   *(Yerel geliştirmede ise `server/.dev.vars` içine `ENERGY_TEST_UIDS=uid1,uid2` şeklinde eklenebilir.)*

2. **`ADMIN_TOKEN`**: `/admin/*` uç noktalarına (çerçeve/jeton/enerji hibesi `grant`, şikayet ve engel listesi `reports`) yetkili erişim sağlayan yönetici anahtarı canlıda mutlaka secret olmalıdır:
   ```bash
   npx wrangler secret put ADMIN_TOKEN
   # İstendiğinde güçlü ve rastgele bir anahtar girin
   ```
   *(Yerel geliştirmede ise `server/.dev.vars` içine `ADMIN_TOKEN=...` şeklinde eklenebilir.)*

3. **`FIREBASE_SERVICE_ACCOUNT_B64`**: Firebase Realtime Database REST erişimi için gereken Google servis hesabı anahtarı da canlıda benzer şekilde secret olarak tanımlanır:
   ```bash
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_B64
   ```

### 🔒 Güvenlik İlkeleri ve IAM Rolleri (Adım 4.4)
- **Loglama Güvenliği:** Servis hesabı içeriği, access token'lar, JWT assertion'lar ve soru/cevap metinleri ASLA loglara yazılmaz.
- **En Az Yetki İlkesi (Least Privilege):** İleride Google Cloud IAM üzerinde üretim için yalnızca **"Firebase Realtime Database Viewer"** rolüne sahip, yazma yetkisi olmayan ayrı ve kısıtlı bir servis hesabına geçilecektir.

### 🔍 Canlı Veritabanı İçerik Kontrolü
Yerel `.dev.vars` dosyasındaki servis hesabı ve veritabanı ayarlarını canlıda test etmek için:
```bash
npm run check:content
```
Bu araç, gerçek veritabanına bağlanır, yetkilendirme yöntemini (`Authorization: Bearer` başlığı), kategori sayısını, geçerli soru ve cevap sayılarını özetler (soru/cevap içeriklerini yazdırmaz).

---

## 🛠️ Yerel Çalıştırma

Geliştirme sunucusunu yerel ortamda Miniflare üzerinde başlatmak için:

```bash
npx wrangler dev
```
Sunucu varsayılan olarak `http://127.0.0.1:8787` üzerinde çalışır.

### 🌐 Gerçek Realtime Database ile Yerel Test (`npm run dev:real`)
Yerel workerd ortamında gerçek Firebase Realtime Database bağlantısını ve servis hesabı doğrulamasını test etmek için:
```bash
npm run dev:real
```
Bu komut, `CONTENT_SOURCE:realtime` değişkenini ileterek `.dev.vars` dosyasındaki gerçek `FIREBASE_DATABASE_URL` ve `FIREBASE_SERVICE_ACCOUNT_B64` yapılandırmasını kullanır.

### 🔍 Canlı Günlük İzleme (Cloudflare Workers Tail) ve İçerik Tanılama
Yayındaki sunucuda içerik hatası (`content_unavailable`) oluştuğunda günlüğü canlı izlemek için:
```bash
npx wrangler tail
```
İçerik hattındaki olası hatalar tek satırlık yapılandırılmış JSON olarak `console.warn` ile günlüğe düşer (`event: "content_error"`).

Örnek çıktı:
```json
{"event":"content_error","stage":"token_exchange","status":400,"errorName":"OAuthTokenError","code":"invalid_grant","detail":"Invalid JWT Signature.","hasSecret":true,"hasClientEmail":true,"hasPrivateKey":true,"isPemFormatValid":true}
```

#### Tail çıktısında aranacak aşamalar (`stage`):
1. **`secret_missing`**: Ortam değişkenleri (`FIREBASE_DATABASE_URL` veya `FIREBASE_SERVICE_ACCOUNT_B64`) eksik ya da yer tutucu.
2. **`secret_decode`**: Servis hesabı Base64 dizesi bozuk, JSON biçimi geçersiz ya da `client_email` / `private_key` alanları eksik.
3. **`jwt_sign`**: Web Crypto PKCS8 özel anahtarını içe aktaramadı (`importKey`) ya da JWT assertion imzalanamadı (`sign`).
4. **`token_exchange`**: Google OAuth2 uç noktasına erişilemedi (ağ hatası) ya da Google `invalid_grant` / `invalid_client` gibi bir HTTP hatası döndürdü.
5. **`rtdb_fetch`**: Firebase Realtime Database'e bağlanılamadı ya da RTDB HTTP 401/403 (yetki reddi) döndürdü.
6. **`parse`**: RTDB yanıtı geçerli JSON değil ya da soru havuzunda oynanabilir 8 soru bulunamadı.

#### Güvenlik Güvencesi:
- Base64 secret, private key, client email, access token, JWT assertion ve URL sorgu parametreleri (`?access_token=...`) ASLA loglanmaz.
- `hasSecret`, `hasClientEmail`, `hasPrivateKey`, `isPemFormatValid` alanları YALNIZCA boolean (`true`/`false`) değer içerir; anahtar boyutu veya içeriği yazılmaz.
- Tekrarlanan aynı hata 10 saniye boyunca log spam'i oluşturmayacak şekilde filtrelenir.

Sağlık kontrolü testi:
```bash
# Yerel geliştirme ortamı:
curl http://127.0.0.1:8787/health
# Canlı sunucu (Custom Domain):
curl https://api.riestudio.com.tr/health
# Çıktı: ok
```

---

## 🧪 Testler

### 1. Birim Testleri (Unit Tests)
Saf TypeScript motorunu, normalizer'ı, yakın deneme algoritmasını, tek alarm çizelgeleyicisini ve depolama filtrelerini doğrular (290+ test):

```bash
npm test
```

### 2. Statik Tip Kontrolü (Type Check)
Tam strict TypeScript derleme kontrolü:

```bash
npx tsc --noEmit
```

### 3. Canlı E2E Test Paketi (End-to-End Tests)
Wrangler dev sunucusu üzerinde gerçek WebSocket bağlantılarıyla 8 temel senaryoyu test eder:

```bash
npm run e2e
```

#### E2E Kapsamı:
- **(a)** 2-0 biten normal maç (başlayan rotasyonu, soru havuzu, skorlar).
- **(b)** Bir yanlış cevap sonrası doğru cevap (sıra kaybettirmez, turu bitirmez).
- **(c)** Yakın deneme gizliliği (aktif turda rakibin ekranına asla sızmaz).
- **(d)** Süre aşımı (timeout - FAST_TIMERS ile DO alarmı üzerinden tur bitişi).
- **(e)** Maçı terk etme (`leave` mesajı ile anında hükmen galibiyet).
- **(f)** Bağlantı kopması, 1 sn içinde geri dönüş ve kopup geri dönmeme sonucu forfeit.
- **(g)** Rakip bağlanmadığında maçın iptali (`voided` - opponent_absent).
- **(h)** Yetkisiz 3. oyuncunun odaya sızmasının engellenmesi (HTTP 403 Forbidden).

### 4. Canlı Sunucu "Hayalet Rakip" Test Aracı (Ghost Opponent)
Gerçek sunucuya karşı telefonunuzla ya da başka bir istemciyle eşleşip maç oynamak, bağlantı kopmasını ve süre aşımlarını test etmek için kullanılan otomatik rakip betiği:

#### Firebase Web API Anahtarının Temini:
Anonim Firebase girişi yapabilmek için Firebase Web API anahtarı gereklidir:
- Flutter projesindeki `app/lib/firebase_options.dart` dosyasındaki `apiKey` değerinden veya Firebase Console -> Proje Ayarları -> Web API Anahtarı bölümünden alınabilir.
- `server/.dev.vars` içine şu satır eklenebilir:
  ```env
  FIREBASE_WEB_API_KEY=AIzaSy...
  ```
  *(Bu dosya `.gitignore` kapsamındadır ve versiyon kontrolüne girmez.)*
- Alternatif olarak `FIREBASE_WEB_API_KEY` ortam değişkeniyle veya `--api-key=...` komut satırı argümanıyla verilebilir.

#### Kullanım ve Örnek Komutlar:

```bash
# 1. Normal oyun modu (play - varsayılan):
# 2-6 sn bekleyip geçerli cevap gönderir (%20 ihtimalle önce yanlış dener)
npm run ghost -- --mode=play

# 2. Hareketsiz mod (idle):
# Kuyruğa girer, eşleşir ama hiç cevap göndermez (süre aşımı testleri için)
npm run ghost -- --mode=idle

# 3. Maçı terk etme modu (leave):
# 15 sn sonra (veya --leave-after=<sn>) maçı terk eder (forfeit testi için)
npm run ghost -- --mode=leave --leave-after=10

# 4. Bağlantı koparma modu (drop):
# 15 sn sonra (veya --drop-after=<sn>) soketi kapatır ve 5 sn sonra geri dönüp sync ister
npm run ghost -- --mode=drop --drop-after=15 --back-after=5

# 5. Ardışık birden fazla maç oynama:
npm run ghost -- --mode=play --rounds=3

# 6. Farklı sunucu adresi ve doğrudan API anahtarı verme:
npm run ghost -- --url=wss://api.riestudio.com.tr --api-key=AIzaSy... --mode=play
```

### 5. Liderlik Tablosu Yerel Tohumlama Aracı (seed-leaderboard)
Liderlik tablosunu yerel ortamda test etmek, 100 satırlık listenin kaydırılmasını, eşitlik kurallarını ve yeni görsel avatar çerçevelerini incelemek için kullanılan test verisi tohumlama aracıdır.

#### 🛡️ Güvenlik Garantisi:
- Bu araç canlı sunucuya (`api.riestudio.com.tr`) **KESİNLİKLE BAĞLANMAZ VE VERİ YAZMAZ**.
- Hedeflenen sunucu adresi `127.0.0.1` veya `localhost` dışında ise araç anında hata vererek çalışmayı durdurur.
- Eklenen tüm oyuncu kayıtları `seed_` ön ekine (`seed_001` .. `seed_100`) sahiptir; gerçek kullanıcı verilerine ASLA dokunmaz.

#### Özellikler:
- **100 Sahte Oyuncu:** `seed_001` .. `seed_100`, takma adlar `Test 001` .. `Test 100`.
- **Galibiyet Dağılımı:** 1 ile 40 arasında dengeli azalan dağılım.
- **Eşitlik Bozucu Kuralların Doğrulanması:**
  1. `wins DESC` (Galibiyeti çok olan üstte)
  2. `losses ASC` (Eşit galibiyette az mağlubiyeti olan üstte, örn: 38G/1M > 38G/4M)
  3. `reached_at ASC` (Eşit galibiyet ve mağlubiyette skora daha erken ulaşan üstte)
  4. `uid ASC` (Tam eşitlikte alfabetik deterministik sıra)
- **Çerçeve Dağılımı:** Hem `classic` hem de 9 yeni görsel çerçeveyi (`vine`, `silver_engraved`, `bronze_engraved`, `gold_leaf`, `emerald`, `sakura`, `ice`, `gear`, `nazar`) 10'ar kez dengeli olarak içerir.

#### Kullanım Komutları:

```bash
# 1. 100 sahte oyuncuyu yerel liderlik tablosuna tohumla:
npm run seed:lb

# 2. Sahte oyuncuları tablodan temizle:
npm run seed:lb -- --clear

# 3. İsteğe bağlı farklı yerel port belirtme (varsayılan: http://127.0.0.1:8787):
npm run seed:lb -- --server=http://127.0.0.1:8788
```

---

## 📱 Flutter Uygulamasını Yerel Sunucuya Bağlama Adım Adım Kılavuzu

Flutter uygulaması varsayılan olarak canlı sunucuya (`https://api.riestudio.com.tr`) bağlanır. Geliştirme yaparken yerel `wrangler dev` sunucusuna bağlanmak için:

### 1. Adım: Yerel Sunucuyu Başlatın
```bash
cd server
npm run dev
# Sunucu http://127.0.0.1:8787 adresinde dinlemeye başlar
```
*(Eğer gerçek fiziksel cihazdan test yapacaksanız sunucuyu yerel ağa açmak için `npx wrangler dev --ip 0.0.0.0` kullanabilirsiniz).*

### 2. Adım: Liderlik Tablosunu Tohumlayın
```bash
cd server
npm run seed:lb
```

### 3. Adım: Flutter Uygulamasını İlgili Hedefe Göre Çalıştırın

- **Android Emülatör (Önerilen):**
  Android emülatörü bilgisayarın `127.0.0.1` adresine `10.0.2.2` özel sanal IP'si üzerinden erişir:
  ```bash
  cd app
  flutter run --dart-define=SERVER_URL=http://10.0.2.2:8787
  ```

- **Gerçek Android veya iOS Cihazı (Aynı Wi-Fi):**
  1. Bilgisayarınızın yerel Wi-Fi IP adresini öğrenin (Windows: `ipconfig`, macOS/Linux: `ifconfig` - örn: `192.168.1.35`).
  2. Sunucuyu `npx wrangler dev --ip 0.0.0.0` ile başlatın.
  3. Uygulamayı çalıştırın:
     ```bash
     cd app
     flutter run --dart-define=SERVER_URL=http://192.168.1.35:8787
     ```
  *(Not: Android 9+ cihazlarda yerel ağdaki şifresiz HTTP trafiği için debug derlemesi cleartext bağlantıyı destekler).*

- **Windows Masaüstü / macOS / iOS Simülatör:**
  Simülatör veya masaüstü doğrudan makinenin yerel döngü adresini kullanabilir:
  ```bash
  cd app
  flutter run --dart-define=SERVER_URL=http://127.0.0.1:8787
  ```

### 4. Adım: Test Sonrası Temizleme
Liderlik tablosundaki test kayıtlarını silmek için:
```bash
cd server
npm run seed:lb -- --clear
```

---

## 📂 Dizin Yapısı

```
server/
├── src/
│   ├── index.ts                # Worker giriş noktası ve yönlendirme (/health, /ws/...)
│   ├── auth.ts                 # Dev mod token ayrıştırıcı (Adım 4.3b'de Firebase Auth)
│   ├── protocol.ts             # İstemci-sunucu JSON protokol tipleri ve validatörler
│   ├── powerup.ts              # Güçlendirici maliyet yapılandırması ve doğrulayıcılar
│   ├── matchmaker.ts           # Matchmaker Durable Object (global kuyruk, FIFO, eşleştirme)
│   ├── matchRoom.ts            # MatchRoom Durable Object (canlı oda, WebSocket Hibernation, SQLite)
│   ├── scheduler.ts            # Tek alarmlı zamanlayıcı hesaplayıcı (pure functions)
│   ├── storage.ts              # SQLite serileştirme ve oyuncuya özel durum filtreleme
│   ├── content/                # Soru içerik sağlayıcıları (DevContentProvider)
│   ├── dev/questions.json      # Geliştirme modu soru havuzu (CMS export yansıması)
│   └── engine/                 # Dart motorunun SAF TypeScript karşılığı
│       ├── engine.ts           # MatchEngine saf state machine
│       ├── models.ts           # Question, Answer, RoundRecord, MatchState tipleri
│       ├── normalizer.ts       # Türkçe uyumlu TextNormalizer
│       ├── matcher.ts          # AnswerMatcher
│       ├── nearMiss.ts         # Damerau-Levenshtein yakınlık hesabı
│       ├── sanitizer.ts        # AttemptTextSanitizer
│       └── visibility.ts       # visibleAttempts deneme filtreleme mantığı
├── test/                       # Vitest birim test dosyaları
├── tools/
│   └── e2e.ts                  # Canlı sunucu E2E test koşucusu
├── wrangler.jsonc              # Cloudflare Workers ve Durable Objects yapılandırması
├── tsconfig.json               # TypeScript yapılandırması
└── package.json
```

---

## 📖 Protokol Dokümantasyonu

Tüm WebSocket mesaj formatları, JSON şemaları, gizlilik kuralları ve hata kodları için [docs/PROTOCOL.md](../docs/PROTOCOL.md) belgesine bakınız.

### ⚡ Bot Maçı Joker Harcama Uç Noktası (`POST /powerups/spend`)
Bot maçlarında oda (`MatchRoom`) sunucuda bulunmadığından, istemci tarafındaki joker harcamaları (`extra_time`: 30, `give_answer`: 50) bu uç nokta üzerinden `UserProfile` Durable Object'ine atomik ve idempotent olarak yansıtılır. Yalnızca `bot:` önekli maç kimlikleri kabul edilir. Detaylar için [docs/PROTOCOL.md](../docs/PROTOCOL.md) belgesine bakınız.

