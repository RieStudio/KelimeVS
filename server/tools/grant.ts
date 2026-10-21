import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function resolveAdminToken(): string {
  if (process.env.ADMIN_TOKEN && process.env.ADMIN_TOKEN.trim().length > 0) {
    return process.env.ADMIN_TOKEN.trim();
  }

  // .dev.vars dosyasını kontrol et (lokal geliştirme için)
  const devVarsPath = resolve(process.cwd(), '.dev.vars');
  if (existsSync(devVarsPath)) {
    try {
      const content = readFileSync(devVarsPath, 'utf8');
      const lines = content.split('\n');
      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.startsWith('ADMIN_TOKEN=')) {
          const val = trimmed.slice('ADMIN_TOKEN='.length).trim().replace(/^["']|["']$/g, '');
          if (val.length > 0) {
            return val;
          }
        }
      }
    } catch {
      // yoksay
    }
  }

  console.error('HATA: ADMIN_TOKEN bulunamadı.');
  console.error('Lütfen ortam değişkeni olarak ayarlayın veya server/.dev.vars dosyasına ekleyin:');
  console.error('  ADMIN_TOKEN=gizli-yonetici-anahtari');
  console.error('Veya komut öncesinde:');
  console.error('  $env:ADMIN_TOKEN="gizli-yonetici-anahtari"; npm run grant -- --uid=<uid> --coins=1000 --frames=gold,diamond');
  process.exit(1);
}

function parseCliArgs(): {
  uid?: string;
  coins?: number;
  frames?: string[];
  serverUrl: string;
} {
  const args = process.argv.slice(2);
  let uid: string | undefined;
  let coins: number | undefined;
  let frames: string[] | undefined;
  let serverUrl = 'https://api.riestudio.com.tr';

  for (const arg of args) {
    if (arg === '--local') {
      serverUrl = 'http://localhost:8787';
    } else if (arg.startsWith('--server=')) {
      serverUrl = arg.slice('--server='.length).trim().replace(/\/+$/, '');
    } else if (arg.startsWith('--uid=')) {
      uid = arg.slice('--uid='.length).trim();
    } else if (arg.startsWith('--coins=')) {
      const parsed = parseInt(arg.slice('--coins='.length).trim(), 10);
      if (!Number.isNaN(parsed)) {
        coins = parsed;
      }
    } else if (arg.startsWith('--frames=')) {
      frames = arg
        .slice('--frames='.length)
        .split(',')
        .map((f) => f.trim().toLowerCase())
        .filter((f) => f.length > 0);
    }
  }

  return { uid, coins, frames, serverUrl };
}

async function main(): Promise<void> {
  const { uid, coins, frames, serverUrl } = parseCliArgs();

  if (!uid) {
    console.error('HATA: --uid parametresi zorunludur.');
    console.error('Kullanım:');
    console.error('  npm run grant -- --uid=<uid> [--coins=1000] [--frames=gold,diamond] [--local]');
    process.exit(1);
  }

  if (coins === undefined && (!frames || frames.length === 0)) {
    console.error('HATA: En az bir tanımlama parametresi (--coins veya --frames) belirtilmelidir.');
    process.exit(1);
  }

  const adminToken = resolveAdminToken();

  try {
    const res = await fetch(`${serverUrl}/admin/grant`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${adminToken}`,
      },
      body: JSON.stringify({
        uid,
        coins,
        frameIds: frames,
      }),
    });

    if (res.status === 401) {
      console.error('Yetkilendirme Hatası: ADMIN_TOKEN geçersiz veya sunucuda tanımlanmamış.');
      process.exit(1);
    }

    if (res.status === 410) {
      console.error('Hata: Hesap silinmiş (tombstone), tanımlama uygulanamaz.');
      process.exit(1);
    }

    const data = (await res.json().catch(() => ({}))) as {
      success?: boolean;
      uid?: string;
      coins?: number;
      grantedFrames?: string[];
      error?: string;
      message?: string;
    };

    if (!res.ok || !data.success) {
      console.error(`İşlem Başarısız (HTTP ${res.status}): ${data.message ?? data.error ?? 'Bilinmeyen hata'}`);
      process.exit(1);
    }

    console.log('✓ Tanımlama başarıyla tamamlandı:');
    console.log(`  Hedef UID           : ${data.uid}`);
    console.log(`  Güncel Jeton Bakiyesi: ${data.coins}`);
    console.log(`  Tanımlanan Çerçeveler: ${data.grantedFrames && data.grantedFrames.length > 0 ? data.grantedFrames.join(', ') : '(yeni çerçeve eklenmedi)'}`);
  } catch (err) {
    console.error(`Bağlantı hatası: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}

main();

