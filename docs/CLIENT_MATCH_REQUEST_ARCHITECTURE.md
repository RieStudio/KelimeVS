# İstemci Maç İsteği Mimarisi (Client Match Request Architecture)

Bu doküman, KelimeVS uygulamasında kullanıcı ön plandayken çalışan `/ws/user` WebSocket bağlantısının yaşam döngüsünü, varlık (presence) yönetimini, durum akışını ve FAZ 3 arayüz katmanına sunulan API sözleşmesini açıklar.

---

## 1. Genel Mimari ve Sorumluluk Dağılımı

"Maç İsteği" sistemi hem maç sonu **Rövanş** tekliflerini hem de profilden gönderilen **Dostluk Maçı** isteklerini tek bir ortak istemci-sunucu omurgası üzerinden yürütür.

```
                              ┌─────────────────────────────────────────┐
                              │     UserInboxLifecycleCoordinator       │
                              │  (WidgetsBindingObserver, Auth, Profile)│
                              └────────────────────┬────────────────────┘
                                                   │ evaluateConnection()
                                                   ▼
┌─────────────────────────┐   gönderim/olaylar   ┌───────────────────────────┐
│     PresenceController  │ ◄──────────────────► │      UserInboxClient      │ ◄────► /ws/user (Durable Object)
│ (Ref-counted meşguliyet)│                      │   (WebSocket Katmanı)     │
└─────────────────────────┘                      └─────────────┬─────────────┘
                                                               │ events
                                                               ▼
                                                 ┌───────────────────────────┐
                                                 │   MatchRequestsNotifier   │
                                                 │    (Riverpod Durumu)      │
                                                 └─────────────┬─────────────┘
                                                               │
                                         ┌─────────────────────┴─────────────────────┐
                                         ▼                                           ▼
                              MatchRequestsState                           matchedEvents (Stream)
                       (incoming, outgoing, errors)                         (FAZ 3 Navigasyon)
```

---

## 2. Bağlantı Yaşam Döngüsü (`UserInboxLifecycleCoordinator`)

### 2.1 Bağlanma Koşulları (shouldConnect)
Uygulama istemcisi yalnızca aşağıdaki 3 koşul **aynı anda** sağlandığında `/ws/user` soketine bağlı kalır:
1. `isAuthenticated == true`: Kullanıcı anonim veya Google ile Firebase oturumu açmış olmalıdır.
2. `hasNickname == true`: Kullanıcının takma adı olmalıdır (onboarding / nickname seçimi tamamlanmış olmalıdır).
3. `isForeground == true`: Uygulama ön planda (aktif) olmalıdır.

### 2.2 Arka Plan / Ön Plan Geçişleri
- **Arka Plana Geçiş (`paused`, `inactive`, `detached`, `hidden`):**
  - Cihaz arka plana geçtiğinde sunucuya gereksiz bağlantı yükü bindirmemek ve süresi dolacak istekleri yerelde temizlemek için soket temiz bir şekilde kapatılır (`code: 1000`, `reason: 'app_backgrounded'`).
  - `matchRequestsProvider.notifier.clearLocalRequests()` çağrılarak yerel bekleyen `incoming` ve `outgoing` istekler temizlenir.
- **Ön Plana Dönüş (`resumed`):**
  - `_isForeground = true` yapılır.
  - `evaluateConnection()` çalıştırılır; taze Firebase ID token alınarak `/ws/user` soketi yeniden bağlanır.
  - Bağlantı kurulur kurulmaz sunucudan güncel snapshot (`match_request_received` veya `match_request_sent`) beklenir ve yetkili kabul edilir.

### 2.3 Oturum Kapatma (`onSignOut`) ve Hesap Silinmesi
- **Sign Out:**
  - `presenceControllerProvider.notifier.forceReset()` ile tüm meşguliyet kilitleri sıfırlanır (`idle`).
  - `matchRequestsProvider.notifier.reset()` ile tüm istek ve hata durumları sıfırlanır.
  - Soket `code: 1000`, `reason: 'sign_out'` ile kapatılır.
- **Hesap Silinmesi (Permanent Deletion):**
  - Sunucu soketi `4001` kodu ile kapatırsa veya HTTP el sıkışmasında `410 Gone` dönerse istemci yeniden bağlanma döngüsünü kalıcı olarak durdurur ve `onAccountDeleted` kancasını tetikler.

### 2.4 Kalp Atışı (Ping/Pong) ve Yeniden Bağlanma
- **Kalp Atışı:**
  - Her 25 saniyede bir `{t: "ping"}` gönderilir.
  - 10 saniye içinde `{t: "pong"}` gelmezse soket "ölü" kabul edilerek zorla kapatılır ve yeniden bağlanma tetiklenir.
- **Yeniden Bağlanma:**
  - Beklenmedik kopmalarda üstel geri çekilme + ±%20 jitter uygulanır (1s, 2s, 4s, 8s, 16s... maksimum 30s).
  - Her yeniden bağlanma denemesinde `AuthTokenProvider` üzerinden **taze Firebase ID token** talep edilir.

---

## 3. Varlık (Presence) Yönetimi (`PresenceController`)

Kullanıcının maçta veya eşleşme kuyruğunda olup olmadığını sunucuya bildirmek için referans sayaçlı bir yapı kullanılır.

### 3.1 Belirteçler (Keyed Tokens)
Aşağıdaki ekran ve oturumlar yaşam döngüleri boyunca kendi benzersiz anahtarlarıyla meşguliyet alır:
- `matchmaking`: Online rankli eşleşme arama ekranı (`MatchmakingScreen`).
- `friend_host`: Oda kurma ekranı (`FriendHostScreen`).
- `friend_join`: Odaya katılma ekranı (`FriendJoinScreen`).
- `friend_reveal`: Maç başlangıç geri sayım ekranı (`FriendMatchRevealScreen`).
- `online_match`: Aktif canlı online maç odası (`OnlineMatchSession`).
- `bot_match`: Aktif bot maçı oturumu (`MatchController`).

### 3.2 İkili Durum ve Tekilleştirme (Deduplication)
- İç yapıda `Set<String> _busyTokens` tutulur.
- `_busyTokens.isNotEmpty` ise durum `busy`, boş ise `idle`dır.
- Birden fazla ekran ardışık olarak `busy` bildirirse (örneğin matchmaking -> reveal -> match) durum `busy` kalmaya devam eder ve sunucuya **mükerrer soket mesajı iletilmez**.
- Yeni bir WebSocket bağlantısı kurulduğunda `attachClient` mevcut güncel durumu derhal ilk mesaj olarak sunucuya iletir.
- **Güvenlik Ağı (`forceReset`):** Olası sayaç sızıntılarına karşı oturum kapatıldığında veya maç sonu ekranından ana menüye dönüldüğünde tüm tokenlar tek hamlede temizlenebilir.

---

## 4. Durum Yönetimi ve Reducer (`MatchRequestsNotifier`)

### 4.1 Tekil İstek Garantisi
- İstemci durumunda aynı anda en fazla **1 gelen (`incoming`)** ve **1 giden (`outgoing`)** istek tutulur.
- Yeni bir istek geldiğinde önceki isteğin yerini alır (sunucunun tekil istek politikası ile uyumlu).

### 4.2 Saat Sapması Telafisi (`calculateRemainingSeconds`)
Cihaz saati sunucu saatinden ileri veya geri olsa dahi, arayüzde gösterilecek kalan süre aşağıdaki formülle hesaplanır:
$$\text{serverRemainingMs} = \text{expiresAtMs} - \text{localNowMs}$$
$$\text{elapsedLocalMs} = \max(0, \text{localNowMs} - \text{receivedAtLocalMs})$$
$$\text{localRemainingMs} = 45000 - \text{elapsedLocalMs}$$
$$\text{effectiveRemainingSec} = \left\lceil \frac{\min(\text{serverRemainingMs}, \text{localRemainingMs})}{1000} \right\rceil.clamp(0, 45)$$
Bu sayede cihaz saati ne kadar saparsa sapsın:
- Asla 45 saniyenin üzerinde bir süre gösterilmez.
- Asla negatif bir süreye düşmez.
- Hangi taraf önce biterse süre o anda 0 kabul edilir.

---

## 5. FAZ 3 İçin Sunulan İstemci API'si

FAZ 3'te geliştirilecek UI bileşenleri (üst bildirim bandı, maç sonu rövanş butonu, profil maç isteği butonu) aşağıdaki hazır Riverpod API'sini kullanacaktır:

### 5.1 Provider'lar
```dart
// İstek durumunu dinlemek için:
final matchState = ref.watch(matchRequestsProvider);

// Varlık durumunu okumak için:
final presenceState = ref.watch(presenceControllerProvider);

// Maç isteklerini kapatma ayarını okumak için:
final allowMatchRequests = ref.watch(profileProvider.select((p) => p.allowMatchRequests));
```

### 5.2 Eylemler
```dart
// 1. Yeni istek gönderme
final success = await ref.read(matchRequestsProvider.notifier).sendRequest(
  origin: MatchRequestOrigin.profile, // veya MatchRequestOrigin.rematch
  toUid: targetUserId,
  matchId: finishedMatchId, // rematch için zorunlu
);

// 2. Gelen isteği kabul etme
await ref.read(matchRequestsProvider.notifier).accept(requestId);

// 3. Gelen isteği reddetme
await ref.read(matchRequestsProvider.notifier).decline(requestId);

// 4. Giden isteği iptal etme
await ref.read(matchRequestsProvider.notifier).cancel(requestId);

// 5. Maç isteklerini kapatma/açma ayarını güncelleme
await ref.read(profileProvider.notifier).updateAllowMatchRequests(false);
```

### 5.3 Navigasyon Akışı (`matchedEvents`)
İstek kabul edildiğinde sunucudan gelen `matched` mesajı `MatchRequestsNotifier.matchedEvents` yayın akışına (broadcast stream) iletilir. FAZ 3'te global navigasyon dinleyicisi bu akışı dinleyerek iki tarafı da `FriendMatchRevealScreen` veya maç ekranına aktaracaktır:
```dart
ref.listen(matchRequestsProvider.notifier.matchedEvents, (previous, event) {
  // Reveal ekranına geçiş
});
```
