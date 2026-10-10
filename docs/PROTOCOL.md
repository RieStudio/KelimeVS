# KelimeGo İstemci - Sunucu WebSocket Protokolü (v1)

Bu belge, KelimeGo istemcisi (Flutter) ile eşleştirme ve maç sunucusu (Cloudflare Workers + Durable Objects) arasındaki gerçek zamanlı iletişim protokolünü tanımlar.

---

## 1. Genel Yapı ve Bağlantı Noktaları

Tüm iletişim JSON formatında WebSocket üzerinden gerçekleştirilir.

### Uç Noktalar (Endpoints)
- **Sağlık Kontrolü (HTTP GET):** `GET /health` -> `200 OK` (`"ok"`)
- **Eşleştirme (Matchmaking WebSocket):** `/ws/matchmaking`
- **Canlı Maç Odası (Match Room WebSocket):** `/ws/match/:matchId`

### Kimlik Doğrulama ve Jeton Taşıma (Authentication & Transport)
- **Tercih Edilen Taşıma Yöntemi (Üretim & Standart):**
  WebSocket yükseltme isteğinde (handshake) `Authorization: Bearer <jeton>` HTTP başlığı kullanılır.
- **Geliştirme Modu Kolaylığı (`ALLOW_DEV_AUTH=true`):**
  - Yalnızca yerel ortamda (`.dev.vars`) tanımlıysa geçerlidir; üretimde (`wrangler.jsonc`) asla yer almaz.
  - Test ve geliştirme kolaylığı için URL sorgu parametresi (`?token=dev:<uid>`) kabul edilir.
  - Geliştirme modunda olsa dahi gerçek Firebase jetonları `?token=` ile taşınamaz; başlıkla gönderilmelidir.
- **Üretim Modu Güvenlik Kuralı:**
  - URL'ler ara sunucu ve erişim günlüklerine (access logs) yazılabileceğinden, üretim modunda `?token=` sorgu parametresi KESİNLİKLE reddedilir (HTTP 401).
  - Kimlik doğrulama yalnızca `Authorization: Bearer <firebase-id-token>` başlığıyla yapılır.
- **Firebase ID Token Doğrulama Kuralları (Adım 4.3b):**
  - **Algoritma:** Yalnızca `RS256` kabul edilir (`"none"`, `"HS256"` vb. saldırı denemeleri derhal reddedilir).
  - **İmza:** Google'ın açık anahtarları (JWK: `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`) ile Web Crypto (`crypto.subtle`) kullanılarak doğrulanır.
  - **Talepler (Claims):**
    - `aud === env.FIREBASE_PROJECT_ID`
    - `iss === https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`
    - `sub`: Boş olmayan kullanıcı kimliği (1-128 karakter `uid`)
    - `exp`: Gelecekte, `iat`: Geçmişte, `auth_time`: Geçmişte (60 saniye saat sapması toleransı).
  - **Anahtar Önbelleği:** Bellek içi önbellek (`Cache-Control: max-age` süresince geçerli). Bilinmeyen `kid` geldiğinde dakikada en fazla 1 kez dış istek tetikleyen hız sınırı koruması mevcuttur.
- **Hata Durumları:**
  - Geçersiz, süresi dolmuş veya eksik token: HTTP `401 Unauthorized`.
  - Maç odasına eşleşmemiş yabancı bir kullanıcının bağlanması: HTTP `403 Forbidden`.
  - İptal edilmiş (voided) maça bağlanma: HTTP `410 Gone`.
  - Bulunamayan maç: HTTP `404 Not Found`.

---

## 2. Eşleştirme Protokolü (`/ws/matchmaking`)

### İstemci -> Sunucu Mesajları

#### Kuyruğa Girme (`queue`)
```json
{
  "t": "queue",
  "name": "Ahmet"
}
```
- `name`: Oyuncunun ekranda görünecek adı (en fazla 20 karakter, baştaki/sondaki boşluklar kırpılır).

#### Kuyruktan Çıkma (`cancel`)
```json
{
  "t": "cancel"
}
```

### Sunucu -> İstemci Mesajları

#### Kuyruğa Alındı (`queued`)
```json
{
  "t": "queued"
}
```

#### Kuyruktan Çıkıldı (`cancelled`)
```json
{
  "t": "cancelled"
}
```

#### Eşleşme Bulundu (`matched`)
```json
{
  "t": "matched",
  "matchId": "m_1728518400000_abc123",
  "opponentName": "Mehmet"
}
```
- İstemci bu mesajı aldığında eşleştirme WebSocket bağlantısını kapatır ve doğrudan `/ws/match/:matchId?token=...` adresine bağlanır.

#### Hata (`error`)
```json
{
  "t": "error",
  "code": "already_queued"
}
```

---

## 3. Canlı Maç Odası Protokolü (`/ws/match/:matchId`)

### İstemci -> Sunucu Mesajları

#### Kelime Gönderme (`submit`)
```json
{
  "t": "submit",
  "text": "ankara"
}
```
- Gönderim kısıtlamaları:
  - Maksimum mesaj uzunluğu: 200 bayt.
  - Hız sınırı (Rate limit): Saniyede en fazla 10 mesaj.
  - Minimum gönderim aralığı (cooldown): 600 ms.

#### Maçı Terk Etme (`leave`)
```json
{
  "t": "leave"
}
```
- Oyuncu maçı gönüllü terk ettiğinde sunucu maçı derhal bitirir (`endedBy: "forfeit"`), galibiyeti rakibe verir.

#### Durum Senkronizasyonu Talebi (`sync`)
```json
{
  "t": "sync"
}
```
- İstemcinin güncel durumu sunucudan yeniden talep etmesini sağlar.

---

### Sunucu -> İstemci Mesajları

#### Maç Durumu (`state`)
Her hamle, tur geçişi veya durum değişikliğinde (veya `sync` istendiğinde) her iki oyuncuya durumlarına göre filtrelenerek gönderilir.

```json
{
  "t": "state",
  "serverNowMs": 1728518400000,
  "phase": "roundActive",
  "roundNumber": 1,
  "scores": {
    "me": 1,
    "opponent": 0
  },
  "question": {
    "id": "q_baskentler",
    "text": "Türkiye'nin başkenti neresidir?"
  },
  "turnIsMine": true,
  "deadlineMs": 1728518415000,
  "myHintsLeft": 1,
  "attempts": [
    {
      "mine": true,
      "text": "izmir",
      "result": "wrong"
    },
    {
      "mine": true,
      "text": "ankra",
      "result": "nearMiss",
      "hintShown": true
    }
  ],
  "opponentName": "Mehmet",
  "opponentConnected": true,
  "nextRoundAtMs": 1728518417000,
  "endedBy": "normal",
  "winnerIsMe": true,
  "lastRound": {
    "winnerIsMe": true,
    "draw": false,
    "reason": "normal"
  }
}
```

##### Alan Açıklamaları:
- `phase`: `"roundActive"` (tur sürüyor), `"roundEnded"` (tur arası bekleme), `"matchFinished"` (maç bitti).
- `roundNumber`: Kaçıncı turun oynandığı (1, 2 veya 3).
- `turnIsMine`: Sıranın bu istemcide olup olmadığı.
- `deadlineMs`: Sıradaki oyuncunun hamle yapması gereken son zaman (Unix ms).
- `myHintsLeft`: Oyuncunun bu tur kalan "çok yakın" ipucu hakkı (başlangıçta 1).
- `attempts`: Turdaki balonlar / denemeler listesi (gizlilik kurallarına göre filtrelenmiş).
- `opponentConnected`: Rakibin bağlantısının aktif olup olmadığı (`false` ise bağlantı koptu ve geri dönüş sayacı çalışıyor).
- `nextRoundAtMs`: Tur arası geçişte bir sonraki turun başlama zamanı.

#### Hamle Geribildirimi (`feedback`)
Yalnızca cevabı gönderen oyuncuya iletilir:
```json
{
  "t": "feedback",
  "kind": "wrong" | "nearMiss" | "alreadySaid" | "ignored",
  "reason": "cooldown" | "not_your_turn" | "empty" | "limit_exceeded" | "round_not_active"
}
```

#### Maç Sonu ve Özet (`final`)
Maç sonuçlandığında her iki oyuncuya gönderilir. Maç detay ekranı ve geçmiş kaydı için tüm turların ve denemelerin sansürsüz dökümünü içerir:
```json
{
  "t": "final",
  "rounds": [
    {
      "questionId": "q_baskentler",
      "attempts": [
        { "mine": true, "text": "ankara", "result": "correct" }
      ],
      "winnerIsMe": true,
      "reason": "normal"
    }
  ],
  "scores": {
    "me": 2,
    "opponent": 1
  },
  "winnerIsMe": true,
  "endedBy": "normal" | "forfeit"
}
```

#### İptal Edilen Maç (`voided`)
Rakip oyuncu belirlenen süre içinde maç odasına hiç bağlanmazsa gönderilir:
```json
{
  "t": "voided",
  "reason": "opponent_absent"
}
```

---

## 4. Yakın Deneme Gizlilik Kuralları (Near-Miss Secrecy)

- **Aktif Tur Sırasında (`roundActive`):**
  - Henüz söylenmemiş bir cevaba yakın olan tüm yanlış denemeler (`isClose === true`), tur bitene kadar **yalnızca sahibine** gösterilir.
  - İpucu verilmişse (`hintShown === true`): Balon olarak gizlenir, sadece sahibine "Çok yakın!" ipucu kutusu görünür.
  - İpucu hakkı bittiği için ipucu verilmemişse (`hintShown === false`): Sahibine normal kırmızı yanlış balon görünür, rakibe **hiç gösterilmez** (rakibin ipucu / kopya alması engellenir).
- **Tur Bittikten Sonra ve Maç Detayında:**
  - Tüm denemeler her iki oyuncuya da açıkça görünür.

---

## 5. Bağlantı Kopması, Yeniden Bağlanma ve Terk

1. **Aynı UID ile Yeni Bağlantı Açılması:**
   - Eski WebSocket bağlantısı kod `4000` (`"replaced"`) ile kapatılır; maç durumu korunur.
2. **Beklenmeyen Bağlantı Kopması:**
   - Oyuncu koptuğunda, bağlı kalan rakibe `opponentConnected: false` bilgisi iletilir.
   - Kopma zamanlayıcısı başlar (Normal: 30 saniye, Hızlı mod: 3 saniye).
3. **Süre İçinde Geri Dönüş:**
   - Oyuncu süre dolmadan `/ws/match/:matchId` adresine yeniden bağlandığında sayaç iptal edilir.
   - Rakibe `opponentConnected: true` bilgisi iletilir.
4. **Süre Aşımı ve Hükmen Mağlubiyet:**
   - Belirlenen sürede geri dönmeyen oyuncu maçı terk etmiş sayılır (`endedBy: "forfeit"`).
   - Bağlı kalan rakip maçı kazanır.
5. **Hiç Bağlanmama Durumu:**
   - Eşleşme sağlandıktan sonra bir oyuncu odaya bağlanır, diğeri belirlenen süre içinde (Normal: 10 saniye, Hızlı: 3 saniye) hiç bağlanmazsa maç `voided` olarak iptal edilir.

---

## 6. Zamanlayıcı Süreleri (Timers)

| Zamanlayıcı | Normal Süre | Hızlı Test Modu (`FAST_TIMERS=true`) | Açıklama |
|---|---|---|---|
| Hamle Süresi (`answerSeconds`) | 15 sn | 3 sn | Oyuncunun doğru cevap vermek için sahip olduğu süre |
| Tur Geçiş Süresi (`roundTransitionMs`) | 2000 ms | 500 ms | Tur sonu ile yeni turun başlaması arasındaki bekleme |
| Bağlantı Kopma Toleransı (`disconnectTimeoutMs`) | 30 sn | 3 sn | Kopan oyuncunun geri dönmesi için tanınan süre |
| İlk Bağlantı Bekleme (`connectTimeoutMs`) | 10 sn | 3 sn | Eşleşme sonrası rakibin odaya ilk bağlantısını bekleme |
| Oda Temizlik Süresi (`cleanupMs`) | 10 dk | 5 sn | Maç bittikten sonra DO SQLite verilerinin silinmesi |

---

## 7. Geliştirme Bayrakları (`.dev.vars`)

| Bayrak | Değerler | Varsayılan | Amaç |
|---|---|---|---|
| `ALLOW_DEV_AUTH` | `"true"` / `"false"` | `"false"` | Geliştirme ortamında `dev:<uid>` token'larına izin verir. |
| `FAST_TIMERS` | `"true"` / `"false"` | `"false"` | E2E ve otomatik testlerin saniyeler içinde tamamlanması için zamanlayıcıları hızlandırır. |

