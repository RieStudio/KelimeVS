import { DurableObject } from 'cloudflare:workers';
import {
  MatchEngine,
  type MatchConfig,
  type Question,
} from './engine';
import {
  parseMatchRoomMessage,
  type ClientFeedbackMessage,
  type ClientVoidedMessage,
} from './protocol';
import {
  computeNextAlarm,
  getRoomDurations,
  processDueTimers,
  type RoomDurations,
  type TimersSchedule,
} from './scheduler';
import {
  buildFinalMessage,
  deserializeMatchState,
  filterStateForPlayer,
  serializeMatchState,
  type SerializedMatchState,
} from './storage';
import type { Env } from './index';

interface PlayerInfo {
  readonly uid: string;
  readonly name: string;
}

export interface MatchRoomInitParams {
  readonly matchId: string;
  readonly p1: PlayerInfo;
  readonly p2: PlayerInfo;
  readonly questions: readonly Question[];
  readonly questionOrder: readonly string[];
}

interface StoredRoomData {
  readonly matchId: string;
  readonly p1: PlayerInfo;
  readonly p2: PlayerInfo;
  readonly questions: Question[];
  readonly questionOrder: string[];
  readonly status: 'waiting_for_players' | 'active' | 'finished' | 'voided';
  readonly engineState?: SerializedMatchState;
  readonly schedule: TimersSchedule;
  readonly disconnectedUid?: string;
}

export class MatchRoom extends DurableObject<Env> {
  private data: StoredRoomData | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      const stored = await this.ctx.storage.get<StoredRoomData>('roomData');
      if (stored) {
        this.data = stored;
      }
    });
  }

  private get durations(): RoomDurations {
    const isFast = this.env.FAST_TIMERS === 'true';
    return getRoomDurations(isFast);
  }

  /** Matchmaker tarafından maç başlangıcı verileriyle çağrılır */
  async initMatch(params: MatchRoomInitParams): Promise<void> {
    const nowMs = Date.now();
    const connectTimeoutAtMs = nowMs + this.durations.connectTimeoutMs;

    this.data = {
      matchId: params.matchId,
      p1: params.p1,
      p2: params.p2,
      questions: [...params.questions],
      questionOrder: [...params.questionOrder],
      status: 'waiting_for_players',
      schedule: { connectTimeoutAtMs },
    };

    await this.persist();
    await this.updateAlarm();
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected WebSocket Upgrade', { status: 400 });
    }

    if (!this.data) {
      return new Response('Match not found', { status: 404 });
    }

    const uid = request.headers.get('X-User-Id');
    if (!uid) {
      return new Response('Unauthorized', { status: 401 });
    }

    // Yalnızca atanan iki oyuncu bağlanabilir
    if (uid !== this.data.p1.uid && uid !== this.data.p2.uid) {
      return new Response('Forbidden', { status: 403 });
    }

    if (this.data.status === 'voided') {
      return new Response('Match voided', { status: 410 });
    }

    // Aynı UID için eski bağlantı varsa kapat (kod 4000, "replaced")
    const existing = this.ctx.getWebSockets(uid);
    for (const ws of existing) {
      try {
        ws.close(4000, 'replaced');
      } catch {
        // yoksay
      }
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    this.ctx.acceptWebSocket(server, [uid]);

    // Bağlantı durumunu değerlendir
    await this.handlePlayerConnected(uid);

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (!this.data) return;

    const tags = this.ctx.getTags(ws);
    const uid = tags[0];
    if (!uid) return;

    // Hız sınırı: saniyede en fazla 10 mesaj
    const nowMs = Date.now();
    const att = ws.deserializeAttachment() as { count: number; windowStart: number } | null;
    let newAtt: { count: number; windowStart: number };
    if (!att || nowMs - att.windowStart >= 1000) {
      newAtt = { count: 1, windowStart: nowMs };
    } else {
      newAtt = { count: att.count + 1, windowStart: att.windowStart };
    }
    ws.serializeAttachment(newAtt);
    if (newAtt.count > 10) {
      return; // 10 msg/sn aşıldı, yok say
    }

    // En fazla 200 bayt kontrolü
    const rawStr = typeof message === 'string' ? message : new TextDecoder().decode(message);
    const byteLen = typeof message === 'string' ? new TextEncoder().encode(message).length : message.byteLength;
    if (byteLen > 200) return;

    const parsed = parseMatchRoomMessage(rawStr, byteLen);
    if (!parsed) return;

    if (parsed.t === 'sync') {
      this.sendStateToPlayer(uid);
      return;
    }

    if (this.data.status !== 'active' || !this.data.engineState) return;

    if (parsed.t === 'leave') {
      // Oyuncu maçı terk etti (forfeit)
      const state = deserializeMatchState(this.data.engineState);
      const res = MatchEngine.forfeit({
        state,
        playerId: uid,
        nowMs: Date.now(),
      });
      this.data = {
        ...this.data,
        engineState: serializeMatchState(res.state),
      };
      await this.handleMatchFinished();
      return;
    }

    if (parsed.t === 'submit') {
      const state = deserializeMatchState(this.data.engineState);
      const questions = this.data.questions;
      const res = MatchEngine.submit({
        state,
        playerId: uid,
        rawInput: parsed.text,
        nowMs,
        questionsPool: questions,
      });

      this.data = {
        ...this.data,
        engineState: serializeMatchState(res.state),
      };

      // Denemeyi yapan oyuncuya özel geribildirim (feedback)
      for (const e of res.events) {
        if (e.type === 'WrongAnswer') {
          const fb: ClientFeedbackMessage = { t: 'feedback', kind: 'wrong' };
          this.sendToUid(uid, JSON.stringify(fb));
        } else if (e.type === 'NearMiss') {
          const fb: ClientFeedbackMessage = { t: 'feedback', kind: 'nearMiss' };
          this.sendToUid(uid, JSON.stringify(fb));
        } else if (e.type === 'AlreadySaid') {
          const fb: ClientFeedbackMessage = { t: 'feedback', kind: 'alreadySaid' };
          this.sendToUid(uid, JSON.stringify(fb));
        } else if (e.type === 'Ignored') {
          const fb: ClientFeedbackMessage = { t: 'feedback', kind: 'ignored', reason: e.reason };
          this.sendToUid(uid, JSON.stringify(fb));
        }
      }

      if (res.state.phase === 'matchFinished') {
        await this.handleMatchFinished();
      } else if (res.state.phase === 'roundEnded') {
        this.data = {
          ...this.data,
          schedule: {
            ...this.data.schedule,
            turnDeadlineMs: undefined,
            nextRoundAtMs: nowMs + this.durations.roundTransitionMs,
          },
        };
        await this.persist();
        await this.updateAlarm();
        this.broadcastState();
      } else {
        this.data = {
          ...this.data,
          schedule: {
            ...this.data.schedule,
            turnDeadlineMs: res.state.deadlineMs,
          },
        };
        await this.persist();
        await this.updateAlarm();
        this.broadcastState();
      }
    }
  }

  async webSocketClose(ws: WebSocket, code: number, _reason: string): Promise<void> {
    if (code === 4000) return; // 'replaced' bağlantı, yenisi zaten mevcut

    const tags = this.ctx.getTags(ws);
    const uid = tags[0];
    if (!uid || !this.data) return;

    if (this.data.status === 'active') {
      const nowMs = Date.now();
      const disconnectTimeoutAtMs = nowMs + this.durations.disconnectTimeoutMs;

      this.data = {
        ...this.data,
        disconnectedUid: uid,
        schedule: {
          ...this.data.schedule,
          disconnectTimeoutAtMs,
        },
      };

      await this.persist();
      await this.updateAlarm();
      this.broadcastState();
    }
  }

  async webSocketError(ws: WebSocket, _error: unknown): Promise<void> {
    await this.webSocketClose(ws, 1006, 'error');
  }

  async alarm(): Promise<void> {
    if (!this.data) return;

    const nowMs = Date.now();
    const { dueActions, remainingSchedule } = processDueTimers(this.data.schedule, nowMs);

    this.data = {
      ...this.data,
      schedule: remainingSchedule,
    };

    for (const action of dueActions) {
      if (action === 'connectTimeout') {
        if (this.data.status === 'waiting_for_players') {
          this.data = {
            ...this.data,
            status: 'voided',
            schedule: { cleanupAtMs: nowMs + 5000 },
          };
          const voidedMsg: ClientVoidedMessage = { t: 'voided', reason: 'opponent_absent' };
          this.broadcastAll(JSON.stringify(voidedMsg));
          this.closeAllSockets(1000, 'voided');
        }
      } else if (action === 'disconnectForfeit') {
        if (this.data.status === 'active' && this.data.disconnectedUid && this.data.engineState) {
          const state = deserializeMatchState(this.data.engineState);
          const res = MatchEngine.forfeit({
            state,
            playerId: this.data.disconnectedUid,
            nowMs,
          });
          this.data = {
            ...this.data,
            engineState: serializeMatchState(res.state),
          };
          await this.handleMatchFinished();
        }
      } else if (action === 'turnTimeout') {
        if (this.data.status === 'active' && this.data.engineState) {
          const state = deserializeMatchState(this.data.engineState);
          const res = MatchEngine.checkTimeout({
            state,
            nowMs,
          });
          this.data = {
            ...this.data,
            engineState: serializeMatchState(res.state),
          };
          if (res.state.phase === 'matchFinished') {
            await this.handleMatchFinished();
          } else if (res.state.phase === 'roundEnded') {
            this.data = {
              ...this.data,
              schedule: {
                ...this.data.schedule,
                turnDeadlineMs: undefined,
                nextRoundAtMs: nowMs + this.durations.roundTransitionMs,
              },
            };
            await this.persist();
            await this.updateAlarm();
            this.broadcastState();
          } else {
            await this.persist();
            await this.updateAlarm();
            this.broadcastState();
          }
        }
      } else if (action === 'startNextRound') {
        if (this.data.status === 'active' && this.data.engineState) {
          const state = deserializeMatchState(this.data.engineState);
          const questions = this.data.questions;
          const res = MatchEngine.startNextRound({
            state,
            questions,
            nowMs,
            questionOrder: this.data.questionOrder,
          });
          this.data = {
            ...this.data,
            engineState: serializeMatchState(res.state),
            schedule: {
              ...this.data.schedule,
              nextRoundAtMs: undefined,
              turnDeadlineMs: res.state.deadlineMs,
            },
          };
          await this.persist();
          await this.updateAlarm();
          this.broadcastState();
        }
      } else if (action === 'cleanup') {
        await this.ctx.storage.deleteAll();
        this.data = null;
        return;
      }
    }

    await this.persist();
    await this.updateAlarm();
  }

  private async handlePlayerConnected(uid: string): Promise<void> {
    if (!this.data) return;

    if (this.data.status === 'waiting_for_players') {
      const p1Connected = this.ctx.getWebSockets(this.data.p1.uid).length > 0;
      const p2Connected = this.ctx.getWebSockets(this.data.p2.uid).length > 0;

      if (p1Connected && p2Connected) {
        // İki oyuncu da bağlandı -> Maç başlar!
        const config: MatchConfig = {
          roundsToWin: 2,
          answerSeconds: this.durations.answerSeconds,
          graceMs: 0,
          nearMissPerRound: 1,
          minAnswersPerQuestion: 0,
          minSubmitIntervalMs: 600,
          maxAttemptsPerTurn: 25,
        };

        const nowMs = Date.now();
        const questions = this.data.questions;
        const res = MatchEngine.start({
          config,
          playerIds: [this.data.p1.uid, this.data.p2.uid],
          questions,
          nowMs,
          questionOrder: this.data.questionOrder,
        });

        this.data = {
          ...this.data,
          status: 'active',
          engineState: serializeMatchState(res.state),
          schedule: {
            connectTimeoutAtMs: undefined,
            turnDeadlineMs: res.state.deadlineMs,
          },
        };

        await this.persist();
        await this.updateAlarm();
        this.broadcastState();
      }
    } else if (this.data.status === 'active') {
      // Kopan oyuncu geri bağlandıysa sayacı iptal et
      if (this.data.disconnectedUid === uid) {
        this.data = {
          ...this.data,
          disconnectedUid: undefined,
          schedule: {
            ...this.data.schedule,
            disconnectTimeoutAtMs: undefined,
          },
        };
        await this.persist();
        await this.updateAlarm();
      }
      this.broadcastState();
    } else if (this.data.status === 'finished') {
      this.sendStateToPlayer(uid);
      this.sendFinalToPlayer(uid);
    }
  }

  private async handleMatchFinished(): Promise<void> {
    if (!this.data) return;

    const nowMs = Date.now();
    this.data = {
      ...this.data,
      status: 'finished',
      schedule: {
        cleanupAtMs: nowMs + this.durations.cleanupMs,
      },
    };

    await this.persist();
    await this.updateAlarm();
    this.broadcastState();
    this.broadcastFinal();
  }

  private broadcastState(): void {
    if (!this.data || !this.data.engineState) return;
    this.sendStateToPlayer(this.data.p1.uid);
    this.sendStateToPlayer(this.data.p2.uid);
  }

  private sendStateToPlayer(uid: string): void {
    if (!this.data || !this.data.engineState) return;

    const isP1 = uid === this.data.p1.uid;
    const opponent = isP1 ? this.data.p2 : this.data.p1;
    const isDisconnected = this.data.disconnectedUid === opponent.uid;
    const opponentConnected =
      !isDisconnected &&
      this.ctx
        .getWebSockets(opponent.uid)
        .some((s) => s.readyState === 1 || s.readyState === undefined);

    const state = deserializeMatchState(this.data.engineState);
    const msg = filterStateForPlayer({
      state,
      playerUid: uid,
      opponentUid: opponent.uid,
      opponentName: opponent.name,
      opponentConnected,
      serverNowMs: Date.now(),
      nextRoundAtMs: this.data.schedule.nextRoundAtMs,
    });

    this.sendToUid(uid, JSON.stringify(msg));
  }

  private broadcastFinal(): void {
    if (!this.data || !this.data.engineState) return;
    this.sendFinalToPlayer(this.data.p1.uid);
    this.sendFinalToPlayer(this.data.p2.uid);
  }

  private sendFinalToPlayer(uid: string): void {
    if (!this.data || !this.data.engineState) return;

    const isP1 = uid === this.data.p1.uid;
    const opponent = isP1 ? this.data.p2 : this.data.p1;
    const state = deserializeMatchState(this.data.engineState);

    const msg = buildFinalMessage({
      state,
      playerUid: uid,
      opponentUid: opponent.uid,
    });

    this.sendToUid(uid, JSON.stringify(msg));
  }

  private sendToUid(uid: string, text: string): void {
    const sockets = this.ctx.getWebSockets(uid);
    for (const ws of sockets) {
      try {
        ws.send(text);
      } catch {
        // yoksay
      }
    }
  }

  private broadcastAll(text: string): void {
    const sockets = this.ctx.getWebSockets();
    for (const ws of sockets) {
      try {
        ws.send(text);
      } catch {
        // yoksay
      }
    }
  }

  private closeAllSockets(code: number, reason: string): void {
    const sockets = this.ctx.getWebSockets();
    for (const ws of sockets) {
      try {
        ws.close(code, reason);
      } catch {
        // yoksay
      }
    }
  }

  private async persist(): Promise<void> {
    if (this.data) {
      await this.ctx.storage.put('roomData', this.data);
    }
  }

  private async updateAlarm(): Promise<void> {
    if (!this.data) return;
    const nextAlarm = computeNextAlarm(this.data.schedule);
    if (nextAlarm !== null) {
      await this.ctx.storage.setAlarm(nextAlarm);
    }
  }
}
