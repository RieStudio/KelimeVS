import type { ContentProvider } from './contentProvider';
import { normalize, type Answer, type Question } from '../engine';
import {
  ServiceAccountTokenProvider,
  type FetchFunction,
} from './serviceAccountAuth';

export interface RealtimeDbContentProviderOptions {
  readonly databaseUrl: string;
  readonly serviceAccountB64?: string;
  readonly tokenProvider?: ServiceAccountTokenProvider;
  readonly ttlSeconds?: number;
  readonly fetchFn?: FetchFunction;
  readonly nowFn?: () => number;
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
  private readonly fetchFn: FetchFunction;
  private readonly nowFn: () => number;

  private cachedQuestions: Question[] | null = null;
  private cacheExpiresAtMs = 0;
  private isRefreshing = false;

  private lastAuthMethodUsed: AuthMethodUsed = 'none';
  private lastStats: ContentStats | null = null;

  constructor(options: RealtimeDbContentProviderOptions) {
    this.baseUrl = options.databaseUrl.trim().replace(/\/+$/, '');
    this.ttlMs = (options.ttlSeconds ?? 3600) * 1000;
    this.fetchFn = options.fetchFn ?? fetch;
    this.nowFn = options.nowFn ?? Date.now;

    if (options.tokenProvider) {
      this.tokenProvider = options.tokenProvider;
    } else if (options.serviceAccountB64) {
      this.tokenProvider = new ServiceAccountTokenProvider(options.serviceAccountB64, {
        fetchFn: this.fetchFn,
        nowFn: this.nowFn,
      });
    } else {
      this.tokenProvider = null;
    }
  }

  get authMethodUsed(): AuthMethodUsed {
    return this.lastAuthMethodUsed;
  }

  get latestStats(): ContentStats | null {
    return this.lastStats;
  }

  /**
   * Firebase Realtime Database'ten questions_pool.json çeker ve ayrıştırır.
   */
  async fetchFromDatabase(): Promise<{
    readonly questions: Question[];
    readonly stats: ContentStats;
    readonly authMethod: AuthMethodUsed;
  }> {
    let accessToken: string | null = null;
    if (this.tokenProvider) {
      accessToken = await this.tokenProvider.getAccessToken();
    }

    const endpointUrl = `${this.baseUrl}/questions_pool.json`;

    let res: Response;
    let authMethod: AuthMethodUsed = 'none';

    // 1. Önce Authorization: Bearer başlığını dene
    if (accessToken) {
      res = await this.fetchFn(endpointUrl, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      });

      if (res.ok) {
        authMethod = 'header';
      } else if (res.status === 401 || res.status === 403) {
        // 2. RTDB başlığı reddederse ?access_token= sorgu parametresiyle dene (URL ASLA loglanmaz)
        const fallbackUrl = `${endpointUrl}?access_token=${encodeURIComponent(accessToken)}`;
        res = await this.fetchFn(fallbackUrl);
        if (res.ok) {
          authMethod = 'query_param';
        }
      }
    } else {
      // Token yoksa doğrudan dene
      res = await this.fetchFn(endpointUrl);
    }

    if (!res.ok) {
      throw new Error(`Realtime Database request failed with HTTP ${res.status}`);
    }

    const rawData = (await res.json()) as unknown;
    const { questions, stats } = parseQuestionsPoolWithStats(rawData);

    this.lastAuthMethodUsed = authMethod;
    this.lastStats = stats;

    return { questions, stats, authMethod };
  }

  /**
   * ContentProvider arayüzünü uygular.
   * Önbellek yoksa çeker; önbellek varsa süresi dolduğunda arka planda yeniler.
   */
  async getQuestions(): Promise<Question[]> {
    const now = this.nowFn();

    // 1. İlk çekme (önbellek boş) -> Başarısız olursa hata fırlat
    if (this.cachedQuestions === null) {
      const { questions } = await this.fetchFromDatabase();
      this.cachedQuestions = questions;
      this.cacheExpiresAtMs = now + this.ttlMs;
      return questions;
    }

    // 2. Önbelleğin süresi dolmuşsa arka planda yenile (stale-while-revalidate)
    if (now >= this.cacheExpiresAtMs && !this.isRefreshing) {
      this.isRefreshing = true;
      this.fetchFromDatabase()
        .then(({ questions }) => {
          this.cachedQuestions = questions;
          this.cacheExpiresAtMs = this.nowFn() + this.ttlMs;
        })
        .catch(() => {
          // Yenileme başarısızsa eski önbellek korunur; peş peşe istek yağmasını önlemek için süreyi uzat
          this.cacheExpiresAtMs = this.nowFn() + this.ttlMs;
        })
        .finally(() => {
          this.isRefreshing = false;
        });
    }

    return this.cachedQuestions;
  }
}
