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

## ⚙️ Yapılandırma (`.dev.vars`)

Yerel geliştirme ortamında gizli anahtarlar ve geliştirme bayrakları `.dev.vars` dosyasında tutulur (`.gitignore` ile versiyon kontrolü dışındadır).

Örnek `server/.dev.vars`:
```env
ALLOW_DEV_AUTH=true
FAST_TIMERS=true
```

- **`ALLOW_DEV_AUTH=true`**: Geliştirme ortamında `dev:<uid>` biçimindeki test token'larının kabul edilmesini sağlar (Örn: `dev:alice`). Üretim yapılandırmasında (`wrangler.jsonc`) asla yer almaz.
- **`FAST_TIMERS=true`**: Testleri ve E2E akışlarını saniyeler içinde tamamlamak üzere hamle süresini (15s -> 3s), tur geçişini (2s -> 500ms) ve bağlantı kopma süresini (30s -> 3s) hızlandırır.

---

## 🛠️ Yerel Çalıştırma

Geliştirme sunucusunu yerel ortamda Miniflare üzerinde başlatmak için:

```bash
npx wrangler dev
```
Sunucu varsayılan olarak `http://127.0.0.1:8787` üzerinde çalışır.

Sağlık kontrolü testi:
```bash
curl http://127.0.0.1:8787/health
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

