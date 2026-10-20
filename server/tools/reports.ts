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
  console.error('  $env:ADMIN_TOKEN="gizli-yonetici-anahtari"; npm run reports');
  process.exit(1);
}

function parseCliArgs(): {
  isLocal: boolean;
  uid?: string;
  limit: number;
  summaryOnly: boolean;
} {
  const args = process.argv.slice(2);
  let isLocal = false;
  let uid: string | undefined;
  let limit = 20;
  let summaryOnly = false;

  for (const arg of args) {
    if (arg === '--local') {
      isLocal = true;
    } else if (arg.startsWith('--uid=')) {
      uid = arg.slice('--uid='.length).trim();
    } else if (arg.startsWith('--limit=')) {
      const parsed = parseInt(arg.slice('--limit='.length), 10);
      if (Number.isFinite(parsed) && parsed > 0) {
        limit = parsed;
      }
    } else if (arg === '--summary') {
      summaryOnly = true;
    }
  }

  return { isLocal, uid, limit, summaryOnly };
}

async function main(): Promise<void> {
  const token = resolveAdminToken();
  const { isLocal, uid, limit, summaryOnly } = parseCliArgs();

  const baseUrl = isLocal
    ? 'http://localhost:8787'
    : (process.env.SERVER_URL ?? 'https://api.riestudio.com.tr');

  console.log(`\n=== KelimeVS Bildirim İnceleme Aracı ===`);
  console.log(`Hedef Sunucu: ${baseUrl}`);
  if (uid) console.log(`Filtre: reportedUid = ${uid}`);
  console.log(`Limit: ${limit}\n`);

  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/json',
  };

  try {
    // 1. Özet Bilgileri Çek (En çok bildirilen oyuncular)
    const summaryUrl = `${baseUrl}/admin/reports?view=summary&limit=15`;
    const summaryRes = await fetch(summaryUrl, { headers });

    if (!summaryRes.ok) {
      if (summaryRes.status === 401) {
        console.error('Yetkilendirme Hatası: ADMIN_TOKEN geçersiz veya sunucuda tanımlanmamış.');
        process.exit(1);
      }
      console.error(`Sunucu Hatası: HTTP ${summaryRes.status} ${summaryRes.statusText}`);
      process.exit(1);
    }

    const summaryData = (await summaryRes.json()) as {
      summary?: Array<{
        reportedUid: string;
        reportedNickname: string;
        reportCount: number;
        lastReportedAt: number;
      }>;
    };

    const summaries = summaryData.summary ?? [];
    console.log('--- EN ÇOK BİLDİRİLEN OYUNCULAR (ÖZET) ---');
    if (summaries.length === 0) {
      console.log('Kayıtlı bildirim bulunmamaktadır.\n');
    } else {
      console.table(
        summaries.map((s) => ({
          'Bildirilen UID': s.reportedUid,
          'Takma Ad': s.reportedNickname,
          'Bildirim Sayısı': s.reportCount,
          'Son Bildirim': new Date(s.lastReportedAt).toLocaleString('tr-TR'),
        }))
      );
      console.log();
    }

    if (summaryOnly) {
      return;
    }

    // 2. Detaylı Bildirim Listesini Çek
    let reportsUrl = `${baseUrl}/admin/reports?limit=${limit}`;
    if (uid) {
      reportsUrl += `&reportedUid=${encodeURIComponent(uid)}`;
    }

    const reportsRes = await fetch(reportsUrl, { headers });
    if (!reportsRes.ok) {
      console.error(`Rapor listesi çekilemedi: HTTP ${reportsRes.status}`);
      process.exit(1);
    }

    const reportsData = (await reportsRes.json()) as {
      reports?: Array<{
        id: string;
        reporterUid: string;
        reportedUid: string;
        matchId: string;
        reason: string;
        reportedNickname: string;
        answers: string[];
        createdAt: number;
      }>;
      total?: number;
    };

    const reports = reportsData.reports ?? [];
    console.log(`--- SON BİLDİRİMLER (Toplam Kayıt: ${reportsData.total ?? reports.length}) ---`);

    if (reports.length === 0) {
      console.log('Kayıt bulunamadı.\n');
      return;
    }

    for (let i = 0; i < reports.length; i++) {
      const r = reports[i];
      const dateStr = new Date(r.createdAt).toLocaleString('tr-TR');
      console.log(`\n[#${i + 1}] ID: ${r.id} | Tarih: ${dateStr}`);
      console.log(`  Bildirilen: "${r.reportedNickname}" (UID: ${r.reportedUid})`);
      console.log(`  Bildiren:   UID ${r.reporterUid}`);
      console.log(`  Maç ID:     ${r.matchId}`);
      console.log(`  Sebep:      ${r.reason}`);
      console.log(`  Cevaplar:   ${r.answers.length > 0 ? r.answers.map((a) => `"${a}"`).join(', ') : '(Cevap kaydı yok)'}`);
    }
    console.log('\n========================================\n');
  } catch (err) {
    console.error('İstek sırasında bir ağ hatası oluştu:', err);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Beklenmeyen hata:', err);
  process.exit(1);
});

