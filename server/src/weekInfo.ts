const daysMap: Record<string, number> = {
  Mon: 0,
  Tue: 1,
  Wed: 2,
  Thu: 3,
  Fri: 4,
  Sat: 5,
  Sun: 6,
};

export interface IstanbulWeekInfo {
  readonly weekKey: string;
  readonly startOfWeekMs: number;
  readonly endsAtMs: number;
}

export interface LeaderboardSeedEntry {
  readonly uid: string;
  readonly nickname: string;
  readonly wins: number;
  readonly losses: number;
  readonly reachedAt: number;
  readonly frame: string;
}

/**
 * Verilen tarihe göre Türkiye (Europe/Istanbul) saat diliminde
 * haftanın başlangıcı (Pazartesi 00:00:00), bitişi (sonraki Pazartesi 00:00:00)
 * ve ISO hafta anahtarını (örn. "2026-W42") hesaplar.
 */
export function getIstanbulWeekInfo(date: Date = new Date()): IstanbulWeekInfo {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    weekday: 'short',
    hourCycle: 'h23',
  });

  const map: Record<string, string> = {};
  for (const p of formatter.formatToParts(date)) {
    map[p.type] = p.value;
  }

  const daysSinceMonday = daysMap[map.weekday] ?? 0;
  const hour = parseInt(map.hour, 10);
  const min = parseInt(map.minute, 10);
  const sec = parseInt(map.second, 10);
  const ms = date.getUTCMilliseconds();

  const elapsedSinceMondayMs =
    (daysSinceMonday * 86400 + hour * 3600 + min * 60 + sec) * 1000 + ms;
  const startOfWeekMs = date.getTime() - elapsedSinceMondayMs;
  const endsAtMs = startOfWeekMs + 7 * 86400 * 1000;

  // ISO 8601 hafta numarası: Haftanın Perşembe gününün takvim yılı ve haftası belirler
  const thursday = new Date(startOfWeekMs + 3 * 86400 * 1000 + 12 * 3600 * 1000);
  const thuMap: Record<string, string> = {};
  for (const p of formatter.formatToParts(thursday)) {
    thuMap[p.type] = p.value;
  }
  const thuYear = parseInt(thuMap.year, 10);
  const thuMonth = parseInt(thuMap.month, 10);
  const thuDay = parseInt(thuMap.day, 10);

  const thuUtc = Date.UTC(thuYear, thuMonth - 1, thuDay);
  const jan1Day = new Date(Date.UTC(thuYear, 0, 1)).getUTCDay();
  const firstThursdayUtc = Date.UTC(thuYear, 0, 1 + ((4 - jan1Day + 7) % 7));
  const weekNumber = 1 + Math.round((thuUtc - firstThursdayUtc) / (7 * 86400 * 1000));
  const weekKey = `${thuYear}-W${String(weekNumber).padStart(2, '0')}`;

  return {
    weekKey,
    startOfWeekMs,
    endsAtMs,
  };
}
