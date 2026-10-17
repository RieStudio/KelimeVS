// Saf TypeScript - Ağ bağımlılığı yoktur.
// ghost-opponent betiğinin karar ve veri mantığı birim test edilebilir fonksiyonlar içerir.

import type { Answer, Question } from '../src/engine/models';
import { normalize } from '../src/engine/normalizer';

export type GhostMode = 'play' | 'idle' | 'leave' | 'drop';

export const DEFAULT_GHOST_NAMES: readonly string[] = [
  'Zeynep',
  'Mehmet',
  'Elif',
  'Can',
  'Deniz',
  'Barış',
];

export function pickGhostName(nameArg?: string): string {
  if (nameArg && nameArg.trim().length > 0) {
    return nameArg.trim();
  }
  const idx = Math.floor(Math.random() * DEFAULT_GHOST_NAMES.length);
  return DEFAULT_GHOST_NAMES[idx] ?? 'Zeynep';
}

export interface GhostConfig {
  readonly mode: GhostMode;
  readonly serverUrl: string;
  readonly apiKey?: string;
  readonly rounds: number;
  readonly leaveAfterSeconds: number;
  readonly dropAfterSeconds: number;
  readonly backAfterSeconds: number;
  readonly fresh: boolean;
  readonly devAuth: boolean;
  readonly name: string;
}

/** Komut satırı argümanlarını ayrıştırır. */
export function parseGhostArgs(argv: readonly string[], env: Record<string, string | undefined> = {}): GhostConfig {
  let mode: GhostMode = 'play';
  let serverUrl = env.SERVER_URL?.trim() || 'wss://api.riestudio.com.tr';
  let apiKey = env.FIREBASE_WEB_API_KEY?.trim();
  let rounds = 1;
  let leaveAfterSeconds = 15;
  let dropAfterSeconds = 15;
  let backAfterSeconds = 5;
  let fresh = false;
  let devAuth = false;
  let nameArg: string | undefined;

  for (const arg of argv) {
    if (arg === '--dev-auth' || arg === '--dev-auth=true') {
      devAuth = true;
    } else if (arg === '--fresh' || arg === '--fresh=true') {
      fresh = true;
    } else if (arg.startsWith('--mode=')) {
      const val = arg.slice('--mode='.length).toLowerCase();
      if (val === 'play' || val === 'idle' || val === 'leave' || val === 'drop') {
        mode = val;
      }
    } else if (arg.startsWith('--url=')) {
      serverUrl = arg.slice('--url='.length).trim();
    } else if (arg.startsWith('--api-key=')) {
      apiKey = arg.slice('--api-key='.length).trim();
    } else if (arg.startsWith('--name=')) {
      nameArg = arg.slice('--name='.length).trim();
    } else if (arg.startsWith('--rounds=')) {
      const parsed = parseInt(arg.slice('--rounds='.length), 10);
      if (Number.isFinite(parsed) && parsed > 0) {
        rounds = parsed;
      }
    } else if (arg.startsWith('--leave-after=')) {
      const parsed = parseInt(arg.slice('--leave-after='.length), 10);
      if (Number.isFinite(parsed) && parsed >= 0) {
        leaveAfterSeconds = parsed;
      }
    } else if (arg.startsWith('--drop-after=')) {
      const parsed = parseInt(arg.slice('--drop-after='.length), 10);
      if (Number.isFinite(parsed) && parsed >= 0) {
        dropAfterSeconds = parsed;
      }
    } else if (arg.startsWith('--back-after=')) {
      const parsed = parseInt(arg.slice('--back-after='.length), 10);
      if (Number.isFinite(parsed) && parsed >= 0) {
        backAfterSeconds = parsed;
      }
    }
  }

  return {
    mode,
    serverUrl: toWebSocketUrl(serverUrl),
    apiKey: apiKey && apiKey.length > 0 ? apiKey : undefined,
    rounds,
    leaveAfterSeconds,
    dropAfterSeconds,
    backAfterSeconds,
    fresh,
    devAuth,
    name: pickGhostName(nameArg),
  };
}

/** Firebase Auth REST hata yanıtından yalnızca error.message alanını çeker. */
export function parseFirebaseErrorMessage(json: unknown): string | undefined {
  if (typeof json !== 'object' || json === null) return undefined;
  const obj = json as Record<string, unknown>;

  if (typeof obj.error === 'object' && obj.error !== null) {
    const errorObj = obj.error as Record<string, unknown>;
    if (typeof errorObj.message === 'string' && errorObj.message.trim().length > 0) {
      return errorObj.message.replace(/key=[^&\s]+/gi, 'key=[REDACTED]').trim();
    }
  }

  if (typeof obj.error === 'string' && obj.error.trim().length > 0) {
    return obj.error.trim();
  }

  return undefined;
}

export interface GhostSessionData {
  readonly refreshToken: string;
}

/** server/.ghost-session.json dosya içeriğini ayrıştırır. */
export function parseSessionCache(content: string): GhostSessionData | undefined {
  try {
    const parsed = JSON.parse(content) as Record<string, unknown>;
    if (typeof parsed.refreshToken === 'string' && parsed.refreshToken.trim().length > 0) {
      return { refreshToken: parsed.refreshToken.trim() };
    }
  } catch {
    // bozuk json
  }
  return undefined;
}

/** Session önbellek nesnesini serileştirir. */
export function serializeSessionCache(refreshToken: string): string {
  return JSON.stringify({ refreshToken }, null, 2);
}

/** HTTP(S) adresini WebSocket adresine çevirir. */
export function toWebSocketUrl(url: string): string {
  const trimmed = url.trim().replace(/\/+$/, '');
  if (trimmed.startsWith('https://')) {
    return `wss://${trimmed.slice('https://'.length)}`;
  }
  if (trimmed.startsWith('http://')) {
    return `ws://${trimmed.slice('http://'.length)}`;
  }
  return trimmed;
}

/** .dev.vars dosya içeriğinden FIREBASE_WEB_API_KEY değerini ayrıştırır. */
export function parseApiKeyFromDevVars(content: string): string | undefined {
  const lines = content.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const [key, ...rest] = trimmed.split('=');
    if (key.trim() === 'FIREBASE_WEB_API_KEY') {
      const value = rest.join('=').trim().replace(/^['"]|['"]$/g, '');
      if (value.length > 0) return value;
    }
  }
  return undefined;
}

/** State mesajındaki soruya karşılık gelen Question nesnesini bulur. */
export function findQuestionByState(
  questions: readonly Question[],
  stateQuestion: { readonly id: string; readonly text: string } | null
): Question | undefined {
  if (!stateQuestion) return undefined;

  // Önce ID ile ara
  const byId = questions.find((q) => q.id === stateQuestion.id);
  if (byId) return byId;

  // Bulunamazsa metinle ara (boşlukları temizleyerek)
  const cleanTargetText = stateQuestion.text.replace(/\s+/g, ' ').trim().toLowerCase();
  return questions.find((q) => q.text.replace(/\s+/g, ' ').trim().toLowerCase() === cleanTargetText);
}

export interface AttemptLike {
  readonly mine?: boolean;
  readonly text: string;
  readonly result: string;
}

/** Soru içinde daha önce doğru söylenmemiş cevapları bulur. */
export function findUnusedAnswers(
  question: Question,
  attempts: readonly AttemptLike[]
): Answer[] {
  // Önceki doğru cevapların normalleştirilmiş kimliklerini topla
  const usedNormalizedAnswers = new Set<string>();

  for (const attempt of attempts) {
    if (attempt.result === 'correct') {
      const norm = normalize(attempt.text);
      for (const ans of question.answers) {
        if (ans.id === norm || ans.aliases.includes(norm)) {
          usedNormalizedAnswers.add(ans.id);
        }
      }
    }
  }

  return question.answers.filter((ans) => !usedNormalizedAnswers.has(ans.id));
}

/** Söylenecek cevabı seçer. Bulamazsa null döner. */
export function selectAnswer(
  question: Question,
  attempts: readonly AttemptLike[]
): string | null {
  const unused = findUnusedAnswers(question, attempts);
  if (unused.length === 0) return null;

  // Kalan cevaplardan ilkini seç (display veya ilk alias)
  const chosen = unused[0];
  return chosen.display || chosen.aliases[0] || null;
}

/** %20 olasılıkla önce yanlış deneme yapılacağını belirler. */
export function shouldMakeMistake(randomValue: number): boolean {
  return randomValue < 0.20;
}

/** 2-6 saniye arasında rastgele yanıt gecikmesi hesaplar (milisaniye cinsinden). */
export function getRandomDelayMs(minMs = 2000, maxMs = 6000, randomValue = Math.random()): number {
  return Math.floor(minMs + randomValue * (maxMs - minMs));
}

