# KelimeGo Paylaşılan Test Vektörleri (Shared Test Vectors)

Bu dizin, KelimeGo oyun motorunun kurallarını ve saf fonksiyonlarını doğrulamak için Dart motorundan üretilmiş referans test verilerini içerir. Amaç, gelecekte geliştirilecek **TypeScript oyun motorunun (Cloudflare Worker / Durable Object)** Dart motoru ile birebir aynı davranış ve kurallarla çalışmasını garanti etmektir.

Tüm test dosyaları deterministiktir ve `app/tool/export_test_vectors.dart` betiği tarafından üretilir:
```bash
cd app
dart run tool/export_test_vectors.dart
```

---

## Dosya Yapısı ve Şemalar

Tüm JSON dosyalarında kök düzeyde `"version": 1` alanı bulunur.

### 1. `normalizer.json`
Metin normalizasyonu (`TextNormalizer`) için Türkçe büyük/küçük harf dönüşümü, aksan katlama, noktalama temizliği, `c`/`c++`/`c#` koruması ve boşluk düzenlemesini test eder.

- **Şema**:
```json
{
  "version": 1,
  "description": "...",
  "totalCases": 102,
  "cases": [
    {
      "id": "norm_001",
      "input": "ISPANAK",
      "expected": "ispanak"
    }
  ]
}
```
- **TypeScript Doğrulaması**:
```typescript
import normalizerVectors from './normalizer.json';
import { normalize } from '../src/domain/text_normalizer';

for (const tc of normalizerVectors.cases) {
  expect(normalize(tc.input)).toBe(tc.expected);
}
```

---

### 2. `matcher.json`
Cevap eşleştirici (`AnswerMatcher`) ve alias dizinlemesi testleri. Kullanılmış cevaplar (`usedAnswerIds`) seti verildiğinde girdinin sonucunu (`correct`, `repeated`, `wrong`, `empty`), eşleşen `answerId` değerini ve henüz söylenmemiş cevaplara yakınlığını (`isClose`) doğrular.

- **Şema**:
```json
{
  "version": 1,
  "description": "...",
  "totalCases": 50,
  "cases": [
    {
      "id": "match_001",
      "description": "exact display match",
      "question": {
        "id": "q_g20",
        "categoryId": "genel_kultur",
        "title": "G20 Ülkeleri",
        "answers": [
          {
            "id": "guney_kore",
            "display": "Güney Kore",
            "aliases": ["guney kore", "kore"]
          }
        ]
      },
      "input": "Güney Kore",
      "usedAnswerIds": [],
      "expectedResult": "correct",
      "expectedAnswerId": "guney_kore",
      "expectedIsClose": false
    }
  ]
}
```
- **TypeScript Doğrulaması**:
```typescript
import matcherVectors from './matcher.json';
import { AnswerMatcher } from '../src/domain/answer_matcher';
import { isNearMiss } from '../src/domain/near_miss';

for (const tc of matcherVectors.cases) {
  const matcher = new AnswerMatcher(tc.question);
  const res = matcher.check(tc.input, new Set(tc.usedAnswerIds));
  expect(res.type).toBe(tc.expectedResult);
  expect(res.answer?.id ?? null).toBe(tc.expectedAnswerId);
  if (res.type === 'wrong') {
    const isClose = isNearMiss(tc.input, matcher.getUnusedAliases(new Set(tc.usedAnswerIds)));
    expect(isClose).toBe(tc.expectedIsClose);
  }
}
```

---

### 3. `near_miss.json`
"Çok yakın" toleransı ve Damerau-Levenshtein (OSA) mesafe hesabı (`NearMissCalculator`). Eşik kuralları:
- $\le 3$ karakter: kapalı (maksimum mesafe: 0, `isClose: false`)
- 4–8 karakter: 1 düzenleme (`maxAllowedDistance: 1`)
- 9+ karakter: 2 düzenleme (`maxAllowedDistance: 2`)

- **Şema**:
```json
{
  "version": 1,
  "description": "...",
  "totalCases": 44,
  "cases": [
    {
      "id": "nm_001",
      "description": "exact match 3 chars",
      "word1": "van",
      "word2": "van",
      "targetLength": 3,
      "maxAllowedDistance": 0,
      "distance": 0,
      "isClose": false
    }
  ]
}
```
- **TypeScript Doğrulaması**:
```typescript
import nearMissVectors from './near_miss.json';
import { distance, maxAllowedDistance } from '../src/domain/near_miss';

for (const tc of nearMissVectors.cases) {
  expect(maxAllowedDistance(tc.targetLength)).toBe(tc.maxAllowedDistance);
  expect(distance(tc.word1, tc.word2)).toBe(tc.distance);
}
```

---

### 4. `visibility.json`
İstemci tarafında ve sunucu bildirimlerinde deneme görünürlük filtresi (`visibleAttempts`).
Kurallar:
- Tur aktifken (`roundActive = true`):
  - `hintShown = true`: HERKESE gizli.
  - `isClose = true, hintShown = false`: Sahibine görünür, rakibe gizli.
  - Normal yanlış, doğru ve tekrar cevaplar: Herkese görünür.
- Tur bittiğinde (`roundActive = false`): Tüm denemeler herkese görünür.

- **Şema**:
```json
{
  "version": 1,
  "description": "...",
  "totalCases": 25,
  "cases": [
    {
      "id": "vis_001",
      "description": "Mixed attempts: p1 view during active round",
      "attempts": [ ... ],
      "viewerId": "p1",
      "roundActive": true,
      "expectedVisibleIndices": [0, 2, 3, 4, 7]
    }
  ]
}
```
- **TypeScript Doğrulaması**:
```typescript
import visibilityVectors from './visibility.json';
import { visibleAttempts } from '../src/domain/visibility';

for (const tc of visibilityVectors.cases) {
  const visible = visibleAttempts(tc.attempts, tc.viewerId, tc.roundActive);
  const indices = visible.map(a => tc.attempts.indexOf(a));
  expect(indices).toEqual(tc.expectedVisibleIndices);
}
```

---

### 5. `engine_scenarios.json`
Tam maç akışı senaryoları (`MatchEngine`). 26 farklı senaryo içerir:
- 2-0 temiz galibiyet (P1 / P2)
- 2-1 çekişmeli maç
- Cevap tükenmesiyle beraberlikler (exhausted)
- Başlangıç ve sıradaki oyuncu süre aşımları (timeout)
- Çift süre aşımı
- Terk (forfeit) varyasyonları: aktif turda, turlar arasında, maç bitmişken (ignored), skorun dondurulması, çift terk
- "Çok yakın" ipucu kotası tükenmesi
- Sıra devri ve yanlış cevapta sıranın kalması
- Boş ve tekrar cevapların reddedilmesi
- Tur başlatıcı dönüşümü (1. tur P1, 2. tur P2, 3. tur P1)
- Kötüye kullanım önleme (`tooFast` < 600 ms, `not_player_turn`)
- Süre sayımı tick ve roundEnded bekleme adımları

- **Şema**:
```json
{
  "version": 1,
  "description": "...",
  "totalScenarios": 26,
  "scenarios": [
    {
      "id": "scen_01_clean_win_p1",
      "name": "2-0 Clean Win (P1 wins)",
      "description": "...",
      "config": {
        "roundsToWin": 2,
        "answerSeconds": 15,
        "graceMs": 0,
        "nearMissPerRound": 1,
        "minAnswersPerQuestion": 0,
        "minSubmitIntervalMs": 600,
        "maxAttemptsPerTurn": 25
      },
      "playerIds": ["p1", "p2"],
      "questionOrder": ["q1", "q2", "q3"],
      "initialNowMs": 1000,
      "initialStateSnapshot": { ... },
      "steps": [
        {
          "stepIndex": 0,
          "action": "submit | tick | forfeit | startNextRound",
          "payload": { ... },
          "expectedEvents": [
            {
              "type": "AnswerAccepted",
              "playerId": "p1",
              "answerDisplay": "Audi"
            }
          ],
          "expectedStateSnapshot": {
            "phase": "roundActive | roundEnded | matchFinished",
            "turnPlayerId": "p2",
            "scores": { "p1": 0, "p2": 0 },
            "decisiveRounds": 0,
            "totalRoundsPlayed": 0,
            "currentQuestionId": "q1",
            "winnerId": null,
            "endedBy": null,
            "usedAnswerIds": ["audi"],
            "remainingNearMisses": { "p1": 1, "p2": 1 },
            "attemptsCount": 1,
            "deadlineMs": 18000
          }
        }
      ]
    }
  ]
}
```
- **TypeScript Doğrulaması**:
```typescript
import scenariosData from './engine_scenarios.json';
import { MatchEngine } from '../src/domain/match_engine';

for (const scen of scenariosData.scenarios) {
  let state = MatchEngine.start({
    config: scen.config,
    playerIds: scen.playerIds,
    questions: questionsPool,
    questionOrder: scen.questionOrder,
    nowMs: scen.initialNowMs,
  });

  for (const step of scen.steps) {
    let result;
    switch (step.action) {
      case 'submit':
        result = MatchEngine.submit(state, step.payload);
        break;
      case 'tick':
        result = MatchEngine.checkTimeout(state, step.payload.nowMs);
        break;
      case 'forfeit':
        result = MatchEngine.forfeit(state, step.payload.playerId, step.payload.nowMs);
        break;
      case 'startNextRound':
        result = MatchEngine.startNextRound(state, questionsPool, step.payload.nowMs);
        break;
    }
    state = result.state;
    expect(result.events).toMatchObject(step.expectedEvents);
    expect(snapshot(state)).toMatchObject(step.expectedStateSnapshot);
  }
}
```

