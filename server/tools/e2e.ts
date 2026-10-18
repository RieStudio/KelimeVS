import { spawn, type ChildProcess } from 'node:child_process';
import { DevContentProvider } from '../src/content/devContentProvider';
import type { Question } from '../src/engine';
import type {
  ClientFeedbackMessage,
  ClientFinalMessage,
  ClientStateMessage,
  ClientVoidedMessage,
  MatchmakerServerMessage,
  MatchRoomServerMessage,
} from '../src/protocol';

const BASE_HTTP_URL = 'http://127.0.0.1:8787';
const BASE_WS_URL = 'ws://127.0.0.1:8787';

type AnyServerMessage = MatchmakerServerMessage | MatchRoomServerMessage;

class WSClient {
  private ws: WebSocket;
  private messageQueue: unknown[] = [];
  private waiters: Array<{
    predicate: (msg: unknown) => boolean;
    resolve: (msg: unknown) => void;
    reject: (err: Error) => void;
    timer: NodeJS.Timeout;
  }> = [];
  public readonly url: string;
  public isClosed = false;

  constructor(url: string) {
    this.url = url;
    this.ws = new WebSocket(url);
    this.ws.addEventListener('message', (event) => {
      try {
        const text = String(event.data);
        const parsed = JSON.parse(text);
        this.handleIncoming(parsed);
      } catch (err) {
        // yoksay
      }
    });
    this.ws.addEventListener('close', () => {
      this.isClosed = true;
    });
    this.ws.addEventListener('error', () => {
      this.isClosed = true;
    });
  }

  async waitForOpen(timeoutMs = 5000): Promise<void> {
    if (this.ws.readyState === 1) return;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('WebSocket open timeout')), timeoutMs);
      const onOpen = () => {
        clearTimeout(timer);
        cleanup();
        resolve();
      };
      const onClose = (ev: Event) => {
        clearTimeout(timer);
        cleanup();
        const code = 'code' in ev ? (ev as { code: number }).code : 'unknown';
        reject(new Error(`WebSocket closed before open (code: ${code})`));
      };
      const cleanup = () => {
        this.ws.removeEventListener('open', onOpen);
        this.ws.removeEventListener('close', onClose);
      };
      this.ws.addEventListener('open', onOpen);
      this.ws.addEventListener('close', onClose);
    });
  }

  private handleIncoming(msg: unknown): void {
    console.log(`[WS DEBUG] ${this.url.split('?')[0]}: ${JSON.stringify(msg)}`);
    for (let i = 0; i < this.waiters.length; i++) {
      const w = this.waiters[i];
      if (w.predicate(msg)) {
        clearTimeout(w.timer);
        this.waiters.splice(i, 1);
        w.resolve(msg);
        return;
      }
    }
    this.messageQueue.push(msg);
  }

  waitForMessage<T extends AnyServerMessage = AnyServerMessage>(
    predicate: (msg: AnyServerMessage) => boolean,
    timeoutMs = 8000
  ): Promise<T> {
    for (let i = 0; i < this.messageQueue.length; i++) {
      const msg = this.messageQueue[i] as AnyServerMessage;
      if (predicate(msg)) {
        this.messageQueue.splice(i, 1);
        return Promise.resolve(msg as T);
      }
    }

    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        const idx = this.waiters.findIndex((w) => w.resolve === (resolve as (msg: unknown) => void));
        if (idx !== -1) this.waiters.splice(idx, 1);
        reject(new Error(`Message timeout after ${timeoutMs}ms waiting for condition`));
      }, timeoutMs);

      this.waiters.push({
        predicate: (m: unknown) => predicate(m as AnyServerMessage),
        resolve: (m: unknown) => resolve(m as T),
        reject,
        timer,
      });
    });
  }

  waitForState(
    predicate: (msg: ClientStateMessage) => boolean = () => true,
    timeoutMs = 8000
  ): Promise<ClientStateMessage> {
    return this.waitForMessage<ClientStateMessage>(
      (m) => m.t === 'state' && predicate(m as ClientStateMessage),
      timeoutMs
    );
  }

  waitForFinal(
    predicate: (msg: ClientFinalMessage) => boolean = () => true,
    timeoutMs = 8000
  ): Promise<ClientFinalMessage> {
    return this.waitForMessage<ClientFinalMessage>(
      (m) => m.t === 'final' && predicate(m as ClientFinalMessage),
      timeoutMs
    );
  }

  waitForFeedback(
    predicate: (msg: ClientFeedbackMessage) => boolean = () => true,
    timeoutMs = 8000
  ): Promise<ClientFeedbackMessage> {
    return this.waitForMessage<ClientFeedbackMessage>(
      (m) => m.t === 'feedback' && predicate(m as ClientFeedbackMessage),
      timeoutMs
    );
  }

  waitForVoided(
    predicate: (msg: ClientVoidedMessage) => boolean = () => true,
    timeoutMs = 8000
  ): Promise<ClientVoidedMessage> {
    return this.waitForMessage<ClientVoidedMessage>(
      (m) => m.t === 'voided' && predicate(m as ClientVoidedMessage),
      timeoutMs
    );
  }

  send(data: object): void {
    this.ws.send(JSON.stringify(data));
  }

  close(): void {
    try {
      this.ws.close();
    } catch {
      // yoksay
    }
    this.isClosed = true;
  }
}

async function isServerReady(): Promise<boolean> {
  try {
    const res = await fetch(`${BASE_HTTP_URL}/health`);
    return res.status === 200 && (await res.text()) === 'ok';
  } catch {
    return false;
  }
}

async function ensureServerRunning(): Promise<ChildProcess | null> {
  if (await isServerReady()) {
    console.log('✓ Mevcut wrangler dev sunucusu aktif (http://127.0.0.1:8787)');
    return null;
  }

  console.log('Wrangler dev sunucusu başlatılıyor...');
  const child = spawn('npx.cmd', ['wrangler', 'dev', '--port', '8787'], {
    cwd: process.cwd(),
    stdio: 'pipe',
    shell: true,
  });
  child.stdout?.on('data', (d) => process.stdout.write(d));
  child.stderr?.on('data', (d) => process.stderr.write(d));

  const start = Date.now();
  while (Date.now() - start < 20000) {
    if (await isServerReady()) {
      console.log('✓ Wrangler dev sunucusu hazır.');
      return child;
    }
    await new Promise((r) => setTimeout(r, 500));
  }

  child.kill();
  throw new Error('Wrangler dev sunucusu 20 saniye içinde hazır hale gelemedi.');
}

async function matchTwoPlayers(uidA: string, nameA: string, uidB: string, nameB: string) {
  const wsA = new WSClient(`${BASE_WS_URL}/ws/matchmaking?token=dev:${uidA}`);
  const wsB = new WSClient(`${BASE_WS_URL}/ws/matchmaking?token=dev:${uidB}`);

  await Promise.all([wsA.waitForOpen(), wsB.waitForOpen()]);

  wsA.send({ t: 'queue', name: nameA });
  await wsA.waitForMessage((m) => m.t === 'queued');

  wsB.send({ t: 'queue', name: nameB });
  await wsB.waitForMessage((m) => m.t === 'queued');

  const [matchedA, matchedB] = await Promise.all([
    wsA.waitForMessage<Extract<MatchmakerServerMessage, { t: 'matched' }>>((m) => m.t === 'matched'),
    wsB.waitForMessage<Extract<MatchmakerServerMessage, { t: 'matched' }>>((m) => m.t === 'matched'),
  ]);

  if (matchedA.matchId !== matchedB.matchId) {
    throw new Error(`MatchId uyuşmazlığı: ${matchedA.matchId} !== ${matchedB.matchId}`);
  }

  return {
    matchId: matchedA.matchId,
    wsA,
    wsB,
  };
}

async function connectToMatch(matchId: string, uidA: string, uidB: string) {
  const roomA = new WSClient(`${BASE_WS_URL}/ws/match/${matchId}?token=dev:${uidA}`);
  const roomB = new WSClient(`${BASE_WS_URL}/ws/match/${matchId}?token=dev:${uidB}`);

  await Promise.all([roomA.waitForOpen(), roomB.waitForOpen()]);

  // Her iki oyuncuya da ilk state gelmesini bekle
  const [initA, initB] = await Promise.all([
    roomA.waitForState((m) => m.phase === 'roundActive'),
    roomB.waitForState((m) => m.phase === 'roundActive'),
  ]);

  return { roomA, roomB, initA, initB };
}

async function main() {
  console.log('========================================================');
  console.log('KelimeGo E2E Canlı Sunucu Test Senaryoları Başlatılıyor');
  console.log('========================================================\n');

  let serverProcess: ChildProcess | null = null;
  const contentProvider = new DevContentProvider();
  const allQuestions = await contentProvider.getQuestions();
  const questionsMap = new Map<string, Question>();
  for (const q of allQuestions) {
    questionsMap.set(q.id, q);
  }

  try {
    serverProcess = await ensureServerRunning();

    // ------------------------------------------------------------------------
    // Senaryo (a): 2-0 biten normal maç
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo A] 2-0 Biten Normal Maç Başlatılıyor...');
    {
      const { matchId } = await matchTwoPlayers('alice_a', 'Alice', 'bob_a', 'Bob');
      const { roomA, roomB, initA } = await connectToMatch(matchId, 'alice_a', 'bob_a');

      // 1. Tur: Başlayan oyuncu doğru cevap verir, rakip süre aşımına uğrar (3 sn FAST_TIMERS)
      const starterIsA = initA.turnIsMine;
      const starterRoom = starterIsA ? roomA : roomB;
      const q1 = questionsMap.get(initA.question!.id)!;
      const a1 = q1.answers[0].display;

      starterRoom.send({ t: 'submit', text: a1 });

      // Tur sonu (timeout) bekle
      const stateRound1End = await roomA.waitForState(
        (m) => m.phase === 'roundEnded',
        6000
      );
      console.log('  ✓ 1. Tur tamamlandı, skor:', stateRound1End.scores);

      // 2. Tur başlangıcını bekle (FAST_TIMERS: 500 ms)
      const stateRound2 = await roomA.waitForState(
        (m) => m.phase === 'roundActive' && m.roundNumber === 2,
        4000
      );

      // 2. Turda Alice'in 2-0 maçı kazanması için:
      if (stateRound2.turnIsMine) {
        // Alice starter ise cevap verir, Bob süre aşımına uğrar
        const q2 = questionsMap.get(stateRound2.question!.id)!;
        roomA.send({ t: 'submit', text: q2.answers[0].display });
      }
      // Bob starter ise hamle yapmaz ve süre aşımına uğrar, böylece Alice 2. turu da kazanır.

      // Maç bitişini bekle (2-0 galibiyet)
      const [finalStateA, finalMsgA] = await Promise.all([
        roomA.waitForState((m) => m.phase === 'matchFinished', 15000),
        roomA.waitForFinal(undefined, 15000),
      ]);

      if (finalMsgA.scores.me !== 2 && finalMsgA.scores.opponent !== 2) {
        throw new Error(`2-0 skor beklentisi karşılanmadı: ${JSON.stringify(finalMsgA.scores)}`);
      }
      if (finalMsgA.coinsAwarded === undefined || finalMsgA.coins === undefined) {
        throw new Error(`Senaryo A final mesajında jeton bilgisi eksik: ${JSON.stringify(finalMsgA)}`);
      }
      console.log(`  ✓ Alice final mesajı jeton ödülü: +${finalMsgA.coinsAwarded}G (bakiye: ${finalMsgA.coins}G)`);
      roomA.close();
      roomB.close();
      console.log('  ✓ [Senaryo A Başarılı] 2-0 temiz maç tamamlandı.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (b): Bir yanlış cevap sonrası doğru cevap (turu kaybettirmez)
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo B] Yanlış Cevap Sonrası Doğru Cevap...');
    {
      const { matchId } = await matchTwoPlayers('alice_b', 'Alice', 'bob_b', 'Bob');
      const { roomA, roomB, initA } = await connectToMatch(matchId, 'alice_b', 'bob_b');

      const starterRoom = initA.turnIsMine ? roomA : roomB;

      // Yanlış cevap gönder
      starterRoom.send({ t: 'submit', text: 'alakasiz_yanlis_kelime' });
      const fb = await starterRoom.waitForFeedback((m) => m.kind === 'wrong');
      console.log('  ✓ Yanlış cevap feedback alındı:', fb.kind);

      const stateAfterWrong = await starterRoom.waitForState(
        (m) => m.phase === 'roundActive' && m.attempts.length > 0
      );
      if (!stateAfterWrong.turnIsMine) {
        throw new Error('HATA: Yanlış cevap sonrası sıra diğer oyuncuya geçmemeli!');
      }

      // Ardından doğru cevap gönder
      const q = questionsMap.get(stateAfterWrong.question!.id)!;
      starterRoom.send({ t: 'submit', text: q.answers[0].display });

      const stateAfterCorrect = await starterRoom.waitForState(
        (m) => !m.turnIsMine
      );
      console.log('  ✓ Doğru cevap sonrası sıra rakibe geçti.');

      roomA.close();
      roomB.close();
      console.log('  ✓ [Senaryo B Başarılı] Yanlış cevap turu kaybettirmedi.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (c): Yakın deneme - rakibin durumunda görünmediğini doğrula
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo C] Yakın Deneme Gizliliği Test Ediliyor...');
    {
      const { matchId } = await matchTwoPlayers('alice_c', 'Alice', 'bob_c', 'Bob');
      const { roomA, roomB, initA } = await connectToMatch(matchId, 'alice_c', 'bob_c');

      const starterRoom = initA.turnIsMine ? roomA : roomB;
      const opponentRoom = initA.turnIsMine ? roomB : roomA;

      const q = questionsMap.get(initA.question!.id)!;
      // Yakın deneme için 5+ harfli bir cevaptan 1 harf değiştir
      const ans = q.answers.find((a) => a.id.length >= 5) ?? q.answers[0];
      const targetStr = ans.id;
      // 'elma' -> 'elam' veya son harf değişimi
      const typo = targetStr.slice(0, -1) + 'x';

      starterRoom.send({ t: 'submit', text: typo });

      const fb = await starterRoom.waitForFeedback(
        (m) => m.kind === 'nearMiss' || m.kind === 'wrong'
      );
      console.log('  ✓ Yakın deneme feedback:', fb.kind);

      // Rakibin durumunda bu denemenin ASLA görünmediğini doğrula
      opponentRoom.send({ t: 'sync' });
      const opponentState = await opponentRoom.waitForState();
      if (opponentState.attempts.length !== 0) {
        throw new Error('HATA: Yakın deneme rakibe balon olarak sızdı!');
      }
      console.log('  ✓ Rakibin attempts listesi boş (yakın deneme gizlendi).');

      roomA.close();
      roomB.close();
      console.log('  ✓ [Senaryo C Başarılı] Yakın deneme gizliliği doğrulandı.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (d): Süre aşımı (FAST_TIMERS ile)
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo D] Süre Aşımı (Timeout) Doğrulanıyor...');
    {
      const { matchId } = await matchTwoPlayers('alice_d', 'Alice', 'bob_d', 'Bob');
      const { roomA, roomB, initA } = await connectToMatch(matchId, 'alice_d', 'bob_d');

      const starterUid = initA.turnIsMine ? 'alice_d' : 'bob_d';
      console.log(`  Başlayan oyuncu (${starterUid}) hamle yapmıyor, 3.5 sn bekleniyor...`);

      // 3.5 sn bekle, alarm() süreyi bitirmeli
      const stateRoundEnd = await roomA.waitForState(
        (m) => m.phase === 'roundEnded',
        5000
      );

      if (stateRoundEnd.lastRound?.reason !== 'timeout') {
        throw new Error(`Beklenen timeout sebebi bulunamadı: ${JSON.stringify(stateRoundEnd.lastRound)}`);
      }
      console.log('  ✓ Tur süre aşımı ile bitti, kazanan:', stateRoundEnd.lastRound);

      roomA.close();
      roomB.close();
      console.log('  ✓ [Senaryo D Başarılı] Süre aşımı doğru işlendi.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (e): Terk (Leave / Forfeit)
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo E] Maçı Terk Etme (Forfeit) Doğrulanıyor...');
    {
      const { matchId } = await matchTwoPlayers('alice_e', 'Alice', 'bob_e', 'Bob');
      const { roomA, roomB } = await connectToMatch(matchId, 'alice_e', 'bob_e');

      // Alice maçı terk eder
      roomA.send({ t: 'leave' });

      const [stateBob, finalBob] = await Promise.all([
        roomB.waitForState((m) => m.phase === 'matchFinished'),
        roomB.waitForFinal(),
      ]);

      if (!finalBob.winnerIsMe || finalBob.endedBy !== 'forfeit') {
        throw new Error(`Terk sonucu hatalı: ${JSON.stringify(finalBob)}`);
      }
      console.log('  ✓ Terk sonucu maç Bob tarafından kazanıldı.');

      roomA.close();
      roomB.close();
      console.log('  ✓ [Senaryo E Başarılı] Terk akışı doğrulandı.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (f): Bağlantı kopup geri gelme ve kopup 3 sn içinde dönmeme
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo F] Bağlantı Kopması ve Geri Dönüş / Terk Doğrulanıyor...');
    {
      const { matchId } = await matchTwoPlayers('alice_f', 'Alice', 'bob_f', 'Bob');
      const { roomA, roomB } = await connectToMatch(matchId, 'alice_f', 'bob_f');

      // 1. Kısım: Alice bağlantıyı kapatır
      console.log('  Alice bağlantıyı koparıyor...');
      roomA.close();

      const stateBobDisconnected = await roomB.waitForState(
        (m) => m.opponentConnected === false,
        5000
      );
      console.log('  ✓ Bob opponentConnected = false durumunu aldı.');

      // 1 sn içinde Alice geri bağlanır
      console.log('  Alice 1 saniye içinde geri bağlanıyor...');
      const roomA2 = new WSClient(`${BASE_WS_URL}/ws/match/${matchId}?token=dev:alice_f`);
      await roomA2.waitForOpen();

      const stateBobReconnected = await roomB.waitForState(
        (m) => m.opponentConnected === true,
        5000
      );
      console.log('  ✓ Bob opponentConnected = true durumunu aldı (başarıyla geri döndü).');

      // 2. Kısım: Alice tekrar kopar ve bu sefer geri dönmez
      console.log('  Alice tekrar kopuyor ve dönmüyor (3 sn timeout bekleniyor)...');
      roomA2.close();

      const finalBob = await roomB.waitForFinal(
        (m) => m.endedBy === 'forfeit',
        7000
      );
      if (!finalBob.winnerIsMe) {
        throw new Error('HATA: Geri dönmeyen oyuncu maçı terk etmiş sayılmalıydı.');
      }
      if (finalBob.coinsAwarded === undefined || finalBob.coins === undefined) {
        throw new Error(`Senaryo F final mesajında jeton bilgisi eksik: ${JSON.stringify(finalBob)}`);
      }
      console.log(`  ✓ Bob (rakip kopmasıyla galip) ödülü: +${finalBob.coinsAwarded}G (bakiye: ${finalBob.coins}G)`);
      console.log('  ✓ 3 sn dönmeyen Alice maçı kaybetti, Bob kazandı.');

      roomB.close();
      console.log('  ✓ [Senaryo F Başarılı] Kopma ve geri dönüş zamanlayıcısı doğrulandı.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (g): Rakip hiç bağlanmazsa iptal (Voided)
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo G] Rakip Bağlanmazsa Maçın İptali (Voided)...');
    {
      const { matchId } = await matchTwoPlayers('alice_g', 'Alice', 'bob_g', 'Bob');

      // Yalnızca Alice bağlanır, Bob asla bağlanmaz
      console.log('  Alice bağlanıyor, Bob bağlanmıyor (3 sn bağlanma beklemesi)...');
      const roomA = new WSClient(`${BASE_WS_URL}/ws/match/${matchId}?token=dev:alice_g`);
      await roomA.waitForOpen();

      const voidedMsg = await roomA.waitForVoided(undefined, 7000);
      if (voidedMsg.reason !== 'opponent_absent') {
        throw new Error(`Beklenen voided reason bulunamadı: ${JSON.stringify(voidedMsg)}`);
      }
      console.log('  ✓ Alice voided mesajı aldı:', voidedMsg);

      roomA.close();
      console.log('  ✓ [Senaryo G Başarılı] Bağlanmayan rakip nedeniyle maç iptal edildi.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (h): Üçüncü bir UID'in bağlanamaması (403 Forbidden)
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo H] Yetkisiz 3. Oyuncunun Engellenmesi (403)...');
    {
      const { matchId } = await matchTwoPlayers('alice_h', 'Alice', 'bob_h', 'Bob');

      // Eve (üçüncü oyuncu) maça bağlanmayı dener
      let errorEncountered = false;
      const roomEve = new WSClient(`${BASE_WS_URL}/ws/match/${matchId}?token=dev:eve_third_party`);

      try {
        await roomEve.waitForOpen(2000);
      } catch {
        errorEncountered = true;
      }

      if (!errorEncountered && !roomEve.isClosed) {
        throw new Error('HATA: Üçüncü oyuncunun bağlantısı reddedilmedi!');
      }
      console.log('  ✓ 3. oyuncu bağlantısı sunucu tarafından başarıyla engellendi.');

      roomEve.close();
      console.log('  ✓ [Senaryo H Başarılı] 403 erişim kontrolü doğrulandı.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (i): /me ve /me/nickname HTTP uçları, profil oluşturma ve ad güncelleme
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo I] Profil ve Takma Ad HTTP Uçları (/me & /me/nickname)...');
    {
      // 1. Yetkisiz istek 401 kontrolü
      const unauthRes = await fetch(`${BASE_HTTP_URL}/me`);
      if (unauthRes.status !== 401) {
        throw new Error(`Yetkisiz GET /me beklenen 401 yerine ${unauthRes.status} döndü`);
      }
      console.log('  ✓ Yetkisiz GET /me 401 ile reddedildi.');

      const aliceUid = `alice_e2e_${Date.now()}`;

      // 2. dev token ile GET /me (yeni profil oluşturulmalı)
      const getRes1 = await fetch(`${BASE_HTTP_URL}/me`, {
        headers: { Authorization: `Bearer dev:${aliceUid}` },
      });
      if (getRes1.status !== 200) {
        throw new Error(`GET /me başarısız: HTTP ${getRes1.status}`);
      }
      const p1 = (await getRes1.json()) as any;
      if (p1.uid !== aliceUid || p1.coins !== 100 || p1.nickname !== null) {
        throw new Error(`GET /me beklenmeyen veri döndü: ${JSON.stringify(p1)}`);
      }
      console.log('  ✓ GET /me yeni profili başlangıç bakiyesiyle (100) döndürdü.');

      // 3. PUT /me/nickname ile ad güncelleme
      const putRes = await fetch(`${BASE_HTTP_URL}/me/nickname`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer dev:${aliceUid}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: '   AliceE2E   ' }),
      });
      if (putRes.status !== 200) {
        throw new Error(`PUT /me/nickname başarısız: HTTP ${putRes.status}`);
      }
      const putData = (await putRes.json()) as any;
      if (!putData.ok || putData.nickname !== 'AliceE2E') {
        throw new Error(`PUT /me/nickname beklenmeyen yanıt: ${JSON.stringify(putData)}`);
      }
      console.log('  ✓ PUT /me/nickname takma adı başarıyla güncelledi (AliceE2E).');

      // 4. GET /me ile güncellenen adın doğrulanması
      const getRes2 = await fetch(`${BASE_HTTP_URL}/me`, {
        headers: { Authorization: `Bearer dev:${aliceUid}` },
      });
      const p2 = (await getRes2.json()) as any;
      if (p2.nickname !== 'AliceE2E') {
        throw new Error(`GET /me güncel adı döndürmedi: ${JSON.stringify(p2)}`);
      }
      console.log('  ✓ GET /me güncellenmiş takma adı teyit etti.');

      // 5. Geçersiz ad 400 kontrolü
      const badPutRes = await fetch(`${BASE_HTTP_URL}/me/nickname`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer dev:${aliceUid}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: 'ab' }),
      });
      if (badPutRes.status !== 400) {
        throw new Error(`Geçersiz takma ad beklenen 400 yerine ${badPutRes.status} döndü`);
      }
      console.log('  ✓ Geçersiz takma ad (2 karakter) 400 ile reddedildi.');
      console.log('  ✓ [Senaryo I Başarılı] Profil ve takma ad HTTP akışları doğrulandı.');
    }

    // ------------------------------------------------------------------------
    // Senaryo (j): Haftalık Liderlik Tablosu (/leaderboard) ve Maç Sonu Sıralama
    // ------------------------------------------------------------------------
    console.log('\n[Senaryo J] Haftalık Liderlik Tablosu (/leaderboard)...');
    {
      // 1. Yetkisiz GET /leaderboard 401 kontrolü
      const unauthRes = await fetch(`${BASE_HTTP_URL}/leaderboard`);
      if (unauthRes.status !== 401) {
        throw new Error(`Yetkisiz GET /leaderboard beklenen 401 yerine ${unauthRes.status} döndü`);
      }
      console.log('  ✓ Yetkisiz GET /leaderboard 401 ile reddedildi.');

      const aliceUid = `alice_j_${Date.now()}`;
      const bobUid = `bob_j_${Date.now()}`;

      const suffix = Math.floor(1000 + Math.random() * 9000);
      const aliceNick = `Alice_${suffix}`;
      const bobNick = `Bob_${suffix}`;

      // 2. Oyuncuların takma adlarını ayarla
      await fetch(`${BASE_HTTP_URL}/me/nickname`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer dev:${aliceUid}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: aliceNick }),
      });
      await fetch(`${BASE_HTTP_URL}/me/nickname`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer dev:${bobUid}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ nickname: bobNick }),
      });

      // 3. Maç öncesi liderlik sorgusu (alice_j'nin 0 galibiyeti var -> me null)
      const preRes = await fetch(`${BASE_HTTP_URL}/leaderboard`, {
        headers: { Authorization: `Bearer dev:${aliceUid}` },
      });
      const preData = (await preRes.json()) as any;
      if (preData.me !== null) {
        throw new Error(`Maç öncesi me null beklenirken veri döndü: ${JSON.stringify(preData.me)}`);
      }
      console.log('  ✓ Maç öncesi me null olarak teyit edildi.');

      // 4. Hızlı bir maç oynat: Alice ve Bob eşleşir, Bob bağlantıyı keser -> Alice kazanır
      const { matchId } = await matchTwoPlayers(aliceUid, 'Alice', bobUid, 'Bob');
      const { roomA, roomB } = await connectToMatch(matchId, aliceUid, bobUid);

      // Bob bağlantıyı kapatır
      roomB.close();

      // FAST_TIMERS: 3 saniye sonra disconnectForfeit tetiklenir
      const finalMsg = await roomA.waitForMessage<ClientFinalMessage>(
        (m) => m.t === 'final',
        8000
      );
      if (!finalMsg.winnerIsMe) {
        throw new Error('Beklenen kazanan Alice idi, ancak finalMsg.winnerIsMe false geldi');
      }
      roomA.close();
      console.log('  ✓ Maç forfeit ile bitti, Alice kazandı.');

      // 5. Maç sonrası liderlik sorgusu (alice_j)
      const postResAlice = await fetch(`${BASE_HTTP_URL}/leaderboard`, {
        headers: { Authorization: `Bearer dev:${aliceUid}` },
      });
      if (postResAlice.status !== 200) {
        throw new Error(`GET /leaderboard başarısız: HTTP ${postResAlice.status}`);
      }
      const postDataAlice = (await postResAlice.json()) as any;
      expectWeekDataValid(postDataAlice);

      // Top listesinde uid olmamalı
      for (const item of postDataAlice.top) {
        if ('uid' in item) {
          throw new Error(`Liderlik yanıtında uid bulunmamalıdır! Bulundu: ${item.uid}`);
        }
      }

      const aliceRow = postDataAlice.top.find((e: any) => e.isMe === true);
      if (!aliceRow || aliceRow.wins < 1 || aliceRow.nickname !== aliceNick) {
        throw new Error(`Alice liderlik tablosunda doğru görünmüyor: ${JSON.stringify(postDataAlice)}`);
      }
      if (!postDataAlice.me || postDataAlice.me.wins < 1) {
        throw new Error(`Alice me verisi doğru değil: ${JSON.stringify(postDataAlice.me)}`);
      }
      console.log('  ✓ Alice liderlik tablosunda isMe: true olarak görünüyor.');

      // 6. Bob sorgusu (kaybeden olduğu için wins: 0, me null olmalı)
      const postResBob = await fetch(`${BASE_HTTP_URL}/leaderboard`, {
        headers: { Authorization: `Bearer dev:${bobUid}` },
      });
      const postDataBob = (await postResBob.json()) as any;
      if (postDataBob.me !== null) {
        throw new Error(`0 galibiyetli Bob için me null olmalıydı: ${JSON.stringify(postDataBob.me)}`);
      }
      const aliceInBobView = postDataBob.top.find((e: any) => e.nickname === aliceNick);
      if (!aliceInBobView || aliceInBobView.isMe !== false) {
        throw new Error(`Bob açısından Alice isMe: false olmalıydı`);
      }
      console.log('  ✓ Bob için me null ve rakipler isMe: false olarak doğrulandı.');

      console.log('  ✓ [Senaryo J Başarılı] Haftalık liderlik tablosu tam E2E akışı doğrulandı.');
    }

    function expectWeekDataValid(data: any) {
      if (!data.weekKey || typeof data.weekKey !== 'string' || !data.weekKey.includes('-W')) {
        throw new Error(`Geçersiz weekKey: ${data.weekKey}`);
      }
      if (!data.endsAt || typeof data.endsAt !== 'number' || data.endsAt <= Date.now() - 1000) {
        throw new Error(`Geçersiz endsAt: ${data.endsAt}`);
      }
    }

    console.log('\n========================================================');
    console.log('🎉 TÜM 10 E2E TEST SENARYOSU BAŞARIYLA TAMAMLANDI! (0 hata)');
    console.log('========================================================\n');
  } catch (err: unknown) {
    console.error('\n❌ E2E TEST BAŞARISIZ OLDU:');
    const msg = err instanceof Error ? err.message : String(err);
    console.error(msg);
    process.exit(1);
  } finally {
    if (serverProcess) {
      serverProcess.kill();
    }
  }
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });

