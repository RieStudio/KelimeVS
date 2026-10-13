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

---

## 📂 Dizin Yapısı

```
server/
├── src/
│   ├── index.ts                # Worker giriş noktası ve yönlendirme (/health, /ws/...)
│   ├── auth.ts                 # Dev mod token ayrıştırıcı (Adım 4.3b'de Firebase Auth)
│   ├── protocol.ts             # İstemci-sunucu JSON protokol tipleri ve validatörler
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

