/**
 * KelimeGo Yerel Liderlik Tablosu Test Verisi Tohumlama Aracı (seed-leaderboard)
 *
 * GÜVENLİK KURALI:
 * Bu araç YALNIZCA yerel geliştirme sunucusu (127.0.0.1 veya localhost) için çalışır.
 * Canlı sunucuya (api.riestudio.com.tr) ASLA bağlanmaz ve veri yazmaz.
 *
 * KOD YOLU VE DURABLE OBJECT AÇIKLAMASI:
 * Bu araç Miniflare/workerd diskindeki SQLite dosyalarını doğrudan bypass ETMEZ;
 * yerel Worker üzerindeki /admin/leaderboard/seed ve /admin/leaderboard/clear
 * uç noktaları üzerinden doğrudan Leaderboard Durable Object'i ile iletişim kurar.
 *
 * Neden Leaderboard DO içinde toplu INSERT kullanılıyor?
 * - recordMatchResult metodu anlık 1v1 maç sonu için tasarlanmıştır (her çağrıda 1 galibiyet,
 *   pair_wins ikili galibiyet sınırı ve processed_matches kaydı oluşturur). 100 oyuncu için
 *   bunu çağırmak ~2.500 sahte maç kaydı oluşturur.
 * - DO içindeki seedUsers metodu ise eşitlik bozucu kuralları (wins, losses, reached_at, uid)
 *   ve yeni görsel çerçeveleri deterministik olarak test edebilmek için yalnızca 'seed_'
 *   ön eki taşıyan kayıtları (veya açıkça belirtilen --me-uid kaydını) güncel haftaya toplu ve güvenle yazar.
 * - Gerçek kullanıcı kayıtlarına ASLA dokunulmaz; --clear parametresi yalnızca 'seed_%'
 *   kayıtlarını temizler. İsteğe bağlı --clear-me=<uid> ile yalnızca ilgili test kullanıcısı silinebilir.
 */

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { getIstanbulWeekInfo, type LeaderboardSeedEntry } from '../src/weekInfo';

export const SEED_FRAMES = [
  'classic',
  'vine',
  'silver_engraved',
  'bronze_engraved',
  'gold_leaf',
  'emerald',
  'sakura',
  'ice',
  'gear',
  'nazar',
] as const;

/**
 * Belirtilen URL'in yalnızca yerel makine (127.0.0.1 / localhost) olduğunu doğrular.
 * Canlı veya uzak sunucu tespit edilirse istisna fırlatır.
 */
export function validateLocalServerUrl(rawUrl: string): string {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new Error(`Geçersiz URL formatı: "${rawUrl}"`);
  }

  const hostname = parsed.hostname.toLowerCase();
  const isLocal =
    hostname === '127.0.0.1' ||
    hostname === 'localhost' ||
    hostname === '::1';

  if (!isLocal || parsed.protocol !== 'http:') {
    throw new Error(
      `GÜVENLİK ENGELİ: seed-leaderboard aracı canlı sunucuya (api.riestudio.com.tr vb.) KESİNLİKLE bağlanmaz.\n` +
      `Yalnızca yerel "wrangler dev" (http://127.0.0.1:8787 veya http://localhost:8787) için çalıştırılabilir.\n` +
      `Belirtilen adres yerel değil: "${rawUrl}"`
    );
  }

  return parsed.origin;
}

export interface GenerateSeedOptions {
  count?: number;
  nowMs?: number;
  meUid?: string;
  meRank?: number;
}

/**
 * Güncel hafta için sahte oyuncu ve opsiyonel test kullanıcısı verisi üretir.
 * - count: Toplam oyuncu sayısı (varsayılan: 100)
 * - meUid & meRank: Belirtilen kullanıcının tam istenen sırada (örn. 167.) yer almasını sağlar
 * - Eşitlik bozucu kuralları (ORDER BY wins DESC, losses ASC, reached_at ASC, uid ASC) deterministik sağlar
 */
export function generateSeedPlayers(
  optionsOrNowMs?: number | GenerateSeedOptions
): LeaderboardSeedEntry[] {
  let count = 100;
  let nowMs = Date.now();
  let meUid: string | undefined;
  let meRank: number | undefined;

  if (typeof optionsOrNowMs === 'number') {
    nowMs = optionsOrNowMs;
  } else if (optionsOrNowMs && typeof optionsOrNowMs === 'object') {
    count = Math.max(1, Math.floor(optionsOrNowMs.count ?? 100));
    nowMs = optionsOrNowMs.nowMs ?? Date.now();
    meUid = optionsOrNowMs.meUid?.trim();
    if (optionsOrNowMs.meRank != null) {
      meRank = Math.max(1, Math.min(count, Math.floor(optionsOrNowMs.meRank)));
    } else if (meUid) {
      meRank = Math.min(167, count);
    }
  }

  const weekInfo = getIstanbulWeekInfo(new Date(nowMs));
  const startMs = weekInfo.startOfWeekMs;

  // 100 oyunculu ve meUid olmayan varsayılan çağrılarda mevcut eşitlik senaryolarını koru
  if (count === 100 && !meUid) {
    const players: LeaderboardSeedEntry[] = [];
    for (let i = 1; i <= 100; i++) {
      const pad = String(i).padStart(3, '0');
      const uid = `seed_${pad}`;
      const nickname = `Test ${pad}`;
      const frame = SEED_FRAMES[(i - 1) % SEED_FRAMES.length];

      let wins: number;
      let losses: number;
      let reachedAt: number;

      if (i === 1) {
        wins = 40;
        losses = 1;
        reachedAt = startMs + 10 * 3600 * 1000;
      } else if (i === 2) {
        wins = 39;
        losses = 2;
        reachedAt = startMs + 12 * 3600 * 1000;
      } else if (i === 3) {
        wins = 38;
        losses = 1;
        reachedAt = startMs + 14 * 3600 * 1000;
      } else if (i === 4) {
        wins = 38;
        losses = 4;
        reachedAt = startMs + 14 * 3600 * 1000;
      } else if (i === 5) {
        wins = 37;
        losses = 2;
        reachedAt = startMs + 15 * 3600 * 1000;
      } else if (i === 6) {
        wins = 37;
        losses = 2;
        reachedAt = startMs + 18 * 3600 * 1000;
      } else if (i === 7) {
        wins = 36;
        losses = 3;
        reachedAt = startMs + 24 * 3600 * 1000;
      } else if (i === 8) {
        wins = 36;
        losses = 3;
        reachedAt = startMs + 24 * 3600 * 1000;
      } else if (i <= 15) {
        wins = 35 - Math.floor((i - 9) * 0.8);
        losses = 2 + (i % 5);
        reachedAt = startMs + (i * 4) * 3600 * 1000;
      } else if (i <= 40) {
        wins = Math.max(20, 30 - Math.floor((i - 16) * 0.45));
        losses = 3 + (i % 7);
        reachedAt = startMs + ((i * 3) % 120) * 3600 * 1000;
      } else if (i <= 75) {
        wins = Math.max(10, 20 - Math.floor((i - 41) * 0.3));
        losses = 4 + (i % 9);
        reachedAt = startMs + ((i * 2) % 140) * 3600 * 1000;
      } else {
        wins = Math.max(1, 10 - Math.floor((i - 76) * 0.38));
        losses = 5 + (i % 12);
        reachedAt = startMs + ((i * 5) % 150) * 3600 * 1000;
      }

      players.push({ uid, nickname, wins, losses, reachedAt, frame });
    }
    return players;
  }

  // count != 100 veya meUid içeren dinamik ve deterministik üretim:
  // Sıralama Kriteri: ORDER BY wins DESC, losses ASC, reached_at ASC, uid ASC
  // Slot rank 1'den count'a kadar artarken:
  // - wins monotonic azalan
  // - losses monotonic artan
  // - reachedAt strictly artan (startMs + rank * 60_000)
  // Bu üç kural sayesinde her rank kesin olarak bir sonraki rank'ın önündedir.
  const players: LeaderboardSeedEntry[] = [];
  const maxWins = Math.max(40, Math.ceil(count * 0.35));
  let fakePlayerIndex = 1;

  for (let rank = 1; rank <= count; rank++) {
    const isMeSlot = Boolean(meUid && rank === meRank);
    const pad = String(fakePlayerIndex).padStart(3, '0');
    const uid = isMeSlot ? meUid! : `seed_${pad}`;
    const nickname = isMeSlot ? 'Sen (Test)' : `Test ${pad}`;
    const frame = isMeSlot ? 'classic' : SEED_FRAMES[(fakePlayerIndex - 1) % SEED_FRAMES.length];

    if (!isMeSlot) {
      fakePlayerIndex++;
    }

    const wins =
      count === 1
        ? maxWins
        : Math.max(1, Math.round(maxWins - ((rank - 1) * (maxWins - 1)) / (count - 1)));
    const losses = 1 + Math.floor((rank - 1) / 5);
    const reachedAt = startMs + rank * 60 * 1000;

    players.push({ uid, nickname, wins, losses, reachedAt, frame });
  }

  return players;
}

function resolveAuthToken(): string {
  if (process.env.ADMIN_TOKEN && process.env.ADMIN_TOKEN.trim().length > 0) {
    return process.env.ADMIN_TOKEN.trim();
  }

  const devVarsPath = resolve(process.cwd(), '.dev.vars');
  if (existsSync(devVarsPath)) {
    try {
      const content = readFileSync(devVarsPath, 'utf8');
      const lines = content.split('\n');
      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.startsWith('ADMIN_TOKEN=')) {
          const val = trimmed.slice('ADMIN_TOKEN='.length).trim().replace(/^["']|["']$/g, '');
          if (val.length > 0) return val;
        }
      }
    } catch {}
  }

  return 'dev:admin';
}

export interface CliArgs {
  isClear: boolean;
  clearMeUid?: string;
  serverUrl: string;
  count: number;
  meUid?: string;
  meRank?: number;
}

export function parseCliArgs(argv: string[] = process.argv.slice(2)): CliArgs {
  let isClear = false;
  let clearMeUid: string | undefined;
  let rawServerUrl = 'http://127.0.0.1:8787';
  let count = 100;
  let meUid: string | undefined;
  let meRank: number | undefined;

  for (const arg of argv) {
    if (arg === '--clear') {
      isClear = true;
    } else if (arg.startsWith('--clear-me=')) {
      clearMeUid = arg.slice('--clear-me='.length).trim();
    } else if (arg.startsWith('--server=')) {
      rawServerUrl = arg.slice('--server='.length).trim();
    } else if (arg.startsWith('--count=')) {
      const parsed = parseInt(arg.slice('--count='.length).trim(), 10);
      if (!isNaN(parsed) && parsed > 0) count = parsed;
    } else if (arg.startsWith('--me-uid=')) {
      const val = arg.slice('--me-uid='.length).trim();
      if (val.length > 0) meUid = val;
    } else if (arg.startsWith('--me-rank=')) {
      const parsed = parseInt(arg.slice('--me-rank='.length).trim(), 10);
      if (!isNaN(parsed) && parsed > 0) meRank = parsed;
    }
  }

  const serverUrl = validateLocalServerUrl(rawServerUrl);
  return { isClear, clearMeUid, serverUrl, count, meUid, meRank };
}

export async function run(): Promise<void> {
  const { isClear, clearMeUid, serverUrl, count, meUid, meRank } = parseCliArgs();
  const token = resolveAuthToken();

  console.log('========================================================');
  console.log('KelimeGo Liderlik Tablosu Yerel Tohumlama Aracı');
  console.log(`Hedef Sunucu : ${serverUrl}`);
  if (isClear || clearMeUid) {
    console.log(
      `Mod          : TEMİZLEME (${isClear ? 'seed_*' : ''}${isClear && clearMeUid ? ' + ' : ''}${clearMeUid ? `me-uid=${clearMeUid}` : ''})`
    );
  } else {
    console.log(
      `Mod          : TOHUMLAMA (${count} Oyuncu${meUid ? `, me-uid=${meUid} @ sıra ${meRank ?? (count >= 167 ? 167 : count)}` : ''})`
    );
  }
  console.log('========================================================\n');

  // Temizleme modu
  if (isClear || clearMeUid) {
    if (isClear) {
      console.log("Liderlik tablosundaki 'seed_' ön ekli test kayıtları temizleniyor...");
      try {
        const res = await fetch(`${serverUrl}/admin/leaderboard/clear`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
        });

        if (!res.ok) {
          const errText = await res.text();
          console.error(`Temizleme başarısız (HTTP ${res.status}): ${errText}`);
          process.exit(1);
        }

        const data = (await res.json()) as { success: boolean; deleted: number };
        console.log(`✓ Başarılı: ${data.deleted} adet test oyuncusu liderlik tablosundan temizlendi.`);
        console.log('  (Gerçek kullanıcı kayıtlarına dokunulmadı.)\n');
      } catch (err) {
        console.error(`Bağlantı hatası: ${err instanceof Error ? err.message : String(err)}`);
        console.error('Lütfen yerel "npx wrangler dev" sunucusunun çalıştığından emin olun.');
        process.exit(1);
      }
    }

    if (clearMeUid) {
      console.log(`Test kullanıcısı (${clearMeUid}) liderlik tablosundan temizleniyor...`);
      try {
        const res = await fetch(`${serverUrl}/admin/leaderboard/clear`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ clearMeUid }),
        });

        if (!res.ok) {
          const errText = await res.text();
          console.error(`Temizleme başarısız (HTTP ${res.status}): ${errText}`);
          process.exit(1);
        }

        const data = (await res.json()) as { success: boolean; deleted: number };
        console.log(`✓ Başarılı: ${clearMeUid} liderlik tablosundan temizlendi (Silinen: ${data.deleted}).\n`);
      } catch (err) {
        console.error(`Bağlantı hatası: ${err instanceof Error ? err.message : String(err)}`);
        process.exit(1);
      }
    }
    return;
  }

  // Tohumlama modu: oyuncu üret
  const effectiveMeRank = meUid ? (meRank ?? (count >= 167 ? 167 : count)) : undefined;
  const players = generateSeedPlayers({ count, meUid, meRank: effectiveMeRank });
  const weekInfo = getIstanbulWeekInfo();

  console.log(`${players.length} oyuncu verisi hazırlandı (Hafta: ${weekInfo.weekKey}).`);
  if (meUid) {
    const meEntry = players.find((p) => p.uid === meUid);
    console.log(
      `Özel kullanıcı konumu: UID=${meUid}, Hedef Sıra=${effectiveMeRank}, Galibiyet=${meEntry?.wins}, Mağlubiyet=${meEntry?.losses}`
    );
  }
  console.log(`Leaderboard DO uç noktasına (${serverUrl}/admin/leaderboard/seed) gönderiliyor...\n`);

  try {
    const res = await fetch(`${serverUrl}/admin/leaderboard/seed`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ entries: players, meUid }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error(`Tohumlama başarısız (HTTP ${res.status}): ${errText}`);
      process.exit(1);
    }

    const data = (await res.json()) as { success: boolean; inserted: number };
    console.log(`✓ Başarılı: ${data.inserted} oyuncu liderlik tablosuna eklendi.`);
    console.log(`  Hafta Anahtarı : ${weekInfo.weekKey}`);
    console.log(`  Oyuncu Sayısı  : ${players.length}`);
    console.log(`  Çerçeveler     : ${SEED_FRAMES.join(', ')}\n`);

    if (meUid) {
      const meEntry = players.find((p) => p.uid === meUid);
      console.log(
        `✓ Belirtilen test kullanıcısı (${meUid}) deterministik olarak tam ${effectiveMeRank}. sıraya yerleştirildi.`
      );
      console.log(`  Galibiyet: ${meEntry?.wins}, Mağlubiyet: ${meEntry?.losses}\n`);
    }

    const sampleSlots = [0, 1, 2, 3];
    if (players.length >= 100) sampleSlots.push(99);
    if (effectiveMeRank && effectiveMeRank > 0 && effectiveMeRank <= players.length) {
      sampleSlots.push(effectiveMeRank - 1);
    }
    if (players.length > 100 && !sampleSlots.includes(players.length - 1)) {
      sampleSlots.push(players.length - 1);
    }
    sampleSlots.sort((a, b) => a - b);
    const uniqueSlots = Array.from(new Set(sampleSlots));

    console.log('Örnek Sıralama Dağılımı:');
    console.log('----------------------------------------------------------------------');
    console.log('Sıra | UID          | Takma Ad     | G  | M  | Çerçeve         ');
    console.log('----------------------------------------------------------------------');
    for (const idx of uniqueSlots) {
      const p = players[idx];
      const rankNum = idx + 1;
      console.log(
        `${String(rankNum).padEnd(4)} | ` +
        `${p.uid.padEnd(12)} | ` +
        `${p.nickname.padEnd(12)} | ` +
        `${String(p.wins).padStart(2)} | ` +
        `${String(p.losses).padStart(2)} | ` +
        `${p.frame.padEnd(16)}`
      );
    }
    console.log('----------------------------------------------------------------------\n');
    console.log('İpucu: Testleri tamamladıktan sonra sahte verileri temizlemek için:');
    console.log('  npm run seed:lb -- --clear\n');
    if (meUid) {
      console.log(`Kendi test kaydınızı da temizlemek için:`);
      console.log(`  npm run seed:lb -- --clear-me=${meUid}\n`);
    }
  } catch (err) {
    console.error(`Bağlantı hatası: ${err instanceof Error ? err.message : String(err)}`);
    console.error('Lütfen yerel "npx wrangler dev" sunucusunun çalıştığından emin olun.');
    process.exit(1);
  }
}

// Komut satırından doğrudan çağrıldığında çalıştır
if (process.argv[1] && process.argv[1].endsWith('seed-leaderboard.ts')) {
  run();
}
