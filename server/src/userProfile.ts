import { DurableObject } from 'cloudflare:workers';
import { validateNickname } from './engine/nicknameValidator';
import type { Env } from './index';

export type MatchRewardOutcome =
  | 'win'
  | 'loss'
  | 'win_by_opponent_disconnect'
  | 'loss_by_disconnect';

export interface UserStats {
  readonly played: number;
  readonly won: number;
  readonly lost: number;
}

export interface UserProfileData {
  readonly uid: string;
  readonly nickname: string | null;
  readonly coins: number;
  readonly stats: UserStats;
  readonly createdAt: number;
}

export interface MatchRewardResult {
  readonly coinsAwarded: number;
  readonly coins: number;
  readonly nickname?: string | null;
  readonly alreadyProcessed?: boolean;
}

interface ProfileRow extends Record<string, string | number | null> {
  uid: string;
  nickname: string | null;
  coins: number;
  played: number;
  won: number;
  lost: number;
  created_at: number;
}

interface DailyCoinsRow extends Record<string, string | number | null> {
  day_key: string;
  earned: number;
}

interface ProcessedMatchRow extends Record<string, string | number | null> {
  match_id: string;
  applied_at: number;
  outcome: string;
  coins_awarded: number;
}

interface TombstoneRow extends Record<string, string | number | null> {
  uid: string;
  deleted_at: number;
}

export class UserProfile extends DurableObject<Env> {
  private initialized = false;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  private ensureSchema(): void {
    if (this.initialized) return;

    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS profiles (
        uid TEXT PRIMARY KEY,
        nickname TEXT,
        coins INTEGER NOT NULL,
        played INTEGER NOT NULL DEFAULT 0,
        won INTEGER NOT NULL DEFAULT 0,
        lost INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS daily_coins (
        day_key TEXT PRIMARY KEY,
        earned INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS processed_matches (
        match_id TEXT PRIMARY KEY,
        applied_at INTEGER NOT NULL,
        outcome TEXT NOT NULL,
        coins_awarded INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS tombstone (
        uid TEXT PRIMARY KEY,
        deleted_at INTEGER NOT NULL
      );
    `);

    this.initialized = true;
  }

  /**
   * Profilin silinip silinmediğini (tombstone) kontrol eder.
   */
  isDeleted(): boolean {
    this.ensureSchema();
    const cursor = this.ctx.storage.sql.exec<TombstoneRow>(
      'SELECT uid, deleted_at FROM tombstone LIMIT 1'
    );
    return cursor.toArray().length > 0;
  }

  /**
   * Hesabı kalıcı olarak siler ve 24 saatlik tombstone kaydı bırakır.
   * 24 saat sonra DO alarmı tetiklenir ve tüm depolama silinir.
   * İdempotenttir; tombstone zaten varken çağrılsa bile 200 döner.
   */
  async deleteProfile(uid?: string): Promise<{ ok: true; deleted: true }> {
    this.ensureSchema();

    let effectiveUid = uid && uid.trim().length > 0 ? uid.trim() : '';
    if (!effectiveUid) {
      const existing = this.ctx.storage.sql.exec<ProfileRow>(
        'SELECT uid FROM profiles LIMIT 1'
      ).toArray();
      effectiveUid = existing.length > 0 ? existing[0].uid : 'unknown';
    }

    // Tablolardaki tüm kişisel verileri sil
    this.ctx.storage.sql.exec(`
      DELETE FROM profiles;
      DELETE FROM daily_coins;
      DELETE FROM processed_matches;
    `);

    // Tombstone kaydı ekle veya güncelle
    const nowMs = Date.now();
    this.ctx.storage.sql.exec(
      'INSERT OR REPLACE INTO tombstone (uid, deleted_at) VALUES (?, ?)',
      effectiveUid,
      nowMs
    );

    // 24 saat sonra DO verilerini tamamen temizleyecek alarm kur
    const twentyFourHoursMs = 24 * 60 * 60 * 1000;
    await this.ctx.storage.setAlarm(nowMs + twentyFourHoursMs);

    return { ok: true, deleted: true };
  }

  /**
   * 24 saat sonra çalışan alarm: tombstone dahil tüm Durable Object verisini temizler.
   */
  async alarm(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }

  /**
   * Kullanıcının profilini döndürür; mevcut değilse varsayılan başlangıç bakiyesiyle oluşturur.
   */
  async getProfile(uid?: string): Promise<UserProfileData> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const cursor = this.ctx.storage.sql.exec<ProfileRow>(
      'SELECT uid, nickname, coins, played, won, lost, created_at FROM profiles LIMIT 1'
    );
    const rows = cursor.toArray();

    if (rows.length > 0) {
      const row = rows[0];
      return {
        uid: row.uid,
        nickname: row.nickname,
        coins: row.coins,
        stats: {
          played: row.played,
          won: row.won,
          lost: row.lost,
        },
        createdAt: row.created_at,
      };
    }

    const effectiveUid = uid && uid.trim().length > 0 ? uid.trim() : 'unknown';
    const startCoins = parseInt(this.env.START_COINS ?? '100', 10);
    const initialCoins = Number.isFinite(startCoins) && startCoins >= 0 ? startCoins : 100;
    const nowMs = Date.now();

    this.ctx.storage.sql.exec(
      `INSERT INTO profiles (uid, nickname, coins, played, won, lost, created_at)
       VALUES (?, NULL, ?, 0, 0, 0, ?)`,
      effectiveUid,
      initialCoins,
      nowMs
    );

    return {
      uid: effectiveUid,
      nickname: null,
      coins: initialCoins,
      stats: { played: 0, won: 0, lost: 0 },
      createdAt: nowMs,
    };
  }

  /**
   * Takma adı sanitize/validate edip kaydeder.
   */
  async setNickname(nickname: string, uid?: string): Promise<{ ok: true; nickname: string }> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const validation = validateNickname(nickname);
    if (!validation.isValid || validation.normalized === null) {
      throw new Error('invalid_nickname');
    }

    const normalized = validation.normalized;

    // Profil yoksa önce oluştur
    await this.getProfile(uid);

    this.ctx.storage.sql.exec(
      'UPDATE profiles SET nickname = ?',
      normalized
    );

    return { ok: true, nickname: normalized };
  }

  /**
   * Maç ödülü uygular. İdempotenttir; aynı matchId için ödül ve istatistik tekrar yazılmaz.
   */
  async applyMatchReward(params: {
    readonly matchId: string;
    readonly outcome: MatchRewardOutcome;
    readonly uid?: string;
  }): Promise<MatchRewardResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    // Profilin varlığını garantiye al
    const profile = await this.getProfile(params.uid);

    // 1. İdempotentlik kontrolü: bu matchId daha önce işlendi mi?
    const existingMatchCursor = this.ctx.storage.sql.exec<ProcessedMatchRow>(
      'SELECT match_id, coins_awarded FROM processed_matches WHERE match_id = ? LIMIT 1',
      params.matchId
    );
    const existingMatches = existingMatchCursor.toArray();

    if (existingMatches.length > 0) {
      return {
        coinsAwarded: existingMatches[0].coins_awarded,
        coins: profile.coins,
        nickname: profile.nickname,
        alreadyProcessed: true,
      };
    }

    // 2. Taban ödülü hesapla
    let baseReward = 0;
    switch (params.outcome) {
      case 'win': {
        const val = parseInt(this.env.WIN_COINS ?? '30', 10);
        baseReward = Number.isFinite(val) && val >= 0 ? val : 30;
        break;
      }
      case 'loss': {
        const val = parseInt(this.env.LOSS_COINS ?? '5', 10);
        baseReward = Number.isFinite(val) && val >= 0 ? val : 5;
        break;
      }
      case 'win_by_opponent_disconnect': {
        const val = parseInt(this.env.DISCONNECT_WIN_COINS ?? '30', 10);
        baseReward = Number.isFinite(val) && val >= 0 ? val : 30;
        break;
      }
      case 'loss_by_disconnect': {
        const val = parseInt(this.env.DISCONNECT_LOSS_COINS ?? '0', 10);
        baseReward = Number.isFinite(val) && val >= 0 ? val : 0;
        break;
      }
    }

    // 3. Günlük üst sınır (Cap) kontrolü: UTC gün
    const dayKey = new Date().toISOString().slice(0, 10);
    const dailyCursor = this.ctx.storage.sql.exec<DailyCoinsRow>(
      'SELECT day_key, earned FROM daily_coins WHERE day_key = ? LIMIT 1',
      dayKey
    );
    const dailyRows = dailyCursor.toArray();
    const currentEarnedToday = dailyRows.length > 0 ? dailyRows[0].earned : 0;

    const capVal = parseInt(this.env.DAILY_MATCH_COIN_CAP ?? '300', 10);
    const dailyCap = Number.isFinite(capVal) && capVal >= 0 ? capVal : 300;
    const remainingCap = Math.max(0, dailyCap - currentEarnedToday);

    const actualCoinsAwarded = Math.max(0, Math.min(baseReward, remainingCap));

    // 4. Günlük kazanç sayacını güncelle
    this.ctx.storage.sql.exec(
      `INSERT INTO daily_coins (day_key, earned) VALUES (?, ?)
       ON CONFLICT(day_key) DO UPDATE SET earned = earned + ?`,
      dayKey,
      actualCoinsAwarded,
      actualCoinsAwarded
    );

    // 5. İstatistikleri ve bakiyeyi güncelle
    const isWin =
      params.outcome === 'win' || params.outcome === 'win_by_opponent_disconnect';
    const isLoss =
      params.outcome === 'loss' || params.outcome === 'loss_by_disconnect';

    this.ctx.storage.sql.exec(
      `UPDATE profiles
       SET coins = coins + ?,
           played = played + 1,
           won = won + ?,
           lost = lost + ?`,
      actualCoinsAwarded,
      isWin ? 1 : 0,
      isLoss ? 1 : 0
    );

    // 6. İşlenen maçı kaydet
    const nowMs = Date.now();
    this.ctx.storage.sql.exec(
      `INSERT INTO processed_matches (match_id, applied_at, outcome, coins_awarded)
       VALUES (?, ?, ?, ?)`,
      params.matchId,
      nowMs,
      params.outcome,
      actualCoinsAwarded
    );

    // Son 100 maçı koruyup daha eskilerini temizle
    this.ctx.storage.sql.exec(`
      DELETE FROM processed_matches
      WHERE match_id NOT IN (
        SELECT match_id FROM processed_matches ORDER BY applied_at DESC LIMIT 100
      )
    `);

    // 7. Güncel bakiyeyi oku
    const updatedProfile = await this.getProfile();
    return {
      coinsAwarded: actualCoinsAwarded,
      coins: updatedProfile.coins,
      nickname: updatedProfile.nickname,
    };
  }

  /**
   * HTTP Fetch arayüzü desteği
   */
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const uid = request.headers.get('X-User-Id') ?? undefined;

    if (request.method === 'DELETE' && (url.pathname === '/profile' || url.pathname === '/me')) {
      const res = await this.deleteProfile(uid);
      return new Response(JSON.stringify(res), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (request.method === 'GET' && url.pathname === '/profile') {
      try {
        const data = await this.getProfile(uid);
        return new Response(JSON.stringify(data), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: { 'Content-Type': 'application/json' } }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    if (request.method === 'PUT' && url.pathname === '/nickname') {
      try {
        const body = (await request.json()) as { nickname?: unknown };
        if (typeof body?.nickname !== 'string') {
          return new Response(JSON.stringify({ error: 'invalid_nickname', message: 'Metin bekleniyor' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
          });
        }
        const res = await this.setNickname(body.nickname, uid);
        return new Response(JSON.stringify(res), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: { 'Content-Type': 'application/json' } }
          );
        }
        return new Response(JSON.stringify({ error: 'invalid_nickname', message: msg }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    if (request.method === 'POST' && url.pathname === '/reward') {
      try {
        const body = (await request.json()) as {
          matchId?: unknown;
          outcome?: unknown;
        };
        if (typeof body?.matchId !== 'string' || typeof body?.outcome !== 'string') {
          return new Response(JSON.stringify({ error: 'bad_request' }), { status: 400 });
        }
        const res = await this.applyMatchReward({
          matchId: body.matchId,
          outcome: body.outcome as MatchRewardOutcome,
          uid,
        });
        return new Response(JSON.stringify(res), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: { 'Content-Type': 'application/json' } }
          );
        }
        return new Response(JSON.stringify({ error: 'reward_error', message: msg }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    return new Response('Not Found', { status: 404 });
  }
}
