import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index';

export interface ReportEntry {
  readonly id: string;
  readonly reporterUid: string;
  readonly reportedUid: string;
  readonly matchId: string;
  readonly reason: string;
  readonly reportedNickname: string;
  readonly answers: readonly string[];
  readonly createdAt: number;
}

export interface ReportSummaryEntry {
  readonly reportedUid: string;
  readonly reportedNickname: string;
  readonly reportCount: number;
  readonly lastReportedAt: number;
}

interface ReportRow extends Record<string, string | number | null> {
  id: string;
  reporter_uid: string;
  reported_uid: string;
  match_id: string;
  reason: string;
  reported_nickname: string;
  answers_json: string;
  created_at: number;
}

interface SummaryRow extends Record<string, string | number | null> {
  reported_uid: string;
  reported_nickname: string;
  report_count: number;
  last_reported_at: number;
}

interface CountRow extends Record<string, string | number | null> {
  cnt: number;
}

export class ReportStore extends DurableObject<Env> {
  private initialized = false;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  private ensureSchema(): void {
    if (this.initialized) return;

    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS reports (
        id TEXT PRIMARY KEY,
        reporter_uid TEXT NOT NULL,
        reported_uid TEXT NOT NULL,
        match_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        reported_nickname TEXT NOT NULL,
        answers_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(reporter_uid, match_id)
      );

      CREATE INDEX IF NOT EXISTS idx_reports_reported_uid ON reports(reported_uid);
      CREATE INDEX IF NOT EXISTS idx_reports_created_at ON reports(created_at);
      CREATE INDEX IF NOT EXISTS idx_reports_reporter_created ON reports(reporter_uid, created_at);
    `);

    this.initialized = true;
  }

  /**
   * Yeni bir oyuncu bildirimi kaydeder.
   *
   * ÖNEMLİ KURAL: Bildirimler yalnızca inceleme içindir.
   * Çok bildirim alan oyunculara burada veya sistemin başka bir yerinde
   * otomatik yaptırım / otomatik engel UYGULANMAZ. İnceleme yönetici tarafından yapılır.
   */
  async addReport(params: {
    readonly reporterUid: string;
    readonly reportedUid: string;
    readonly matchId: string;
    readonly reason: string;
    readonly reportedNickname: string;
    readonly answers: readonly string[];
  }): Promise<{ ok: true } | { ok: false; error: 'already_reported' | 'daily_limit_exceeded' }> {
    this.ensureSchema();

    // 1. Mükerrer bildirim kontrolü (aynı maç için tek bildirim)
    const existing = this.ctx.storage.sql.exec<ReportRow>(
      'SELECT id FROM reports WHERE reporter_uid = ? AND match_id = ? LIMIT 1',
      params.reporterUid,
      params.matchId
    ).toArray();

    if (existing.length > 0) {
      return { ok: false, error: 'already_reported' };
    }

    // 2. 24 saatlik günlük kota kontrolü
    const nowMs = Date.now();
    const twentyFourHoursAgo = nowMs - 24 * 60 * 60 * 1000;
    const maxDaily = parseInt(this.env.MAX_REPORTS_PER_DAY ?? '10', 10);
    const limit = Number.isFinite(maxDaily) && maxDaily > 0 ? maxDaily : 10;

    const countRow = this.ctx.storage.sql.exec<CountRow>(
      'SELECT COUNT(*) as cnt FROM reports WHERE reporter_uid = ? AND created_at > ?',
      params.reporterUid,
      twentyFourHoursAgo
    ).toArray();

    const count = countRow.length > 0 ? Number(countRow[0].cnt) : 0;
    if (count >= limit) {
      return { ok: false, error: 'daily_limit_exceeded' };
    }

    // 3. Bildirimi ekle
    const reportId = crypto.randomUUID();
    const answersJson = JSON.stringify(params.answers ?? []);

    this.ctx.storage.sql.exec(
      `INSERT INTO reports (
        id, reporter_uid, reported_uid, match_id, reason, reported_nickname, answers_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      reportId,
      params.reporterUid,
      params.reportedUid,
      params.matchId,
      params.reason,
      params.reportedNickname,
      answersJson,
      nowMs
    );

    // 4. 90 günlük saklama temizliğini planla / fırsatçı temizle
    await this.pruneExpiredReports(nowMs);
    await this.schedulePruneAlarm(nowMs);

    return { ok: true };
  }

  /**
   * Bildirimleri listeler. İsteğe bağlı olarak reportedUid ile filtreler.
   */
  async getReports(params?: {
    readonly limit?: number;
    readonly offset?: number;
    readonly reportedUid?: string;
  }): Promise<{ reports: ReportEntry[]; total: number }> {
    this.ensureSchema();

    const limit = Math.min(100, Math.max(1, params?.limit ?? 50));
    const offset = Math.max(0, params?.offset ?? 0);

    let rows: ReportRow[];
    let totalCount = 0;

    if (params?.reportedUid && params.reportedUid.trim().length > 0) {
      const uid = params.reportedUid.trim();
      const countRes = this.ctx.storage.sql.exec<CountRow>(
        'SELECT COUNT(*) as cnt FROM reports WHERE reported_uid = ?',
        uid
      ).toArray();
      totalCount = countRes.length > 0 ? Number(countRes[0].cnt) : 0;

      rows = this.ctx.storage.sql.exec<ReportRow>(
        `SELECT id, reporter_uid, reported_uid, match_id, reason, reported_nickname, answers_json, created_at
         FROM reports
         WHERE reported_uid = ?
         ORDER BY created_at DESC
         LIMIT ? OFFSET ?`,
        uid,
        limit,
        offset
      ).toArray();
    } else {
      const countRes = this.ctx.storage.sql.exec<CountRow>(
        'SELECT COUNT(*) as cnt FROM reports'
      ).toArray();
      totalCount = countRes.length > 0 ? Number(countRes[0].cnt) : 0;

      rows = this.ctx.storage.sql.exec<ReportRow>(
        `SELECT id, reporter_uid, reported_uid, match_id, reason, reported_nickname, answers_json, created_at
         FROM reports
         ORDER BY created_at DESC
         LIMIT ? OFFSET ?`,
        limit,
        offset
      ).toArray();
    }

    const reports: ReportEntry[] = rows.map((r) => {
      let answers: string[] = [];
      try {
        answers = JSON.parse(r.answers_json);
      } catch {
        // yoksay
      }
      return {
        id: r.id,
        reporterUid: r.reporter_uid,
        reportedUid: r.reported_uid,
        matchId: r.match_id,
        reason: r.reason,
        reportedNickname: r.reported_nickname,
        answers,
        createdAt: r.created_at,
      };
    });

    return { reports, total: totalCount };
  }

  /**
   * Bildirilen oyunculara göre bildirim sayımlarını özetler.
   */
  async getSummary(limit = 50): Promise<ReportSummaryEntry[]> {
    this.ensureSchema();

    const maxLimit = Math.min(100, Math.max(1, limit));
    const rows = this.ctx.storage.sql.exec<SummaryRow>(
      `SELECT reported_uid, reported_nickname, COUNT(*) as report_count, MAX(created_at) as last_reported_at
       FROM reports
       GROUP BY reported_uid
       ORDER BY report_count DESC, last_reported_at DESC
       LIMIT ?`,
      maxLimit
    ).toArray();

    return rows.map((r) => ({
      reportedUid: r.reported_uid,
      reportedNickname: r.reported_nickname,
      reportCount: Number(r.report_count),
      lastReportedAt: Number(r.last_reported_at),
    }));
  }

  /**
   * 90 günden eski bildirimleri siler.
   */
  async alarm(): Promise<void> {
    const nowMs = Date.now();
    await this.pruneExpiredReports(nowMs);
    await this.schedulePruneAlarm(nowMs);
  }

  private async pruneExpiredReports(nowMs: number): Promise<void> {
    const ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;
    const cutoff = nowMs - ninetyDaysMs;
    this.ctx.storage.sql.exec(
      'DELETE FROM reports WHERE created_at < ?',
      cutoff
    );
  }

  private async schedulePruneAlarm(nowMs: number): Promise<void> {
    // 24 saat sonrasına alarm kur
    const currentAlarm = await this.ctx.storage.getAlarm();
    if (currentAlarm === null || currentAlarm <= nowMs) {
      await this.ctx.storage.setAlarm(nowMs + 24 * 60 * 60 * 1000);
    }
  }
}

