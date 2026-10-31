import { DurableObject } from 'cloudflare:workers';
import { validateNickname } from './engine/nicknameValidator';
import {
  FRAME_CATALOG,
  getFrameCatalogItem,
  getMinClientBuildForFrame,
  isValidFrameId,
  RETIRED_FRAME_IDS,
  isFrameRetiredForBuild,
  DEFAULT_RETIRED_FRAMES_BUILD,
  type FrameKind,
  type FrameTier,
} from './frames';
import {
  calculateRegeneratedEnergy,
  getEnergyMax,
  getEnergyRegenMinutes,
  getEnergyCostPerMatch,
  getEnergyPackOneCost,
  getEnergyPackFullCost,
  buildEnergyPacks,
  isEnergyEnabledForUser,
  type EnergyState,
  type EnergyPack,
} from './energy';
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
  readonly correctAnswers: number;
}

export interface FrameMigrationResult {
  readonly refundedCoins: number;
  readonly removedFrames: readonly string[];
}

export interface UserProfileData {
  readonly uid: string;
  readonly nickname: string | null;
  readonly coins: number;
  readonly stats: UserStats;
  readonly createdAt: number;
  readonly equippedFrame: string;
  readonly frameMigration?: FrameMigrationResult;
}

export interface MatchRewardResult {
  readonly coinsAwarded: number;
  readonly coins: number;
  readonly nickname?: string | null;
  readonly alreadyProcessed?: boolean;
}

export interface SpendCoinsResult {
  readonly success: boolean;
  readonly coins: number;
  readonly alreadySpent?: boolean;
  readonly error?: 'not_enough_coins' | 'account_deleted';
}

export interface RefundPowerupResult {
  readonly ok: true;
  readonly refunded: boolean;
  readonly coins: number;
}

export interface StoreCatalogItem {
  readonly id: string;
  readonly name: string;
  readonly cost: number;
  readonly price?: number;
  readonly description: string;
  readonly order: number;
  readonly isOwned: boolean;
  readonly owned?: boolean;
  readonly isEquipped: boolean;
  readonly kind?: FrameKind;
  readonly tier?: FrameTier;
}

export interface StoreStateResult {
  readonly coins: number;
  readonly equippedFrame: string;
  readonly items: readonly StoreCatalogItem[];
}

export type PurchaseItemResult =
  | { readonly success: true; readonly itemId: string; readonly coins: number }
  | {
      readonly success: false;
      readonly error:
        | 'not_enough_coins'
        | 'already_owned'
        | 'invalid_item'
        | 'unsupported_client_version'
        | 'item_retired';
      readonly coins?: number;
    };

export type EquipFrameResult =
  | { readonly success: true; readonly equippedFrame: string }
  | { readonly success: false; readonly error: 'item_not_owned' | 'invalid_frame' | 'item_retired' };

export interface SpendEnergyResult {
  readonly success: boolean;
  readonly energy: number;
  readonly max?: number;
  readonly nextEnergyAtMs?: number | null;
  readonly alreadySpent?: boolean;
  readonly error?: 'not_enough_energy' | 'account_deleted';
}

export interface RefundEnergyResult {
  readonly ok: true;
  readonly refunded: boolean;
  readonly energy: number;
}

export type PurchaseEnergyResult =
  | {
      readonly success: true;
      readonly pack: 'one' | 'full';
      readonly coins: number;
      readonly energy: number;
      readonly max: number;
      readonly nextEnergyAtMs: number | null;
      readonly serverNowMs: number;
    }
  | {
      readonly success: false;
      readonly error: 'not_enough_coins' | 'energy_full' | 'energy_disabled' | 'invalid_pack';
      readonly coins?: number;
      readonly energy?: number;
    };

export type AdminGrantResult =
  | { readonly success: true; readonly coins: number; readonly grantedFrames: readonly string[]; readonly energy?: number }
  | { readonly success: false; readonly error: 'account_deleted' | string };

interface ProfileRow extends Record<string, string | number | null> {
  uid: string;
  nickname: string | null;
  coins: number;
  played: number;
  won: number;
  lost: number;
  correct_answers: number;
  created_at: number;
  equipped_frame: string | null;
  energy: number | null;
  energy_updated_at: number | null;
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

interface BlockedUserRow extends Record<string, string | number | null> {
  id: string;
  blocked_uid: string;
  blocked_nickname: string;
  blocked_at: number;
}

interface CountRow extends Record<string, string | number | null> {
  cnt: number;
}

interface PowerupPurchaseRow extends Record<string, string | number | null> {
  match_id: string;
  powerup: string;
  amount: number;
  created_at: number;
}

export interface BlockedUserItem {
  readonly id: string;
  readonly nickname: string;
  readonly blockedAt: number;
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

      CREATE TABLE IF NOT EXISTS blocked_users (
        id TEXT PRIMARY KEY,
        blocked_uid TEXT UNIQUE NOT NULL,
        blocked_nickname TEXT NOT NULL,
        blocked_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS powerup_purchases (
        match_id TEXT NOT NULL,
        powerup TEXT NOT NULL,
        amount INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (match_id, powerup)
      );

      CREATE TABLE IF NOT EXISTS owned_items (
        item_id TEXT PRIMARY KEY,
        purchased_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS energy_spends (
        match_id TEXT NOT NULL,
        uid TEXT NOT NULL,
        amount INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        refunded_at INTEGER,
        PRIMARY KEY (match_id, uid)
      );

      CREATE TABLE IF NOT EXISTS energy_purchases (
        id TEXT PRIMARY KEY,
        uid TEXT NOT NULL,
        pack TEXT NOT NULL,
        amount INTEGER NOT NULL,
        cost INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      );
    `);

    // PRAGMA ile equipped_frame sütununun varlığı kontrol edilir, yoksa ALTER çalıştırılır
    const profileCols = this.ctx.storage.sql
      .exec<{ name: string }>('PRAGMA table_info(profiles)')
      .toArray();
    const hasEquippedFrame = profileCols.some((c) => c.name === 'equipped_frame');
    if (!hasEquippedFrame) {
      this.ctx.storage.sql.exec(
        "ALTER TABLE profiles ADD COLUMN equipped_frame TEXT NOT NULL DEFAULT 'classic'"
      );
    }

    const hasEnergy = profileCols.some((c) => c.name === 'energy');
    if (!hasEnergy) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN energy INTEGER NOT NULL DEFAULT 5'
      );
    }

    const hasEnergyUpdatedAt = profileCols.some((c) => c.name === 'energy_updated_at');
    if (!hasEnergyUpdatedAt) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN energy_updated_at INTEGER NOT NULL DEFAULT 0'
      );
    }

    const hasCorrectAnswers = profileCols.some((c) => c.name === 'correct_answers');
    if (!hasCorrectAnswers) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN correct_answers INTEGER NOT NULL DEFAULT 0'
      );
    }

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
      DELETE FROM blocked_users;
      DELETE FROM powerup_purchases;
      DELETE FROM owned_items;
      DELETE FROM energy_spends;
      DELETE FROM energy_purchases;
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
   * Emekli çerçevelerin iadeli geçişi (build >= 11 için).
   * Kullanıcı bu emekli çerçevelerden birine sahipse veya kuşanmışsa:
   * 1. owned_items tablosundan silinir.
   * 2. Orijinal maliyetleri jeton olarak bakiye eklenir (günlük kazanç tavanını etkilemez).
   * 3. Kuşanılan çerçeve emeklilerden biriyse 'classic' yapılır ve Leaderboard güncellenir.
   * 4. Idempotent: İkinci çağrıda silinecek kayıt olmayacağı için iade yapılmaz.
   */
  async migrateRetiredFrames(
    uid?: string,
    clientBuild = 0
  ): Promise<FrameMigrationResult | null> {
    const minRetiredBuild = parseInt(
      this.env.RETIRED_FRAMES_BUILD ?? String(DEFAULT_RETIRED_FRAMES_BUILD),
      10
    );
    const effectiveThreshold =
      Number.isFinite(minRetiredBuild) && minRetiredBuild >= 0
        ? minRetiredBuild
        : DEFAULT_RETIRED_FRAMES_BUILD;

    if (clientBuild < effectiveThreshold) {
      return null;
    }

    const retiredIds = RETIRED_FRAME_IDS;
    const placeholders = retiredIds.map(() => '?').join(',');

    // Ucuz kontrol: kullanıcının owned_items tablosunda emekli çerçeve var mı?
    const ownedRetired = this.ctx.storage.sql
      .exec<{ item_id: string }>(
        `SELECT item_id FROM owned_items WHERE item_id IN (${placeholders})`,
        ...retiredIds
      )
      .toArray();

    // Kuşanılan çerçeve emekli mi?
    const profileRows = this.ctx.storage.sql
      .exec<{ equipped_frame: string | null }>(
        'SELECT equipped_frame FROM profiles LIMIT 1'
      )
      .toArray();
    const currentEquipped = profileRows.length > 0 ? profileRows[0].equipped_frame : null;
    const isEquippedRetired = currentEquipped ? retiredIds.includes(currentEquipped) : false;

    // Emekli çerçeveye sahip değilse ve kuşanmamışsa hiçbir işlem yapma
    if (ownedRetired.length === 0 && !isEquippedRetired) {
      return null;
    }

    // Atomik geçiş işlemi
    const migrationResult = this.ctx.storage.transactionSync(() => {
      // 1. Transaction içinde güncel listeyi al
      const itemsToRefund = this.ctx.storage.sql
        .exec<{ item_id: string }>(
          `SELECT item_id FROM owned_items WHERE item_id IN (${placeholders})`,
          ...retiredIds
        )
        .toArray();

      let totalRefund = 0;
      const removedFrames: string[] = [];

      for (const row of itemsToRefund) {
        const itemDef = getFrameCatalogItem(row.item_id);
        const cost = itemDef?.cost ?? 0;
        totalRefund += cost;
        removedFrames.push(row.item_id);
      }

      // 2. owned_items tablosundan emeklileri sil
      if (itemsToRefund.length > 0) {
        this.ctx.storage.sql.exec(
          `DELETE FROM owned_items WHERE item_id IN (${placeholders})`,
          ...retiredIds
        );
      }

      // 3. Jetonları ekle (günlük kazanç tavanını etkilemez, direkt profiles.coins artar)
      if (totalRefund > 0) {
        this.ctx.storage.sql.exec(
          'UPDATE profiles SET coins = coins + ?',
          totalRefund
        );
      }

      // 4. Kuşanılan çerçeve kontrolü
      const pRows = this.ctx.storage.sql
        .exec<{ equipped_frame: string | null }>(
          'SELECT equipped_frame FROM profiles LIMIT 1'
        )
        .toArray();
      const equipped = pRows.length > 0 ? pRows[0].equipped_frame : null;
      let resetEquipped = false;
      if (equipped && retiredIds.includes(equipped)) {
        this.ctx.storage.sql.exec(
          "UPDATE profiles SET equipped_frame = 'classic'"
        );
        resetEquipped = true;
      }

      return {
        totalRefund,
        removedFrames,
        resetEquipped,
      };
    });

    // 5. Kuşanılan çerçeve 'classic' olduysa haftalık sıralamayı (Leaderboard) güncelle
    if (migrationResult.resetEquipped && this.env.LEADERBOARD) {
      const effectiveUid =
        uid && uid.trim().length > 0
          ? uid.trim()
          : (this.ctx.storage.sql
              .exec<{ uid: string }>('SELECT uid FROM profiles LIMIT 1')
              .toArray()[0]?.uid ?? 'unknown');
      try {
        const leaderboardStub = this.env.LEADERBOARD.get(
          this.env.LEADERBOARD.idFromName('global')
        );
        await leaderboardStub.updateFrame(effectiveUid, 'classic');
      } catch (lbErr) {
        console.error('Leaderboard updateFrame during frame migration failed:', lbErr);
      }
    }

    if (migrationResult.removedFrames.length > 0 || migrationResult.resetEquipped) {
      return {
        refundedCoins: migrationResult.totalRefund,
        removedFrames: migrationResult.removedFrames,
      };
    }

    return null;
  }

  /**
   * Kullanıcının profilini döndürür; mevcut değilse varsayılan başlangıç bakiyesiyle oluşturur.
   */
  async getProfile(uid?: string, clientBuild = 0): Promise<UserProfileData> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    let frameMigration: FrameMigrationResult | undefined;
    if (clientBuild > 0) {
      const res = await this.migrateRetiredFrames(uid, clientBuild);
      if (res) {
        frameMigration = res;
      }
    }

    const cursor = this.ctx.storage.sql.exec<ProfileRow>(
      'SELECT uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame FROM profiles LIMIT 1'
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
          correctAnswers: row.correct_answers ?? 0,
        },
        createdAt: row.created_at,
        equippedFrame: (row.equipped_frame as string) || 'classic',
        ...(frameMigration ? { frameMigration } : {}),
      };
    }

    const effectiveUid = uid && uid.trim().length > 0 ? uid.trim() : 'unknown';
    const startCoins = parseInt(this.env.START_COINS ?? '100', 10);
    const initialCoins = Number.isFinite(startCoins) && startCoins >= 0 ? startCoins : 100;
    const nowMs = Date.now();
    const maxEnergy = getEnergyMax(this.env);

    this.ctx.storage.sql.exec(
      `INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, energy, energy_updated_at)
       VALUES (?, NULL, ?, 0, 0, 0, 0, ?, 'classic', ?, 0)`,
      effectiveUid,
      initialCoins,
      nowMs,
      maxEnergy
    );

    return {
      uid: effectiveUid,
      nickname: null,
      coins: initialCoins,
      stats: { played: 0, won: 0, lost: 0, correctAnswers: 0 },
      createdAt: nowMs,
      equippedFrame: 'classic',
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
    readonly correctAnswers?: number;
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
    const correctCount = Math.max(0, params.correctAnswers ?? 0);

    this.ctx.storage.sql.exec(
      `UPDATE profiles
       SET coins = coins + ?,
           played = played + 1,
           won = won + ?,
           lost = lost + ?,
           correct_answers = correct_answers + ?`,
      actualCoinsAwarded,
      isWin ? 1 : 0,
      isLoss ? 1 : 0,
      correctCount
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
   * Güçlendirici harcamasını tek bir SQLite transaction içinde atomik ve idempotent olarak uygular.
   * Aynı (match_id, powerup) için tekrar jeton düşülmez.
   * Günlük maç ödülü limitini (daily_coins) etkilemez.
   * 7 günden eski powerup_purchases kayıtlarını fırsatçı temizler.
   */
  async spendCoins(params: {
    readonly matchId: string;
    readonly powerup: string;
    readonly amount: number;
    readonly uid?: string;
  }): Promise<SpendCoinsResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return { success: false, error: 'account_deleted', coins: 0 };
    }

    // Profilin varlığını garantiye al
    await this.getProfile(params.uid);

    const nowMs = Date.now();

    // 7 günden eski powerup kayıtlarını fırsatçı temizle
    const sevenDaysAgoMs = nowMs - 7 * 24 * 60 * 60 * 1000;
    this.ctx.storage.sql.exec(
      'DELETE FROM powerup_purchases WHERE created_at < ?',
      sevenDaysAgoMs
    );

    // ctx.storage.transactionSync ile tek SQLite transaction içinde atomik kontrol + bakiye düşme + kayıt ekleme
    return this.ctx.storage.transactionSync(() => {
      // 1. İdempotentlik kontrolü: bu (match_id, powerup) zaten satın alındı mı?
      const existingCursor = this.ctx.storage.sql.exec<PowerupPurchaseRow>(
        'SELECT match_id, amount FROM powerup_purchases WHERE match_id = ? AND powerup = ? LIMIT 1',
        params.matchId,
        params.powerup
      );
      const existing = existingCursor.toArray();

      const profileRows = this.ctx.storage.sql.exec<ProfileRow>(
        'SELECT coins FROM profiles LIMIT 1'
      ).toArray();
      const currentCoins = profileRows.length > 0 ? profileRows[0].coins : 0;

      if (existing.length > 0) {
        return {
          success: true,
          coins: currentCoins,
          alreadySpent: true,
        };
      }

      // 2. Bakiye kontrolü
      if (currentCoins < params.amount) {
        return {
          success: false,
          error: 'not_enough_coins',
          coins: currentCoins,
        };
      }

      // 3. Atomik düşme (coins >= amount ile çift koruma)
      this.ctx.storage.sql.exec(
        'UPDATE profiles SET coins = coins - ? WHERE coins >= ?',
        params.amount,
        params.amount
      );

      // 4. powerup_purchases tablosuna kayıt
      this.ctx.storage.sql.exec(
        'INSERT INTO powerup_purchases (match_id, powerup, amount, created_at) VALUES (?, ?, ?, ?)',
        params.matchId,
        params.powerup,
        params.amount,
        nowMs
      );

      return {
        success: true,
        coins: currentCoins - params.amount,
      };
    });
  }

  /**
   * Yarış durumunda güçlendirici kullanılamadıysa jeton iadesi yapar.
   * İdempotenttir; kayıt zaten silinmişse tekrar iade yapmaz.
   */
  async refundPowerup(params: {
    readonly matchId: string;
    readonly powerup: string;
    readonly amount: number;
    readonly uid?: string;
  }): Promise<RefundPowerupResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return { ok: true, refunded: false, coins: 0 };
    }

    return this.ctx.storage.transactionSync(() => {
      const existing = this.ctx.storage.sql.exec<PowerupPurchaseRow>(
        'SELECT amount FROM powerup_purchases WHERE match_id = ? AND powerup = ? LIMIT 1',
        params.matchId,
        params.powerup
      ).toArray();

      if (existing.length === 0) {
        const profileRows = this.ctx.storage.sql.exec<ProfileRow>(
          'SELECT coins FROM profiles LIMIT 1'
        ).toArray();
        const currentCoins = profileRows.length > 0 ? profileRows[0].coins : 0;
        return { ok: true, refunded: false, coins: currentCoins };
      }

      const refundAmount = existing[0].amount ?? params.amount;

      this.ctx.storage.sql.exec(
        'DELETE FROM powerup_purchases WHERE match_id = ? AND powerup = ?',
        params.matchId,
        params.powerup
      );

      this.ctx.storage.sql.exec(
        'UPDATE profiles SET coins = coins + ?',
        refundAmount
      );

      const profileRows = this.ctx.storage.sql.exec<ProfileRow>(
        'SELECT coins FROM profiles LIMIT 1'
      ).toArray();
      const currentCoins = profileRows.length > 0 ? profileRows[0].coins : 0;

      return { ok: true, refunded: true, coins: currentCoins };
    });
  }

  /**
   * Bir oyuncuyu engeller. Üst sınır kontrol edilir (varsayılan 100).
   * Engellenen oyuncu için opak bir ID (UUID) üretilerek kaydedilir.
   */
  async blockUser(params: {
    readonly blockedUid: string;
    readonly blockedNickname: string;
    readonly uid?: string;
  }): Promise<{ ok: true; id: string } | { ok: false; error: 'block_limit_reached' }> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    // Profil yoksa önce oluştur
    await this.getProfile(params.uid);

    // Zaten engelliyse mevcut kaydın ID'sini döndür
    const existing = this.ctx.storage.sql.exec<BlockedUserRow>(
      'SELECT id FROM blocked_users WHERE blocked_uid = ? LIMIT 1',
      params.blockedUid
    ).toArray();

    if (existing.length > 0) {
      return { ok: true, id: existing[0].id };
    }

    // Üst sınır kontrolü (100)
    const maxBlocks = parseInt(this.env.MAX_BLOCKS_PER_USER ?? '100', 10);
    const limit = Number.isFinite(maxBlocks) && maxBlocks > 0 ? maxBlocks : 100;

    const countRes = this.ctx.storage.sql.exec<CountRow>(
      'SELECT COUNT(*) as cnt FROM blocked_users'
    ).toArray();
    const count = countRes.length > 0 ? Number(countRes[0].cnt) : 0;

    if (count >= limit) {
      return { ok: false, error: 'block_limit_reached' };
    }

    const opaqueId = crypto.randomUUID();
    const nowMs = Date.now();

    this.ctx.storage.sql.exec(
      'INSERT INTO blocked_users (id, blocked_uid, blocked_nickname, blocked_at) VALUES (?, ?, ?, ?)',
      opaqueId,
      params.blockedUid,
      params.blockedNickname,
      nowMs
    );

    return { ok: true, id: opaqueId };
  }

  /**
   * Opak kimlik (UUID) ile engeli kaldırır.
   */
  async unblockUser(id: string): Promise<{ ok: true }> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    this.ctx.storage.sql.exec(
      'DELETE FROM blocked_users WHERE id = ?',
      id
    );

    return { ok: true };
  }

  /**
   * Kullanıcının engellediği oyuncuları istemciye sunmak üzere döndürür.
   * GÜVENLİK / GİZLİLİK: Engellenen oyuncunun gerçek UID'si ASLA döndürülmez.
   */
  async getBlockedUsers(): Promise<BlockedUserItem[]> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const rows = this.ctx.storage.sql.exec<BlockedUserRow>(
      'SELECT id, blocked_nickname, blocked_at FROM blocked_users ORDER BY blocked_at DESC'
    ).toArray();

    return rows.map((r) => ({
      id: r.id,
      nickname: r.blocked_nickname,
      blockedAt: Number(r.blocked_at),
    }));
  }

  /**
   * Matchmaker tarafından dahili kullanım için engellenen UID listesini döndürür.
   */
  async getBlockedUids(): Promise<string[]> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return [];
    }

    const rows = this.ctx.storage.sql.exec<BlockedUserRow>(
      'SELECT blocked_uid FROM blocked_users'
    ).toArray();

    return rows.map((r) => r.blocked_uid);
  }

  /**
   * Mağaza durumunu döndürür: güncel bakiye, kuşanılan çerçeve ve tüm katalog ürünlerinin
   * sahiplik/kuşanılma durumu.
   */
  async getStoreState(uid?: string, clientBuild = 0): Promise<StoreStateResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const profile = await this.getProfile(uid, clientBuild);

    const ownedRows = this.ctx.storage.sql
      .exec<{ item_id: string }>('SELECT item_id FROM owned_items')
      .toArray();
    const ownedSet = new Set(ownedRows.map((r) => r.item_id));
    ownedSet.add('classic'); // 'classic' her zaman ücretsiz ve sahiplenilmiştir

    const visibleCatalog = FRAME_CATALOG.filter((item) => {
      const minBuild = getMinClientBuildForFrame(item, this.env as any);
      if (minBuild > clientBuild) return false;
      if (isFrameRetiredForBuild(item, clientBuild, this.env as any)) return false;
      return true;
    });

    const items: StoreCatalogItem[] = visibleCatalog.map((item) => ({
      id: item.id,
      name: item.name,
      cost: item.cost,
      price: item.cost,
      description: item.description,
      order: item.order,
      isOwned: ownedSet.has(item.id),
      owned: ownedSet.has(item.id),
      isEquipped: profile.equippedFrame === item.id,
      kind: item.kind,
      ...(item.tier ? { tier: item.tier } : {}),
    }));

    return {
      coins: profile.coins,
      equippedFrame: profile.equippedFrame,
      items,
    };
  }

  /**
   * Jetonla bir avatar çerçevesi satın alır.
   * DO SQLite depolama kuralı: BEGIN/COMMIT yasak; ctx.storage.transactionSync kullanılır.
   * Atomik olarak:
   * 1. Ürün ve sahiplik kontrolü
   * 2. Bakiye kontrolü
   * 3. Bakiye düşme + owned_items tablosuna ekleme
   */
  async purchaseItem(
    itemId: string,
    uid?: string,
    clientBuild = 0
  ): Promise<PurchaseItemResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const catalogItem = getFrameCatalogItem(itemId);
    if (!catalogItem) {
      return { success: false, error: 'invalid_item' };
    }

    if (isFrameRetiredForBuild(catalogItem, clientBuild, this.env as any)) {
      return { success: false, error: 'item_retired' };
    }

    const minBuild = getMinClientBuildForFrame(catalogItem, this.env as any);
    if (minBuild > clientBuild) {
      return { success: false, error: 'unsupported_client_version' };
    }

    if (catalogItem.id === 'classic') {
      return { success: false, error: 'already_owned' };
    }

    await this.getProfile(uid);

    return this.ctx.storage.transactionSync(() => {
      // 1. Mükerrer alım kontrolü
      const existing = this.ctx.storage.sql
        .exec<{ item_id: string }>(
          'SELECT item_id FROM owned_items WHERE item_id = ? LIMIT 1',
          itemId
        )
        .toArray();
      if (existing.length > 0) {
        return { success: false, error: 'already_owned' as const };
      }

      // 2. Bakiye kontrolü
      const profileRows = this.ctx.storage.sql
        .exec<{ coins: number }>('SELECT coins FROM profiles LIMIT 1')
        .toArray();
      const currentCoins = profileRows.length > 0 ? profileRows[0].coins : 0;
      if (currentCoins < catalogItem.cost) {
        return {
          success: false,
          error: 'not_enough_coins' as const,
          coins: currentCoins,
        };
      }

      // 3. Bakiye düş ve sahiplik kaydet
      this.ctx.storage.sql.exec(
        'UPDATE profiles SET coins = coins - ? WHERE coins >= ?',
        catalogItem.cost,
        catalogItem.cost
      );

      this.ctx.storage.sql.exec(
        'INSERT INTO owned_items (item_id, purchased_at) VALUES (?, ?)',
        itemId,
        Date.now()
      );

      const updatedRows = this.ctx.storage.sql
        .exec<{ coins: number }>('SELECT coins FROM profiles LIMIT 1')
        .toArray();
      const finalCoins =
        updatedRows.length > 0 ? updatedRows[0].coins : currentCoins - catalogItem.cost;

      return {
        success: true as const,
        itemId,
        coins: finalCoins,
      };
    });
  }

  /**
   * Oyuncunun avatar çerçevesini kuşandırır.
   * Klasik çerçeve her zaman kuşanılabilir; diğerleri için owned_items sahiplik doğrulaması yapılır.
   */
  async equipFrame(
    frameId: string,
    uid?: string,
    clientBuild = 0
  ): Promise<EquipFrameResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const normalizedFrameId = typeof frameId === 'string' ? frameId.trim().toLowerCase() : '';

    if (!isValidFrameId(normalizedFrameId)) {
      return { success: false, error: 'invalid_frame' };
    }

    const catalogItem = getFrameCatalogItem(normalizedFrameId);
    if (catalogItem && isFrameRetiredForBuild(catalogItem, clientBuild, this.env as any)) {
      return { success: false, error: 'item_retired' };
    }

    if (normalizedFrameId !== 'classic') {
      const owned = this.ctx.storage.sql
        .exec<{ item_id: string }>(
          'SELECT item_id FROM owned_items WHERE item_id = ? LIMIT 1',
          normalizedFrameId
        )
        .toArray();
      if (owned.length === 0) {
        return { success: false, error: 'item_not_owned' };
      }
    }

    await this.getProfile(uid, clientBuild);

    this.ctx.storage.sql.exec(
      'UPDATE profiles SET equipped_frame = ?',
      normalizedFrameId
    );

    return {
      success: true,
      equippedFrame: normalizedFrameId,
    };
  }

  /**
   * Kullanıcının güncel enerji durumunu hesaplar ve döndürür.
   * Tembel (lazy) yenilenme hesabı ile zaman geçişinde kazanılan enerjiyi veritabanına yansıtır.
   */
  async getEnergyState(uid?: string, nowMs = Date.now()): Promise<EnergyState> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const profile = await this.getProfile(uid);
    const effectiveUid = profile.uid;
    const enabled = isEnergyEnabledForUser(this.env, effectiveUid);

    const maxEnergy = getEnergyMax(this.env);
    const regenMinutes = getEnergyRegenMinutes(this.env);

    const rows = this.ctx.storage.sql
      .exec<{ energy?: number; energy_updated_at?: number }>(
        'SELECT energy, energy_updated_at FROM profiles LIMIT 1'
      )
      .toArray();

    const savedEnergy =
      rows.length > 0 && rows[0].energy !== undefined && rows[0].energy !== null
        ? Number(rows[0].energy)
        : maxEnergy;
    const savedUpdatedAt =
      rows.length > 0 &&
      rows[0].energy_updated_at !== undefined &&
      rows[0].energy_updated_at !== null
        ? Number(rows[0].energy_updated_at)
        : 0;

    const regen = calculateRegeneratedEnergy(
      savedEnergy,
      savedUpdatedAt,
      nowMs,
      maxEnergy,
      regenMinutes
    );

    if (regen.gained > 0) {
      this.ctx.storage.sql.exec(
        'UPDATE profiles SET energy = ?, energy_updated_at = ?',
        regen.current,
        regen.updatedAtMs
      );
    }

    if (!enabled) {
      return {
        enabled: false,
        current: maxEnergy,
        max: maxEnergy,
        nextEnergyAtMs: null,
        regenSeconds: regenMinutes * 60,
        packs: [],
      };
    }

    return {
      enabled: true,
      current: regen.current,
      max: maxEnergy,
      nextEnergyAtMs: regen.nextEnergyAtMs,
      regenSeconds: regenMinutes * 60,
      packs: buildEnergyPacks(this.env),
    };
  }

  /**
   * Hızlı maç başlangıcında enerji harcamasını atomik ve idempotent olarak uygular.
   * Kural: Enerji tam iken (max) ilk harcamada yenilenme sayacı harcama anına (nowMs) ayarlanır.
   */
  async spendEnergy(params: {
    readonly matchId: string;
    readonly amount?: number;
    readonly uid?: string;
    readonly nowMs?: number;
  }): Promise<SpendEnergyResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return { success: false, error: 'account_deleted', energy: 0 };
    }

    const profile = await this.getProfile(params.uid);
    const effectiveUid = profile.uid;
    const nowMs = params.nowMs ?? Date.now();
    const cost = params.amount ?? getEnergyCostPerMatch(this.env);

    return this.ctx.storage.transactionSync(() => {
      // 1. İdempotentlik kontrolü: bu maç için zaten enerji düşüldü mü?
      const existing = this.ctx.storage.sql
        .exec<{ match_id: string; amount: number }>(
          'SELECT match_id, amount FROM energy_spends WHERE match_id = ? AND uid = ? LIMIT 1',
          params.matchId,
          effectiveUid
        )
        .toArray();

      const maxEnergy = getEnergyMax(this.env);
      const regenMinutes = getEnergyRegenMinutes(this.env);

      const rows = this.ctx.storage.sql
        .exec<{ energy?: number; energy_updated_at?: number }>(
          'SELECT energy, energy_updated_at FROM profiles LIMIT 1'
        )
        .toArray();

      const savedEnergy =
        rows.length > 0 && rows[0].energy !== undefined && rows[0].energy !== null
          ? Number(rows[0].energy)
          : maxEnergy;
      const savedUpdatedAt =
        rows.length > 0 &&
        rows[0].energy_updated_at !== undefined &&
        rows[0].energy_updated_at !== null
          ? Number(rows[0].energy_updated_at)
          : 0;

      const regen = calculateRegeneratedEnergy(
        savedEnergy,
        savedUpdatedAt,
        nowMs,
        maxEnergy,
        regenMinutes
      );

      if (existing.length > 0) {
        return {
          success: true,
          alreadySpent: true,
          energy: regen.current,
          max: maxEnergy,
          nextEnergyAtMs: regen.current < maxEnergy ? regen.nextEnergyAtMs : null,
        };
      }

      // 2. Yeterli enerji var mı?
      if (regen.current < cost) {
        return {
          success: false,
          error: 'not_enough_energy',
          energy: regen.current,
          max: maxEnergy,
          nextEnergyAtMs: regen.nextEnergyAtMs,
        };
      }

      // 3. Enerji düşme & yenilenme zaman damgası belirleme:
      // KURAL: Eğer mevcut enerji tam enerji (max) idiyse veya tam dolduysa, sayaç harcama anına (nowMs) ayarlanır.
      // Eğer enerji zaten tamın altındaysa ve yenilenme döngüsü sürüyorsa, döngü ankeri (regen.updatedAtMs) korunur.
      const newEnergy = regen.current - cost;
      const newUpdatedAtMs = regen.current >= maxEnergy ? nowMs : regen.updatedAtMs;

      this.ctx.storage.sql.exec(
        'UPDATE profiles SET energy = ?, energy_updated_at = ?',
        newEnergy,
        newUpdatedAtMs
      );

      this.ctx.storage.sql.exec(
        'INSERT INTO energy_spends (match_id, uid, amount, created_at) VALUES (?, ?, ?, ?)',
        params.matchId,
        effectiveUid,
        cost,
        nowMs
      );

      const nextEnergyAtMs =
        newEnergy < maxEnergy ? newUpdatedAtMs + regenMinutes * 60 * 1000 : null;

      return {
        success: true,
        energy: newEnergy,
        max: maxEnergy,
        nextEnergyAtMs,
      };
    });
  }

  /**
   * İptal veya eşleşme hatasında enerjiyi idempotent olarak iade eder.
   */
  async refundEnergy(params: {
    readonly matchId: string;
    readonly amount?: number;
    readonly uid?: string;
    readonly nowMs?: number;
  }): Promise<RefundEnergyResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return { ok: true, refunded: false, energy: 0 };
    }

    const profile = await this.getProfile(params.uid);
    const effectiveUid = profile.uid;
    const nowMs = params.nowMs ?? Date.now();

    return this.ctx.storage.transactionSync(() => {
      const existing = this.ctx.storage.sql
        .exec<{ amount: number; refunded_at: number | null }>(
          'SELECT amount, refunded_at FROM energy_spends WHERE match_id = ? AND uid = ? LIMIT 1',
          params.matchId,
          effectiveUid
        )
        .toArray();

      const maxEnergy = getEnergyMax(this.env);
      const regenMinutes = getEnergyRegenMinutes(this.env);

      const rows = this.ctx.storage.sql
        .exec<{ energy?: number; energy_updated_at?: number }>(
          'SELECT energy, energy_updated_at FROM profiles LIMIT 1'
        )
        .toArray();

      const savedEnergy =
        rows.length > 0 && rows[0].energy !== undefined && rows[0].energy !== null
          ? Number(rows[0].energy)
          : maxEnergy;
      const savedUpdatedAt =
        rows.length > 0 &&
        rows[0].energy_updated_at !== undefined &&
        rows[0].energy_updated_at !== null
          ? Number(rows[0].energy_updated_at)
          : 0;

      const regen = calculateRegeneratedEnergy(
        savedEnergy,
        savedUpdatedAt,
        nowMs,
        maxEnergy,
        regenMinutes
      );

      if (existing.length === 0 || existing[0].refunded_at !== null) {
        return { ok: true, refunded: false, energy: regen.current };
      }

      const refundAmount = existing[0].amount ?? params.amount ?? 1;

      this.ctx.storage.sql.exec(
        'UPDATE energy_spends SET refunded_at = ? WHERE match_id = ? AND uid = ?',
        nowMs,
        params.matchId,
        effectiveUid
      );

      const newEnergy = Math.min(maxEnergy, regen.current + refundAmount);
      const newUpdatedAtMs = newEnergy >= maxEnergy ? nowMs : regen.updatedAtMs;

      this.ctx.storage.sql.exec(
        'UPDATE profiles SET energy = ?, energy_updated_at = ?',
        newEnergy,
        newUpdatedAtMs
      );

      return {
        ok: true,
        refunded: true,
        energy: newEnergy,
      };
    });
  }

  /**
   * Jetonla enerji paketi satın alır.
   * Atomik olarak jeton düşer ve enerjiyi günceller.
   */
  async purchaseEnergy(params: {
    readonly pack: 'one' | 'full';
    readonly uid?: string;
    readonly nowMs?: number;
  }): Promise<PurchaseEnergyResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const profile = await this.getProfile(params.uid);
    const effectiveUid = profile.uid;
    const nowMs = params.nowMs ?? Date.now();

    if (!isEnergyEnabledForUser(this.env, effectiveUid)) {
      return { success: false, error: 'energy_disabled' };
    }

    if (params.pack !== 'one' && params.pack !== 'full') {
      return { success: false, error: 'invalid_pack' };
    }

    const maxEnergy = getEnergyMax(this.env);
    const regenMinutes = getEnergyRegenMinutes(this.env);

    return this.ctx.storage.transactionSync(() => {
      const rows = this.ctx.storage.sql
        .exec<{ coins: number; energy: number; energy_updated_at: number }>(
          'SELECT coins, energy, energy_updated_at FROM profiles LIMIT 1'
        )
        .toArray();

      const currentCoins = rows.length > 0 ? rows[0].coins : 0;
      const savedEnergy =
        rows.length > 0 && rows[0].energy !== undefined && rows[0].energy !== null
          ? Number(rows[0].energy)
          : maxEnergy;
      const savedUpdatedAt =
        rows.length > 0 &&
        rows[0].energy_updated_at !== undefined &&
        rows[0].energy_updated_at !== null
          ? Number(rows[0].energy_updated_at)
          : 0;

      const regen = calculateRegeneratedEnergy(
        savedEnergy,
        savedUpdatedAt,
        nowMs,
        maxEnergy,
        regenMinutes
      );

      if (regen.current >= maxEnergy) {
        return {
          success: false,
          error: 'energy_full',
          energy: regen.current,
        };
      }

      const cost =
        params.pack === 'one'
          ? getEnergyPackOneCost(this.env)
          : getEnergyPackFullCost(this.env);

      if (currentCoins < cost) {
        return {
          success: false,
          error: 'not_enough_coins',
          coins: currentCoins,
          energy: regen.current,
        };
      }

      const energyToAdd =
        params.pack === 'one' ? 1 : maxEnergy - regen.current;

      const newEnergy = Math.min(maxEnergy, regen.current + energyToAdd);
      const newUpdatedAtMs = newEnergy >= maxEnergy ? nowMs : regen.updatedAtMs;

      this.ctx.storage.sql.exec(
        'UPDATE profiles SET coins = coins - ?, energy = ?, energy_updated_at = ? WHERE coins >= ?',
        cost,
        newEnergy,
        newUpdatedAtMs,
        cost
      );

      const purchaseId = crypto.randomUUID();
      this.ctx.storage.sql.exec(
        'INSERT INTO energy_purchases (id, uid, pack, amount, cost, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        purchaseId,
        effectiveUid,
        params.pack,
        energyToAdd,
        cost,
        nowMs
      );

      const nextEnergyAtMs =
        newEnergy >= maxEnergy ? null : newUpdatedAtMs + regenMinutes * 60 * 1000;

      return {
        success: true,
        pack: params.pack,
        coins: currentCoins - cost,
        energy: newEnergy,
        max: maxEnergy,
        nextEnergyAtMs,
        serverNowMs: nowMs,
      };
    });
  }

  /**
   * Yönetici tarafından kullanıcıya jeton, çerçeve ve/veya enerji tanımlar.
   * Atomik (transactionSync), idempotent (INSERT OR IGNORE) ve silinmiş hesaplara kapalıdır.
   */
  async adminGrant(params: {
    uid?: string;
    coins?: number;
    frameIds?: readonly string[];
    energy?: number;
  }): Promise<AdminGrantResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return { success: false, error: 'account_deleted' };
    }

    await this.getProfile(params.uid);

    return this.ctx.storage.transactionSync(() => {
      if (typeof params.coins === 'number' && Number.isFinite(params.coins) && params.coins !== 0) {
        this.ctx.storage.sql.exec(
          'UPDATE profiles SET coins = MAX(0, coins + ?)',
          Math.floor(params.coins)
        );
      }

      const grantedFrames: string[] = [];
      if (Array.isArray(params.frameIds)) {
        const now = Date.now();
        for (const rawId of params.frameIds) {
          const frameId = typeof rawId === 'string' ? rawId.trim().toLowerCase() : '';
          if (isValidFrameId(frameId) && frameId !== 'classic') {
            this.ctx.storage.sql.exec(
              'INSERT OR IGNORE INTO owned_items (item_id, purchased_at) VALUES (?, ?)',
              frameId,
              now
            );
            grantedFrames.push(frameId);
          }
        }
      }

      let finalEnergy: number | undefined;
      if (typeof params.energy === 'number' && Number.isFinite(params.energy)) {
        const maxEnergy = getEnergyMax(this.env);
        finalEnergy = Math.max(0, Math.min(maxEnergy, Math.floor(params.energy)));
        this.ctx.storage.sql.exec(
          'UPDATE profiles SET energy = ?, energy_updated_at = ?',
          finalEnergy,
          Date.now()
        );
      }

      const rows = this.ctx.storage.sql
        .exec<{ coins: number; energy: number }>('SELECT coins, energy FROM profiles LIMIT 1')
        .toArray();
      const finalCoins = rows.length > 0 ? rows[0].coins : 0;
      if (finalEnergy === undefined && rows.length > 0 && rows[0].energy !== undefined) {
        finalEnergy = Number(rows[0].energy);
      }

      return {
        success: true,
        coins: finalCoins,
        grantedFrames,
        ...(finalEnergy !== undefined ? { energy: finalEnergy } : {}),
      };
    });
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

    if (request.method === 'POST' && url.pathname === '/admin/grant') {
      try {
        const body = (await request.json().catch(() => ({}))) as {
          uid?: unknown;
          coins?: unknown;
          frameIds?: unknown;
          energy?: unknown;
        };
        const res = await this.adminGrant({
          uid: typeof body.uid === 'string' ? body.uid : uid,
          coins: typeof body.coins === 'number' ? body.coins : undefined,
          frameIds: Array.isArray(body.frameIds) ? (body.frameIds as string[]) : undefined,
          energy: typeof body.energy === 'number' ? body.energy : undefined,
        });
        if (!res.success) {
          if (res.error === 'account_deleted') {
            return new Response(JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }), {
              status: 410,
              headers: { 'Content-Type': 'application/json' },
            });
          }
          return new Response(JSON.stringify({ error: res.error }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
          });
        }
        return new Response(JSON.stringify(res), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }

    return new Response('Not Found', { status: 404 });
  }
}
