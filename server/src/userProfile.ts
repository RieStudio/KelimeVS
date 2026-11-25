import { DurableObject } from 'cloudflare:workers';
import { validateNickname, isGuestPatternNickname } from './engine/nicknameValidator';
import { generateGuestNickname, resolveDisplayName } from './displayName';
export { generateGuestNickname, resolveDisplayName };
import {
  type UserClientMessage,
  type UserServerMessage,
  parseUserClientMessage,
} from './protocol';
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

export const GUEST_NICKNAME_LOCK_MIN_BUILD = 13;

export const NICKNAME_WINDOW_MS = 24 * 60 * 60 * 1000;
export const NICKNAME_MAX_CHANGES = 2;

export function formatRemainingCooldown(remainingSeconds: number): string {
  if (remainingSeconds >= 3600) {
    const hours = Math.ceil(remainingSeconds / 3600);
    return `${hours} saat sonra`;
  }
  const minutes = Math.max(1, Math.ceil(remainingSeconds / 60));
  return `${minutes} dakika sonra`;
}

export function getNicknameCooldownMessage(remainingSeconds: number): string {
  const timeStr = formatRemainingCooldown(remainingSeconds);
  return `Takma adını 24 saat içinde en fazla 2 kez değiştirebilirsin. Bir sonraki değişiklik hakkın: ${timeStr}.`;
}

export function getGuestNicknameLockMinBuild(env?: { GUEST_NICKNAME_LOCK_MIN_BUILD?: string }): number {
  if (env?.GUEST_NICKNAME_LOCK_MIN_BUILD) {
    const parsed = parseInt(env.GUEST_NICKNAME_LOCK_MIN_BUILD, 10);
    if (Number.isFinite(parsed) && parsed > 0) return parsed;
  }
  return GUEST_NICKNAME_LOCK_MIN_BUILD;
}
import type { Env } from './index';
import { evaluateAchievements } from './achievements/definitions';
import {
  MIN_SOLO_WIN_SECONDS,
  SOLO_DAILY_SAFETY_CAP,
  SOLO_VOID_DAILY_REFUND_CAP,
} from './soloMatch';

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

export interface UserAchievementItem {
  readonly id: string;
  readonly unlockedAt: number;
}

export interface ApplyResultToCountersParams {
  readonly matchId: string;
  readonly isWin: boolean;
  readonly isLoss: boolean;
  readonly source: 'ranked' | 'solo';
  readonly correctCount?: number;
  readonly nowMs?: number;
}

export interface ApplyResultToCountersResult {
  readonly unlockedAchievements: readonly string[];
  readonly currentStreak: number;
  readonly maxStreak: number;
  readonly played: number;
  readonly won: number;
}

export interface ApplyBotMatchRewardParams {
  readonly matchId?: string;
  readonly ticketId: string;
  readonly outcome: 'win' | 'loss' | 'void';
  readonly myScore?: number;
  readonly oppScore?: number;
  readonly correctAnswers?: number;
  readonly durationSeconds?: number;
  readonly endedBy?: 'normal' | 'forfeit' | 'draw_limit_reached';
  readonly uid?: string;
  readonly nowMs?: number;
}

export interface IssueSoloTicketResult {
  readonly ok: boolean;
  readonly reason?: 'no_energy' | 'account_deleted';
  readonly ticketId?: string;
  readonly matchId?: string;
  readonly issuedAt?: number;
  readonly energy?: {
    readonly current: number;
    readonly max: number;
    readonly nextEnergyAtMs: number | null;
  };
}

export interface ApplyBotMatchRewardResult {
  readonly ok: true;
  readonly counted: boolean;
  readonly voided?: boolean;
  readonly refunded?: boolean;
  readonly alreadyProcessed?: boolean;
  readonly coinsAwarded?: number;
  readonly coins?: number;
  readonly energy: EnergyState;
  readonly unlockedAchievements: readonly string[];
}

export interface FrameMigrationResult {
  readonly refundedCoins: number;
  readonly removedFrames: readonly string[];
}

export interface PublicProfileStats {
  readonly played: number;
  readonly won: number;
  readonly lost: number;
  readonly winRate: number;
}

export interface PublicProfileData {
  readonly nickname: string;
  readonly equippedFrame: string;
  readonly stats: PublicProfileStats;
  readonly isGuest: boolean;
}

export type PublicProfileResult =
  | { readonly kind: 'deleted' }
  | { readonly kind: 'not_found' }
  | {
      readonly kind: 'ok';
      readonly profile: PublicProfileData;
    };

export interface UserProfileData {
  readonly uid: string;
  readonly nickname: string | null;
  readonly coins: number;
  readonly stats: UserStats;
  readonly createdAt: number;
  readonly equippedFrame: string;
  readonly isGuest?: boolean;
  readonly isSystemNickname?: boolean;
  readonly frameMigration?: FrameMigrationResult;
  readonly allowMatchRequests?: boolean;
  readonly currentStreak?: number;
  readonly maxStreak?: number;
  readonly achievements?: readonly UserAchievementItem[];
}

export interface MatchRewardResult {
  readonly coinsAwarded: number;
  readonly coins: number;
  readonly nickname?: string | null;
  readonly alreadyProcessed?: boolean;
  readonly unlockedAchievements?: readonly string[];
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
  allow_match_requests: number | null;
  current_streak: number | null;
  max_streak: number | null;
  achievements_initialized: number | null;
  played_solo: number | null;
  won_solo: number | null;
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
  private inTransaction = false;

  private runInTransaction<T>(fn: () => T): T {
    if (this.inTransaction) {
      return fn();
    }
    if (typeof this.ctx.storage.transactionSync === 'function') {
      this.inTransaction = true;
      try {
        return this.ctx.storage.transactionSync(fn);
      } finally {
        this.inTransaction = false;
      }
    }
    return fn();
  }

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  private ensureSchema(nowMs = Date.now()): void {
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

      CREATE TABLE IF NOT EXISTS user_achievements (
        id TEXT PRIMARY KEY,
        unlocked_at INTEGER NOT NULL,
        match_id TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_user_achievements_match ON user_achievements(match_id);

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

    const hasNicknameUpdatedAt = profileCols.some((c) => c.name === 'nickname_updated_at');
    if (!hasNicknameUpdatedAt) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN nickname_updated_at INTEGER NOT NULL DEFAULT 0'
      );
    }

    const hasIsGuest = profileCols.some((c) => c.name === 'is_guest');
    if (!hasIsGuest) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN is_guest INTEGER NOT NULL DEFAULT 1'
      );
    }

    const hasIsSystemNickname = profileCols.some((c) => c.name === 'is_system_nickname');
    if (!hasIsSystemNickname) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN is_system_nickname INTEGER NOT NULL DEFAULT 0'
      );
      // Mevcut satırlar için: Eğer nickname null ise veya M-#### kalıbına uyuyorsa is_system_nickname = 1,
      // aksi takdirde (özel adlı mevcut kullanıcılar, örn. "Sevbans") is_system_nickname = 0 olarak kalır.
      const rows = this.ctx.storage.sql
        .exec<{ uid: string; nickname: string | null }>('SELECT uid, nickname FROM profiles')
        .toArray();
      for (const row of rows) {
        const isSys = !row.nickname || isGuestPatternNickname(row.nickname);
        if (isSys) {
          this.ctx.storage.sql.exec(
            'UPDATE profiles SET is_system_nickname = 1 WHERE uid = ?',
            row.uid
          );
        }
      }
    }

    const hasNicknameChangesTable = this.ctx.storage.sql
      .exec<{ name: string }>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'nickname_changes'"
      )
      .toArray().length > 0;

    if (!hasNicknameChangesTable) {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS nickname_changes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          changed_at INTEGER NOT NULL
        );
      `);

      // KRİTİK GÖÇ: Yalnızca tablo ilk kez oluşturulurken BİR KEZ çalışır.
      // profiles tablosunda is_system_nickname = 0 VE nickname_updated_at > 0 VE (şimdi - nickname_updated_at) < NICKNAME_WINDOW_MS
      // ise kullanıcının tek bir geçmiş değişikliği olduğu kabul edilip nickname_changes tablosuna eklenir (1 hakkı kalır).
      const legacyProfiles = this.ctx.storage.sql
        .exec<{ nickname_updated_at: number | null; is_system_nickname: number | null }>(
          'SELECT nickname_updated_at, is_system_nickname FROM profiles LIMIT 1'
        )
        .toArray();

      if (legacyProfiles.length > 0) {
        const lastUpdated = legacyProfiles[0].nickname_updated_at ?? 0;
        const isSystem = legacyProfiles[0].is_system_nickname ?? 0;
        if (isSystem === 0 && lastUpdated > 0 && nowMs - lastUpdated < NICKNAME_WINDOW_MS) {
          this.ctx.storage.sql.exec(
            'INSERT INTO nickname_changes (changed_at) VALUES (?)',
            lastUpdated
          );
        }
      }
    }

    const hasAllowMatchRequests = profileCols.some((c) => c.name === 'allow_match_requests');
    if (!hasAllowMatchRequests) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN allow_match_requests INTEGER NOT NULL DEFAULT 1'
      );
    }

    const hasCurrentStreak = profileCols.some((c) => c.name === 'current_streak');
    if (!hasCurrentStreak) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN current_streak INTEGER NOT NULL DEFAULT 0'
      );
    }

    const hasMaxStreak = profileCols.some((c) => c.name === 'max_streak');
    if (!hasMaxStreak) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN max_streak INTEGER NOT NULL DEFAULT 0'
      );
    }

    const hasAchievementsInitialized = profileCols.some((c) => c.name === 'achievements_initialized');
    if (!hasAchievementsInitialized) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN achievements_initialized INTEGER NOT NULL DEFAULT 0'
      );
    }

    const hasPlayedSolo = profileCols.some((c) => c.name === 'played_solo');
    if (!hasPlayedSolo) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN played_solo INTEGER NOT NULL DEFAULT 0'
      );
    }

    const hasWonSolo = profileCols.some((c) => c.name === 'won_solo');
    if (!hasWonSolo) {
      this.ctx.storage.sql.exec(
        'ALTER TABLE profiles ADD COLUMN won_solo INTEGER NOT NULL DEFAULT 0'
      );
    }

    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS daily_solo_matches (
        day_key TEXT PRIMARY KEY,
        count INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS solo_tickets (
        ticket_id TEXT PRIMARY KEY,
        match_id TEXT NOT NULL,
        issued_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        used INTEGER NOT NULL DEFAULT 0
      );

      CREATE INDEX IF NOT EXISTS idx_solo_tickets_match ON solo_tickets(match_id);
    `);

    const soloDailyCols = this.ctx.storage.sql
      .exec<{ name: string }>('PRAGMA table_info(daily_solo_matches)')
      .toArray();
    if (!soloDailyCols.some((c) => c.name === 'void_refund_count')) {
      try {
        this.ctx.storage.sql.exec(
          'ALTER TABLE daily_solo_matches ADD COLUMN void_refund_count INTEGER NOT NULL DEFAULT 0'
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (!msg.includes('duplicate column name')) {
          throw err;
        }
      }
    }

    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS incoming_requests (
        id TEXT PRIMARY KEY,
        from_uid TEXT NOT NULL,
        from_nickname TEXT NOT NULL,
        from_frame TEXT NOT NULL,
        type TEXT NOT NULL,
        origin TEXT NOT NULL,
        match_id TEXT,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        status TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS outgoing_requests (
        id TEXT PRIMARY KEY,
        to_uid TEXT NOT NULL,
        to_nickname TEXT NOT NULL,
        type TEXT NOT NULL,
        origin TEXT NOT NULL,
        match_id TEXT,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        status TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS match_request_cooldowns (
        target_uid TEXT PRIMARY KEY,
        cooldown_until INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS match_request_rate_limits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS user_presence (
        key TEXT PRIMARY KEY,
        state TEXT NOT NULL
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
      DELETE FROM user_achievements;
      DELETE FROM blocked_users;
      DELETE FROM powerup_purchases;
      DELETE FROM owned_items;
      DELETE FROM energy_spends;
      DELETE FROM energy_purchases;
      DELETE FROM nickname_changes;
      DELETE FROM incoming_requests;
      DELETE FROM outgoing_requests;
      DELETE FROM match_request_cooldowns;
      DELETE FROM match_request_rate_limits;
      DELETE FROM user_presence;
      DELETE FROM daily_solo_matches;
      DELETE FROM solo_tickets;
    `);

    // Tombstone kaydı ekle veya güncelle
    const nowMs = Date.now();
    this.ctx.storage.sql.exec(
      'INSERT OR REPLACE INTO tombstone (uid, deleted_at) VALUES (?, ?)',
      effectiveUid,
      nowMs
    );

    // Açık tüm WebSocket bağlantılarını 4001, "account_deleted" ile kapat
    const sockets = this.getWebSocketsSafe();
    for (const ws of sockets) {
      try {
        ws.close(4001, 'account_deleted');
      } catch {}
    }

    // 24 saat sonra DO verilerini tamamen temizleyecek alarm kur (multiplexer üzerinden)
    await this.scheduleNextAlarm(nowMs);

    return { ok: true, deleted: true };
  }

  /**
   * Alarm multiplexer:
   * 1. 24 saat sonra çalışan tombstone temizliği
   * 2. Süresi dolan (45 sn) bekleyen gelen isteklerin 'expired' yapılması ve taraflara bildirilmesi
   * 3. Süresi dolan (45 sn) bekleyen giden isteklerin 'expired' yapılması ve taraflara bildirilmesi
   */
  async alarm(): Promise<void> {
    const nowMs = Date.now();
    const tombstone = this.ctx.storage.sql
      .exec<{ deleted_at: number }>('SELECT deleted_at FROM tombstone LIMIT 1')
      .toArray();
    if (tombstone.length > 0) {
      const tombstoneExpiry = tombstone[0].deleted_at + 24 * 60 * 60 * 1000;
      if (nowMs >= tombstoneExpiry) {
        if (typeof this.ctx.storage.deleteAll === 'function') {
          await this.ctx.storage.deleteAll();
        }
        return;
      }
      await this.scheduleNextAlarm(nowMs);
      return;
    }

    await this.expirePendingIncomingRequests(nowMs);
    await this.expirePendingOutgoingRequests(nowMs);
    this.pruneExpiredRecords(nowMs);
    await this.scheduleNextAlarm(nowMs);
  }

  /**
   * Sonuçlanmış ve süresi dolmuş istek, bekleme süresi ve hız sınırı kayıtlarını temizler.
   * Tabloların sonsuz büyümesini engeller.
   */
  pruneExpiredRecords(nowMs = Date.now()): void {
    // 1. Sonuçlanmış (accepted, declined, cancelled, expired) istekleri 5 dakika sonra sil
    const fiveMinutesAgo = nowMs - 5 * 60 * 1000;
    this.ctx.storage.sql.exec(
      "DELETE FROM incoming_requests WHERE status IN ('accepted', 'declined', 'cancelled', 'expired') AND expires_at < ?",
      fiveMinutesAgo
    );
    this.ctx.storage.sql.exec(
      "DELETE FROM outgoing_requests WHERE status IN ('accepted', 'declined', 'cancelled', 'expired') AND expires_at < ?",
      fiveMinutesAgo
    );

    // 2. Süresi dolmuş bekleme sürelerini (cooldown) temizle
    this.ctx.storage.sql.exec(
      'DELETE FROM match_request_cooldowns WHERE cooldown_until <= ?',
      nowMs
    );

    // 3. 1 dakikadan eski hız sınırı kayıtlarını temizle
    this.ctx.storage.sql.exec(
      'DELETE FROM match_request_rate_limits WHERE created_at <= ?',
      nowMs - 60_000
    );
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
    if (this.isDeleted()) {
      return null;
    }

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
   * Herkese açık profil verisini döndürür.
   * SADECE OKUMA yapar. Var olmayan bir uid için profil oluşturmaz ve yan etki yaratmaz.
   * Silinmiş hesap (tombstone) için { kind: 'deleted' }, bulunamazsa { kind: 'not_found' } döner.
   */
  async getPublicProfile(): Promise<PublicProfileResult> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return { kind: 'deleted' };
    }

    const cursor = this.ctx.storage.sql.exec<{
      uid: string;
      nickname: string | null;
      played: number;
      won: number;
      lost: number;
      equipped_frame: string | null;
      is_guest: number | null;
    }>(
      'SELECT uid, nickname, played, won, lost, equipped_frame, is_guest FROM profiles LIMIT 1'
    );
    const rows = cursor.toArray();

    if (rows.length === 0) {
      return { kind: 'not_found' };
    }

    const row = rows[0];
    const isGuest = (row.is_guest as number | undefined) === 1;
    const nickname = resolveDisplayName({
      nickname: row.nickname,
      uid: row.uid,
      isGuest,
    });

    const played = Math.max(0, row.played ?? 0);
    const won = Math.max(0, row.won ?? 0);
    const lost = Math.max(0, row.lost ?? 0);
    const winRate = played === 0 ? 0 : Math.round((won / played) * 100);

    return {
      kind: 'ok',
      profile: {
        nickname,
        equippedFrame: (row.equipped_frame as string) || 'classic',
        stats: {
          played,
          won,
          lost,
          winRate,
        },
        isGuest,
      },
    };
  }

  /**
   * Kullanıcının profilini döndürür; mevcut değilse varsayılan başlangıç bakiyesiyle oluşturur.
   */
  async getProfile(
    uid?: string,
    clientBuild = 0,
    isGuest?: boolean,
    nowMs = Date.now()
  ): Promise<UserProfileData> {
    this.ensureSchema(nowMs);

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    // Achievements listesi ve gerekirse sessiz backfill
    this.ensureAchievementsBackfilled(nowMs);

    let frameMigration: FrameMigrationResult | undefined;
    if (clientBuild > 0) {
      const res = await this.migrateRetiredFrames(uid, clientBuild);
      if (res) {
        frameMigration = res;
      }
    }

    const cursor = this.ctx.storage.sql.exec<ProfileRow>(
      'SELECT uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, is_guest, is_system_nickname, allow_match_requests, current_streak, max_streak, achievements_initialized FROM profiles LIMIT 1'
    );
    let rows = cursor.toArray();

    if (rows.length > 0) {
      if (this.expireAbandonedTickets(nowMs, rows[0].uid)) {
        rows = this.ctx.storage.sql.exec<ProfileRow>(
          'SELECT uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, is_guest, is_system_nickname, allow_match_requests, current_streak, max_streak, achievements_initialized FROM profiles LIMIT 1'
        ).toArray();
      }
      const row = rows[0];
      let currentIsGuest = (row.is_guest as number | undefined) ?? 0;
      let currentIsSystem = (row.is_system_nickname as number | undefined) ?? 0;
      let currentNickname = row.nickname;

      // 1) Misafirlik bayrağı tek yönlü kuralı: profiles.is_guest yalnızca 1 -> 0 geçebilir.
      // Bir kez 0 olduktan sonra (Google'a bağlanmış), eski anonim token gelse bile ASLA tekrar 1 yapma!
      if (currentIsGuest === 1 && isGuest === false) {
        this.ctx.storage.sql.exec(
          'UPDATE profiles SET is_guest = 0 WHERE uid = ?',
          row.uid
        );
        currentIsGuest = 0;
      }

      // 2) Tembel migrasyon & Misafir takma ad atama:
      // A) Token isGuest === true VE DB'de is_guest hâlâ 1 iken (tüm misafirler M-#### yapılır).
      // B) Token isGuest === true VE DB'de nickname NULL/boş iken (takma adsız kalmış misafir profilleri).
      // YALNIZCA DB'de is_guest === 0 VE mevcut özel bir takma adı olan (Google'a bağlanmış) hesaplarda anonim token gelse bile ad DEĞİŞMEZ.
      if (isGuest === true && (currentIsGuest === 1 || !currentNickname)) {
        const autoName = generateGuestNickname(row.uid);
        if (currentNickname !== autoName || currentIsGuest !== 1 || currentIsSystem !== 1) {
          this.ctx.storage.sql.exec(
            'UPDATE profiles SET nickname = ?, is_guest = 1, is_system_nickname = 1, nickname_updated_at = 0 WHERE uid = ?',
            autoName,
            row.uid
          );
          currentNickname = autoName;
          currentIsGuest = 1;
          currentIsSystem = 1;

          // Leaderboard tablosundaki adı da güncelle
          if (this.env.LEADERBOARD) {
            try {
              const leaderboardStub = this.env.LEADERBOARD.get(
                this.env.LEADERBOARD.idFromName('global')
              );
              await leaderboardStub.updateNickname(row.uid, autoName);
            } catch (lbErr) {
              console.error('Leaderboard updateNickname failed for guest migration:', lbErr);
            }
          }
        }
      }

      const allowMatchRequests = (row.allow_match_requests as number | undefined) !== 0;

      const achRows = this.ctx.storage.sql
        .exec<{ id: string; unlocked_at: number }>(
          'SELECT id, unlocked_at FROM user_achievements ORDER BY unlocked_at ASC, id ASC'
        )
        .toArray();
      const achievements: UserAchievementItem[] = achRows.map((r) => ({
        id: r.id,
        unlockedAt: r.unlocked_at,
      }));

      return {
        uid: row.uid,
        nickname: currentNickname,
        coins: row.coins,
        stats: {
          played: row.played,
          won: row.won,
          lost: row.lost,
          correctAnswers: row.correct_answers ?? 0,
        },
        createdAt: row.created_at,
        equippedFrame: (row.equipped_frame as string) || 'classic',
        isGuest: currentIsGuest === 1,
        isSystemNickname: currentIsSystem === 1,
        allowMatchRequests,
        currentStreak: (row.current_streak as number | undefined) ?? 0,
        maxStreak: (row.max_streak as number | undefined) ?? 0,
        achievements,
        ...(frameMigration ? { frameMigration } : {}),
      };
    }

    const effectiveUid = uid && uid.trim().length > 0 ? uid.trim() : 'unknown';
    const startCoins = parseInt(this.env.START_COINS ?? '100', 10);
    const initialCoins = Number.isFinite(startCoins) && startCoins >= 0 ? startCoins : 100;
    const maxEnergy = getEnergyMax(this.env);

    const initialIsGuest = isGuest === true ? 1 : 0;
    const initialNickname = isGuest === true ? generateGuestNickname(effectiveUid) : null;
    const initialIsSystem = isGuest === true ? 1 : 0;

    this.ctx.storage.sql.exec(
      `INSERT INTO profiles (uid, nickname, coins, played, won, lost, correct_answers, created_at, equipped_frame, energy, energy_updated_at, is_guest, is_system_nickname, allow_match_requests, current_streak, max_streak, achievements_initialized)
       VALUES (?, ?, ?, 0, 0, 0, 0, ?, 'classic', ?, 0, ?, ?, 1, 0, 0, 1)`,
      effectiveUid,
      initialNickname,
      initialCoins,
      nowMs,
      maxEnergy,
      initialIsGuest,
      initialIsSystem
    );

    return {
      uid: effectiveUid,
      nickname: initialNickname,
      coins: initialCoins,
      stats: { played: 0, won: 0, lost: 0, correctAnswers: 0 },
      createdAt: nowMs,
      equippedFrame: 'classic',
      isGuest: initialIsGuest === 1,
      isSystemNickname: initialIsSystem === 1,
      allowMatchRequests: true,
      currentStreak: 0,
      maxStreak: 0,
      achievements: [],
    };
  }

  /**
   * Takma adı sanitize/validate edip kaydeder.
   * İlk özel ad belirleme kotaya sayılmaz ve serbesttir.
   * Sonraki değişiklikler 24 saatlik kayan pencerede en fazla 2 kez yapılabilir (NICKNAME_MAX_CHANGES).
   */
  async setNickname(
    nickname: string,
    uid?: string,
    nowMs = Date.now(),
    isGuest?: boolean
  ): Promise<{ ok: true; nickname: string }> {
    this.ensureSchema(nowMs);

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    if (isGuest === true) {
      throw new Error('guest_nickname_locked');
    }

    const validation = validateNickname(nickname);
    if (!validation.isValid || validation.normalized === null) {
      if (validation.error === 'reserved') {
        throw new Error('reserved_nickname');
      }
      if (validation.error === 'profanity') {
        throw new Error('nickname_blocked');
      }
      throw new Error('invalid_nickname');
    }

    const normalized = validation.normalized;

    // Profil yoksa önce oluştur
    await this.getProfile(uid, 0, isGuest, nowMs);

    return this.ctx.storage.transactionSync(() => {
      // 1. 24 saatten eski kayıtları temizle
      const windowStart = nowMs - NICKNAME_WINDOW_MS;
      this.ctx.storage.sql.exec(
        'DELETE FROM nickname_changes WHERE changed_at < ?',
        windowStart
      );

      // 2. Mevcut profil bilgilerini al
      const rows = this.ctx.storage.sql
        .exec<{
          nickname: string | null;
          nickname_updated_at: number | null;
          is_guest: number | null;
          is_system_nickname: number | null;
        }>(
          'SELECT nickname, nickname_updated_at, is_guest, is_system_nickname FROM profiles LIMIT 1'
        )
        .toArray();

      if (rows.length > 0) {
        if (rows[0].is_guest === 1) {
          throw new Error('guest_nickname_locked');
        }

        const currentNickname = rows[0].nickname;
        const lastUpdatedAt = rows[0].nickname_updated_at ?? 0;
        const isSystemNickname = rows[0].is_system_nickname ?? 0;

        const hasExistingNickname =
          typeof currentNickname === 'string' && currentNickname.trim().length > 0;

        // İlk özel ad belirleme kontrolü (SEÇENEK A):
        // Eğer mevcut ad null/boş ise VEYA sistem tarafından atanmışsa (is_system_nickname === 1)
        // VEYA lastUpdatedAt <= 0 ise: İLK ÖZEL AD SEÇİMİDİR -> Cooldown uygulanmaz ve kotaya sayılmaz!
        const isFirstCustomNickname =
          !hasExistingNickname || isSystemNickname === 1 || lastUpdatedAt <= 0;

        if (!isFirstCustomNickname) {
          const recentChanges = this.ctx.storage.sql
            .exec<{ changed_at: number }>(
              'SELECT changed_at FROM nickname_changes WHERE changed_at >= ? ORDER BY changed_at ASC',
              windowStart
            )
            .toArray();

          if (recentChanges.length >= NICKNAME_MAX_CHANGES) {
            const oldestChange = recentChanges[0].changed_at;
            const nextAvailable = oldestChange + NICKNAME_WINDOW_MS;
            const remainingSeconds = Math.max(1, Math.ceil((nextAvailable - nowMs) / 1000));
            const error = new Error('nickname_cooldown');
            (error as any).remainingSeconds = remainingSeconds;
            throw error;
          }

          this.ctx.storage.sql.exec(
            'INSERT INTO nickname_changes (changed_at) VALUES (?)',
            nowMs
          );
        }
      }

      this.ctx.storage.sql.exec(
        'UPDATE profiles SET nickname = ?, nickname_updated_at = ?, is_system_nickname = 0',
        normalized,
        nowMs
      );

      return { ok: true, nickname: normalized };
    });
  }

  /**
   * profiles.achievements_initialized = 0 ise mevcut played/won değerleriyle
   * evaluateAchievements çalıştırıp açılanları match_id = 'backfill' ile ekler.
   * Bu kayıtlar maç sonu unlockedAchievements listesine girmez.
   */
  private ensureAchievementsBackfilled(nowMs = Date.now()): void {
    const row = this.ctx.storage.sql
      .exec<{
        uid: string;
        played: number;
        won: number;
        achievements_initialized: number | null;
      }>('SELECT uid, played, won, achievements_initialized FROM profiles LIMIT 1')
      .toArray()[0];

    if (!row || (row.achievements_initialized ?? 0) === 1) {
      return;
    }

    const unlockedRows = this.ctx.storage.sql
      .exec<{ id: string }>('SELECT id FROM user_achievements')
      .toArray();
    const unlocked = new Set(unlockedRows.map((x) => x.id));

    const toUnlock = evaluateAchievements(
      {
        played: Math.max(0, row.played ?? 0),
        won: Math.max(0, row.won ?? 0),
        currentStreak: 0,
        maxStreak: 0,
      },
      unlocked
    );

    this.runInTransaction(() => {
      for (const achId of toUnlock) {
        this.ctx.storage.sql.exec(
          'INSERT OR IGNORE INTO user_achievements (id, unlocked_at, match_id) VALUES (?, ?, ?)',
          achId,
          nowMs,
          'backfill'
        );
      }

      this.ctx.storage.sql.exec(
        'UPDATE profiles SET achievements_initialized = 1 WHERE uid = ?',
        row.uid
      );
    });
  }

  /**
   * Sayaç, seri ve başarım güncellemesini gerçekleştiren yeniden kullanılabilir fonksiyon.
   * Galibiyet/mağlubiyet sonucu, kaynak ('ranked' | 'solo') ve maç kimliği alır.
   * applyMatchReward'a bağımlı değildir.
   */
  applyResultToCounters(params: ApplyResultToCountersParams): ApplyResultToCountersResult {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const nowMs = params.nowMs ?? Date.now();

    // 1. Önce sessiz backfill: Maçın sayaçları uygulanmadan ÖNCE mevcut played/won değerleriyle çalışır
    this.ensureAchievementsBackfilled(nowMs);

    // 2. Mevcut sayaçları oku
    const profRows = this.ctx.storage.sql
      .exec<{
        uid: string;
        played: number;
        won: number;
        lost: number;
        correct_answers: number;
        current_streak: number | null;
        max_streak: number | null;
      }>(
        'SELECT uid, played, won, lost, correct_answers, current_streak, max_streak FROM profiles LIMIT 1'
      )
      .toArray();

    if (profRows.length === 0) {
      throw new Error('profile_not_found');
    }

    const prof = profRows[0];
    const curStreak = prof.current_streak ?? 0;
    const maxStreak = prof.max_streak ?? 0;

    let newCurrentStreak = curStreak;
    if (params.isWin) {
      newCurrentStreak = curStreak + 1;
    } else if (params.isLoss) {
      newCurrentStreak = 0;
    }
    const newMaxStreak = Math.max(maxStreak, newCurrentStreak);

    const isPlayedInc = params.source === 'ranked' || params.source === 'solo';
    const newPlayed = prof.played + (isPlayedInc ? 1 : 0);
    const newWon = prof.won + (params.isWin ? 1 : 0);
    const newLost = prof.lost + (params.isLoss ? 1 : 0);
    const correctCount = Math.max(0, params.correctCount ?? 0);
    const newCorrectAnswers = (prof.correct_answers ?? 0) + correctCount;

    // 3. Profili güncelle
    this.ctx.storage.sql.exec(
      `UPDATE profiles
       SET played = ?,
           won = ?,
           lost = ?,
           correct_answers = ?,
           current_streak = ?,
           max_streak = ?,
           achievements_initialized = 1
       WHERE uid = ?`,
      newPlayed,
      newWon,
      newLost,
      newCorrectAnswers,
      newCurrentStreak,
      newMaxStreak,
      prof.uid
    );

    // 4. Açılmış başarımları oku
    const unlockedRows = this.ctx.storage.sql
      .exec<{ id: string }>('SELECT id FROM user_achievements')
      .toArray();
    const unlockedSet = new Set(unlockedRows.map((r) => r.id));

    // 5. Güncel sayaçlarla evaluateAchievements çalıştır
    const newlyUnlocked = evaluateAchievements(
      {
        played: newPlayed,
        won: newWon,
        currentStreak: newCurrentStreak,
        maxStreak: newMaxStreak,
      },
      unlockedSet
    );

    // 6. Yeni açılanları match_id ile ekle
    for (const achId of newlyUnlocked) {
      this.ctx.storage.sql.exec(
        'INSERT INTO user_achievements (id, unlocked_at, match_id) VALUES (?, ?, ?)',
        achId,
        nowMs,
        params.matchId
      );
    }

    return {
      unlockedAchievements: newlyUnlocked,
      currentStreak: newCurrentStreak,
      maxStreak: newMaxStreak,
      played: newPlayed,
      won: newWon,
    };
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
      const unlockedRows = this.ctx.storage.sql
        .exec<{ id: string }>(
          "SELECT id FROM user_achievements WHERE match_id = ? AND match_id != 'backfill' ORDER BY rowid ASC",
          params.matchId
        )
        .toArray();

      return {
        coinsAwarded: existingMatches[0].coins_awarded,
        coins: profile.coins,
        nickname: profile.nickname,
        alreadyProcessed: true,
        unlockedAchievements: unlockedRows.map((r) => r.id),
      };
    }

    // 2-3. Jeton ödülü ve günlük tavan hesabı
    const nowMs = Date.now();
    const { actualCoinsAwarded, dayKey } = this.calculateMatchCoins(params.outcome, nowMs);

    const isWin =
      params.outcome === 'win' || params.outcome === 'win_by_opponent_disconnect';
    const isLoss =
      params.outcome === 'loss' || params.outcome === 'loss_by_disconnect';
    const correctCount = Math.max(0, params.correctAnswers ?? 0);

    // 4-6. Atomik SQLite işlemi (tüm yazmalar tek transactionSync içinde, processed_matches en sonda)
    const counterRes = this.runInTransaction(() => {
      // 4. Günlük kazanç sayacını güncelle
      this.ctx.storage.sql.exec(
        `INSERT INTO daily_coins (day_key, earned) VALUES (?, ?)
         ON CONFLICT(day_key) DO UPDATE SET earned = earned + ?`,
        dayKey,
        actualCoinsAwarded,
        actualCoinsAwarded
      );

      // Bakiyeyi güncelle
      this.ctx.storage.sql.exec(
        'UPDATE profiles SET coins = coins + ? WHERE uid = ?',
        actualCoinsAwarded,
        profile.uid
      );

      // 5. İstatistikleri, seriyi ve başarımları uygula
      const res = this.applyResultToCounters({
        matchId: params.matchId,
        isWin,
        isLoss,
        source: 'ranked',
        correctCount,
        nowMs,
      });

      // 6. İŞLEMİN EN SONUNDA: İşlenen maçı kaydet
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

      return res;
    });

    // 7. Güncel bakiyeyi oku
    const updatedProfile = await this.getProfile();
    return {
      coinsAwarded: actualCoinsAwarded,
      coins: updatedProfile.coins,
      nickname: updatedProfile.nickname,
      unlockedAchievements: counterRes.unlockedAchievements,
    };
  }

  /**
   * Online ve solo maçlar için taban jeton ödülü ve günlük tavanı (DAILY_MATCH_COIN_CAP) ortak hesaplar.
   */
  private calculateMatchCoins(
    outcome: MatchRewardOutcome,
    nowMs = Date.now()
  ): { actualCoinsAwarded: number; dayKey: string } {
    let baseReward = 0;
    switch (outcome) {
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

    const dayKey = new Date(nowMs).toISOString().slice(0, 10);
    const dailyCursor = this.ctx.storage.sql.exec<DailyCoinsRow>(
      'SELECT day_key, earned FROM daily_coins WHERE day_key = ? LIMIT 1',
      dayKey
    );
    const dailyRows = dailyCursor.toArray();
    const currentEarnedToday = dailyRows.length > 0 ? dailyRows[0].earned : 0;

    const rawCap = this.env.DAILY_MATCH_COIN_CAP?.trim().toLowerCase();
    const isUnlimited = !rawCap || rawCap === 'unlimited' || rawCap === '0';
    if (isUnlimited) {
      return { actualCoinsAwarded: baseReward, dayKey };
    }

    const capVal = parseInt(rawCap, 10);
    const dailyCap = Number.isFinite(capVal) && capVal > 0 ? capVal : baseReward;
    const remainingCap = Math.max(0, dailyCap - currentEarnedToday);

    const actualCoinsAwarded = Math.max(0, Math.min(baseReward, remainingCap));
    return { actualCoinsAwarded, dayKey };
  }

  private closeTicketAsAbandonedInTransaction(params: {
    readonly ticketId: string;
    readonly matchId: string;
    readonly uid: string;
    readonly nowMs: number;
  }): ApplyResultToCountersResult {
    this.ctx.storage.sql.exec(
      'UPDATE solo_tickets SET used = 1 WHERE ticket_id = ?',
      params.ticketId
    );
    this.ctx.storage.sql.exec(
      'UPDATE profiles SET played_solo = played_solo + 1 WHERE uid = ?',
      params.uid
    );
    const counterRes = this.applyResultToCounters({
      matchId: params.matchId,
      isWin: false,
      isLoss: true,
      correctCount: 0,
      source: 'solo',
      nowMs: params.nowMs,
    });
    this.ctx.storage.sql.exec(
      `INSERT OR IGNORE INTO processed_matches (match_id, applied_at, outcome, coins_awarded)
       VALUES (?, ?, 'solo_abandoned', 0)`,
      params.matchId,
      params.nowMs
    );
    return counterRes;
  }

  private expireAbandonedTickets(nowMs: number, effectiveUid: string): boolean {
    const expired = this.ctx.storage.sql
      .exec<{ ticket_id: string; match_id: string }>(
        'SELECT ticket_id, match_id FROM solo_tickets WHERE used = 0 AND expires_at < ? LIMIT 10',
        nowMs
      )
      .toArray();

    if (expired.length === 0) return false;

    this.runInTransaction(() => {
      for (const t of expired) {
        this.closeTicketAsAbandonedInTransaction({
          ticketId: t.ticket_id,
          matchId: t.match_id,
          uid: effectiveUid,
          nowMs,
        });
      }
      this.ctx.storage.sql.exec(`
        DELETE FROM processed_matches
        WHERE match_id NOT IN (
          SELECT match_id FROM processed_matches ORDER BY applied_at DESC LIMIT 100
        )
      `);
    });
    return true;
  }

  /**
   * İstemcide oynanacak maç için bilet üretir ve enerjiyi atomik olarak düşer.
   * Önceki kullanılmamış biletleri 'terk edilmiş' (kayıp) olarak kapatır.
   */
  async issueSoloTicket(uid?: string, nowMs = Date.now()): Promise<IssueSoloTicketResult> {
    this.ensureSchema(nowMs);

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const profile = await this.getProfile(uid, 0, undefined, nowMs);
    const effectiveUid = profile.uid;

    return this.runInTransaction(() => {
      // 1. Enerji kontrolü (yetersizse HİÇBİR ŞEY yazma ve hemen dön)
      const energyEnabled = isEnergyEnabledForUser(this.env, effectiveUid);
      const maxEnergy = getEnergyMax(this.env);
      const regenMinutes = getEnergyRegenMinutes(this.env);
      const cost = getEnergyCostPerMatch(this.env);

      let newEnergy = maxEnergy;
      let nextEnergyAtMs: number | null = null;
      let newUpdatedAtMs = nowMs;

      if (energyEnabled) {
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

        if (regen.current < cost) {
          return {
            ok: false,
            reason: 'no_energy',
          };
        }

        newEnergy = regen.current - cost;
        newUpdatedAtMs = regen.current >= maxEnergy ? nowMs : regen.updatedAtMs;
        nextEnergyAtMs =
          newEnergy < maxEnergy ? newUpdatedAtMs + regenMinutes * 60 * 1000 : null;
      }

      // 2. Önceki kullanılmamış (used=0) biletleri "terk edilmiş" (kayıp) olarak kapat
      const unusedTickets = this.ctx.storage.sql
        .exec<{ ticket_id: string; match_id: string }>(
          'SELECT ticket_id, match_id FROM solo_tickets WHERE used = 0'
        )
        .toArray();

      for (const t of unusedTickets) {
        this.closeTicketAsAbandonedInTransaction({
          ticketId: t.ticket_id,
          matchId: t.match_id,
          uid: effectiveUid,
          nowMs,
        });
      }
      if (unusedTickets.length > 0) {
        this.ctx.storage.sql.exec(`
          DELETE FROM processed_matches
          WHERE match_id NOT IN (
            SELECT match_id FROM processed_matches ORDER BY applied_at DESC LIMIT 100
          )
        `);
      }

      // 3. match_id ve ticketId üret
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
      const matchBytes = new Uint8Array(24);
      crypto.getRandomValues(matchBytes);
      let randMatch = '';
      for (let i = 0; i < 24; i++) {
        randMatch += chars[matchBytes[i] % chars.length];
      }
      const matchId = `bot:${randMatch}`;

      const ticketBytes = new Uint8Array(24);
      crypto.getRandomValues(ticketBytes);
      let randTicket = '';
      for (let i = 0; i < 24; i++) {
        randTicket += chars[ticketBytes[i] % chars.length];
      }
      const ticketId = `stk_${randTicket}`;

      // 4. Enerjiyi düş
      if (energyEnabled) {
        this.ctx.storage.sql.exec(
          'UPDATE profiles SET energy = ?, energy_updated_at = ?',
          newEnergy,
          newUpdatedAtMs
        );
        this.ctx.storage.sql.exec(
          'INSERT INTO energy_spends (match_id, uid, amount, created_at) VALUES (?, ?, ?, ?)',
          matchId,
          effectiveUid,
          cost,
          nowMs
        );
      }

      // 5. Yeni bileti kaydet (15 dakika geçerli) ve eski kayıtları buda
      const expiresAt = nowMs + 15 * 60 * 1000;
      this.ctx.storage.sql.exec(
        'INSERT INTO solo_tickets (ticket_id, match_id, issued_at, expires_at, used) VALUES (?, ?, ?, ?, 0)',
        ticketId,
        matchId,
        nowMs,
        expiresAt
      );

      const ticketPruneCutoffMs = nowMs - 30 * 24 * 60 * 60 * 1000;
      this.ctx.storage.sql.exec(
        'DELETE FROM solo_tickets WHERE used = 1 AND issued_at < ?',
        ticketPruneCutoffMs
      );
      const dailySoloCutoffKey = new Date(nowMs - 7 * 24 * 60 * 60 * 1000)
        .toISOString()
        .slice(0, 10);
      this.ctx.storage.sql.exec(
        'DELETE FROM daily_solo_matches WHERE day_key < ?',
        dailySoloCutoffKey
      );

      return {
        ok: true,
        ticketId,
        matchId,
        issuedAt: nowMs,
        energy: {
          current: newEnergy,
          max: maxEnergy,
          nextEnergyAtMs,
        },
      };
    });
  }

  /**
   * İstemcide oynanan solo maç sonucunu bilet doğrulamasıyla atomik ve idempotent olarak işler.
   * Lider tablosuna yazmaz.
   */
  async applyBotMatchReward(params: ApplyBotMatchRewardParams): Promise<ApplyBotMatchRewardResult> {
    this.ensureSchema(params.nowMs);

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const nowMs = params.nowMs ?? Date.now();
    const profile = await this.getProfile(params.uid, 0, undefined, nowMs);
    const effectiveUid = profile.uid;

    // 0. İptal / beraberlik ('void') akışı: bileti kapatır, günlük tavan dahilinde 1 enerji iade eder,
    // sayaç/seri/başarım/jeton/liderliğe dokunmaz.
    if (params.outcome === 'void') {
      if (!params.ticketId || typeof params.ticketId !== 'string' || params.ticketId.trim().length === 0) {
        throw new Error('ticket_required');
      }

      const trimmedTicketId = params.ticketId.trim();
      const ticketRows = this.ctx.storage.sql
        .exec<{
          ticket_id: string;
          match_id: string;
          issued_at: number;
          expires_at: number;
          used: number;
        }>(
          'SELECT ticket_id, match_id, issued_at, expires_at, used FROM solo_tickets WHERE ticket_id = ? LIMIT 1',
          trimmedTicketId
        )
        .toArray();

      if (ticketRows.length === 0) {
        throw new Error('ticket_invalid');
      }
      const ticket = ticketRows[0];
      if (params.matchId && ticket.match_id !== params.matchId) {
        throw new Error('ticket_invalid');
      }

      // Aynı bilet/maç daha önce 'solo_voided' olarak işlendiyse idempotent yanıt dön (ikinci kez iade etme)
      const existingVoidRows = this.ctx.storage.sql
        .exec<ProcessedMatchRow>(
          'SELECT match_id, coins_awarded, outcome FROM processed_matches WHERE match_id = ? LIMIT 1',
          ticket.match_id
        )
        .toArray();

      if (existingVoidRows.length > 0 && existingVoidRows[0].outcome === 'solo_voided') {
        const energyState = await this.getEnergyState(effectiveUid, nowMs);
        return {
          ok: true,
          counted: false,
          voided: true,
          refunded: false,
          alreadyProcessed: true,
          energy: energyState,
          unlockedAchievements: [],
        };
      }

      if (ticket.expires_at < nowMs) {
        throw new Error('ticket_expired');
      }
      if (ticket.used === 1) {
        throw new Error('ticket_already_used');
      }

      const dayKey = new Date(nowMs).toISOString().slice(0, 10);
      const voidTxResult = this.runInTransaction(() => {
        const dailyRow = this.ctx.storage.sql
          .exec<{ void_refund_count: number }>(
            'SELECT void_refund_count FROM daily_solo_matches WHERE day_key = ? LIMIT 1',
            dayKey
          )
          .toArray()[0];
        const currentVoidRefunds = dailyRow?.void_refund_count ?? 0;

        if (currentVoidRefunds >= SOLO_VOID_DAILY_REFUND_CAP) {
          // Günlük iade sınırı aşıldı: terk edilmiş bilet (solo_abandoned) gibi kapat (kayıp + seri sıfırla, jeton yok)
          const counterRes = this.closeTicketAsAbandonedInTransaction({
            ticketId: ticket.ticket_id,
            matchId: ticket.match_id,
            uid: effectiveUid,
            nowMs,
          });

          this.ctx.storage.sql.exec(`
            DELETE FROM processed_matches
            WHERE match_id NOT IN (
              SELECT match_id FROM processed_matches ORDER BY applied_at DESC LIMIT 100
            )
          `);

          return {
            counted: true,
            voided: false,
            refunded: false,
            unlockedAchievements: counterRes.unlockedAchievements,
          };
        }

        this.ctx.storage.sql.exec(
          'UPDATE solo_tickets SET used = 1 WHERE ticket_id = ?',
          ticket.ticket_id
        );

        const refundRes = this.refundEnergyInTransaction({
          matchId: ticket.match_id,
          uid: effectiveUid,
          nowMs,
          amount: 1,
        });
        const didRefund = refundRes.refunded;
        if (didRefund) {
          this.ctx.storage.sql.exec(
            `INSERT INTO daily_solo_matches (day_key, count, void_refund_count) VALUES (?, 0, 1)
             ON CONFLICT(day_key) DO UPDATE SET void_refund_count = void_refund_count + 1`,
            dayKey
          );
        }

        this.ctx.storage.sql.exec(
          `INSERT INTO processed_matches (match_id, applied_at, outcome, coins_awarded)
           VALUES (?, ?, 'solo_voided', 0)`,
          ticket.match_id,
          nowMs
        );

        this.ctx.storage.sql.exec(`
          DELETE FROM processed_matches
          WHERE match_id NOT IN (
            SELECT match_id FROM processed_matches ORDER BY applied_at DESC LIMIT 100
          )
        `);

        return {
          counted: false,
          voided: true,
          refunded: didRefund,
          unlockedAchievements: [] as readonly string[],
        };
      });

      const energyState = await this.getEnergyState(effectiveUid, nowMs);
      return {
        ok: true,
        counted: voidTxResult.counted,
        voided: voidTxResult.voided,
        refunded: voidTxResult.refunded,
        energy: energyState,
        unlockedAchievements: voidTxResult.unlockedAchievements,
      };
    }

    if (!params.matchId) {
      throw new Error('bad_request');
    }
    const matchId = params.matchId;

    // 1. İdempotency kontrolü: Bu matchId zaten işlendi mi?
    // Not: Normal tamamlanmış bir maç tekrar gelirse 200 idempotent yanıt dönülür.
    // Terk edilmiş (solo_abandoned) veya iptal edilmiş (solo_voided) biletler ise geçerli sonuç olarak kabul edilmez.
    const existingMatchCursor = this.ctx.storage.sql.exec<ProcessedMatchRow>(
      'SELECT match_id, coins_awarded, outcome FROM processed_matches WHERE match_id = ? LIMIT 1',
      matchId
    );
    const existingMatches = existingMatchCursor.toArray();

    if (
      existingMatches.length > 0 &&
      existingMatches[0].outcome !== 'solo_abandoned' &&
      existingMatches[0].outcome !== 'solo_voided'
    ) {
      const unlockedRows = this.ctx.storage.sql
        .exec<{ id: string }>(
          "SELECT id FROM user_achievements WHERE match_id = ? AND match_id != 'backfill' ORDER BY rowid ASC",
          matchId
        )
        .toArray();

      const energyState = await this.getEnergyState(effectiveUid, nowMs);
      return {
        ok: true,
        counted: true,
        alreadyProcessed: true,
        coinsAwarded: existingMatches[0].coins_awarded,
        coins: profile.coins,
        energy: energyState,
        unlockedAchievements: unlockedRows.map((r) => r.id),
      };
    }

    // 2. Bilet doğrulaması: Var, bu kullanıcıya ait, match_id eşleşiyor, used=0, süresi dolmamış
    if (!params.ticketId || typeof params.ticketId !== 'string') {
      throw new Error('ticket_required');
    }
    const ticketRows = this.ctx.storage.sql
      .exec<{
        ticket_id: string;
        match_id: string;
        issued_at: number;
        expires_at: number;
        used: number;
      }>(
        'SELECT ticket_id, match_id, issued_at, expires_at, used FROM solo_tickets WHERE ticket_id = ? LIMIT 1',
        params.ticketId.trim()
      )
      .toArray();

    if (ticketRows.length === 0) {
      throw new Error('ticket_invalid');
    }
    const ticket = ticketRows[0];
    if (ticket.expires_at < nowMs) {
      throw new Error('ticket_expired');
    }
    if (ticket.used === 1) {
      throw new Error('ticket_already_used');
    }
    if (ticket.match_id !== matchId) {
      throw new Error('ticket_invalid');
    }

    // 3. Galibiyette sunucu saatine göre minimum süre kontrolü (MIN_SOLO_WIN_SECONDS = 20)
    // Çok hızlı galibiyet 400 ile reddedilir ve bilet kullanılmamış (used=0) kalır.
    if (params.outcome === 'win') {
      const elapsedSeconds = Math.floor((nowMs - ticket.issued_at) / 1000);
      if (elapsedSeconds < MIN_SOLO_WIN_SECONDS) {
        throw new Error('match_too_fast');
      }
    }

    // 4. Günlük güvenlik tavanı kontrolü (SOLO_DAILY_SAFETY_CAP = 1000)
    const dayKey = new Date(nowMs).toISOString().slice(0, 10);
    const safetyCursor = this.ctx.storage.sql.exec<{ count: number }>(
      'SELECT count FROM daily_solo_matches WHERE day_key = ? LIMIT 1',
      dayKey
    );
    const safetyRows = safetyCursor.toArray();
    const todaySoloCount = safetyRows.length > 0 ? safetyRows[0].count : 0;

    if (todaySoloCount >= SOLO_DAILY_SAFETY_CAP) {
      this.ctx.storage.sql.exec(
        'UPDATE solo_tickets SET used = 1 WHERE ticket_id = ?',
        ticket.ticket_id
      );
      const energyState = await this.getEnergyState(effectiveUid, nowMs);
      return {
        ok: true,
        counted: false,
        coinsAwarded: 0,
        coins: profile.coins,
        energy: energyState,
        unlockedAchievements: [],
      };
    }

    // 5. Jeton hesaplama (online ile aynı ortak sayaç ve günlük tavan)
    const { actualCoinsAwarded } = this.calculateMatchCoins(params.outcome, nowMs);

    const isWin = params.outcome === 'win';
    const isLoss = params.outcome === 'loss';
    const correctCount = Math.max(0, params.correctAnswers ?? 0);

    // 6. Atomik SQLite işlemi (bileti used=1 yap, sayaçları artır, processed_matches en sonda)
    // NOT: Enerji bilet verilirken düşüldüğü için tekrar düşülmez!
    const counterRes = this.runInTransaction(() => {
      this.ctx.storage.sql.exec(
        'UPDATE solo_tickets SET used = 1 WHERE ticket_id = ?',
        ticket.ticket_id
      );

      this.ctx.storage.sql.exec(
        `INSERT INTO daily_coins (day_key, earned) VALUES (?, ?)
         ON CONFLICT(day_key) DO UPDATE SET earned = earned + ?`,
        dayKey,
        actualCoinsAwarded,
        actualCoinsAwarded
      );

      this.ctx.storage.sql.exec(
        'UPDATE profiles SET coins = coins + ? WHERE uid = ?',
        actualCoinsAwarded,
        effectiveUid
      );

      this.ctx.storage.sql.exec(
        `UPDATE profiles
         SET played_solo = played_solo + 1,
             won_solo = won_solo + ?
         WHERE uid = ?`,
        isWin ? 1 : 0,
        effectiveUid
      );

      this.ctx.storage.sql.exec(
        `INSERT INTO daily_solo_matches (day_key, count) VALUES (?, 1)
         ON CONFLICT(day_key) DO UPDATE SET count = count + 1`,
        dayKey
      );

      const res = this.applyResultToCounters({
        matchId,
        isWin,
        isLoss,
        source: 'solo',
        correctCount,
        nowMs,
      });

      this.ctx.storage.sql.exec(
        `INSERT INTO processed_matches (match_id, applied_at, outcome, coins_awarded)
         VALUES (?, ?, ?, ?)`,
        matchId,
        nowMs,
        params.outcome,
        actualCoinsAwarded
      );

      this.ctx.storage.sql.exec(`
        DELETE FROM processed_matches
        WHERE match_id NOT IN (
          SELECT match_id FROM processed_matches ORDER BY applied_at DESC LIMIT 100
        )
      `);

      return res;
    });

    const updatedProfile = await this.getProfile(effectiveUid);
    const energyState = await this.getEnergyState(effectiveUid, nowMs);

    return {
      ok: true,
      counted: true,
      coinsAwarded: actualCoinsAwarded,
      coins: updatedProfile.coins,
      energy: energyState,
      unlockedAchievements: counterRes.unlockedAchievements,
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
      'SELECT id, blocked_uid, blocked_nickname, blocked_at FROM blocked_users ORDER BY blocked_at DESC'
    ).toArray();

    return rows.map((r) => ({
      id: r.id,
      nickname: resolveDisplayName({
        nickname: r.blocked_nickname,
        uid: r.blocked_uid,
      }),
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
   * İstek yapan kullanıcının verilen UID'yi engelleyip engellemediğini ve varsa blok UUID'sini döner.
   */
  async getBlockInfoForUid(blockedUid: string): Promise<{ isBlocked: boolean; blockId: string | null }> {
    this.ensureSchema();

    if (this.isDeleted()) {
      return { isBlocked: false, blockId: null };
    }

    const rows = this.ctx.storage.sql.exec<{ id: string }>(
      'SELECT id FROM blocked_users WHERE blocked_uid = ? LIMIT 1',
      blockedUid
    ).toArray();

    if (rows.length > 0) {
      return { isBlocked: true, blockId: rows[0].id };
    }

    return { isBlocked: false, blockId: null };
  }

  /**
   * UID bazında engeli kaldırır. İdempotenttir; kullanıcı engelli değilse de hata vermez.
   */
  async unblockUserByUid(blockedUid: string): Promise<{ ok: true }> {
    this.ensureSchema();

    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    this.ctx.storage.sql.exec(
      'DELETE FROM blocked_users WHERE blocked_uid = ?',
      blockedUid
    );

    return { ok: true };
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

    return this.runInTransaction(() => {
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

  private refundEnergyInTransaction(params: {
    readonly matchId: string;
    readonly uid: string;
    readonly nowMs: number;
    readonly amount?: number;
  }): RefundEnergyResult {
    const existing = this.ctx.storage.sql
      .exec<{ amount: number; refunded_at: number | null }>(
        'SELECT amount, refunded_at FROM energy_spends WHERE match_id = ? AND uid = ? LIMIT 1',
        params.matchId,
        params.uid
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
      params.nowMs,
      maxEnergy,
      regenMinutes
    );

    if (existing.length === 0 || existing[0].refunded_at !== null) {
      return { ok: true, refunded: false, energy: regen.current };
    }

    const refundAmount = existing[0].amount ?? params.amount ?? 1;

    this.ctx.storage.sql.exec(
      'UPDATE energy_spends SET refunded_at = ? WHERE match_id = ? AND uid = ?',
      params.nowMs,
      params.matchId,
      params.uid
    );

    const newEnergy = Math.min(maxEnergy, regen.current + refundAmount);
    const newUpdatedAtMs = newEnergy >= maxEnergy ? params.nowMs : regen.updatedAtMs;

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

    return this.runInTransaction(() =>
      this.refundEnergyInTransaction({
        matchId: params.matchId,
        uid: effectiveUid,
        nowMs,
        amount: params.amount,
      })
    );
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
   * Güvenli WebSocket listesi döndürücü (ctx.getWebSockets yoksa veya test mock'larında boş dizi)
   */
  getWebSocketsSafe(tag?: string): WebSocket[] {
    if (typeof this.ctx?.getWebSockets === 'function') {
      return this.ctx.getWebSockets(tag) as WebSocket[];
    }
    return [];
  }

  isOnline(): boolean {
    return this.getWebSocketsSafe().length > 0;
  }

  isBlocked(targetUid: string): boolean {
    this.ensureSchema();
    const rows = this.ctx.storage.sql
      .exec<{ id: string }>(
        'SELECT id FROM blocked_users WHERE blocked_uid = ? LIMIT 1',
        targetUid
      )
      .toArray();
    return rows.length > 0;
  }

  getEffectiveUid(): string {
    try {
      const idObj = (this.ctx as any)?.id;
      if (idObj?.name && typeof idObj.name === 'string') {
        return idObj.name;
      }
    } catch {}
    const rows = this.ctx.storage.sql
      .exec<{ uid: string }>('SELECT uid FROM profiles LIMIT 1')
      .toArray();
    return rows.length > 0 ? rows[0].uid : 'unknown';
  }

  async scheduleNextAlarm(nowMs = Date.now()): Promise<void> {
    if (typeof this.ctx.storage.setAlarm !== 'function') return;

    const dueTimes: number[] = [];

    const tombstone = this.ctx.storage.sql
      .exec<{ deleted_at: number }>('SELECT deleted_at FROM tombstone LIMIT 1')
      .toArray();
    if (tombstone.length > 0) {
      const tombstoneDue = tombstone[0].deleted_at + 24 * 60 * 60 * 1000;
      dueTimes.push(tombstoneDue);
    }

    const incExp = this.ctx.storage.sql
      .exec<{ min_exp: number | null }>(
        "SELECT MIN(expires_at) as min_exp FROM incoming_requests WHERE status = 'pending'"
      )
      .toArray();
    if (incExp.length > 0 && typeof incExp[0].min_exp === 'number' && incExp[0].min_exp > 0) {
      dueTimes.push(incExp[0].min_exp);
    }

    const outExp = this.ctx.storage.sql
      .exec<{ min_exp: number | null }>(
        "SELECT MIN(expires_at) as min_exp FROM outgoing_requests WHERE status = 'pending'"
      )
      .toArray();
    if (outExp.length > 0 && typeof outExp[0].min_exp === 'number' && outExp[0].min_exp > 0) {
      dueTimes.push(outExp[0].min_exp);
    }

    if (dueTimes.length === 0) {
      if (typeof this.ctx.storage.deleteAlarm === 'function') {
        try {
          await this.ctx.storage.deleteAlarm();
        } catch {}
      }
      return;
    }

    const nextAlarm = Math.min(...dueTimes);
    await this.ctx.storage.setAlarm(nextAlarm);
  }

  async expirePendingIncomingRequests(nowMs = Date.now()): Promise<void> {
    const expired = this.ctx.storage.sql
      .exec<{
        id: string;
        from_uid: string;
      }>(
        "SELECT id, from_uid FROM incoming_requests WHERE status = 'pending' AND expires_at <= ?",
        nowMs
      )
      .toArray();

    for (const item of expired) {
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'expired' WHERE id = ?",
        item.id
      );
      this.broadcastToUser({ t: 'match_request_status', id: item.id, status: 'expired' });
      if (this.env.USER_PROFILE) {
        try {
          const senderStub = this.env.USER_PROFILE.get(
            this.env.USER_PROFILE.idFromName(item.from_uid)
          );
          await senderStub.notifyExpired(item.id, this.getEffectiveUid());
        } catch {}
      }
    }
  }

  async expirePendingOutgoingRequests(nowMs = Date.now()): Promise<void> {
    const expired = this.ctx.storage.sql
      .exec<{
        id: string;
        to_uid: string;
      }>(
        "SELECT id, to_uid FROM outgoing_requests WHERE status = 'pending' AND expires_at <= ?",
        nowMs
      )
      .toArray();

    for (const item of expired) {
      this.ctx.storage.sql.exec(
        "UPDATE outgoing_requests SET status = 'expired' WHERE id = ?",
        item.id
      );
      this.ctx.storage.sql.exec(
        'INSERT OR REPLACE INTO match_request_cooldowns (target_uid, cooldown_until) VALUES (?, ?)',
        item.to_uid,
        nowMs + 45_000
      );
      this.broadcastToUser({ t: 'match_request_status', id: item.id, status: 'expired' });
      if (this.env.USER_PROFILE) {
        try {
          const targetStub = this.env.USER_PROFILE.get(
            this.env.USER_PROFILE.idFromName(item.to_uid)
          );
          await targetStub.notifyExpired(item.id, this.getEffectiveUid());
        } catch {}
      }
    }
  }

  async notifyExpired(requestId: string, _otherUid: string): Promise<void> {
    this.ensureSchema();
    const nowMs = Date.now();
    const out = this.ctx.storage.sql
      .exec<{ id: string; to_uid: string; status: string }>(
        'SELECT id, to_uid, status FROM outgoing_requests WHERE id = ? LIMIT 1',
        requestId
      )
      .toArray();
    if (out.length > 0 && out[0].status === 'pending') {
      this.ctx.storage.sql.exec(
        "UPDATE outgoing_requests SET status = 'expired' WHERE id = ?",
        requestId
      );
      this.ctx.storage.sql.exec(
        'INSERT OR REPLACE INTO match_request_cooldowns (target_uid, cooldown_until) VALUES (?, ?)',
        out[0].to_uid,
        nowMs + 45_000
      );
      this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'expired' });
    }

    const inc = this.ctx.storage.sql
      .exec<{ id: string; status: string }>(
        'SELECT id, status FROM incoming_requests WHERE id = ? LIMIT 1',
        requestId
      )
      .toArray();
    if (inc.length > 0 && inc[0].status === 'pending') {
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'expired' WHERE id = ?",
        requestId
      );
      this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'expired' });
    }
  }

  async notifyDeclined(requestId: string, receiverUid: string): Promise<void> {
    this.ensureSchema();
    const now = Date.now();
    this.ctx.storage.sql.exec(
      "UPDATE outgoing_requests SET status = 'declined' WHERE id = ?",
      requestId
    );
    this.ctx.storage.sql.exec(
      'INSERT OR REPLACE INTO match_request_cooldowns (target_uid, cooldown_until) VALUES (?, ?)',
      receiverUid,
      now + 45_000
    );
    this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'declined' });
  }

  async notifyCancelled(requestId: string): Promise<void> {
    this.ensureSchema();
    const inc = this.ctx.storage.sql
      .exec<{ id: string; status: string }>(
        'SELECT id, status FROM incoming_requests WHERE id = ? LIMIT 1',
        requestId
      )
      .toArray();
    if (inc.length > 0 && inc[0].status === 'pending') {
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'cancelled' WHERE id = ?",
        requestId
      );
      this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'cancelled' });
    }
  }

  async notifyMatched(params: {
    matchId: string;
    opponentName: string;
    opponentFrame: string;
    opponentUid: string;
    isFriendly: boolean;
  }): Promise<void> {
    this.ensureSchema();
    this.broadcastToUser({
      t: 'matched',
      matchId: params.matchId,
      opponentName: params.opponentName,
      opponentFrame: params.opponentFrame,
      opponentUid: params.opponentUid,
      isFriendly: params.isFriendly,
    });
  }

  async notifyCrossMatched(params: {
    matchId: string;
    opponentName: string;
    opponentFrame: string;
    opponentUid: string;
    isFriendly: boolean;
    crossRequestId: string;
  }): Promise<void> {
    this.ensureSchema();
    this.ctx.storage.sql.exec(
      "UPDATE outgoing_requests SET status = 'accepted' WHERE id = ?",
      params.crossRequestId
    );
    this.broadcastToUser({
      t: 'matched',
      matchId: params.matchId,
      opponentName: params.opponentName,
      opponentFrame: params.opponentFrame,
      opponentUid: params.opponentUid,
      isFriendly: params.isFriendly,
    });
  }

  async notifyMatchError(
    requestId: string,
    code:
      | 'unavailable'
      | 'cooldown_active'
      | 'rate_limited'
      | 'invalid'
      | 'no_energy'
      | 'opponent_no_energy'
  ): Promise<void> {
    this.ensureSchema();
    this.ctx.storage.sql.exec(
      "UPDATE outgoing_requests SET status = 'cancelled' WHERE id = ?",
      requestId
    );
    this.ctx.storage.sql.exec(
      "UPDATE incoming_requests SET status = 'cancelled' WHERE id = ?",
      requestId
    );
    this.broadcastToUser({ t: 'match_request_error', code });
  }

  async updateSettings(settings: {
    allowMatchRequests?: boolean;
    uid?: string;
  }): Promise<{ allowMatchRequests: boolean }> {
    this.ensureSchema();
    if (this.isDeleted()) {
      throw new Error('account_deleted');
    }

    const existing = this.ctx.storage.sql
      .exec<{ uid: string }>('SELECT uid FROM profiles LIMIT 1')
      .toArray();
    if (existing.length === 0) {
      await this.getProfile(settings.uid);
    }

    if (typeof settings.allowMatchRequests === 'boolean') {
      const val = settings.allowMatchRequests ? 1 : 0;
      this.ctx.storage.sql.exec(
        'UPDATE profiles SET allow_match_requests = ?',
        val
      );
    }

    const rows = this.ctx.storage.sql
      .exec<{ allow_match_requests: number }>(
        'SELECT allow_match_requests FROM profiles LIMIT 1'
      )
      .toArray();
    const allow = rows.length > 0 ? rows[0].allow_match_requests !== 0 : true;

    return { allowMatchRequests: allow };
  }

  async isMatchRequestsAllowed(): Promise<boolean> {
    this.ensureSchema();
    const profile = this.ctx.storage.sql
      .exec<{ allow_match_requests: number }>(
        'SELECT allow_match_requests FROM profiles LIMIT 1'
      )
      .toArray();
    return profile.length > 0 ? profile[0].allow_match_requests !== 0 : true;
  }

  async isBusy(): Promise<boolean> {
    this.ensureSchema();
    const presence = this.ctx.storage.sql
      .exec<{ state: string }>(
        "SELECT state FROM user_presence WHERE key = 'current' LIMIT 1"
      )
      .toArray();
    return presence.length > 0 && presence[0].state === 'busy';
  }

  async hasPendingIncoming(nowMs = Date.now()): Promise<boolean> {
    this.ensureSchema();
    const rows = this.ctx.storage.sql
      .exec<{ id: string }>(
        "SELECT id FROM incoming_requests WHERE status = 'pending' AND expires_at > ? LIMIT 1",
        nowMs
      )
      .toArray();
    return rows.length > 0;
  }

  async checkMatchRequestAvailability(
    senderUid: string
  ): Promise<{ ok: boolean; reason?: string }> {
    this.ensureSchema();
    if (this.isDeleted()) return { ok: false, reason: 'account_deleted' };

    // 1. Engel: Alıcı göndereni engellemiş mi?
    if (this.isBlocked(senderUid)) {
      return { ok: false, reason: 'blocked' };
    }

    // 2. Ayar: allow_match_requests açık olmalı (1) - Çevrimiçi durumunu sızdırmamak için offline'dan önce kontrol edilir
    const profile = this.ctx.storage.sql
      .exec<{ allow_match_requests: number }>(
        'SELECT allow_match_requests FROM profiles LIMIT 1'
      )
      .toArray();
    if (profile.length > 0 && profile[0].allow_match_requests === 0) {
      return { ok: false, reason: 'settings_off' };
    }

    // 3. En az bir aktif soket bağlı olmalı (ön planda olmalı)
    if (!this.isOnline()) return { ok: false, reason: 'offline' };

    // 4. Durum: 'busy' olmamalı
    const presence = this.ctx.storage.sql
      .exec<{ state: string }>(
        "SELECT state FROM user_presence WHERE key = 'current' LIMIT 1"
      )
      .toArray();
    if (presence.length > 0 && presence[0].state === 'busy') {
      return { ok: false, reason: 'busy' };
    }

    // 5. Zaten bekleyen bir gelen istek olmamalı
    const now = Date.now();
    const activeIncoming = this.ctx.storage.sql
      .exec<{ id: string }>(
        "SELECT id FROM incoming_requests WHERE status = 'pending' AND expires_at > ? LIMIT 1",
        now
      )
      .toArray();
    if (activeIncoming.length > 0) {
      return { ok: false, reason: 'incoming_pending' };
    }

    return { ok: true };
  }

  async isAvailableForMatchRequest(senderUid: string): Promise<boolean> {
    return (await this.checkMatchRequestAvailability(senderUid)).ok;
  }

  async handleClientSendMatchRequest(
    senderUid: string,
    origin: 'rematch' | 'profile',
    toUid: string,
    matchId?: string
  ): Promise<void> {
    this.ensureSchema();
    if (this.isDeleted()) {
      try {
        this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      } catch {}
      return;
    }

    const now = Date.now();

    // 1. Kendine istek -> invalid
    if (senderUid === toUid) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'self',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'invalid' });
      return;
    }

    if (!this.env.USER_PROFILE) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'user_profile_binding_missing',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      return;
    }

    const targetStub = this.env.USER_PROFILE.get(this.env.USER_PROFILE.idFromName(toUid));

    // 2. Gönderen veya alıcı birbirini engellemiş VEYA alıcı hesabı silinmiş -> "offline"
    // (engel asla sızmasın; engelli gönderen, alıcı çevrimiçi olsa bile aynen çevrimdışı kullanıcı gibi görür)
    if (await targetStub.isDeleted()) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'account_deleted',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'offline' });
      return;
    }

    if (this.isBlocked(toUid) || (await targetStub.isBlocked(senderUid))) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'blocked',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'offline' });
      return;
    }

    // 3. Alıcının allow_match_requests kapalı -> "requests_disabled"
    // (çevrimdışı kontrolünden ÖNCE: ayar çevrimiçi durumunu sızdırmasın)
    const isTargetAllowed = await targetStub.isMatchRequestsAllowed();
    if (!isTargetAllowed) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'settings_off',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'requests_disabled' });
      return;
    }

    // 4. Alıcının açık soketi yok -> "offline"
    const isTargetOnline = await targetStub.isOnline();
    if (!isTargetOnline) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'offline',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'offline' });
      return;
    }

    // 5. Alıcı busy veya zaten bekleyen gelen isteği var -> "unavailable"
    const isTargetBusy = await targetStub.isBusy();
    if (isTargetBusy) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'busy',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      return;
    }

    const targetHasPendingIncoming = await targetStub.hasPendingIncoming(now);
    if (targetHasPendingIncoming) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'incoming_pending',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      return;
    }

    // 6. Gönderenin cooldown'u / rate limit'i / bekleyen giden isteği (mevcut sıra ve kodlar korunur)
    // 6a) Cooldown
    const cooldownRow = this.ctx.storage.sql
      .exec<{ cooldown_until: number }>(
        'SELECT cooldown_until FROM match_request_cooldowns WHERE target_uid = ? LIMIT 1',
        toUid
      )
      .toArray();
    if (cooldownRow.length > 0 && cooldownRow[0].cooldown_until > now) {
      const retryAfterSec = Math.max(
        1,
        Math.ceil((cooldownRow[0].cooldown_until - now) / 1000)
      );
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'cooldown',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'cooldown_active', retryAfterSec });
      return;
    }

    // 6b) Rate limit (dakikada en fazla 3 istek)
    this.ctx.storage.sql.exec(
      'DELETE FROM match_request_rate_limits WHERE created_at <= ?',
      now - 60_000
    );
    const countRow = this.ctx.storage.sql
      .exec<{ cnt: number }>(
        'SELECT COUNT(*) as cnt FROM match_request_rate_limits WHERE created_at > ?',
        now - 60_000
      )
      .toArray()[0];
    if (countRow && countRow.cnt >= 3) {
      const oldestRow = this.ctx.storage.sql
        .exec<{ oldest: number }>(
          'SELECT MIN(created_at) as oldest FROM match_request_rate_limits WHERE created_at > ?',
          now - 60_000
        )
        .toArray()[0];
      const retryAfterSec = Math.max(
        1,
        Math.ceil(((oldestRow?.oldest ?? now) + 60_000 - now) / 1000)
      );
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'rate_limited',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'rate_limited', retryAfterSec });
      return;
    }

    // 6c) Gönderenin bekleyen giden isteği
    const activeOut = this.ctx.storage.sql
      .exec<{ id: string }>(
        "SELECT id FROM outgoing_requests WHERE status = 'pending' AND expires_at > ? LIMIT 1",
        now
      )
      .toArray();
    if (activeOut.length > 0) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'outgoing_pending',
          origin,
          matchId,
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      return;
    }

    // 7. Karşılıklı istek (hedef zaten bize istek atmış mı? Varsa doğrudan o isteği kabul et)
    const pendingIncomingFromTarget = this.ctx.storage.sql
      .exec<{ id: string }>(
        "SELECT id FROM incoming_requests WHERE from_uid = ? AND status = 'pending' AND expires_at > ? LIMIT 1",
        toUid,
        now
      )
      .toArray();
    if (pendingIncomingFromTarget.length > 0) {
      await this.handleClientAcceptMatchRequest(senderUid, pendingIncomingFromTarget[0].id);
      return;
    }

    // 8. Rematch ise MatchRoom doğrulaması
    let matchType: 'friendly' | 'ranked' = 'friendly';
    if (origin === 'rematch') {
      if (!matchId) {
        this.broadcastToUser({ t: 'match_request_error', code: 'invalid' });
        return;
      }
      if (!this.env.MATCH_ROOM) {
        console.warn(
          JSON.stringify({
            event: 'match_request_rejected',
            reason: 'room_binding_missing',
            origin,
            matchId,
          })
        );
        this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
        return;
      }
      try {
        const roomStub = this.env.MATCH_ROOM.get(this.env.MATCH_ROOM.idFromName(matchId));
        const val = await roomStub.validateRematchRequest(senderUid, toUid);
        if (!val.ok) {
          console.warn(
            JSON.stringify({
              event: 'match_request_rejected',
              reason: val.error ?? 'room_validation_failed',
              origin,
              matchId,
            })
          );
          this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
          return;
        }
        matchType = val.matchType ?? 'ranked';
      } catch (err) {
        console.warn(
          JSON.stringify({
            event: 'match_request_rejected',
            reason: 'room_exception',
            origin,
            matchId,
            err: err instanceof Error ? err.message : String(err),
          })
        );
        this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
        return;
      }
    }

    // 9. Gönderenin profil bilgileri
    const myProfile = await this.getProfile(senderUid);
    const senderNickname = resolveDisplayName({
      nickname: myProfile.nickname,
      uid: senderUid,
      isGuest: myProfile.isGuest,
    });
    const senderFrame = myProfile.equippedFrame ?? 'classic';

    // 10. Alıcı DO'suna ilet
    try {
      const res = await targetStub.receiveMatchRequest({
        senderUid,
        senderNickname,
        senderFrame,
        type: matchType,
        origin,
        matchId,
      });

      if (!res.ok) {
        console.warn(
          JSON.stringify({
            event: 'match_request_rejected',
            reason: res.reason ?? 'target_rejected',
            origin,
            matchId,
          })
        );
        let errorCode: 'offline' | 'requests_disabled' | 'unavailable' = 'unavailable';
        if (
          res.reason === 'account_deleted' ||
          res.reason === 'blocked' ||
          res.reason === 'offline'
        ) {
          errorCode = 'offline';
        } else if (res.reason === 'settings_off') {
          errorCode = 'requests_disabled';
        }
        this.broadcastToUser({ t: 'match_request_error', code: errorCode });
        return;
      }

      if (res.crossAccepted) {
        // Karşılıklı istek sonucu maç anında kuruldu
        if (origin === 'rematch' && matchId && this.env.MATCH_ROOM) {
          try {
            const roomStub = this.env.MATCH_ROOM.get(
              this.env.MATCH_ROOM.idFromName(matchId)
            );
            await roomStub.markRematchRequestCreated();
          } catch (e) {
            console.warn(
              JSON.stringify({
                event: 'mark_rematch_request_created_failed',
                reason: 'mark_rematch_exception',
                matchId,
                origin,
                err: e instanceof Error ? e.message : String(e),
              })
            );
          }
        }
        return;
      }

      // İstek alıcıya başarıyla iletildi -> Artık bu maç için rövanş hakkı işaretlenir
      if (origin === 'rematch' && matchId && this.env.MATCH_ROOM) {
        try {
          const roomStub = this.env.MATCH_ROOM.get(
            this.env.MATCH_ROOM.idFromName(matchId)
          );
          await roomStub.markRematchRequestCreated();
        } catch (e) {
          console.warn(
            JSON.stringify({
              event: 'mark_rematch_request_created_failed',
              reason: 'mark_rematch_exception',
              matchId,
              origin,
              err: e instanceof Error ? e.message : String(e),
            })
          );
        }
      }

      const requestId = res.requestId!;
      const expiresAt = res.expiresAt!;
      const toNickname = resolveDisplayName({
        nickname: res.receiverNickname,
        uid: toUid,
      });

      this.ctx.storage.sql.exec(
        'INSERT INTO match_request_rate_limits (created_at) VALUES (?)',
        now
      );

      this.ctx.storage.sql.exec(
        "INSERT OR REPLACE INTO outgoing_requests (id, to_uid, to_nickname, type, origin, match_id, created_at, expires_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')",
        requestId,
        toUid,
        toNickname,
        matchType,
        origin,
        matchId ?? null,
        now,
        expiresAt
      );

      await this.scheduleNextAlarm();

      this.broadcastToUser({
        t: 'match_request_sent',
        id: requestId,
        toUid,
        toNickname,
        type: matchType,
        origin,
        expiresAtMs: expiresAt,
      });
    } catch (err) {
      console.warn(
        JSON.stringify({
          event: 'match_request_rejected',
          reason: 'target_exception',
          origin,
          matchId,
          err: err instanceof Error ? err.message : String(err),
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
    }
  }

  async receiveMatchRequest(params: {
    senderUid: string;
    senderNickname: string;
    senderFrame: string;
    type: 'friendly' | 'ranked';
    origin: 'rematch' | 'profile';
    matchId?: string;
  }): Promise<{
    ok: boolean;
    reason?: string;
    requestId?: string;
    expiresAt?: number;
    receiverNickname?: string;
    crossAccepted?: boolean;
  }> {
    this.ensureSchema();
    if (this.isDeleted()) {
      return { ok: false, reason: 'account_deleted' };
    }

    const now = Date.now();
    const receiverUid = this.getEffectiveUid();

    // 1. Engelleme kontrolü (karşılıklı engel durumunda cross-request veya yeni istek kabul edilmez)
    if (this.isBlocked(params.senderUid)) {
      return { ok: false, reason: 'blocked' };
    }

    // 2. Ayar kontrolü (maç istekleri kapalıysa cross-request veya yeni istek kabul edilmez)
    const profile = this.ctx.storage.sql
      .exec<{ allow_match_requests: number }>(
        'SELECT allow_match_requests FROM profiles LIMIT 1'
      )
      .toArray();
    if (profile.length > 0 && profile[0].allow_match_requests === 0) {
      return { ok: false, reason: 'settings_off' };
    }

    // 3. Karşılıklı istek (cross-request) kontrolü
    const crossOutgoing = this.ctx.storage.sql
      .exec<{
        id: string;
        type: string;
        origin: string;
        match_id: string | null;
      }>(
        "SELECT id, type, origin, match_id FROM outgoing_requests WHERE to_uid = ? AND status = 'pending' AND expires_at > ? LIMIT 1",
        params.senderUid,
        now
      )
      .toArray();

    if (crossOutgoing.length > 0) {
      const crossReq = crossOutgoing[0];
      const derivedType =
        crossReq.type === 'ranked' && params.type === 'ranked'
          ? 'ranked'
          : 'friendly';

      this.ctx.storage.sql.exec(
        "UPDATE outgoing_requests SET status = 'accepted' WHERE id = ?",
        crossReq.id
      );

      const myProfile = await this.getProfile(receiverUid);
      const myNickname = resolveDisplayName({
        nickname: myProfile.nickname,
        uid: receiverUid,
        isGuest: myProfile.isGuest,
      });
      const myFrame = myProfile.equippedFrame ?? 'classic';

      if (this.env.MATCHMAKER) {
        const matchmaker = this.env.MATCHMAKER.get(
          this.env.MATCHMAKER.idFromName('global')
        );
        const createRes = await matchmaker.createDirectMatch({
          p1: {
            uid: params.senderUid,
            name: params.senderNickname,
            frame: params.senderFrame,
          },
          p2: {
            uid: receiverUid,
            name: myNickname,
            frame: myFrame,
          },
          matchType: derivedType,
          prevMatchId: params.matchId ?? crossReq.match_id ?? '',
          proposerUid: params.senderUid,
        });

        if (createRes.ok) {
          this.broadcastToUser({
            t: 'matched',
            matchId: createRes.matchId,
            opponentName: params.senderNickname,
            opponentFrame: params.senderFrame,
            opponentUid: params.senderUid,
            isFriendly: createRes.isFriendly,
          });

          if (this.env.USER_PROFILE) {
            const senderStub = this.env.USER_PROFILE.get(
              this.env.USER_PROFILE.idFromName(params.senderUid)
            );
            await senderStub.notifyMatched({
              matchId: createRes.matchId,
              opponentName: myNickname,
              opponentFrame: myFrame,
              opponentUid: receiverUid,
              isFriendly: createRes.isFriendly,
            });
          }

          return { ok: true, crossAccepted: true };
        } else {
          const errorCode =
            createRes.error === 'no_energy' || createRes.error === 'opponent_no_energy'
              ? createRes.errorTargetUid === receiverUid
                ? 'no_energy'
                : 'opponent_no_energy'
              : 'unavailable';
          this.broadcastToUser({ t: 'match_request_error', code: errorCode });
          return { ok: false, reason: 'unavailable' };
        }
      }
      return { ok: false, reason: 'unavailable' };
    }

    // 4. Normal müsaitlik kontrolü
    const avail = await this.checkMatchRequestAvailability(params.senderUid);
    if (!avail.ok) {
      return { ok: false, reason: avail.reason ?? 'unavailable' };
    }

    const requestId = crypto.randomUUID();
    const expiresAt = now + 45_000;

    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO incoming_requests (id, from_uid, from_nickname, from_frame, type, origin, match_id, created_at, expires_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')",
      requestId,
      params.senderUid,
      params.senderNickname,
      params.senderFrame,
      params.type,
      params.origin,
      params.matchId ?? null,
      now,
      expiresAt
    );

    await this.scheduleNextAlarm();

    this.broadcastToUser({
      t: 'match_request_received',
      id: requestId,
      fromUid: params.senderUid,
      fromNickname: params.senderNickname,
      fromFrame: params.senderFrame,
      type: params.type,
      origin: params.origin,
      expiresAtMs: expiresAt,
    });

    const myProfile = await this.getProfile(receiverUid);
    const myNickname = resolveDisplayName({
      nickname: myProfile.nickname,
      uid: receiverUid,
      isGuest: myProfile.isGuest,
    });

    return {
      ok: true,
      requestId,
      expiresAt,
      receiverNickname: myNickname,
    };
  }

  async handleClientAcceptMatchRequest(
    receiverUid: string,
    requestId: string
  ): Promise<void> {
    const now = Date.now();
    const row = this.ctx.storage.sql
      .exec<{
        id: string;
        from_uid: string;
        from_nickname: string;
        from_frame: string;
        type: 'friendly' | 'ranked';
        origin: 'rematch' | 'profile';
        match_id: string | null;
        expires_at: number;
        status: string;
      }>(
        'SELECT id, from_uid, from_nickname, from_frame, type, origin, match_id, expires_at, status FROM incoming_requests WHERE id = ? LIMIT 1',
        requestId
      )
      .toArray();

    if (row.length === 0) {
      this.broadcastToUser({ t: 'match_request_error', code: 'invalid' });
      return;
    }
    const inc = row[0];

    if (inc.status !== 'pending') return;
    if (now >= inc.expires_at) {
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'expired' WHERE id = ?",
        requestId
      );
      this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'expired' });
      return;
    }

    // Atomik geçiş: Yalnızca ilk kabul isteği 'accepted' yapabilir, ikinci kabul sessizce çıkar
    this.ctx.storage.sql.exec(
      "UPDATE incoming_requests SET status = 'accepted' WHERE id = ? AND status = 'pending'",
      requestId
    );
    const changes = this.ctx.storage.sql.exec<{ c: number }>('SELECT changes() as c').toArray()[0]?.c;
    if (!changes || changes === 0) {
      return;
    }

    if (!this.env.USER_PROFILE) {
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'cancelled' WHERE id = ?",
        requestId
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      return;
    }

    const senderStub = this.env.USER_PROFILE.get(
      this.env.USER_PROFILE.idFromName(inc.from_uid)
    );
    let verifyRes;
    try {
      verifyRes = await senderStub.verifySenderForAccept(requestId, receiverUid);
    } catch (err) {
      console.warn(
        JSON.stringify({
          event: 'match_request_accept_failed',
          reason: 'sender_exception',
          requestId,
          err: err instanceof Error ? err.message : String(err),
        })
      );
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'cancelled' WHERE id = ?",
        requestId
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'cancelled' });
      return;
    }
    if (!verifyRes.ok) {
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'cancelled' WHERE id = ?",
        requestId
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'cancelled' });
      return;
    }

    const senderInfo = verifyRes.sender!;
    const myProfile = await this.getProfile(receiverUid);
    const myNickname = resolveDisplayName({
      nickname: myProfile.nickname,
      uid: receiverUid,
      isGuest: myProfile.isGuest,
    });
    const myFrame = myProfile.equippedFrame ?? 'classic';

    if (!this.env.MATCHMAKER) {
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      return;
    }

    const matchmaker = this.env.MATCHMAKER.get(
      this.env.MATCHMAKER.idFromName('global')
    );
    let createRes;
    try {
      createRes = await matchmaker.createDirectMatch({
        p1: { uid: senderInfo.uid, name: senderInfo.nickname, frame: senderInfo.frame },
        p2: { uid: receiverUid, name: myNickname, frame: myFrame },
        matchType: inc.type,
        prevMatchId: inc.match_id ?? '',
        proposerUid: senderInfo.uid,
      });
    } catch (err) {
      console.warn(
        JSON.stringify({
          event: 'match_request_accept_failed',
          reason: 'matchmaker_exception',
          requestId,
          err: err instanceof Error ? err.message : String(err),
        })
      );
      this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
      return;
    }

    if (createRes.ok) {
      this.ctx.storage.sql.exec(
        "UPDATE incoming_requests SET status = 'accepted' WHERE id = ?",
        requestId
      );

      this.broadcastToUser({
        t: 'matched',
        matchId: createRes.matchId,
        opponentName: senderInfo.nickname,
        opponentFrame: senderInfo.frame,
        opponentUid: senderInfo.uid,
        isFriendly: createRes.isFriendly,
      });

      try {
        await senderStub.notifyMatched({
          matchId: createRes.matchId,
          opponentName: myNickname,
          opponentFrame: myFrame,
          opponentUid: receiverUid,
          isFriendly: createRes.isFriendly,
        });
      } catch (err) {
        console.warn(
          JSON.stringify({
            event: 'match_request_notify_failed',
            reason: 'notify_matched_exception',
            requestId,
            err: err instanceof Error ? err.message : String(err),
          })
        );
      }
    } else {
      if (createRes.error === 'no_energy' || createRes.error === 'opponent_no_energy') {
        const isMyEnergyShortage = createRes.errorTargetUid === receiverUid;
        const myErrorCode = isMyEnergyShortage ? 'no_energy' : 'opponent_no_energy';
        const senderErrorCode = isMyEnergyShortage ? 'opponent_no_energy' : 'no_energy';

        this.broadcastToUser({ t: 'match_request_error', code: myErrorCode });
        try {
          await senderStub.notifyMatchError(requestId, senderErrorCode);
        } catch (err) {
          console.warn(
            JSON.stringify({
              event: 'match_request_notify_failed',
              reason: 'notify_match_error_exception',
              requestId,
              err: err instanceof Error ? err.message : String(err),
            })
          );
        }
      } else {
        this.broadcastToUser({ t: 'match_request_error', code: 'unavailable' });
        try {
          await senderStub.notifyMatchError(requestId, 'unavailable');
        } catch (err) {
          console.warn(
            JSON.stringify({
              event: 'match_request_notify_failed',
              reason: 'notify_match_error_exception',
              requestId,
              err: err instanceof Error ? err.message : String(err),
            })
          );
        }
      }
    }
  }

  async verifySenderForAccept(
    requestId: string,
    receiverUid: string
  ): Promise<{
    ok: boolean;
    reason?: string;
    sender?: { uid: string; nickname: string; frame: string };
  }> {
    this.ensureSchema();
    if (this.isDeleted()) {
      return { ok: false, reason: 'unavailable' };
    }

    if (!this.isOnline()) {
      return { ok: false, reason: 'unavailable' };
    }

    if (this.isBlocked(receiverUid)) {
      return { ok: false, reason: 'unavailable' };
    }

    const prof = this.ctx.storage.sql
      .exec<{ allow_match_requests: number }>(
        'SELECT allow_match_requests FROM profiles LIMIT 1'
      )
      .toArray();
    if (prof.length > 0 && prof[0].allow_match_requests === 0) {
      return { ok: false, reason: 'unavailable' };
    }

    const presence = this.ctx.storage.sql
      .exec<{ state: string }>(
        "SELECT state FROM user_presence WHERE key = 'current' LIMIT 1"
      )
      .toArray();
    if (presence.length > 0 && presence[0].state === 'busy') {
      this.ctx.storage.sql.exec(
        "UPDATE outgoing_requests SET status = 'cancelled' WHERE id = ?",
        requestId
      );
      this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'cancelled' });
      return { ok: false, reason: 'busy' };
    }

    const now = Date.now();
    const row = this.ctx.storage.sql
      .exec<{
        id: string;
        to_uid: string;
        status: string;
        expires_at: number;
      }>(
        'SELECT id, to_uid, status, expires_at FROM outgoing_requests WHERE id = ? LIMIT 1',
        requestId
      )
      .toArray();

    if (row.length === 0) {
      return { ok: false, reason: 'cancelled' };
    }

    const out = row[0];
    if (out.status !== 'pending' || out.to_uid !== receiverUid || now >= out.expires_at) {
      return { ok: false, reason: out.status === 'cancelled' ? 'cancelled' : 'unavailable' };
    }

    this.ctx.storage.sql.exec(
      "UPDATE outgoing_requests SET status = 'accepted' WHERE id = ?",
      requestId
    );

    const senderUid = this.getEffectiveUid();
    const profile = await this.getProfile(senderUid);

    return {
      ok: true,
      sender: {
        uid: senderUid,
        nickname: resolveDisplayName({
          nickname: profile.nickname,
          uid: senderUid,
          isGuest: profile.isGuest,
        }),
        frame: profile.equippedFrame ?? 'classic',
      },
    };
  }

  async handleClientDeclineMatchRequest(
    _receiverUid: string,
    requestId: string
  ): Promise<void> {
    const row = this.ctx.storage.sql
      .exec<{
        id: string;
        from_uid: string;
        status: string;
      }>(
        'SELECT id, from_uid, status FROM incoming_requests WHERE id = ? LIMIT 1',
        requestId
      )
      .toArray();

    if (row.length === 0) {
      this.broadcastToUser({ t: 'match_request_error', code: 'invalid' });
      return;
    }
    const inc = row[0];
    if (inc.status !== 'pending') return;

    this.ctx.storage.sql.exec(
      "UPDATE incoming_requests SET status = 'declined' WHERE id = ?",
      requestId
    );

    this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'declined' });

    if (this.env.USER_PROFILE) {
      try {
        const senderStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(inc.from_uid)
        );
        await senderStub.notifyDeclined(requestId, this.getEffectiveUid());
      } catch (err) {
        console.warn(
          JSON.stringify({
            event: 'match_request_notify_failed',
            reason: 'notify_declined_exception',
            requestId,
            err: err instanceof Error ? err.message : String(err),
          })
        );
      }
    }
  }

  async handleClientCancelMatchRequest(
    _senderUid: string,
    requestId: string
  ): Promise<void> {
    const row = this.ctx.storage.sql
      .exec<{
        id: string;
        to_uid: string;
        status: string;
      }>(
        'SELECT id, to_uid, status FROM outgoing_requests WHERE id = ? LIMIT 1',
        requestId
      )
      .toArray();

    if (row.length === 0) {
      this.broadcastToUser({ t: 'match_request_error', code: 'invalid' });
      return;
    }
    const out = row[0];
    if (out.status !== 'pending') return;

    this.ctx.storage.sql.exec(
      "UPDATE outgoing_requests SET status = 'cancelled' WHERE id = ?",
      requestId
    );

    this.broadcastToUser({ t: 'match_request_status', id: requestId, status: 'cancelled' });

    if (this.env.USER_PROFILE) {
      try {
        const targetStub = this.env.USER_PROFILE.get(
          this.env.USER_PROFILE.idFromName(out.to_uid)
        );
        await targetStub.notifyCancelled(requestId);
      } catch (err) {
        console.warn(
          JSON.stringify({
            event: 'match_request_notify_failed',
            reason: 'notify_cancelled_exception',
            requestId,
            err: err instanceof Error ? err.message : String(err),
          })
        );
      }
    }
  }

  sendInitialSnapshots(ws: WebSocket, _uid: string): void {
    const now = Date.now();

    const incoming = this.ctx.storage.sql
      .exec<{
        id: string;
        from_uid: string;
        from_nickname: string;
        from_frame: string;
        type: 'friendly' | 'ranked';
        origin: 'rematch' | 'profile';
        expires_at: number;
      }>(
        "SELECT id, from_uid, from_nickname, from_frame, type, origin, expires_at FROM incoming_requests WHERE status = 'pending' AND expires_at > ? LIMIT 1",
        now
      )
      .toArray();

    if (incoming.length > 0) {
      const inc = incoming[0];
      const msg: UserServerMessage = {
        t: 'match_request_received',
        id: inc.id,
        fromUid: inc.from_uid,
        fromNickname: inc.from_nickname,
        fromFrame: inc.from_frame,
        type: inc.type,
        origin: inc.origin,
        expiresAtMs: inc.expires_at,
      };
      try {
        ws.send(JSON.stringify(msg));
      } catch {}
    }

    const outgoing = this.ctx.storage.sql
      .exec<{
        id: string;
        to_uid: string;
        to_nickname: string;
        type: 'friendly' | 'ranked';
        origin: 'rematch' | 'profile';
        expires_at: number;
      }>(
        "SELECT id, to_uid, to_nickname, type, origin, expires_at FROM outgoing_requests WHERE status = 'pending' AND expires_at > ? LIMIT 1",
        now
      )
      .toArray();

    if (outgoing.length > 0) {
      const out = outgoing[0];
      const msg: UserServerMessage = {
        t: 'match_request_sent',
        id: out.id,
        toUid: out.to_uid,
        toNickname: out.to_nickname,
        type: out.type,
        origin: out.origin,
        expiresAtMs: out.expires_at,
      };
      try {
        ws.send(JSON.stringify(msg));
      } catch {}
    }
  }

  broadcastToUser(msg: UserServerMessage): void {
    const sockets = this.getWebSocketsSafe();
    const raw = JSON.stringify(msg);
    for (const ws of sockets) {
      try {
        ws.send(raw);
      } catch {}
    }
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    this.ensureSchema();
    if (this.isDeleted()) {
      try {
        ws.close(4001, 'account_deleted');
      } catch {}
      return;
    }

    let uid = '';
    if (typeof this.ctx?.getTags === 'function') {
      const tags = this.ctx.getTags(ws);
      uid = tags[0] ?? '';
    }
    if (!uid) {
      uid = this.getEffectiveUid();
    }
    if (!uid) return;

    // Hız sınırı: saniyede en fazla 10 mesaj
    const nowMs = Date.now();
    const att = (typeof ws.deserializeAttachment === 'function'
      ? ws.deserializeAttachment()
      : null) as { count: number; windowStart: number } | null;
    let newAtt: { count: number; windowStart: number };
    if (!att || nowMs - att.windowStart >= 1000) {
      newAtt = { count: 1, windowStart: nowMs };
    } else {
      newAtt = { count: att.count + 1, windowStart: att.windowStart };
    }
    if (typeof ws.serializeAttachment === 'function') {
      ws.serializeAttachment(newAtt);
    }
    if (newAtt.count > 10) {
      return;
    }

    const rawStr =
      typeof message === 'string' ? message : new TextDecoder().decode(message);
    const byteLen =
      typeof message === 'string'
        ? new TextEncoder().encode(message).length
        : message.byteLength;
    if (byteLen > 4096) {
      try {
        ws.close(1009, 'message_too_big');
      } catch {}
      return;
    }

    const parsed = parseUserClientMessage(rawStr, byteLen);
    if (!parsed) return;

    if (parsed.t === 'ping') {
      try {
        ws.send(JSON.stringify({ t: 'pong' }));
      } catch {}
      return;
    }

    if (parsed.t === 'presence') {
      this.ctx.storage.sql.exec(
        "INSERT OR REPLACE INTO user_presence (key, state) VALUES ('current', ?)",
        parsed.state
      );
      return;
    }

    if (parsed.t === 'send_match_request') {
      await this.handleClientSendMatchRequest(
        uid,
        parsed.origin,
        parsed.toUid,
        parsed.matchId
      );
      return;
    }

    if (parsed.t === 'accept_match_request') {
      await this.handleClientAcceptMatchRequest(uid, parsed.id);
      return;
    }

    if (parsed.t === 'decline_match_request') {
      await this.handleClientDeclineMatchRequest(uid, parsed.id);
      return;
    }

    if (parsed.t === 'cancel_match_request') {
      await this.handleClientCancelMatchRequest(uid, parsed.id);
      return;
    }
  }

  async webSocketClose(_ws: WebSocket, _code: number, _reason: string): Promise<void> {
    const remaining = this.getWebSocketsSafe();
    if (remaining.length === 0) {
      this.ctx.storage.sql.exec("DELETE FROM user_presence WHERE key = 'current'");
    }
  }

  async webSocketError(ws: WebSocket, _error: unknown): Promise<void> {
    try {
      ws.close(1011, 'internal_error');
    } catch {}
  }

  /**
   * HTTP Fetch arayüzü desteği
   */
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const uid = request.headers.get('X-User-Id') ?? undefined;

    if (request.headers.get('Upgrade') === 'websocket') {
      const callerUid = uid ?? request.headers.get('X-User-Id');
      if (!callerUid) {
        return new Response('Unauthorized', { status: 401 });
      }

      this.ensureSchema();
      if (this.isDeleted()) {
        return new Response('Account Deleted', { status: 410 });
      }

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);

      if (typeof this.ctx.acceptWebSocket === 'function') {
        this.ctx.acceptWebSocket(server, [callerUid]);
      }

      if (
        typeof (this.ctx as any).setWebSocketAutoResponse === 'function' &&
        typeof (globalThis as any).WebSocketRequestResponsePair !== 'undefined'
      ) {
        try {
          (this.ctx as any).setWebSocketAutoResponse(
            new (globalThis as any).WebSocketRequestResponsePair(
              JSON.stringify({ t: 'ping' }),
              JSON.stringify({ t: 'pong' })
            )
          );
        } catch {}
      }

      this.ctx.storage.sql.exec(
        "INSERT OR REPLACE INTO user_presence (key, state) VALUES ('current', 'idle')"
      );

      this.sendInitialSnapshots(server, callerUid);

      return new Response(null, { status: 101, webSocket: client });
    }

    if (
      request.method === 'PUT' &&
      (url.pathname === '/settings' || url.pathname === '/me/settings')
    ) {
      try {
        const body = (await request.json()) as { allowMatchRequests?: unknown };
        if (typeof body?.allowMatchRequests !== 'boolean') {
          return new Response(
            JSON.stringify({
              error: 'bad_request',
              message: 'allowMatchRequests alanı boolean olmalıdır',
            }),
            { status: 400, headers: { 'Content-Type': 'application/json' } }
          );
        }
        const res = await this.updateSettings({
          allowMatchRequests: body.allowMatchRequests,
        });
        return new Response(JSON.stringify({ ok: true, ...res }), {
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
        return new Response(
          JSON.stringify({ error: 'internal_error', message: msg }),
          { status: 500, headers: { 'Content-Type': 'application/json' } }
        );
      }
    }

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
        if (msg === 'guest_nickname_locked') {
          return new Response(
            JSON.stringify({
              error: 'guest_nickname_locked',
              message:
                'Misafir hesaplar takma ad değiştiremez. Özel takma ad belirlemek için Google ile giriş yapmalısın.',
            }),
            { status: 403, headers: { 'Content-Type': 'application/json' } }
          );
        }
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
        if (msg === 'guest_nickname_locked') {
          return new Response(
            JSON.stringify({
              error: 'guest_nickname_locked',
              message:
                'Misafir hesaplar takma ad değiştiremez. Özel takma ad belirlemek için Google ile giriş yapmalısın.',
            }),
            { status: 403, headers: { 'Content-Type': 'application/json' } }
          );
        }
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: { 'Content-Type': 'application/json' } }
          );
        }
        if (msg === 'nickname_blocked') {
          return new Response(
            JSON.stringify({
              error: 'nickname_blocked',
              message: 'Bu takma ad kullanılamaz.',
            }),
            { status: 422, headers: { 'Content-Type': 'application/json' } }
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
        if (msg === 'guest_nickname_locked') {
          return new Response(
            JSON.stringify({
              error: 'guest_nickname_locked',
              message:
                'Misafir hesaplar takma ad değiştiremez. Özel takma ad belirlemek için Google ile giriş yapmalısın.',
            }),
            { status: 403, headers: { 'Content-Type': 'application/json' } }
          );
        }
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
