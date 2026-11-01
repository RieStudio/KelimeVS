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
 *   ön eki taşıyan kayıtları güncel haftaya toplu ve güvenle yazar.
 * - Gerçek kullanıcı kayıtlarına ASLA dokunulmaz; --clear parametresi yalnızca 'seed_%'
 *   kayıtlarını temizler.
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

/**
 * Güncel hafta için 100 sahte oyuncu üretir.
 * - uid: seed_001 ... seed_100
 * - nickname: Test 001 ... Test 100
 * - wins: 1-40 arası dağılım
 * - Eşitlik bozucu kuralları (ORDER BY wins DESC, losses ASC, reached_at ASC, uid ASC) sergileyen örnekler içerir
 * - classic ve 9 yeni görsel çerçeveyi eşit dağıtır
 */
export function generateSeedPlayers(nowMs: number = Date.now()): LeaderboardSeedEntry[] {
  const weekInfo = getIstanbulWeekInfo(new Date(nowMs));
  const startMs = weekInfo.startOfWeekMs;

  const players: LeaderboardSeedEntry[] = [];

  for (let i = 1; i <= 100; i++) {
    const pad = String(i).padStart(3, '0');
    const uid = `seed_${pad}`;
    const nickname = `Test ${pad}`;
    const frame = SEED_FRAMES[(i - 1) % SEED_FRAMES.length];

    let wins: number;
    let losses: number;
    let reachedAt: number;

    // Eşitlik bozucu kuralları belirgin şekilde göstermek için özel planlanmış sıralar:
    // Sıralama Kuralı: ORDER BY wins DESC, losses ASC, reached_at ASC, uid ASC
    if (i === 1) {
      wins = 40;
      losses = 1;
      reachedAt = startMs + 10 * 3600 * 1000; // Pazartesi 10:00
    } else if (i === 2) {
      wins = 39;
      losses = 2;
      reachedAt = startMs + 12 * 3600 * 1000;
    } else if (i === 3) {
      // 3. ve 4. sıra: Eşit galibiyet (38), farklı mağlubiyet (1 vs 4) -> Az mağlubiyet üstte
      wins = 38;
      losses = 1;
      reachedAt = startMs + 14 * 3600 * 1000;
    } else if (i === 4) {
      wins = 38;
      losses = 4;
      reachedAt = startMs + 14 * 3600 * 1000;
    } else if (i === 5) {
      // 5. ve 6. sıra: Eşit galibiyet (37), eşit mağlubiyet (2), farklı reached_at -> Erken ulaşan üstte
      wins = 37;
      losses = 2;
      reachedAt = startMs + 15 * 3600 * 1000; // 15:00
    } else if (i === 6) {
      wins = 37;
      losses = 2;
      reachedAt = startMs + 18 * 3600 * 1000; // 18:00
    } else if (i === 7) {
      // 7. ve 8. sıra: Eşit galibiyet (36), eşit mağlubiyet (3), eşit reached_at -> uid alfabetik (seed_007 < seed_008)
      wins = 36;
      losses = 3;
      reachedAt = startMs + 24 * 3600 * 1000; // Salı 00:00
    } else if (i === 8) {
      wins = 36;
      losses = 3;
      reachedAt = startMs + 24 * 3600 * 1000;
    } else if (i <= 15) {
      // 9 - 15: 35-30 galibiyet aralığı
      wins = 35 - Math.floor((i - 9) * 0.8);
      losses = 2 + (i % 5);
      reachedAt = startMs + (i * 4) * 3600 * 1000;
    } else if (i <= 40) {
      // 16 - 40: 29-20 galibiyet aralığı (arada eşitlikler)
      wins = Math.max(20, 30 - Math.floor((i - 16) * 0.45));
      losses = 3 + (i % 7);
      reachedAt = startMs + ((i * 3) % 120) * 3600 * 1000;
    } else if (i <= 75) {
      // 41 - 75: 19-10 galibiyet aralığı
      wins = Math.max(10, 20 - Math.floor((i - 41) * 0.3));
      losses = 4 + (i % 9);
      reachedAt = startMs + ((i * 2) % 140) * 3600 * 1000;
    } else {
      // 76 - 100: 9-1 galibiyet aralığı (tablonun alt sıraları)
      wins = Math.max(1, 10 - Math.floor((i - 76) * 0.38));
      losses = 5 + (i % 12);
      reachedAt = startMs + ((i * 5) % 150) * 3600 * 1000;
    }

    players.push({
      uid,
      nickname,
      wins,
      losses,
      reachedAt,
      frame,
    });
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

function parseCliArgs(): { isClear: boolean; serverUrl: string } {
  const args = process.argv.slice(2);
  let isClear = false;
  let rawServerUrl = 'http://127.0.0.1:8787';

  for (const arg of args) {
    if (arg === '--clear') {
      isClear = true;
    } else if (arg.startsWith('--server=')) {
      rawServerUrl = arg.slice('--server='.length).trim();
    }
  }

  // Güvenlik denetimi: Hedef URL yerel değilse anında reddet ve çık
  const serverUrl = validateLocalServerUrl(rawServerUrl);
  return { isClear, serverUrl };
}

export async function run(): Promise<void> {
  const { isClear, serverUrl } = parseCliArgs();
  const token = resolveAuthToken();

  console.log('========================================================');
  console.log('KelimeGo Liderlik Tablosu Yerel Tohumlama Aracı');
  console.log(`Hedef Sunucu : ${serverUrl}`);
  console.log(`Mod          : ${isClear ? 'TEMİZLEME (--clear)' : 'TOHUMLAMA (100 Sahte Oyuncu)'}`);
  console.log('========================================================\n');

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
    return;
  }

  // Tohumlama modu: 100 oyuncu üret
  const players = generateSeedPlayers();
  const weekInfo = getIstanbulWeekInfo();

  console.log(`100 sahte oyuncu verisi hazırlandı (Hafta: ${weekInfo.weekKey}).`);
  console.log(`Leaderboard DO uç noktasına (${serverUrl}/admin/leaderboard/seed) gönderiliyor...\n`);

  try {
    const res = await fetch(`${serverUrl}/admin/leaderboard/seed`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ entries: players }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error(`Tohumlama başarısız (HTTP ${res.status}): ${errText}`);
      process.exit(1);
    }

    const data = (await res.json()) as { success: boolean; inserted: number };
    console.log(`✓ Başarılı: ${data.inserted} sahte oyuncu liderlik tablosuna eklendi.`);
    console.log(`  Hafta Anahtarı : ${weekInfo.weekKey}`);
    console.log(`  Oyuncu Sayısı  : ${players.length}`);
    console.log(`  Çerçeveler     : ${SEED_FRAMES.join(', ')}\n`);

    console.log('Örnek Sıralama Dağılımı ve Eşitlik Bozucu Kurallar:');
    console.log('----------------------------------------------------------------------');
    console.log('Sıra | UID      | Takma Ad | G | M | Çerçeve          | Eşitlik Durumu');
    console.log('----------------------------------------------------------------------');
    for (const p of [players[0], players[1], players[2], players[3], players[4], players[5], players[6], players[7], players[49], players[99]]) {
      const tieNote =
        p.uid === 'seed_003' ? '38G, 1M (4M olan seed_004 ün önünde)' :
        p.uid === 'seed_004' ? '38G, 4M (daha çok mağlubiyet -> 4.)' :
        p.uid === 'seed_005' ? '37G, 2M, 15:00 (erken ulaştı)' :
        p.uid === 'seed_006' ? '37G, 2M, 18:00 (geç ulaştı -> 6.)' :
        p.uid === 'seed_007' ? '36G, 3M, eşit süre (seed_007 < seed_008)' :
        p.uid === 'seed_008' ? '36G, 3M, eşit süre (alfabetik -> 8.)' :
        p.uid === 'seed_050' ? 'Orta sıra örneği' :
        p.uid === 'seed_100' ? '100. sıra (1 Galibiyet)' : 'Liderlik zirvesi';

      console.log(
        `${String(p.uid.replace('seed_', '')).padEnd(4)} | ` +
        `${p.uid.padEnd(8)} | ` +
        `${p.nickname.padEnd(8)} | ` +
        `${String(p.wins).padStart(2)} | ` +
        `${String(p.losses).padStart(2)} | ` +
        `${p.frame.padEnd(16)} | ` +
        `${tieNote}`
      );
    }
    console.log('----------------------------------------------------------------------\n');
    console.log('İpucu: Testleri tamamladıktan sonra sahte verileri temizlemek için:');
    console.log('  npm run seed:lb -- --clear\n');
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
