import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { performance } from 'node:perf_hooks';
import {
  RealtimeDbContentProvider,
  ServiceAccountTokenProvider,
} from '../src/content';

function parseDevVars(filePath: string): Record<string, string> {
  if (!existsSync(filePath)) {
    throw new Error(`Dosya bulunamadı: ${filePath}`);
  }

  const content = readFileSync(filePath, 'utf-8');
  const vars: Record<string, string> = {};

  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const eqIdx = trimmed.indexOf('=');
    if (eqIdx !== -1) {
      const key = trimmed.slice(0, eqIdx).trim();
      const val = trimmed.slice(eqIdx + 1).trim();
      vars[key] = val;
    }
  }

  return vars;
}

async function main() {
  console.log('========================================================');
  console.log('KelimeGo Firebase Realtime Database İçerik Kontrolü');
  console.log('========================================================\n');

  const devVarsPath = resolve(process.cwd(), '.dev.vars');
  let vars: Record<string, string> = {};

  try {
    vars = parseDevVars(devVarsPath);
  } catch (err: unknown) {
    console.error('❌ HATA [Aşama: yapılandırma]: .dev.vars dosyası okunamadı.');
    const msg = err instanceof Error ? err.message : String(err);
    console.error(msg);
    process.exit(1);
  }

  const serviceAccountB64 = vars.FIREBASE_SERVICE_ACCOUNT_B64?.trim();
  if (!serviceAccountB64) {
    console.error('❌ HATA [Aşama: kimlik]: FIREBASE_SERVICE_ACCOUNT_B64 .dev.vars içinde bulunamadı.');
    process.exit(1);
  }

  const databaseUrl =
    vars.FIREBASE_DATABASE_URL?.trim() ||
    'https://kelimegov2-default-rtdb.europe-west1.firebasedatabase.app';

  let tokenProvider: ServiceAccountTokenProvider;

  // 1. Aşama: Kimlik (Service Account & OAuth2 Token Alımı)
  console.log('1. Kimlik doğrulanıyor (Google OAuth2 token alınıyor)...');
  const t0 = performance.now();
  try {
    tokenProvider = new ServiceAccountTokenProvider(serviceAccountB64);
    await tokenProvider.getAccessToken();
    console.log('   ✓ Google OAuth2 access_token başarıyla alındı.');
  } catch (err: unknown) {
    console.error('❌ HATA [Aşama: kimlik]: Google OAuth2 token alımı başarısız oldu.');
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`   Ayrıntı: ${msg}`);
    process.exit(1);
  }

  // 2. Aşama: Ağ & 3. Aşama: Ayrıştırma (Realtime Database Sorgusu ve Analiz)
  console.log('2. Firebase Realtime Database /questions_pool.json sorgulanıyor...');
  const provider = new RealtimeDbContentProvider({
    databaseUrl,
    tokenProvider,
    ttlSeconds: 3600,
  });

  try {
    const { questions, stats, authMethod } = await provider.fetchFromDatabase();
    const durationMs = Math.round(performance.now() - t0);

    const authMethodDesc =
      authMethod === 'header'
        ? 'Authorization: Bearer <access_token> başlığı'
        : authMethod === 'query_param'
          ? '?access_token= URL sorgu parametresi'
          : 'Yetkilendirme olmadan';

    console.log('\n========================================================');
    console.log('🎉 İÇERİK KONTROLÜ BAŞARIYLA TAMAMLANDI');
    console.log('========================================================');
    console.log(`Yetkilendirme Durumu : Başarılı`);
    console.log(`Çalışan Yetki Yöntemi: ${authMethodDesc}`);
    console.log(`Kategori Sayısı      : ${stats.categoriesCount}`);
    console.log(`Geçerli Soru Sayısı  : ${questions.length}`);
    console.log(`Toplam Cevap Sayısı  : ${stats.answersCount}`);
    console.log(`Atlanan Bozuk Soru   : ${stats.skippedQuestionsCount}`);
    console.log(`Toplam Çekme Süresi  : ${durationMs} ms`);
    console.log('========================================================\n');
  } catch (err: unknown) {
    console.error('\n❌ HATA [Aşama: ağ veya ayrıştırma]: Realtime Database içeriği çekilemedi veya ayrıştırılamadı.');
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`   Ayrıntı: ${msg}`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('Beklenmeyen hata:', e instanceof Error ? e.message : e);
  process.exit(1);
});

