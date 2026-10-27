# KelimeGo İstemci - Sunucu WebSocket Protokolü (v1)

Bu belge, KelimeGo istemcisi (Flutter) ile eşleştirme ve maç sunucusu (Cloudflare Workers + Durable Objects) arasındaki gerçek zamanlı iletişim protokolünü tanımlar.

---

## 1. Genel Yapı ve Bağlantı Noktaları

Tüm iletişim JSON formatında WebSocket üzerinden gerçekleştirilir.

### Uç Noktalar (Endpoints)
- **Canlı Sunucu Adresi:** `https://api.riestudio.com.tr` (WebSocket: `wss://api.riestudio.com.tr`)
- **Sağlık Kontrolü (HTTP GET):** `GET /health` -> `200 OK` (`"ok"`) (Örn: `https://api.riestudio.com.tr/health`)
- **Eşleştirme (Matchmaking WebSocket):** `/ws/matchmaking` (Örn: `wss://api.riestudio.com.tr/ws/matchmaking`)
- **Canlı Maç Odası (Match Room WebSocket):** `/ws/match/:matchId` (Örn: `wss://api.riestudio.com.tr/ws/match/:matchId`)

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
  "opponentName": "Mehmet",
  "isFriendly": false
}
```
- İstemci bu mesajı aldığında eşleştirme WebSocket bağlantısını kapatır ve doğrudan `/ws/match/:matchId` adresine bağlanır.

#### Hata (`error`)
```json
{
  "t": "error",
  "code": "content_unavailable"
}
```
- Olası `code` değerleri:
  - `"content_unavailable"`: Veritabanından soru havuzu alınamadığında veya maç başlatmak için en az 8 uygun soru bulunamadığında her iki oyuncuya gönderilir. Sunucu oyuncuları kuyruktan çıkarır ve bağlantıyı kapatır. İstemci bu hatayı aldığında kullanıcıya uyarı gösterip botlu maça yönlendirebilir.
  - `"already_queued"`: Oyuncunun halihazırda aktif bir kuyruk kaydı varken mükerrer kuyruk isteği geldiğinde gönderilir.

### 2.2. Arkadaşla Düello (Friend Duel) Protokolü

Arkadaş düellosu da `/ws/matchmaking` WebSocket uç noktası üzerinden yönetilir. 28 karakterli alfabeden (`23456789BCDFGHJKMNPQRSTVWXYZ`) üretilen 6 haneli tek kullanımlık davet kodları ile çalışır. Kod 5 dakika geçerlidir. Kurucunun soketi koptuğunda (örn. kodu WhatsApp'ta paylaşırken) oda 5 dakika boyunca askıda tutulur (Grace Period).

#### İstemci -> Sunucu Mesajları

##### Oda Kurma (`create_room`)
```json
{
  "t": "create_room",
  "name": "Ahmet"
}
```

##### Askıdaki Odaya Yeniden Bağlanma (`resume_room`)
```json
{
  "t": "resume_room",
  "code": "K7M9P2"
}
```

##### Koda Katılma (`join_room`)
```json
{
  "t": "join_room",
  "code": "K7M9P2",
  "name": "Zeynep"
}
```

##### Odayı İptal Etme (`cancel_room`)
```json
{
  "t": "cancel_room",
  "code": "K7M9P2"
}
```

#### Sunucu -> İstemci Mesajları

##### Oda Kuruldu (`room_created`)
```json
{
  "t": "room_created",
  "code": "K7M9P2",
  "expiresAt": 1729452000000
}
```

##### Odaya Devam Edildi (`room_resumed`)
```json
{
  "t": "room_resumed",
  "code": "K7M9P2",
  "expiresAt": 1729452000000
}
```

##### Oda Süresi Doldu (`room_expired`)
```json
{
  "t": "room_expired"
}
```

##### Eşleşme Bulundu (`matched`)
```json
{
  "t": "matched",
  "matchId": "m_1729452000000_abc123",
  "opponentName": "Zeynep",
  "opponentFrame": "mint",
  "isFriendly": true
}
```
- `isFriendly: true` ise maç arkadaş düellosudur. Jeton ödülü verilmez, UserProfile istatistiklerine ve haftalık liderlik tablosuna galibiyet yazılmaz.

##### Hata Durumları (`error`)
- `"room_not_found"`: Oda kodu bulunamadı veya süresi dolmuş.
- `"room_full"`: Odaya zaten başka bir oyuncu katılmış.
- `"cannot_join_own_room"`: Kurucu kendi oluşturduğu koda katılamaz.
- `"rate_limited"`: Hatalı kod deneme limiti aşıldı (UID için 5/dk veya 15/saat; IP için 30/dk). `retryAfterSeconds` alanı içerir.
- `"room_unavailable"`: Karşılıklı engelleme durumu var (nedeni sızdırmayan genel gizlilik mesajı).
- `"lobby_busy"`: Küresel açık lobi üst sınırına (1000 oda) ulaşıldı.
- `"account_deleted"`: Silinmiş hesap (tombstone).

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

#### Güçlendirici Kullanma (`use_powerup`)
```json
{
  "t": "use_powerup",
  "type": "extra_time"
}
```
- Yalnızca online hızlı maçta (ranked), tur aktifken ve sıra oyuncudayken kullanılabilir.
- Maç başına oyuncu başına 1 kullanım ile sınırlıdır (30 jeton).
- Arkadaş maçında veya bakiye yetersizliğinde reddedilir.

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
  "opponentFrame": "classic",
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
- `attempts`: Turdaki balonlar / denemeler listesi (gizlilik ve görünürlük kurallarına göre filtrelenmiş; aktif turda tekrarlanan cevaplar dahil edilmez). Doğru (`correct`) kabul edilen denemelerde `text` alanı eşleşen ana cevabı (`answer.display`) taşır; böylece kullanıcı alias (ör. `"bjk"`) yazsa bile chat balonunda ana cevap (ör. `"Beşiktaş"`) görünür. Yanlış (`wrong`) denemelerde `text` kullanıcının girdiği ham metni korur.
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
  "opponentName": "Mehmet",
  "opponentFrame": "classic",
  "winnerIsMe": true,
  "endedBy": "normal" | "forfeit"
}
```

#### İptal Edilen Maç (`voided`)
Maçın kazanan olmadan iptal edildiğini bildirir. İptal durumunda jeton verilmez, lig/istatistik kaydı yapılmaz ve maça enerji harcamış tüm oyunculara enerjileri iade edilir:
```json
{
  "t": "voided",
  "reason": "opponent_absent" | "both_disconnected" | "draw_limit_reached"
}
```
##### İptal Nedenleri (`reason`):
- `"opponent_absent"`: Eşleşme sağlandıktan sonra bir oyuncu odaya bağlanır, diğeri belirlenen süre içinde (Normal: 10 sn, Hızlı: 3 sn) hiç bağlanmazsa.
- `"both_disconnected"`: Aktif maç sırasında her iki oyuncunun da bağlantısı kopar ve her ikisinin de kopma süresi (Normal: 30 sn, Hızlı: 3 sn) geri dönmeden dolarsa.
- `"draw_limit_reached"`: Toplam tur tavanına (`maxTotalRounds = 5`) ulaşıldığı halde skorlar eşitse (0-0, 1-1, 2-2) maç iptal edilir ve her iki oyuncuya enerjileri iade edilir. (Tavan dolduğunda skor eşit değilse, örn. 1-0 veya 2-1, lider olan taraf normal galip sayılır).

> **İptal Edilmiş Odaya Yeniden Bağlanma:** İstemci önceden `voided` olmuş bir odaya bağlandığında WebSocket el sıkışması kabul edilir (HTTP 101), derhal güncel `{ "t": "voided", "reason": ... }` mesajı gönderilir ve soket 1000 koduyla kapatılır.

---

### 3.1. Kopma Durum Makinesi, Ağ Toleransı ve Beraberlik Tavanı

1. **Bağımsız Kopma Vadesi (`disconnectedUids`):**
   - Her oyuncunun kopma anı ve vadesi (`nowMs + disconnectTimeoutMs`) ayrı saklanır.
   - Cloudflare Durable Object alarmı her zaman bekleyen en yakın dolmamış vadeye kurulur (Tek Alarm Kuralı).

2. **Hükmen Mağlubiyet (Forfeit):**
   - Bir oyuncunun kopma vadesi dolduğunda rakibi **o anda bağlıysa**: vadesi dolan oyuncu hükmen yenik (`endedBy: 'forfeit'`) sayılır; bağlı kalan galip oyuncuya enerji iade edilir.

3. **İki Oyuncu da Kopukken Tur Süresinin Dondurulması (EK ŞART):**
   - Her iki oyuncu da aynı anda odada yokken turn timeout süresi dondurulur (`turnDeadlineMs` temizlenir, nominal kalan süre `frozenTurnRemainingMs` saklanır).
   - Odada hiç oyuncu yokken turnTimeout alarmı asla tur sonucu (1-0, 2-0 vb.) veya maç sonucu üretmez.

4. **Karşılıklı Kopmada İptal (Voided):**
   - Bir oyuncunun vadesi dolduğunda rakibi de kopuksa ve rakibin vadesi henüz dolmadıysa beklenir.
   - İkinci oyuncunun da vadesi dolduğunda ikisi de dönmemişse maç `both_disconnected` sebebiyle `voided` ilan edilir ve her iki oyuncuya enerjileri iade edilir.

5. **Geri Dönüş (Reconnect):**
   - Oyuncu geri döndüğünde yalnızca kendi kopma kaydı silinir.
   - Rakip kopuk ve vadesi **zaten dolmuşsa**: o anda rakip hükmen yenik sayılır ve dönen oyuncu kazanır.
   - Rakip bağlıysa veya vadesi henüz dolmamışsa: dondurulan nominal tur süresi (`Math.max(1000, frozenTurnRemainingMs)`) üzerinden devam eder, alarm vadesine ağ toleransı eklenir.

6. **Ağ Gecikmesi Toleransı (`TURN_GRACE_MS`):**
   - Sunucu tarafında `TURN_GRACE_MS` (varsayılan: 400 ms) ile cevap kabul toleransı uygulanır (`MatchConfig.graceMs`).
   - İstemciye giden `state.deadlineMs` nominal kalır; böylece istemci arayüzündeki geri sayım çubuğu nominal 15 saniyeyi gösterir.
   - Durable Object `schedule.turnDeadlineMs` alarmı `state.deadlineMs + turnGraceMs` zamanına kurulur.
   - Son milisaniyelerde gönderilen cevaplar ağ gecikmesi olsa dahi tolerans dahilinde kabul edilir.

7. **Beraberlik Tavanı (`maxTotalRounds = 5`):**
   - Peş peşe berabere biten turların sonsuza kadar uzamasını önlemek için azami toplam tur sayısı 5 ile sınırlandırılmıştır.
   - 5. turun sonunda skor eşit değilse (örn. 1-0), daha yüksek puana sahip olan taraf kazanır (`endedBy: 'points_reached'`).
   - 5. turun sonunda skor eşitse (örn. 0-0, 1-1, 2-2), maç berabere biter (`endedBy: 'draw_limit_reached'`), oda `voided` (`draw_limit_reached`) durumuna geçer, her iki oyuncuya enerji iade edilir, coin ve lig puanı değişmez. İstemcide bot maçında da aynı tavan geçerlidir ve maç eşleştirmeye yönlendirilir.

#### Güçlendirici Onayı / Yanıtı (`powerup_ack`)
Yalnızca güçlendiriciyi kullanmak isteyen oyuncuya gönderilir:
```json
{
  "t": "powerup_ack",
  "powerupType": "extra_time",
  "success": true,
  "deadlineMs": 1728518420000,
  "coins": 70,
  "remainingUses": 0
}
```
Başarısızlık durumunda:
```json
{
  "t": "powerup_ack",
  "powerupType": "extra_time",
  "success": false,
  "code": "not_enough_coins" | "already_used" | "not_your_turn" | "round_not_active" | "not_allowed_in_match_type" | "account_deleted",
  "message": "Açıklayıcı Türkçe hata mesajı"
}
```

#### Rakip Güçlendirici Bildirimi (`opponent_powerup`)
Rakip oyuncu bir güçlendirici kullandığında bilgi amaçlı iletilir:
```json
{
  "t": "opponent_powerup",
  "powerupType": "extra_time",
  "seconds": 5
}
```

---

## 4. Deneme Görünürlük ve Gizlilik Kuralları (Attempt Visibility)

- **Tekrarlanan Cevaplar (`repeated` / `alreadySaid`):**
  - Kendisinin veya rakibin daha önce verdiği bir cevabı tekrar yazan oyuncuya `{ "t": "feedback", "kind": "alreadySaid" }` iletilir.
  - Aktif tur sırasında (`roundActive: true`) tekrarlanan cevaplar `state.attempts` listesine eklenmez; böylece chat akışına balon olarak girmez.
  - Tur bittikten sonra (`roundEnded`) ve maç detayında (`final.rounds`) ham deneme kaydı korunur.

- **Yakın Deneme Gizlilik Kuralları (Near-Miss Secrecy):**
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

---

## 8. HTTP REST API Uç Noktaları

Tüm isteklerde `Authorization: Bearer <token>` başlığı zorunludur. Silinmiş hesaplar tüm uçlardan `410 Gone` alır.

### Profil ve Hesap
- `GET /me`: Kullanıcı profilini (`uid`, `nickname`, `coins`, `stats`: `{ played, won, lost, correctAnswers }`, `createdAt`, `equippedFrame`, `energy`) döndürür. İstatistikler yalnızca ranked online maçları içerir (bot ve arkadaş düellosu sayılmaz). `winRate` sunucudan dönmez; istemcide `won / played` oranıyla hesaplanır. Mevcut kullanıcılarda doğru cevap sayacı güncelleme anından itibaren birikir.
- `PUT /me/nickname`: Takma ad günceller (`{ "nickname": "..." }`).
- `DELETE /me`: Hesabı siler (`200 OK`, 24 saatlik tombstone kaydı bırakır).
- `PUT /me/frame`: Avatar çerçevesini kuşandırır (`{ "frameId": "..." }`). Sahip olunmayan çerçeve için `400 item_not_owned` döner. Liderlik tablosundaki çerçeveyi de günceller.

### Mağaza (Store)
- `GET /store`: Mağaza durumu ve katalog ürünlerini döndürür:
  ```json
  {
    "coins": 100,
    "equippedFrame": "classic",
    "items": [
      {
        "id": "classic",
        "name": "Klasik",
        "cost": 0,
        "description": "Sade ve şık orijinal kenarlık",
        "order": 1,
        "isOwned": true,
        "isEquipped": true
      },
      ...
    ]
  }
  ```
- `POST /store/purchase`: Jetonla avatar çerçevesi satın alır (`{ "itemId": "mint" }`).
  - Başarılı: `200 OK` (`{ "success": true, "itemId": "mint", "coins": 0 }`).
  - Yetersiz bakiye: `402 Payment Required` (`{ "error": "not_enough_coins", "coins": ... }`).
  - Zaten sahip olunan ürün: `400 Bad Request` (`{ "error": "already_owned" }`).
  - Geçersiz ürün: `400 Bad Request` (`{ "error": "invalid_item" }`).

### Liderlik Tablosu
- `GET /leaderboard`: Haftalık ilk 50 oyuncuyu ve istek yapanın sırasını döndürür. Her öğede `frame` (varsayılan: `"classic"`) yer alır.


