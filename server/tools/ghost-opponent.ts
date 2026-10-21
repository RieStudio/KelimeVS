// KelimeGo Canlı Sunucu "Hayalet Rakip" (Ghost Opponent) Test Betiği
// Gerçek sunucuya karşı otomatik veya belirlenmiş davranış modlarıyla oynar.

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import WebSocket from 'ws';
import { getFrameCatalogItem } from '../src/frames.js';
import { parseQuestionsPool, type Question } from '../src/engine/models';
import type {
  ClientStateMessage,
  MatchmakerServerMessage,
  MatchRoomServerMessage,
} from '../src/protocol';
import {
  findQuestionByState,
  getRandomDelayMs,
  parseApiKeyFromDevVars,
  parseFirebaseErrorMessage,
  parseGhostArgs,
  parseSessionCache,
  selectAnswer,
  serializeSessionCache,
  shouldMakeMistake,
  type GhostConfig,
} from './ghost-opponent-logic';

function log(message: string): void {
  const now = new Date();
  const timeStr = `${String(now.getHours()).padStart(2, '0')}:${String(
    now.getMinutes()
  ).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  console.log(`[${timeStr}] ${message}`);
}

function logError(message: string): void {
  const now = new Date();
  const timeStr = `${String(now.getHours()).padStart(2, '0')}:${String(
    now.getMinutes()
  ).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  console.error(`[${timeStr}] HATA: ${message}`);
}

function resolveSessionFilePath(): string {
  const inServer = resolve(process.cwd(), 'server', '.ghost-session.json');
  const inCwd = resolve(process.cwd(), '.ghost-session.json');
  if (existsSync(resolve(process.cwd(), 'server'))) {
    return inServer;
  }
  return inCwd;
}

/** Firebase REST API üzerinden anonim yeni hesap oluşturur ve token bilgilerini alır. */
async function createAnonymousSession(
  apiKey: string
): Promise<{ readonly idToken: string; readonly refreshToken: string }> {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });

  if (!response.ok) {
    let errorMessage: string | undefined;
    try {
      const json: unknown = await response.json();
      errorMessage = parseFirebaseErrorMessage(json);
    } catch {
      // yoksay
    }
    const detail = errorMessage ? `: ${errorMessage}` : '';
    throw new Error(`Firebase Auth REST başarısız oldu (HTTP ${response.status}${detail})`);
  }

  const data = (await response.json()) as {
    readonly idToken?: string;
    readonly refreshToken?: string;
  };
  if (!data.idToken || typeof data.idToken !== 'string') {
    throw new Error('Firebase Auth REST yanıtında geçerli bir idToken bulunamadı');
  }
  if (!data.refreshToken || typeof data.refreshToken !== 'string') {
    throw new Error('Firebase Auth REST yanıtında geçerli bir refreshToken bulunamadı');
  }

  return {
    idToken: data.idToken,
    refreshToken: data.refreshToken,
  };
}

/** Google Secure Token API üzerinden refresh token ile yeni idToken alır. */
async function refreshIdToken(
  apiKey: string,
  refreshToken: string
): Promise<{ readonly idToken: string; readonly newRefreshToken?: string }> {
  const url = `https://securetoken.googleapis.com/v1/token?key=${apiKey}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}`,
  });

  if (!response.ok) {
    let errorMessage: string | undefined;
    try {
      const json: unknown = await response.json();
      errorMessage = parseFirebaseErrorMessage(json);
    } catch {
      // yoksay
    }
    const detail = errorMessage ? `: ${errorMessage}` : '';
    throw new Error(`Token yenileme başarısız oldu (HTTP ${response.status}${detail})`);
  }

  const data = (await response.json()) as {
    readonly id_token?: string;
    readonly refresh_token?: string;
  };
  if (!data.id_token || typeof data.id_token !== 'string') {
    throw new Error('Token yenileme yanıtında id_token bulunamadı');
  }

  return {
    idToken: data.id_token,
    newRefreshToken: typeof data.refresh_token === 'string' ? data.refresh_token : undefined,
  };
}

/** Oturum önbelleğini kontrol eder; geçerliyse yeniler, değilse veya --fresh ise yeni oturum açar. */
async function resolveIdToken(
  apiKey: string,
  fresh: boolean,
  sessionFilePath: string
): Promise<string> {
  // 1. --fresh değilse ve önbellek dosyası varsa önbellekten yenilemeyi dene
  if (!fresh && existsSync(sessionFilePath)) {
    try {
      const raw = readFileSync(sessionFilePath, 'utf8');
      const session = parseSessionCache(raw);
      if (session) {
        log('Önbellekteki oturum ile token yenileniyor...');
        const result = await refreshIdToken(apiKey, session.refreshToken);
        if (result.newRefreshToken && result.newRefreshToken !== session.refreshToken) {
          writeFileSync(sessionFilePath, serializeSessionCache(result.newRefreshToken), 'utf8');
        }
        log('Oturum başarıyla yenilendi');
        return result.idToken;
      } else {
        log('Oturum önbelleği bozuk, yeni anonim hesap oluşturuluyor...');
      }
    } catch (err) {
      log(
        `Önbellekteki oturum geçersiz (${err instanceof Error ? err.message : String(err)}), yeni anonim hesap oluşturuluyor...`
      );
    }
  }

  // 2. Yeni anonim oturum oluştur
  log('Firebase Auth REST ile anonim giriş yapılıyor...');
  const newSession = await createAnonymousSession(apiKey);
  try {
    writeFileSync(sessionFilePath, serializeSessionCache(newSession.refreshToken), 'utf8');
    log('Oturum önbelleğe kaydedildi (.ghost-session.json)');
  } catch (err) {
    logError(`Oturum kaydedilemedi: ${err instanceof Error ? err.message : String(err)}`);
  }
  log('Anonim oturum başarıyla oluşturuldu');
  return newSession.idToken;
}

/** API anahtarını argümanlardan, ortam değişkenlerinden veya .dev.vars dosyasından çözer. */
function resolveApiKey(config: GhostConfig): string {
  if (config.apiKey && config.apiKey.length > 0) {
    return config.apiKey;
  }

  const devVarsPath = resolve(process.cwd(), '.dev.vars');
  if (existsSync(devVarsPath)) {
    try {
      const content = readFileSync(devVarsPath, 'utf8');
      const fromFile = parseApiKeyFromDevVars(content);
      if (fromFile) return fromFile;
    } catch {
      // yoksay
    }
  }

  throw new Error(
    'Firebase API anahtarı bulunamadı!\n' +
      'Lütfen --api-key=<KEY> argümanı verin, FIREBASE_WEB_API_KEY ortam değişkenini ayarlayın ' +
      'veya server/.dev.vars içine FIREBASE_WEB_API_KEY=<KEY> satırını ekleyin.'
  );
}

/** Yerel questions.json soru havuzunu yükler. */
function loadLocalQuestions(): Question[] {
  const candidates = [
    resolve(process.cwd(), 'src/dev/questions.json'),
    resolve(__dirname, '../src/dev/questions.json'),
  ];

  for (const path of candidates) {
    if (existsSync(path)) {
      try {
        const raw = readFileSync(path, 'utf8');
        const json: unknown = JSON.parse(raw);
        return parseQuestionsPool(json);
      } catch (err) {
        logError(`Soru havuzu ayrıştırılamadı (${path}): ${err}`);
      }
    }
  }

  log('Uyarı: Yerel questions.json bulunamadı; play modunda cevap bulunamayabilir.');
  return [];
}

// Global aktif temizleme fonksiyonu (SIGINT için)
let currentCleanup: (() => void) | null = null;

process.on('SIGINT', () => {
  log('Kullanıcı tarafından durduruldu (SIGINT)');
  process.exitCode = 130;
  if (currentCleanup) {
    currentCleanup();
    currentCleanup = null;
  }
});

/** Eşleştirme kuyruğuna veya arkadaş lobisine girer ve eşleşme sonucunu döner. */
function runMatchmaking(
  config: GhostConfig,
  idToken: string
): Promise<{ readonly matchId: string; readonly opponentName: string }> {
  return new Promise((resolvePromise, rejectPromise) => {
    const wsUrl = `${config.serverUrl}/ws/matchmaking`;
    const ws = new WebSocket(wsUrl, {
      headers: {
        Authorization: `Bearer ${idToken}`,
      },
    });

    let isDone = false;

    const cleanup = () => {
      if (isDone) return;
      isDone = true;
      try {
        if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
          ws.close();
        }
      } catch {
        // yoksay
      }
    };

    currentCleanup = cleanup;

    ws.on('open', () => {
      if (config.mode === 'friend-host') {
        log(`Arkadaş düellosu odası kuruluyor (Ad: ${config.name})...`);
        ws.send(JSON.stringify({ t: 'create_room', name: config.name }));
      } else if (config.mode === 'friend-join') {
        if (!config.code) {
          cleanup();
          currentCleanup = null;
          rejectPromise(
            new Error(
              '--mode=friend-join için --code parametresi zorunludur! (Örn: --mode=friend-join --code=K7M9P2)'
            )
          );
          return;
        }
        log(
          `Arkadaş düellosu odasına katılınıyor (Kod: ${config.code}, Ad: ${config.name})...`
        );
        ws.send(
          JSON.stringify({
            t: 'join_room',
            code: config.code,
            name: config.name,
          })
        );
      } else {
        log(`Eşleştirme sunucusuna bağlanıldı, kuyruğa giriliyor (Ad: ${config.name})...`);
        ws.send(JSON.stringify({ t: 'queue', name: config.name }));
      }
    });

    ws.on('message', (raw) => {
      try {
        const msg = JSON.parse(String(raw)) as MatchmakerServerMessage;
        if (msg.t === 'queued') {
          log('Kuyruğa girildi, rakip bekleniyor...');
        } else if (msg.t === 'room_created') {
          log('========================================================');
          log(`ARKADAŞ DÜELLOSU ODASI KURULDU!`);
          log(`DAVET KODU: ${msg.code}`);
          log(`Geçerlilik süresi: 5 dakika`);
          log(`Arkadaşının bu kodu girip bağlanması bekleniyor...`);
          log('========================================================');
        } else if (msg.t === 'room_resumed') {
          log(`Arkadaş odası sürdürülüyor (Kod: ${msg.code})`);
        } else if (msg.t === 'matched') {
          log(
            `Eşleşti (maç ID: ${msg.matchId}, rakip: ${msg.opponentName}${
              msg.opponentFrame ? ` [Çerçeve: ${msg.opponentFrame}]` : ''
            }${msg.isFriendly ? ', Dostluk Maçı' : ''})`
          );
          cleanup();
          currentCleanup = null;
          resolvePromise({ matchId: msg.matchId, opponentName: msg.opponentName });
        } else if (msg.t === 'room_expired') {
          cleanup();
          currentCleanup = null;
          rejectPromise(new Error('Oda süresi doldu (5 dakika).'));
        } else if (msg.t === 'error') {
          cleanup();
          currentCleanup = null;
          rejectPromise(
            new Error(
              `Eşleştirme/Oda hatası: ${msg.code}${
                msg.message ? ' - ' + msg.message : ''
              }`
            )
          );
        }
      } catch (err) {
        logError(`Gelen eşleştirme mesajı ayrıştırılamadı: ${err}`);
      }
    });

    ws.on('error', (err) => {
      if (!isDone) {
        cleanup();
        currentCleanup = null;
        rejectPromise(new Error(`Eşleştirme soket hatası: ${err.message}`));
      }
    });

    ws.on('close', (_code, reason) => {
      if (!isDone) {
        cleanup();
        currentCleanup = null;
        rejectPromise(
          new Error(`Eşleştirme bağlantısı kapandı (sebep: ${reason?.toString() || 'bilinmiyor'})`)
        );
      }
    });
  });
}

/** Tek bir maçı verilen konfigürasyona göre oynar veya simüle eder. */
function playMatch(
  serverBaseUrl: string,
  matchId: string,
  idToken: string,
  config: GhostConfig,
  questions: readonly Question[]
): Promise<void> {
  return new Promise((resolvePromise, rejectPromise) => {
    let ws: WebSocket;
    let isFinished = false;
    const activeTimers = new Set<NodeJS.Timeout>();
    let currentRound = 0;
    let attemptCount = 0;
    let lastTurnIsMine = false;
    let extraTimeUsed = false;
    let activeTurnTimer: NodeJS.Timeout | null = null;

    function setTrackedTimeout(fn: () => void, ms: number): NodeJS.Timeout {
      const timer = setTimeout(() => {
        activeTimers.delete(timer);
        fn();
      }, ms);
      activeTimers.add(timer);
      return timer;
    }

    function cleanup(): void {
      if (isFinished) return;
      isFinished = true;
      activeTurnTimer = null;
      for (const timer of activeTimers) {
        clearTimeout(timer);
      }
      activeTimers.clear();
      try {
        if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
          ws.close();
        }
      } catch {
        // yoksay
      }
    }

    currentCleanup = cleanup;

    function createRoomConnection(): WebSocket {
      const roomUrl = `${serverBaseUrl}/ws/match/${matchId}`;
      const socket = new WebSocket(roomUrl, {
        headers: {
          Authorization: `Bearer ${idToken}`,
        },
      });

      socket.on('open', () => {
        log('Maç odasına bağlanıldı');
      });

      socket.on('message', (raw) => {
        try {
          const msg = JSON.parse(String(raw)) as MatchRoomServerMessage;
          handleRoomMessage(msg, socket);
        } catch (err) {
          logError(`Gelen oda mesajı ayrıştırılamadı: ${err}`);
        }
      });

      socket.on('error', (err) => {
        logError(`Oda soket hatası: ${err.message}`);
      });

      socket.on('close', (code, reason) => {
        if (!isFinished && config.mode !== 'drop') {
          log(`Maç odası bağlantısı kapandı (kod: ${code}, sebep: ${reason?.toString() || '-'})`);
        }
      });

      return socket;
    }

    function handleRoomMessage(msg: MatchRoomServerMessage, socket: WebSocket): void {
      if (msg.t === 'state') {
        handleState(msg, socket);
      } else if (msg.t === 'feedback') {
        const reasonText = msg.reason ? ` (${msg.reason})` : '';
        log(`Geri bildirim: ${msg.kind}${reasonText}`);
      } else if (msg.t === 'final') {
        const winText = msg.winnerIsMe ? 'Kazandım' : 'Rakip kazandı';
        const coinsText =
          msg.coinsAwarded !== undefined
            ? `, ödül: +${msg.coinsAwarded}G, yeni bakiye: ${msg.coins ?? '-'}G`
            : '';
        log(
          `Maç bitti: ${winText} (skor: ${msg.scores.me}-${msg.scores.opponent}, bitiş: ${msg.endedBy}${coinsText})`
        );
        cleanup();
        currentCleanup = null;
        resolvePromise();
      } else if (msg.t === 'voided') {
        log(`Maç iptal edildi (voided, sebep: ${msg.reason})`);
        cleanup();
        currentCleanup = null;
        resolvePromise();
      } else if (msg.t === 'powerup_ack') {
        log(
          `⚡ Güçlendirici yanıtı: success=${msg.success}${msg.code ? ` code=${msg.code}` : ''}${msg.coins !== undefined ? ` bakiye=${msg.coins}G` : ''}`
        );
      } else if (msg.t === 'opponent_powerup') {
        log(`⚡ Rakip ek süre kullandı (+${msg.seconds} sn)!`);
      }
    }

    function handleState(state: ClientStateMessage, socket: WebSocket): void {
      if (state.roundNumber !== currentRound) {
        currentRound = state.roundNumber;
        attemptCount = 0;
        log(`Tur ${currentRound} başladı`);
      }

      if (state.turnIsMine !== lastTurnIsMine) {
        lastTurnIsMine = state.turnIsMine;
        if (state.phase === 'roundActive') {
          log(
            `Tur ${state.roundNumber}: ${state.turnIsMine ? 'Sıra bende' : 'Sıra rakipte'}`
          );
        }
      }

      // --use-extra-time bayrağı varsa ve sıra bizdeyse maçta 1 kez ek süre kullan
      if (
        config.useExtraTime &&
        !extraTimeUsed &&
        state.phase === 'roundActive' &&
        state.turnIsMine
      ) {
        extraTimeUsed = true;
        log('⚡ [GHOST] Ek süre güçlendiricisi kullanılıyor (+5 sn)...');
        socket.send(JSON.stringify({ t: 'use_powerup', type: 'extra_time' }));
      }

      if (state.phase === 'roundEnded' && state.lastRound) {
        log(
          `Tur sonucu: ${state.lastRound.winnerIsMe ? 'Turu ben kazandım' : 'Turu rakip kazandı'} (sebep: ${state.lastRound.reason})`
        );
      }

      if (config.mode === 'play') {
        if (state.phase === 'roundActive' && state.turnIsMine) {
          scheduleAnswer(state, socket);
        }
      }
    }

    function scheduleAnswer(state: ClientStateMessage, socket: WebSocket): void {
      if (activeTurnTimer) return;
      const delayMs = getRandomDelayMs(2000, 6000);

      activeTurnTimer = setTrackedTimeout(() => {
        activeTurnTimer = null;
        if (isFinished || socket.readyState !== WebSocket.OPEN) return;

        const q = findQuestionByState(questions, state.question);
        if (!q) {
          log('Soru havuzda bulunamadı, bekleniyor (süre dolsun)...');
          return;
        }

        const answer = selectAnswer(q, state.attempts);
        if (!answer) {
          log('Kullanılmamış cevap kalmadı, bekleniyor (süre dolsun)...');
          return;
        }

        if (shouldMakeMistake(Math.random())) {
          attemptCount++;
          socket.send(JSON.stringify({ t: 'submit', text: 'alakasizdeneme' }));
          log(`Yanlış deneme yapıldı (${attemptCount}. deneme)`);

          setTrackedTimeout(() => {
            if (isFinished || socket.readyState !== WebSocket.OPEN) return;
            attemptCount++;
            socket.send(JSON.stringify({ t: 'submit', text: answer }));
            log(`Cevap gönderildi (${attemptCount}. deneme)`);
          }, 650);
        } else {
          attemptCount++;
          socket.send(JSON.stringify({ t: 'submit', text: answer }));
          log(`Cevap gönderildi (${attemptCount}. deneme)`);
        }
      }, delayMs);
    }

    ws = createRoomConnection();

    if (config.mode === 'leave') {
      setTrackedTimeout(() => {
        if (isFinished || ws.readyState !== WebSocket.OPEN) return;
        log(`leave gönderiliyor (${config.leaveAfterSeconds} sn doldu)...`);
        ws.send(JSON.stringify({ t: 'leave' }));
      }, config.leaveAfterSeconds * 1000);
    }

    if (config.mode === 'drop') {
      setTrackedTimeout(() => {
        if (isFinished) return;
        log(`Bağlantı aniden kesiliyor (${config.dropAfterSeconds} sn doldu)...`);
        try {
          ws.terminate();
        } catch {
          // yoksay
        }

        log(`${config.backAfterSeconds} sn sonra yeniden bağlanılacak...`);
        setTrackedTimeout(() => {
          if (isFinished) return;
          log('Yeniden bağlanılıyor...');
          ws = createRoomConnection();
          ws.on('open', () => {
            log('Yeniden bağlanıldı, sync gönderiliyor...');
            ws.send(JSON.stringify({ t: 'sync' }));
          });
        }, config.backAfterSeconds * 1000);
      }, config.dropAfterSeconds * 1000);
    }
  });
}

async function main(): Promise<void> {
  const config = parseGhostArgs(process.argv.slice(2), process.env);

  console.log('========================================================');
  console.log('KelimeGo Test Rakibi (Ghost Opponent) Başlatılıyor');
  console.log(
    `Mod: ${config.mode.toUpperCase()} | Hedef: ${config.serverUrl} | Maç Sayısı: ${config.rounds}${
      config.devAuth ? ' | Auth: DEV-AUTH' : ''
    }${config.fresh ? ' | Fresh: EVET' : ''}`
  );
  console.log('========================================================\n');

  let idToken: string;

  if (config.devAuth) {
    const randomSuffix = Math.random().toString(36).substring(2, 10);
    idToken = `dev:ghost-${randomSuffix}`;
    log(`Dev Auth modu aktif: ${idToken} kullanılıyor (Firebase Auth atlandı)`);
  } else {
    let apiKey: string;
    try {
      apiKey = resolveApiKey(config);
    } catch (err) {
      logError(err instanceof Error ? err.message : String(err));
      process.exitCode = 1;
      return;
    }

    try {
      const sessionPath = resolveSessionFilePath();
      idToken = await resolveIdToken(apiKey, config.fresh, sessionPath);
    } catch (err) {
      logError(`Giriş başarısız: ${err instanceof Error ? err.message : String(err)}`);
      process.exitCode = 1;
      return;
    }
  }

  if (config.frame) {
    try {
      const httpUrl = config.serverUrl.replace(/^ws(s)?:\/\//, 'http$1://');
      const frameId = config.frame;
      let canEquip = frameId === 'classic';

      if (!canEquip) {
        log(`Avatar çerçevesi satın alma deneniyor: ${frameId}...`);
        const purchaseResp = await fetch(`${httpUrl}/store/purchase`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${idToken}`,
          },
          body: JSON.stringify({ itemId: frameId }),
        });

        if (purchaseResp.ok) {
          log(`✓ Çerçeve (${frameId}) başarıyla satın alındı.`);
          canEquip = true;
        } else if (purchaseResp.status === 400) {
          const errData = (await purchaseResp.json().catch(() => ({}))) as { error?: string };
          if (errData.error === 'already_owned') {
            log(`✓ Çerçeve (${frameId}) zaten sahiplenilmiş.`);
            canEquip = true;
          } else {
            logError(`Çerçeve satın alınamadı: ${errData.error ?? 'geçersiz ürün'}. Kuşanma atlandı.`);
          }
        } else if (purchaseResp.status === 402) {
          const errData = (await purchaseResp.json().catch(() => ({}))) as {
            error?: string;
            coins?: number;
          };
          const catalogItem = getFrameCatalogItem(frameId);
          const frameCost = catalogItem ? catalogItem.cost : '?';
          const currentCoins = typeof errData.coins === 'number' ? errData.coins : '?';
          logError(
            `Çerçeve satın alınamadı: yetersiz bakiye (bakiye ${currentCoins}, çerçeve ${frameCost} jeton). Kuşanma atlandı.`
          );
        } else {
          logError(`Çerçeve satın alınamadı: HTTP ${purchaseResp.status}. Kuşanma atlandı.`);
        }
      }

      if (canEquip) {
        log(`Avatar çerçevesi kuşanılıyor: ${frameId}...`);
        const resp = await fetch(`${httpUrl}/me/frame`, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${idToken}`,
          },
          body: JSON.stringify({ frameId }),
        });
        if (resp.ok) {
          log(`✓ Çerçeve (${frameId}) başarıyla kuşandı.`);
        } else {
          logError(`Çerçeve kuşanılamadı: HTTP ${resp.status}`);
        }
      }
    } catch (frameErr) {
      logError(
        `Çerçeve işleminde hata: ${frameErr instanceof Error ? frameErr.message : String(frameErr)}`
      );
    }
  }

  const questions = loadLocalQuestions();

  for (let round = 1; round <= config.rounds; round++) {
    if (config.rounds > 1) {
      log(`--- Maç ${round} / ${config.rounds} ---`);
    }

    try {
      const matchInfo = await runMatchmaking(config, idToken);
      await playMatch(config.serverUrl, matchInfo.matchId, idToken, config, questions);
    } catch (err) {
      logError(`Maç oynanırken hata oluştu: ${err instanceof Error ? err.message : String(err)}`);
      process.exitCode = 1;
      return;
    }
  }

  log('Tüm maçlar başarıyla tamamlandı.');
  process.exitCode = 0;
}

// Ana fonksiyonu çalıştır
main().catch((err) => {
  logError(`Beklenmeyen hata: ${err instanceof Error ? err.message : String(err)}`);
  process.exitCode = 1;
});
