import type { ContentProvider } from './contentProvider';
import { normalize, type Answer, type Question } from '../engine';
import {
  ServiceAccountTokenProvider,
  type FetchFunction,
} from './serviceAccountAuth';
import {
  inspectSecretB64,
  logContentError,
  extractCauseCode,
  extractErrorMessage,
} from './contentDiagnostics';

export interface RealtimeDbContentProviderOptions {
  readonly databaseUrl: string;
  readonly serviceAccountB64?: string;
  readonly tokenProvider?: ServiceAccountTokenProvider;
  readonly ttlSeconds?: number;
  readonly versionCheckIntervalSeconds?: number;
  readonly initialContentVersion?: string | number | null;
  readonly fetchFn?: FetchFunction;
  readonly nowFn?: () => number;
  readonly sleepFn?: (ms: number) => Promise<void>;
  readonly warnFn?: (msg: string) => void;
  readonly logFn?: (msg: string) => void;
}

export interface AliasCollisionWarning {
  readonly questionId: string;
  readonly categoryId: string;
  readonly alias: string;
  readonly answerDisplay1: string;
  readonly answerDisplay2: string;
}

/**
 * Soruların cevapları arasındaki alias çakışmalarını tespit eder.
 * Aynı soru içindeki farklı cevapların aynı normalize edilmiş alias'ı
 * paylaşması durumunda uyarı kaydı üretir.
 */
export function findAliasCollisions(questions: readonly Question[]): AliasCollisionWarning[] {
  const warnings: AliasCollisionWarning[] = [];

  for (const q of questions) {
    const aliasToAnswer = new Map<string, string>();
    for (const a of q.answers) {
      const allAliases = new Set<string>();
      if (a.id && a.id.trim().length > 0) allAliases.add(a.id);
      for (const al of a.aliases) {
        if (al && al.trim().length > 0) allAliases.add(al);
      }

      for (const alias of allAliases) {
        const existing = aliasToAnswer.get(alias);
        if (existing && existing !== a.display) {
          warnings.push({
            questionId: q.id,
            categoryId: q.categoryId,
            alias,
            answerDisplay1: existing,
            answerDisplay2: a.display,
          });
        } else {
          aliasToAnswer.set(alias, a.display);
        }
      }
    }
  }

  return warnings;
}

export function logAliasCollisions(
  warnings: readonly AliasCollisionWarning[],
  warnFn: (msg: string) => void = (msg) => console.warn(msg)
): void {
  for (const w of warnings) {
    warnFn(
      JSON.stringify({
        event: 'content_warning',
        stage: 'alias_collision',
        questionId: w.questionId,
        categoryId: w.categoryId,
        alias: w.alias,
        answer1: w.answerDisplay1,
        answer2: w.answerDisplay2,
        detail: `Alias collision in question ${w.questionId}: alias '${w.alias}' claimed by both '${w.answerDisplay1}' and '${w.answerDisplay2}'`,
      })
    );
  }
}

export interface ContentStats {
  readonly categoriesCount: number;
  readonly questionsCount: number;
  readonly answersCount: number;
  readonly skippedQuestionsCount: number;
}

export type AuthMethodUsed = 'header' | 'query_param' | 'none';

/**
 * RTDB questions_pool verisini ayrıştırır ve bozuk kayıtları atlar.
 */
export function parseQuestionsPoolWithStats(raw: unknown): {
  readonly questions: Question[];
  readonly stats: ContentStats;
} {
  const questions: Question[] = [];
  let skippedCount = 0;
  let totalAnswers = 0;

  if (typeof raw !== 'object' || raw === null) {
    return {
      questions: [],
      stats: {
        categoriesCount: 0,
        questionsCount: 0,
        answersCount: 0,
        skippedQuestionsCount: 0,
      },
    };
  }

  // Veri root altında 'questions_pool' anahtarında olabilir veya doğrudan pool olabilir
  const pool =
    'questions_pool' in raw && typeof (raw as Record<string, unknown>).questions_pool === 'object'
      ? (raw as Record<string, unknown>).questions_pool
      : raw;

  if (typeof pool !== 'object' || pool === null) {
    return {
      questions: [],
      stats: {
        categoriesCount: 0,
        questionsCount: 0,
        answersCount: 0,
        skippedQuestionsCount: 0,
      },
    };
  }

  const categories = Object.entries(pool as Record<string, unknown>);
  let categoriesCount = 0;

  for (const [categoryId, categoryObj] of categories) {
    if (typeof categoryObj !== 'object' || categoryObj === null) {
      continue;
    }
    categoriesCount++;

    for (const [questionId, qObj] of Object.entries(
      categoryObj as Record<string, unknown>
    )) {
      if (typeof qObj !== 'object' || qObj === null) {
        skippedCount++;
        continue;
      }

      const rawQuestion = (qObj as Record<string, unknown>).question;
      if (typeof rawQuestion !== 'string') {
        skippedCount++;
        continue;
      }

      const cleanText = rawQuestion.replace(/\s+/g, ' ').trim();
      if (cleanText.length === 0) {
        skippedCount++;
        continue;
      }

      const rawAnswers = (qObj as Record<string, unknown>).acceptable_answers;
      if (typeof rawAnswers !== 'object' || rawAnswers === null) {
        skippedCount++;
        continue;
      }

      const answers: Answer[] = [];
      for (const [mainAnswerKey, rawAliases] of Object.entries(
        rawAnswers as Record<string, unknown>
      )) {
        const display = String(mainAnswerKey).trim();
        const id = normalize(display);

        const normalizedAliases: string[] = [];
        if (id.length > 0) {
          normalizedAliases.push(id);
        }

        if (Array.isArray(rawAliases)) {
          for (const aliasItem of rawAliases) {
            const norm = normalize(String(aliasItem));
            if (norm.length > 0 && !normalizedAliases.includes(norm)) {
              normalizedAliases.push(norm);
            }
          }
        }

        if (normalizedAliases.length > 0) {
          answers.push({
            id,
            display,
            aliases: normalizedAliases,
          });
        }
      }

      if (answers.length === 0) {
        // Hiç kabul edilebilir cevabı olmayan soru oynanamaz
        skippedCount++;
        continue;
      }

      totalAnswers += answers.length;
      questions.push({
        id: questionId,
        categoryId,
        text: cleanText,
        answers,
      });
    }
  }

  return {
    questions,
    stats: {
      categoriesCount,
      questionsCount: questions.length,
      answersCount: totalAnswers,
      skippedQuestionsCount: skippedCount,
    },
  };
}

export class RealtimeDbContentProvider implements ContentProvider {
  private readonly baseUrl: string;
  private readonly tokenProvider: ServiceAccountTokenProvider | null;
  private readonly ttlMs: number;
  private readonly versionCheckIntervalMs: number;
  private readonly fetchFn: FetchFunction;
  private readonly nowFn: () => number;
  private readonly sleepFn: (ms: number) => Promise<void>;
  private readonly warnFn: (msg: string) => void;
  private readonly logFn: (msg: string) => void;
  private readonly diagnosticFlags: {
    readonly hasSecret: boolean;
    readonly hasClientEmail: boolean;
    readonly hasPrivateKey: boolean;
    readonly isPemFormatValid: boolean;
  };

  private cachedQuestions: Question[] | null = null;
  private cachedContentVersion: string | number | null | undefined;
  private cacheExpiresAtMs = 0;
  private nextVersionCheckAtMs = 0;
  private inFlightFetchPromise: Promise<Question[]> | null = null;
  private inFlightRefreshPromise: Promise<void> | null = null;
  private isRefreshing = false;

  private lastAuthMethodUsed: AuthMethodUsed = 'none';
  private lastStats: ContentStats | null = null;

  constructor(options: RealtimeDbContentProviderOptions) {
    this.baseUrl = options.databaseUrl.trim().replace(/\/+$/, '');
    this.ttlMs = (options.ttlSeconds ?? 3600) * 1000;
    this.versionCheckIntervalMs = (options.versionCheckIntervalSeconds ?? 15) * 1000;
    this.warnFn = options.warnFn ?? ((msg: string) => console.warn(msg));
    this.logFn = options.logFn ?? ((msg: string) => console.log(msg));
    this.cachedContentVersion = options.initialContentVersion;

    const injectedFetch = options.fetchFn;
    this.fetchFn = injectedFetch
      ? ((url: string, init?: RequestInit) => injectedFetch(url, init))
      : ((url: string, init?: RequestInit) => fetch(url, init));

    const injectedNow = options.nowFn;
    this.nowFn = injectedNow
      ? (() => injectedNow())
      : (() => Date.now());

    const injectedSleep = options.sleepFn;
    this.sleepFn = injectedSleep
      ? ((ms: number) => injectedSleep(ms))
      : ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));

    if (options.tokenProvider) {
      this.tokenProvider = options.tokenProvider;
      this.diagnosticFlags = options.tokenProvider.diagnostics;
    } else if (options.serviceAccountB64) {
      this.diagnosticFlags = inspectSecretB64(options.serviceAccountB64);
      this.tokenProvider = new ServiceAccountTokenProvider(options.serviceAccountB64, {
        fetchFn: this.fetchFn,
        nowFn: this.nowFn,
        sleepFn: this.sleepFn,
      });
    } else {
      this.tokenProvider = null;
      this.diagnosticFlags = {
        hasSecret: false,
        hasClientEmail: false,
        hasPrivateKey: false,
        isPemFormatValid: false,
      };
    }
  }

  get diagnostics(): {
    readonly hasSecret: boolean;
    readonly hasClientEmail: boolean;
    readonly hasPrivateKey: boolean;
    readonly isPemFormatValid: boolean;
  } {
    return this.diagnosticFlags;
  }

  get authMethodUsed(): AuthMethodUsed {
    return this.lastAuthMethodUsed;
  }

  get latestStats(): ContentStats | null {
    return this.lastStats;
  }

  get currentVersion(): string | number | null | undefined {
    return this.cachedContentVersion;
  }

  get inFlightRefresh(): Promise<void> | null {
    return this.inFlightRefreshPromise;
  }

  private async executeRtdbRequest(path: string): Promise<Response | null> {
    let accessToken: string | null = null;
    if (this.tokenProvider) {
      accessToken = await this.tokenProvider.getAccessToken();
    }

    const cleanPath = path.replace(/^\/+/, '');
    const endpointUrl = `${this.baseUrl}/${cleanPath}`;

    let lastNetworkErr: unknown = null;
    let res: Response | null = null;
    let authMethod: AuthMethodUsed = 'none';

    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        if (accessToken) {
          res = await this.fetchFn(endpointUrl, {
            headers: {
              Authorization: `Bearer ${accessToken}`,
              Accept: 'application/json',
            },
          });

          if (res.ok) {
            authMethod = 'header';
          } else if (res.status === 401 || res.status === 403) {
            const fallbackUrl = `${endpointUrl}?access_token=${encodeURIComponent(accessToken)}`;
            res = await this.fetchFn(fallbackUrl, {
              headers: {
                Accept: 'application/json',
              },
            });
            if (res.ok) {
              authMethod = 'query_param';
            }
          }
        } else {
          res = await this.fetchFn(endpointUrl, {
            headers: {
              Accept: 'application/json',
            },
          });
        }

        if (res.status >= 500 && attempt === 1) {
          await this.sleepFn(300);
          continue;
        }

        break;
      } catch (networkErr: unknown) {
        lastNetworkErr = networkErr;
        if (attempt === 1) {
          await this.sleepFn(300);
          continue;
        }
      }
    }

    if (!res) {
      logContentError({
        event: 'content_error',
        stage: 'rtdb_fetch',
        errorName: lastNetworkErr instanceof Error ? lastNetworkErr.name : 'NetworkError',
        detail: `Network failure during Realtime Database fetch for ${cleanPath}`,
        causeCode: extractCauseCode(lastNetworkErr),
        message: extractErrorMessage(lastNetworkErr),
        ...this.diagnosticFlags,
      });
      if (lastNetworkErr) {
        throw lastNetworkErr;
      }
      return null;
    }

    if (res.ok && authMethod !== 'none') {
      this.lastAuthMethodUsed = authMethod;
    }

    return res;
  }

  /**
   * Firebase Realtime Database'ten content_version.json çeker.
   * Düğüm yoksa (null) veya 404 ise null döner.
   */
  async fetchContentVersion(): Promise<string | number | null> {
    let res: Response | null = null;
    try {
      res = await this.executeRtdbRequest('content_version.json');
    } catch {
      return null;
    }

    if (!res) return null;
    if (res.status === 404) return null;

    if (!res.ok) {
      let rtdbErrorCode: string | undefined;
      try {
        const errJson = (await res.json()) as Record<string, unknown>;
        if (typeof errJson.error === 'string') {
          rtdbErrorCode = errJson.error;
        }
      } catch {
        // ignore
      }

      logContentError({
        event: 'content_error',
        stage: 'rtdb_fetch',
        status: res.status,
        errorName: 'RtdbHttpError',
        code: rtdbErrorCode,
        detail: rtdbErrorCode || `Realtime Database request for content_version failed with HTTP ${res.status}`,
        ...this.diagnosticFlags,
      });

      return null;
    }

    let rawData: unknown;
    try {
      rawData = (await res.json()) as unknown;
    } catch {
      return null;
    }

    if (rawData === null || rawData === undefined) {
      return null;
    }

    if (typeof rawData === 'number' || typeof rawData === 'string') {
      return rawData;
    }

    if (typeof rawData === 'object') {
      const rec = rawData as Record<string, unknown>;
      if (typeof rec.version === 'string' || typeof rec.version === 'number') {
        return rec.version;
      }
      return JSON.stringify(rawData);
    }

    return String(rawData);
  }

  /**
   * Firebase Realtime Database'ten questions_pool.json çeker ve ayrıştırır.
   */
  async fetchFromDatabase(): Promise<{
    readonly questions: Question[];
    readonly stats: ContentStats;
    readonly authMethod: AuthMethodUsed;
  }> {
    const res = await this.executeRtdbRequest('questions_pool.json');

    if (!res || !res.ok) {
      let rtdbErrorCode: string | undefined;
      if (res) {
        try {
          const errJson = (await res.json()) as Record<string, unknown>;
          if (typeof errJson.error === 'string') {
            rtdbErrorCode = errJson.error;
          }
        } catch {
          // ignore
        }
      }

      logContentError({
        event: 'content_error',
        stage: 'rtdb_fetch',
        status: res?.status,
        errorName: 'RtdbHttpError',
        code: rtdbErrorCode,
        detail: rtdbErrorCode || `Realtime Database request failed with HTTP ${res?.status ?? 'unknown'}`,
        ...this.diagnosticFlags,
      });

      throw new Error(`Realtime Database request failed with HTTP ${res?.status ?? 'unknown'}`);
    }

    let rawData: unknown;
    try {
      rawData = (await res.json()) as unknown;
    } catch (jsonErr: unknown) {
      logContentError({
        event: 'content_error',
        stage: 'parse',
        status: res.status,
        errorName: jsonErr instanceof Error ? jsonErr.name : 'SyntaxError',
        detail: 'Failed to parse Realtime Database response as JSON',
        ...this.diagnosticFlags,
      });
      throw jsonErr;
    }

    const { questions, stats } = parseQuestionsPoolWithStats(rawData);

    if (questions.length < 8) {
      logContentError({
        event: 'content_error',
        stage: 'parse',
        status: res.status,
        errorName: 'InsufficientQuestionsError',
        detail: `Questions pool parsed fewer than 8 valid questions (found: ${questions.length})`,
        ...this.diagnosticFlags,
      });
    }

    this.lastStats = stats;

    return { questions, stats, authMethod: this.lastAuthMethodUsed };
  }

  private checkAndLogCollisions(questions: readonly Question[]): void {
    const warnings = findAliasCollisions(questions);
    if (warnings.length > 0) {
      logAliasCollisions(warnings, this.warnFn);
    }
  }

  private logContentRefreshed(
    reason: 'initial' | 'version_change' | 'ttl',
    version: string | number | null,
    questionCount: number,
    categoryCount: number
  ): void {
    const payload = {
      event: 'content_refreshed',
      reason,
      version: version ?? null,
      questionCount,
      categoryCount,
    };
    this.logFn(JSON.stringify(payload));
  }

  private triggerBackgroundVersionCheck(): void {
    if (this.isRefreshing) return;
    this.isRefreshing = true;
    this.nextVersionCheckAtMs = this.nowFn() + this.versionCheckIntervalMs;

    this.inFlightRefreshPromise = (async () => {
      try {
        const remoteVersion = await this.fetchContentVersion();
        if (remoteVersion === null) {
          // content_version düğümü yoksa veya okunamadıysa TTL güvenlik ağına güven
          return;
        }

        // Eğer henüz bir versiyon kaydedilmemişse ilk kontrol anındaki versiyonu senkronize et
        if (this.cachedContentVersion === undefined) {
          this.cachedContentVersion = remoteVersion;
          return;
        }

        // Sürüm değiştiyse tam havuzu çek
        if (remoteVersion !== this.cachedContentVersion) {
          const { questions, stats } = await this.fetchFromDatabase();
          this.cachedQuestions = questions;
          this.cachedContentVersion = remoteVersion;
          this.cacheExpiresAtMs = this.nowFn() + this.ttlMs;
          this.checkAndLogCollisions(questions);
          this.logContentRefreshed(
            'version_change',
            this.cachedContentVersion ?? null,
            questions.length,
            stats.categoriesCount
          );
        }
      } catch (err: unknown) {
        logContentError({
          event: 'content_error',
          stage: 'rtdb_fetch',
          errorName: err instanceof Error ? err.name : 'RefreshError',
          detail: 'Background content refresh failed, keeping existing cached questions',
          causeCode: extractCauseCode(err),
          message: extractErrorMessage(err),
          ...this.diagnosticFlags,
        });
      } finally {
        this.isRefreshing = false;
        this.inFlightRefreshPromise = null;
      }
    })();
  }

  private triggerBackgroundFullRefresh(): void {
    if (this.isRefreshing) return;
    this.isRefreshing = true;
    this.cacheExpiresAtMs = this.nowFn() + this.ttlMs;

    this.inFlightRefreshPromise = (async () => {
      try {
        const { questions, stats } = await this.fetchFromDatabase();
        this.cachedQuestions = questions;
        this.cacheExpiresAtMs = this.nowFn() + this.ttlMs;
        this.nextVersionCheckAtMs = this.nowFn() + this.versionCheckIntervalMs;
        this.checkAndLogCollisions(questions);
        this.logContentRefreshed(
          'ttl',
          this.cachedContentVersion ?? null,
          questions.length,
          stats.categoriesCount
        );
      } catch {
        this.cacheExpiresAtMs = this.nowFn() + this.ttlMs;
      } finally {
        this.isRefreshing = false;
        this.inFlightRefreshPromise = null;
      }
    })();
  }

  /**
   * ContentProvider arayüzünü uygular.
   * Önbellek yoksa çeker (maç başlaması için ilk yükleme beklenir);
   * önbellek varsa istek hemen döner, versiyon kontrolü veya TTL dolumu
   * arka planda single-flight olarak çalıştırılır.
   */
  async getQuestions(): Promise<Question[]> {
    const now = this.nowFn();

    // 1. İlk çekme (önbellek boş) -> Başarısız olursa hata fırlat (Single-flight)
    if (this.cachedQuestions === null) {
      if (!this.inFlightFetchPromise) {
        this.inFlightFetchPromise = (async () => {
          try {
            const { questions, stats } = await this.fetchFromDatabase();
            this.cachedQuestions = questions;
            this.cacheExpiresAtMs = this.nowFn() + this.ttlMs;
            this.nextVersionCheckAtMs = this.nowFn() + this.versionCheckIntervalMs;
            this.checkAndLogCollisions(questions);
            this.logContentRefreshed(
              'initial',
              this.cachedContentVersion ?? null,
              questions.length,
              stats.categoriesCount
            );
            return questions;
          } finally {
            this.inFlightFetchPromise = null;
          }
        })();
      }
      return this.inFlightFetchPromise;
    }

    // 2. Önbellek zaten dolu -> Eski/mevcut veriyi hemen döndür, yenilemeyi arka planda yap
    if (now >= this.cacheExpiresAtMs) {
      this.triggerBackgroundFullRefresh();
    } else if (now >= this.nextVersionCheckAtMs) {
      this.triggerBackgroundVersionCheck();
    }

    return this.cachedQuestions;
  }
}
