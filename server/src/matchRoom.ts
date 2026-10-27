import { DurableObject } from 'cloudflare:workers';
import {
  MatchEngine,
  type MatchConfig,
  type MatchState,
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
import type { MatchRewardOutcome, SpendCoinsResult } from './userProfile';
import type { Env } from './index';

interface PlayerInfo {
  readonly uid: string;
  readonly name: string;
  readonly frame?: string;
}

export interface MatchRoomInitParams {
  readonly matchId: string;
  readonly p1: PlayerInfo;
  readonly p2: PlayerInfo;
  readonly questions: readonly Question[];
  readonly questionOrder: readonly string[];
  readonly matchType?: 'ranked' | 'friendly';
  readonly energyChargedUids?: readonly string[];
}

export interface PlayerRewardInfo {
  readonly coinsAwarded: number;
  readonly coins: number;
}

interface PendingRefund {
  readonly uid: string;
  readonly amount: number;
  readonly powerup: string;
}

interface LegacyRoomData {
  readonly matchId?: string;
  readonly disconnectedUid?: string;
  readonly disconnectedUids?: Record<string, number>;
  readonly pendingEnergyRefundUid?: string;
  readonly pendingEnergyRefundUids?: readonly string[];
  readonly schedule?: TimersSchedule;
  readonly [key: string]: unknown;
}

interface StoredRoomData {
  readonly matchId: string;
  readonly p1: PlayerInfo;
  readonly p2: PlayerInfo;
  readonly questions: Question[];
  readonly questionOrder: string[];
  readonly status: 'waiting_for_players' | 'active' | 'finished' | 'voided';
  readonly voidedReason?: 'opponent_absent' | 'both_disconnected' | 'draw_limit_reached';
  readonly matchType?: 'ranked' | 'friendly';
  readonly engineState?: SerializedMatchState;
  readonly schedule: TimersSchedule;
  readonly disconnectedUids?: Record<string, number>;
  readonly frozenTurnRemainingMs?: number;
  readonly rewards?: Record<string, PlayerRewardInfo>;
  readonly rewardRetryCount?: number;
  readonly leaderboardPending?: boolean;
  readonly leaderboardRetryCount?: number;
  readonly leaderboardWinnerUid?: string;
  readonly leaderboardWinnerNickname?: string | null;
  readonly leaderboardLoserUid?: string;
  readonly leaderboardLoserNickname?: string | null;
  readonly powerupsUsed?: Record<string, { extraTime?: boolean }>;
  readonly pendingRefunds?: readonly PendingRefund[];
  readonly refundRetryCount?: number;
  readonly energyChargedUids?: readonly string[];
  readonly pendingEnergyRefundUids?: readonly string[];
  readonly energyRefundRetryCount?: number;
}

export function migrateStoredRoomData(raw: unknown): StoredRoomData | null {
  if (!raw || typeof raw !== 'object') return null;
  const legacy = raw as LegacyRoomData;

  let disconnectedUids = legacy.disconnectedUids;
  if (!disconnectedUids && typeof legacy.disconnectedUid === 'string' && legacy.disconnectedUid.length > 0) {
    const legacyTimeout = legacy.schedule?.disconnectTimeoutAtMs ?? (Date.now() + 30000);
    disconnectedUids = { [legacy.disconnectedUid]: legacyTimeout };
  }

  let pendingEnergyRefundUids = legacy.pendingEnergyRefundUids
    ? [...legacy.pendingEnergyRefundUids]
    : undefined;
  if (
    !pendingEnergyRefundUids &&
    typeof legacy.pendingEnergyRefundUid === 'string' &&
    legacy.pendingEnergyRefundUid.length > 0
  ) {
    pendingEnergyRefundUids = [legacy.pendingEnergyRefundUid];
  }

  const {
    disconnectedUid: _legacyDisconnectedUid,
    pendingEnergyRefundUid: _legacyPendingEnergyRefundUid,
    ...rest
  } = legacy;

  return {
    ...rest,
    disconnectedUids,
    pendingEnergyRefundUids,
  } as unknown as StoredRoomData;
}

export function computeNextDisconnectTimeout(
  disconnectedUids: Record<string, number> | undefined,
  nowMs: number
): number | undefined {
  if (!disconnectedUids) return undefined;
  const unexpired = Object.values(disconnectedUids).filter((t) => t > nowMs);
  if (unexpired.length === 0) return undefined;
  return Math.min(...unexpired);
}

export class MatchRoom extends DurableObject<Env> {
  private data: StoredRoomData | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      const stored = await this.ctx.storage.get<unknown>('roomData');
      if (stored) {
        this.data = migrateStoredRoomData(stored);
      }
    });
  }

  private get durations(): RoomDurations {
    const isFast = this.env.FAST_TIMERS === 'true';
    return getRoomDurations(isFast);
  }

  private get turnGraceMs(): number {
    if (this.env.TURN_GRACE_MS !== undefined) {
      const parsed = Number(this.env.TURN_GRACE_MS);
      if (Number.isFinite(parsed) && parsed >= 0) {
        return parsed;
      }
    }
    return this.env.FAST_TIMERS === 'true' ? 100 : 400;
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
      matchType: params.matchType ?? 'ranked',
      energyChargedUids: params.energyChargedUids ? [...params.energyChargedUids] : [],
      schedule: { connectTimeoutAtMs },
    };

    await this.persist();
    await this.updateAlarm();
  }

  /**
   * Bildirme ve engelleme işlemleri için maç bağlamını ve rakip bilgilerini döndürür.
   * Maç 10 dakikalık tutulma süresinden sonra silindiyse null döner.
   */
  async getMatchReportContext(callerUid: string): Promise<
    | {
        readonly ok: true;
        readonly context: {
          readonly reporterUid: string;
          readonly reportedUid: string;
          readonly reportedNickname: string;
          readonly answers: readonly string[];
        };
      }
    | { readonly ok: false; readonly error: 'forbidden' }
    | null
  > {
    if (!this.data) {
      return null;
    }

    if (callerUid !== this.data.p1.uid && callerUid !== this.data.p2.uid) {
      return { ok: false, error: 'forbidden' };
    }

    const opponent = callerUid === this.data.p1.uid ? this.data.p2 : this.data.p1;
    const answers: string[] = [];

    if (this.data.engineState) {
      const state = deserializeMatchState(this.data.engineState);
      for (const round of state.roundHistory) {
        for (const attempt of round.attempts) {
          if (attempt.playerId === opponent.uid && attempt.rawInput) {
            answers.push(attempt.rawInput);
          }
        }
      }
    }

    return {
      ok: true,
      context: {
        reporterUid: callerUid,
        reportedUid: opponent.uid,
        reportedNickname: opponent.name,
        answers,
      },
    };
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
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server, [uid]);

      const voidedMsg: ClientVoidedMessage = {
        t: 'voided',
        reason: this.data.voidedReason ?? 'opponent_absent',
      };
      server.send(JSON.stringify(voidedMsg));
      server.close(1000, 'voided');

      return new Response(null, { status: 101, webSocket: client });
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

    if (parsed.t === 'use_powerup') {
      if (parsed.type === 'extra_time') {
        await this.handleUseExtraTime(uid);
      }
      return;
    }

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
        if (res.state.endedBy === 'draw_limit_reached') {
          await this.handleDrawLimitVoided(res.state.totalRoundsPlayed);
        } else {
          await this.handleMatchFinished();
        }
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
            turnDeadlineMs: res.state.deadlineMs + this.turnGraceMs,
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

    // Oyuncunun başka açık soketi kalmış mı kontrol et
    const remainingSockets = this.ctx.getWebSockets(uid).filter((s) => s !== ws);
    if (remainingSockets.length > 0) return;

    if (this.data.status === 'active') {
      const nowMs = Date.now();
      const playerTimeoutAtMs = nowMs + this.durations.disconnectTimeoutMs;
      const nextDisconnectedUids: Record<string, number> = {
        ...(this.data.disconnectedUids ?? {}),
        [uid]: playerTimeoutAtMs,
      };

      const p1Uid = this.data.p1.uid;
      const p2Uid = this.data.p2.uid;
      const bothDisconnected =
        nextDisconnectedUids[p1Uid] !== undefined &&
        nextDisconnectedUids[p2Uid] !== undefined;

      let frozenTurnRemainingMs = this.data.frozenTurnRemainingMs;
      let turnDeadlineMs = this.data.schedule.turnDeadlineMs;

      if (bothDisconnected) {
        // EK ŞART: İki oyuncu da odada yokken turnTimeout alarmı tur/maç sonucu üretmesin
        if (turnDeadlineMs !== undefined) {
          if (this.data.engineState) {
            const state = deserializeMatchState(this.data.engineState);
            frozenTurnRemainingMs = Math.max(0, state.deadlineMs - nowMs);
          } else {
            frozenTurnRemainingMs = Math.max(0, turnDeadlineMs - nowMs);
          }
          turnDeadlineMs = undefined;
        }
      }

      const disconnectTimeoutAtMs = computeNextDisconnectTimeout(
        nextDisconnectedUids,
        nowMs
      );

      const nextSchedule: TimersSchedule = {
        ...this.data.schedule,
        turnDeadlineMs,
        disconnectTimeoutAtMs,
      };

      this.data = {
        ...this.data,
        disconnectedUids: nextDisconnectedUids,
        frozenTurnRemainingMs,
        schedule: nextSchedule,
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
          console.log(
            JSON.stringify({
              event: 'match_voided',
              reason: 'opponent_absent',
              matchId: this.data.matchId,
              roundsPlayed: 0,
            })
          );
          this.data = {
            ...this.data,
            status: 'voided',
            voidedReason: 'opponent_absent',
            schedule: { cleanupAtMs: nowMs + this.durations.cleanupMs },
          };
          const voidedMsg: ClientVoidedMessage = { t: 'voided', reason: 'opponent_absent' };
          this.broadcastAll(JSON.stringify(voidedMsg));
          this.closeAllSockets(1000, 'voided');

          if (this.data.energyChargedUids && this.data.energyChargedUids.length > 0) {
            await this.applyEnergyRefunds(this.data.energyChargedUids);
          }
        }
      } else if (action === 'disconnectForfeit') {
        if (this.data.status === 'active' && this.data.disconnectedUids && this.data.engineState) {
          const p1Uid = this.data.p1.uid;
          const p2Uid = this.data.p2.uid;
          const p1Deadline = this.data.disconnectedUids[p1Uid];
          const p2Deadline = this.data.disconnectedUids[p2Uid];

          const p1Disconnected = p1Deadline !== undefined;
          const p2Disconnected = p2Deadline !== undefined;
          const p1Expired = p1Disconnected && nowMs >= p1Deadline;
          const p2Expired = p2Disconnected && nowMs >= p2Deadline;

          if (p1Expired && p2Expired) {
            // İki oyuncunun da vadesi dolmuş ve ikisi de kopuk -> Maç iptal (voided)
            const state = deserializeMatchState(this.data.engineState);
            const roundsPlayed = state.totalRoundsPlayed;
            console.log(
              JSON.stringify({
                event: 'match_voided',
                reason: 'both_disconnected',
                matchId: this.data.matchId,
                roundsPlayed,
              })
            );
            this.data = {
              ...this.data,
              status: 'voided',
              voidedReason: 'both_disconnected',
              schedule: { cleanupAtMs: nowMs + this.durations.cleanupMs },
            };
            const voidedMsg: ClientVoidedMessage = { t: 'voided', reason: 'both_disconnected' };
            this.broadcastAll(JSON.stringify(voidedMsg));
            this.closeAllSockets(1000, 'voided');

            if (this.data.energyChargedUids && this.data.energyChargedUids.length > 0) {
              await this.applyEnergyRefunds(this.data.energyChargedUids);
            }
          } else if (p1Expired && !p2Disconnected) {
            // P1 vadesi doldu, P2 bağlı -> P1 hükmen yenik
            console.log(
              JSON.stringify({
                event: 'disconnect_forfeit',
                matchId: this.data.matchId,
                forfeiterIndex: 1,
              })
            );
            const state = deserializeMatchState(this.data.engineState);
            const res = MatchEngine.forfeit({
              state,
              playerId: p1Uid,
              nowMs,
            });
            this.data = {
              ...this.data,
              engineState: serializeMatchState(res.state),
            };
            await this.handleMatchFinished();
          } else if (p2Expired && !p1Disconnected) {
            // P2 vadesi doldu, P1 bağlı -> P2 hükmen yenik
            console.log(
              JSON.stringify({
                event: 'disconnect_forfeit',
                matchId: this.data.matchId,
                forfeiterIndex: 2,
              })
            );
            const state = deserializeMatchState(this.data.engineState);
            const res = MatchEngine.forfeit({
              state,
              playerId: p2Uid,
              nowMs,
            });
            this.data = {
              ...this.data,
              engineState: serializeMatchState(res.state),
            };
            await this.handleMatchFinished();
          } else {
            // Biri doldu ama diğeri de kopuk ve vadesi henüz dolmadı: bekle!
            // Dolmamış olan vadeye alarm kurulur.
            const nextDisconnectAtMs = computeNextDisconnectTimeout(
              this.data.disconnectedUids,
              nowMs
            );
            this.data = {
              ...this.data,
              schedule: {
                ...this.data.schedule,
                disconnectTimeoutAtMs: nextDisconnectAtMs,
              },
            };
          }
        }
      } else if (action === 'turnTimeout') {
        if (this.data.status === 'active' && this.data.engineState) {
          const p1Disconnected = this.data.disconnectedUids?.[this.data.p1.uid] !== undefined;
          const p2Disconnected = this.data.disconnectedUids?.[this.data.p2.uid] !== undefined;
          if (p1Disconnected && p2Disconnected) {
            // EK ŞART savunma: iki oyuncu da yokken turnTimeout tur/maç sonucu üretmez!
            continue;
          }

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
            if (res.state.endedBy === 'draw_limit_reached') {
              await this.handleDrawLimitVoided(res.state.totalRoundsPlayed);
            } else {
              await this.handleMatchFinished();
            }
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
          const p1Disconnected = this.data.disconnectedUids?.[this.data.p1.uid] !== undefined;
          const p2Disconnected = this.data.disconnectedUids?.[this.data.p2.uid] !== undefined;
          const bothDisconnected = p1Disconnected && p2Disconnected;

          const state = deserializeMatchState(this.data.engineState);
          const questions = this.data.questions;
          const res = MatchEngine.startNextRound({
            state,
            questions,
            nowMs,
            questionOrder: this.data.questionOrder,
          });

          if (bothDisconnected) {
            // İkisi de yokken yeni turun süresi dondurulur
            const answerMs = this.durations.answerSeconds * 1000;
            this.data = {
              ...this.data,
              engineState: serializeMatchState(res.state),
              frozenTurnRemainingMs: answerMs,
              schedule: {
                ...this.data.schedule,
                nextRoundAtMs: undefined,
                turnDeadlineMs: undefined,
              },
            };
          } else {
            this.data = {
              ...this.data,
              engineState: serializeMatchState(res.state),
              schedule: {
                ...this.data.schedule,
                nextRoundAtMs: undefined,
                turnDeadlineMs: res.state.deadlineMs + this.turnGraceMs,
              },
            };
          }
          await this.persist();
          await this.updateAlarm();
          this.broadcastState();
        }
      } else if (action === 'rewardRetry') {
        if (this.data.status === 'finished') {
          await this.applyMatchRewards();
        }
      } else if (action === 'leaderboardRetry') {
        if (this.data.status === 'finished' && this.data.leaderboardPending) {
          await this.applyLeaderboard();
        }
      } else if (action === 'refundRetry') {
        await this.processPendingRefunds();
      } else if (action === 'energyRefundRetry') {
        await this.processPendingEnergyRefund();
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
          graceMs: this.turnGraceMs,
          nearMissPerRound: 1,
          minAnswersPerQuestion: 0,
          minSubmitIntervalMs: 600,
          maxAttemptsPerTurn: 25,
          maxTotalRounds: 5,
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
            turnDeadlineMs: res.state.deadlineMs + this.turnGraceMs,
          },
        };

        await this.persist();
        await this.updateAlarm();
        this.broadcastState();
      }
    } else if (this.data.status === 'active') {
      const nowMs = Date.now();
      const p1Uid = this.data.p1.uid;
      const p2Uid = this.data.p2.uid;
      const isP1 = uid === p1Uid;
      const opponentUid = isP1 ? p2Uid : p1Uid;

      const nextDisconnectedUids: Record<string, number> = {
        ...(this.data.disconnectedUids ?? {}),
      };
      delete nextDisconnectedUids[uid];

      const opponentTimeout = nextDisconnectedUids[opponentUid];
      const opponentDisconnected = opponentTimeout !== undefined;
      const opponentExpired = opponentDisconnected && nowMs >= opponentTimeout;

      if (opponentExpired && this.data.engineState) {
        // Dönen oyuncunun rakibi kopuk ve vadesi zaten dolmuş -> Rakip hükmen yenik!
        const forfeiterIndex = opponentUid === p1Uid ? 1 : 2;
        console.log(
          JSON.stringify({
            event: 'disconnect_forfeit',
            matchId: this.data.matchId,
            forfeiterIndex,
          })
        );
        const state = deserializeMatchState(this.data.engineState);
        const res = MatchEngine.forfeit({
          state,
          playerId: opponentUid,
          nowMs,
        });
        this.data = {
          ...this.data,
          engineState: serializeMatchState(res.state),
          disconnectedUids: nextDisconnectedUids,
        };
        await this.handleMatchFinished();
        return;
      }

      // Rakibin süresi dolmamış veya rakip bağlı: maç devam eder
      let engineState = this.data.engineState;
      let turnDeadlineMs = this.data.schedule.turnDeadlineMs;
      let frozenTurnRemainingMs = this.data.frozenTurnRemainingMs;

      if (frozenTurnRemainingMs !== undefined && engineState) {
        // İki oyuncu kopukken dondurulan süre geri dönen oyuncuyla devam eder
        const state = deserializeMatchState(engineState);
        const resumedRemaining = Math.max(1000, frozenTurnRemainingMs);
        const newDeadlineMs = nowMs + resumedRemaining;
        const updatedState: MatchState = { ...state, deadlineMs: newDeadlineMs };
        engineState = serializeMatchState(updatedState);
        turnDeadlineMs = newDeadlineMs + this.turnGraceMs;
        frozenTurnRemainingMs = undefined;
      }

      const disconnectTimeoutAtMs = computeNextDisconnectTimeout(
        nextDisconnectedUids,
        nowMs
      );

      this.data = {
        ...this.data,
        engineState,
        disconnectedUids: nextDisconnectedUids,
        frozenTurnRemainingMs,
        schedule: {
          ...this.data.schedule,
          turnDeadlineMs,
          disconnectTimeoutAtMs,
        },
      };

      await this.persist();
      await this.updateAlarm();
      this.broadcastState();
    } else if (this.data.status === 'finished') {
      this.sendStateToPlayer(uid);
      this.sendFinalToPlayer(uid);
    } else if (this.data.status === 'voided') {
      const voidedMsg: ClientVoidedMessage = {
        t: 'voided',
        reason: this.data.voidedReason ?? 'opponent_absent',
      };
      this.sendToUid(uid, JSON.stringify(voidedMsg));
    }
  }

  private async handleDrawLimitVoided(totalRounds: number): Promise<void> {
    if (!this.data) return;
    console.log(
      JSON.stringify({
        event: 'match_voided',
        matchId: this.data.matchId,
        reason: 'draw_limit_reached',
        totalRounds,
      })
    );
    this.data = {
      ...this.data,
      status: 'voided',
      voidedReason: 'draw_limit_reached',
      schedule: {},
    };
    const voidedMsg: ClientVoidedMessage = { t: 'voided', reason: 'draw_limit_reached' };
    this.broadcastAll(JSON.stringify(voidedMsg));
    this.closeAllSockets(1000, 'voided');
    await this.persist();
    await this.updateAlarm();
    if (this.data.energyChargedUids && this.data.energyChargedUids.length > 0) {
      await this.applyEnergyRefunds(this.data.energyChargedUids);
    }
  }

  private async handleMatchFinished(): Promise<void> {
    if (!this.data) return;

    const state = this.data.engineState ? deserializeMatchState(this.data.engineState) : null;
    if (state?.endedBy === 'draw_limit_reached') {
      await this.handleDrawLimitVoided(state.totalRoundsPlayed);
      return;
    }

    const nowMs = Date.now();
    const winnerId = state?.winnerId;
    const p1Uid = this.data.p1.uid;
    const p2Uid = this.data.p2.uid;
    const isWinnerPresent = winnerId === p1Uid || winnerId === p2Uid;
    const isFriendly = this.data.matchType === 'friendly';

    this.data = {
      ...this.data,
      status: 'finished',
      schedule: {
        cleanupAtMs: nowMs + this.durations.cleanupMs,
      },
      ...(!isFriendly && isWinnerPresent
        ? {
            leaderboardPending: true,
            leaderboardWinnerUid: winnerId,
            leaderboardLoserUid: winnerId === p1Uid ? p2Uid : p1Uid,
          }
        : {}),
      ...(isFriendly
        ? {
            rewards: {
              [p1Uid]: { coinsAwarded: 0, coins: 0 },
              [p2Uid]: { coinsAwarded: 0, coins: 0 },
            },
          }
        : {}),
    };

    if (!isFriendly) {
      await this.applyMatchRewards();
      if (this.data.leaderboardPending) {
        await this.applyLeaderboard();
      }
      const endedBy = state?.endedBy;
      if (endedBy === 'forfeit' && winnerId && this.data.energyChargedUids?.includes(winnerId)) {
        await this.applyEnergyRefunds([winnerId]);
      }
    }
    await this.persist();
    await this.updateAlarm();
    this.broadcastState();
    this.broadcastFinal();
  }

  private async applyMatchRewards(): Promise<boolean> {
    if (!this.data || !this.data.engineState || this.data.matchType === 'friendly') return false;
    const state = deserializeMatchState(this.data.engineState);
    const winnerId = state.winnerId;
    const endedBy = state.endedBy;

    const p1Uid = this.data.p1.uid;
    const p2Uid = this.data.p2.uid;

    const getOutcome = (uid: string): MatchRewardOutcome => {
      const isWinner = winnerId === uid;
      if (endedBy === 'forfeit') {
        return isWinner ? 'win_by_opponent_disconnect' : 'loss_by_disconnect';
      }
      return isWinner ? 'win' : 'loss';
    };

    const p1Stub = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(p1Uid));
    const p2Stub = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(p2Uid));

    const existingRewards = this.data.rewards ?? {};
    let p1Reward = existingRewards[p1Uid];
    let p2Reward = existingRewards[p2Uid];
    let p1Nick: string | null | undefined = undefined;
    let p2Nick: string | null | undefined = undefined;
    let hasTransientError = false;

    if (!p1Reward) {
      try {
        const r1 = await p1Stub.applyMatchReward({
          matchId: this.data.matchId,
          outcome: getOutcome(p1Uid),
          uid: p1Uid,
        });
        p1Reward = { coinsAwarded: r1.coinsAwarded, coins: r1.coins };
        p1Nick = r1.nickname;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes('account_deleted')) {
          // Kalıcı hata: ödül verilmez, tekrar denenmez
          p1Reward = { coinsAwarded: 0, coins: 0 };
        } else {
          console.error('applyMatchRewards failed for p1:', err);
          hasTransientError = true;
        }
      }
    }

    if (!p2Reward) {
      try {
        const r2 = await p2Stub.applyMatchReward({
          matchId: this.data.matchId,
          outcome: getOutcome(p2Uid),
          uid: p2Uid,
        });
        p2Reward = { coinsAwarded: r2.coinsAwarded, coins: r2.coins };
        p2Nick = r2.nickname;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes('account_deleted')) {
          // Kalıcı hata: ödül verilmez, tekrar denenmez
          p2Reward = { coinsAwarded: 0, coins: 0 };
        } else {
          console.error('applyMatchRewards failed for p2:', err);
          hasTransientError = true;
        }
      }
    }

    const winnerUid = this.data.leaderboardWinnerUid;
    const loserUid = this.data.leaderboardLoserUid;
    const winnerNick =
      winnerUid === p1Uid ? p1Nick : winnerUid === p2Uid ? p2Nick : undefined;
    const loserNick =
      loserUid === p1Uid ? p1Nick : loserUid === p2Uid ? p2Nick : undefined;

    const newRewards: Record<string, { coinsAwarded: number; coins: number }> = {};
    if (p1Reward) newRewards[p1Uid] = p1Reward;
    if (p2Reward) newRewards[p2Uid] = p2Reward;

    if (!hasTransientError) {
      this.data = {
        ...this.data,
        rewards: newRewards,
        leaderboardWinnerNickname:
          winnerNick !== undefined ? winnerNick : this.data.leaderboardWinnerNickname,
        leaderboardLoserNickname:
          loserNick !== undefined ? loserNick : this.data.leaderboardLoserNickname,
        schedule: {
          ...this.data.schedule,
          rewardRetryAtMs: undefined,
        },
      };
      await this.persist();
      return true;
    } else {
      const currentRetries = this.data.rewardRetryCount ?? 0;
      const maxRetries = 3;
      if (currentRetries < maxRetries) {
        const backoffMs = Math.min(30000, 2000 * Math.pow(2, currentRetries));
        this.data = {
          ...this.data,
          rewards: newRewards,
          rewardRetryCount: currentRetries + 1,
          schedule: {
            ...this.data.schedule,
            rewardRetryAtMs: Date.now() + backoffMs,
          },
        };
      } else {
        this.data = {
          ...this.data,
          rewards: newRewards,
          schedule: {
            ...this.data.schedule,
            rewardRetryAtMs: undefined,
          },
        };
      }
      await this.persist();
      await this.updateAlarm();
      return false;
    }
  }

  private async applyLeaderboard(): Promise<boolean> {
    if (
      !this.data ||
      this.data.matchType === 'friendly' ||
      !this.data.leaderboardPending ||
      !this.data.leaderboardWinnerUid ||
      !this.data.leaderboardLoserUid ||
      !this.env.LEADERBOARD
    ) {
      return true;
    }

    let winnerNick = this.data.leaderboardWinnerNickname;
    let loserNick = this.data.leaderboardLoserNickname;
    const deletedUids: string[] = [];

    if (winnerNick === undefined || loserNick === undefined) {
      try {
        const pWinner = await this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(this.data.leaderboardWinnerUid)
        ).getProfile(this.data.leaderboardWinnerUid);
        winnerNick = pWinner.nickname;
      } catch (err) {
        if (err instanceof Error && err.message.includes('account_deleted')) {
          deletedUids.push(this.data.leaderboardWinnerUid);
        }
      }

      try {
        const pLoser = await this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(this.data.leaderboardLoserUid)
        ).getProfile(this.data.leaderboardLoserUid);
        loserNick = pLoser.nickname;
      } catch (err) {
        if (err instanceof Error && err.message.includes('account_deleted')) {
          deletedUids.push(this.data.leaderboardLoserUid);
        }
      }
    }

    try {
      const leaderboardStub = this.env.LEADERBOARD.get(
        this.env.LEADERBOARD.idFromName('global')
      );
      const winnerFrame =
        (this.data.leaderboardWinnerUid === this.data.p1.uid
          ? this.data.p1.frame
          : this.data.p2.frame) || 'classic';

      await leaderboardStub.recordMatchResult({
        matchId: this.data.matchId,
        winnerUid: this.data.leaderboardWinnerUid,
        winnerNickname: winnerNick ?? null,
        winnerFrame,
        loserUid: this.data.leaderboardLoserUid,
        loserNickname: loserNick ?? null,
        deletedUids,
      });

      this.data = {
        ...this.data,
        leaderboardPending: false,
        leaderboardWinnerNickname: winnerNick,
        leaderboardLoserNickname: loserNick,
        schedule: {
          ...this.data.schedule,
          leaderboardRetryAtMs: undefined,
        },
      };
      await this.persist();
      return true;
    } catch (err) {
      console.error('applyLeaderboard failed:', err);
      const currentRetries = this.data.leaderboardRetryCount ?? 0;
      const maxRetries = 3;
      if (currentRetries < maxRetries) {
        const backoffMs = Math.min(30000, 2000 * Math.pow(2, currentRetries));
        this.data = {
          ...this.data,
          leaderboardPending: true,
          leaderboardRetryCount: currentRetries + 1,
          schedule: {
            ...this.data.schedule,
            leaderboardRetryAtMs: Date.now() + backoffMs,
          },
        };
      } else {
        this.data = {
          ...this.data,
          schedule: {
            ...this.data.schedule,
            leaderboardRetryAtMs: undefined,
          },
        };
      }
      await this.persist();
      await this.updateAlarm();
      return false;
    }
  }

  private get extraTimeConfig(): { cost: number; seconds: number } {
    const costVal = parseInt(this.env.EXTRA_TIME_COST ?? '30', 10);
    const secVal = parseInt(this.env.EXTRA_TIME_SECONDS ?? '5', 10);
    return {
      cost: Number.isFinite(costVal) && costVal >= 0 ? costVal : 30,
      seconds: Number.isFinite(secVal) && secVal > 0 ? secVal : 5,
    };
  }

  private async handleUseExtraTime(uid: string): Promise<void> {
    if (!this.data) return;

    if (this.data.matchType === 'friendly') {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'not_allowed_in_match_type',
        message: 'Arkadaş maçında güçlendirici kullanılamaz.',
      }));
      return;
    }

    if (this.data.status !== 'active' || !this.data.engineState) {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'round_not_active',
        message: 'Aktif bir tur bulunmuyor.',
      }));
      return;
    }

    const state = deserializeMatchState(this.data.engineState);

    if (state.phase !== 'roundActive') {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'round_not_active',
        message: 'Aktif bir tur bulunmuyor.',
      }));
      return;
    }

    if (state.turnPlayerId !== uid) {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'not_your_turn',
        message: 'Sıra sende değil.',
      }));
      return;
    }

    if (this.data.powerupsUsed?.[uid]?.extraTime) {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'already_used',
        message: 'Bu maçta zaten ek süre hakkını kullandın.',
      }));
      return;
    }

    const nowMs = Date.now();
    if (nowMs >= state.deadlineMs) {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'round_not_active',
        message: 'Süre doldu.',
      }));
      return;
    }

    const config = this.extraTimeConfig;
    const userProfileStub = this.env.USER_PROFILE.get(
      this.env.USER_PROFILE.idFromName(uid)
    );

    let spendRes: SpendCoinsResult;
    try {
      spendRes = await userProfileStub.spendCoins({
        matchId: this.data.matchId,
        powerup: 'extra_time',
        amount: config.cost,
        uid,
      });
    } catch (err) {
      const errMsg = err instanceof Error ? `${err.message}\n${err.stack}` : String(err);
      console.error(`spendCoins failed for uid ${uid}:`, errMsg);
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'temporary_error',
        message: 'İşlem sırasında bir hata oluştu.',
      }));
      return;
    }

    if (!spendRes.success) {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: spendRes.error ?? 'not_enough_coins',
        message: spendRes.error === 'account_deleted'
          ? 'Hesap silinmiş.'
          : 'Yetersiz jeton bakiyesi.',
      }));
      return;
    }

    // Post-check (Yarış durumu kontrolü):
    // Ağ çağrısı sırasında tur bitti mi veya sıra değişti mi?
    if (
      !this.data ||
      this.data.status !== 'active' ||
      !this.data.engineState
    ) {
      await this.enqueueAndRefund(uid, config.cost, 'extra_time');
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'round_not_active',
        message: 'Tur sona erdiği için harcama iade edildi.',
      }));
      return;
    }

    const currentState = deserializeMatchState(this.data.engineState);
    const currentNowMs = Date.now();

    if (
      currentState.phase !== 'roundActive' ||
      currentState.turnPlayerId !== uid ||
      currentNowMs >= currentState.deadlineMs
    ) {
      await this.enqueueAndRefund(uid, config.cost, 'extra_time');
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'round_not_active',
        message: 'Tur sona erdiği için harcama iade edildi.',
      }));
      return;
    }

    // Eğer alreadySpent: true döndüyse ve bu odada zaten kaydedilmişse tekrar süre ekleme
    if (spendRes.alreadySpent && this.data.powerupsUsed?.[uid]?.extraTime) {
      this.sendToUid(uid, JSON.stringify({
        t: 'powerup_ack',
        powerupType: 'extra_time',
        success: false,
        code: 'already_used',
        message: 'Bu maçta zaten ek süre hakkını kullandın.',
      }));
      return;
    }

    // Süreyi uzat
    const updatedState: MatchState = {
      ...currentState,
      deadlineMs: currentState.deadlineMs + config.seconds * 1000,
    };

    this.data = {
      ...this.data,
      engineState: serializeMatchState(updatedState),
      schedule: {
        ...this.data.schedule,
        turnDeadlineMs: updatedState.deadlineMs + this.turnGraceMs,
      },
      powerupsUsed: {
        ...this.data.powerupsUsed,
        [uid]: { extraTime: true },
      },
    };

    await this.persist();
    await this.updateAlarm();

    // Kullanan oyuncuya onay gönder
    this.sendToUid(uid, JSON.stringify({
      t: 'powerup_ack',
      powerupType: 'extra_time',
      success: true,
      deadlineMs: updatedState.deadlineMs,
      coins: spendRes.coins,
      remainingUses: 0,
    }));

    // Rakibe bilgilendirme bildirimi gönder
    const opponentUid = uid === this.data.p1.uid ? this.data.p2.uid : this.data.p1.uid;
    this.sendToUid(opponentUid, JSON.stringify({
      t: 'opponent_powerup',
      powerupType: 'extra_time',
      seconds: config.seconds,
    }));

    // Her iki oyuncuya güncel durumu yayınla
    this.broadcastState();
  }

  private async enqueueAndRefund(
    uid: string,
    amount: number,
    powerup: string
  ): Promise<void> {
    if (!this.data) return;
    const refunds = [...(this.data.pendingRefunds ?? []), { uid, amount, powerup }];
    this.data = {
      ...this.data,
      pendingRefunds: refunds,
    };
    await this.persist();
    await this.processPendingRefunds();
  }

  private async processPendingRefunds(): Promise<void> {
    if (!this.data || !this.data.pendingRefunds || this.data.pendingRefunds.length === 0) {
      if (this.data?.schedule.refundRetryAtMs) {
        this.data = {
          ...this.data,
          schedule: {
            ...this.data.schedule,
            refundRetryAtMs: undefined,
          },
        };
        await this.persist();
        await this.updateAlarm();
      }
      return;
    }

    const remainingRefunds: PendingRefund[] = [];
    let hasTransientError = false;

    for (const item of this.data.pendingRefunds) {
      try {
        const userProfileStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(item.uid)
        );
        await userProfileStub.refundPowerup({
          matchId: this.data.matchId,
          powerup: item.powerup,
          amount: item.amount,
          uid: item.uid,
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes('account_deleted')) {
          // Kalıcı hata: silinmiş hesap, tekrar denenmez
        } else {
          console.error('refundPowerup transient error for uid:', item.uid, err);
          remainingRefunds.push(item);
          hasTransientError = true;
        }
      }
    }

    const retryCount = (this.data.refundRetryCount ?? 0) + 1;
    const nowMs = Date.now();

    if (hasTransientError && remainingRefunds.length > 0) {
      const delayMs = Math.min(60000, 1000 * Math.pow(2, Math.min(6, retryCount)));
      this.data = {
        ...this.data,
        pendingRefunds: remainingRefunds,
        refundRetryCount: retryCount,
        schedule: {
          ...this.data.schedule,
          refundRetryAtMs: nowMs + delayMs,
        },
      };
      await this.persist();
      await this.updateAlarm();
    } else {
      this.data = {
        ...this.data,
        pendingRefunds: [],
        refundRetryCount: 0,
        schedule: {
          ...this.data.schedule,
          refundRetryAtMs: undefined,
        },
      };
      await this.persist();
      await this.updateAlarm();
    }
  }

  private async applyEnergyRefunds(targetUids: readonly string[]): Promise<void> {
    if (!this.data || targetUids.length === 0) return;

    const remainingUids: string[] = [];
    let hasTransientError = false;

    for (const uid of targetUids) {
      try {
        const userProfileStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(uid)
        );
        const res = await userProfileStub.refundEnergy({
          matchId: this.data.matchId,
          amount: 1,
          uid,
        });
        console.log(`Energy refund applied for uid: refunded=${res.refunded}`);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes('account_deleted')) {
          // Kalıcı hata: silinmiş hesap, tekrar denenmez
        } else {
          console.error('refundEnergy transient error for uid:', err);
          remainingUids.push(uid);
          hasTransientError = true;
        }
      }
    }

    const retryCount = (this.data.energyRefundRetryCount ?? 0) + 1;
    const nowMs = Date.now();

    if (hasTransientError && remainingUids.length > 0 && retryCount <= 5) {
      const delayMs = Math.min(1000 * Math.pow(2, retryCount - 1), 10000);
      this.data = {
        ...this.data,
        pendingEnergyRefundUids: remainingUids,
        energyRefundRetryCount: retryCount,
        schedule: {
          ...this.data.schedule,
          energyRefundRetryAtMs: nowMs + delayMs,
        },
      };
    } else {
      this.data = {
        ...this.data,
        pendingEnergyRefundUids: undefined,
        energyRefundRetryCount: 0,
        schedule: {
          ...this.data.schedule,
          energyRefundRetryAtMs: undefined,
        },
      };
    }
  }

  private async processPendingEnergyRefund(): Promise<void> {
    if (!this.data || !this.data.pendingEnergyRefundUids || this.data.pendingEnergyRefundUids.length === 0) {
      if (this.data?.schedule.energyRefundRetryAtMs) {
        this.data = {
          ...this.data,
          schedule: {
            ...this.data.schedule,
            energyRefundRetryAtMs: undefined,
          },
        };
        await this.persist();
        await this.updateAlarm();
      }
      return;
    }
    await this.applyEnergyRefunds(this.data.pendingEnergyRefundUids);
    await this.persist();
    await this.updateAlarm();
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
    const isDisconnected = this.data.disconnectedUids?.[opponent.uid] !== undefined;
    const opponentConnected =
      !isDisconnected &&
      this.ctx
        .getWebSockets(opponent.uid)
        .some((s) => s.readyState === 1 || s.readyState === undefined);

    const state = deserializeMatchState(this.data.engineState);
    const isFriendly = this.data.matchType === 'friendly';
    const extraTimeCfg = this.extraTimeConfig;
    const isUsed = this.data.powerupsUsed?.[uid]?.extraTime ?? false;
    const powerups = isFriendly
      ? undefined
      : {
          extraTime: {
            cost: extraTimeCfg.cost,
            seconds: extraTimeCfg.seconds,
            remainingUses: isUsed ? 0 : 1,
          },
        };

    const msg = filterStateForPlayer({
      state,
      playerUid: uid,
      opponentUid: opponent.uid,
      opponentName: opponent.name,
      opponentFrame: opponent.frame || 'classic',
      opponentConnected,
      serverNowMs: Date.now(),
      nextRoundAtMs: this.data.schedule.nextRoundAtMs,
      answerSeconds: this.durations.answerSeconds,
      powerups,
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

    const playerReward = this.data.rewards?.[uid];

    const isFriendly = this.data.matchType === 'friendly';
    const msg = buildFinalMessage({
      state,
      playerUid: uid,
      opponentUid: opponent.uid,
      opponentName: opponent.name,
      opponentFrame: opponent.frame || 'classic',
      ...(isFriendly
        ? { coinsAwarded: 0 }
        : playerReward
        ? {
            coinsAwarded: playerReward.coinsAwarded,
            coins: playerReward.coins,
          }
        : {}),
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
