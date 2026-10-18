// KelimeGo Canlı Sunucu Liderlik Tablosu ve Profil Hata Ayıklama Betiği (lb-debug)
// Salt-okunur (GET) çağrılar yapar, prodüksiyona veri yazmaz.

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  parseApiKeyFromDevVars,
  parseFirebaseErrorMessage,
  parseSessionCache,
} from './ghost-opponent-logic';

function resolveApiKey(): string {
  if (process.env.FIREBASE_WEB_API_KEY) {
    return process.env.FIREBASE_WEB_API_KEY.trim();
  }
  const devVarsPath = resolve(process.cwd(), '.dev.vars');
  if (existsSync(devVarsPath)) {
    try {
      const content = readFileSync(devVarsPath, 'utf8');
      const fromFile = parseApiKeyFromDevVars(content);
      if (fromFile) return fromFile;
    } catch {
      // yoksay
    }
  }
  // google-services.json kontrol et
  const gsPath = resolve(process.cwd(), '../app/android/app/google-services.json');
  if (existsSync(gsPath)) {
    try {
      const gs = JSON.parse(readFileSync(gsPath, 'utf8'));
      const key = gs?.client?.[0]?.api_key?.[0]?.current_key;
      if (typeof key === 'string' && key.length > 0) return key;
    } catch {}
  }

  // firebase_options.dart kontrol et
  const foPath = resolve(process.cwd(), '../app/lib/firebase_options.dart');
  if (existsSync(foPath)) {
    try {
      const fo = readFileSync(foPath, 'utf8');
      const m = fo.match(/apiKey:\s*'([^']+)'/);
      if (m && m[1]) return m[1];
    } catch {}
  }

  throw new Error('FIREBASE_WEB_API_KEY bulunamadı (.dev.vars, ortam değişkeni veya google-services.json)');
}

async function createAnonymousSession(apiKey: string): Promise<string> {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });

  if (!response.ok) {
    let errorMessage: string | undefined;
    try {
      const json: unknown = await response.json();
      errorMessage = parseFirebaseErrorMessage(json);
    } catch {}
    throw new Error(`Firebase Auth REST başarısız (HTTP ${response.status}: ${errorMessage})`);
  }

  const data = (await response.json()) as { readonly idToken?: string };
  if (!data.idToken) throw new Error('idToken alınamadı');
  return data.idToken;
}

async function refreshIdToken(apiKey: string, refreshToken: string): Promise<string> {
  const url = `https://securetoken.googleapis.com/v1/token?key=${apiKey}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}`,
  });

  if (!response.ok) {
    throw new Error(`Token yenileme başarısız (HTTP ${response.status})`);
  }

  const data = (await response.json()) as { readonly id_token?: string };
  if (!data.id_token) throw new Error('id_token bulunamadı');
  return data.id_token;
}

async function main(): Promise<void> {
  const serverUrl = process.env.SERVER_URL?.trim() || 'https://api.riestudio.com.tr';
  const apiKey = resolveApiKey();

  console.log('========================================================');
  console.log(`KelimeGo Liderlik Tablosu ve Profil Tanı Aracı (lb-debug)`);
  console.log(`Hedef: ${serverUrl}`);
  console.log('========================================================\n');

  // 1. Yeni anonim hesap oluştur
  console.log('1. Yeni test anonim hesabı oluşturuluyor...');
  const newIdToken = await createAnonymousSession(apiKey);
  console.log('✓ Yeni anonim oturum alındı.\n');

  // 2. GET /me (Yeni anonim kullanıcı)
  console.log('2. GET /me (Yeni kullanıcı) çağrılıyor...');
  const meRes = await fetch(`${serverUrl}/me`, {
    headers: { Authorization: `Bearer ${newIdToken}` },
  });
  console.log(`HTTP ${meRes.status} ${meRes.statusText}`);
  const meBody = await meRes.text();
  console.log('Ham Yanıt /me:', meBody, '\n');

  // 3. GET /leaderboard (Yeni anonim kullanıcı)
  console.log('3. GET /leaderboard çağrılıyor...');
  const lbRes = await fetch(`${serverUrl}/leaderboard`, {
    headers: { Authorization: `Bearer ${newIdToken}` },
  });
  console.log(`HTTP ${lbRes.status} ${lbRes.statusText}`);
  const lbBody = await lbRes.text();
  console.log('Ham Yanıt /leaderboard:', lbBody, '\n');

  // 4. Eğer .ghost-session.json varsa, Ghost'un profilini (GET /me) de kontrol et
  const ghostSessionPath = resolve(process.cwd(), '.ghost-session.json');
  if (existsSync(ghostSessionPath)) {
    console.log('4. Mevcut Ghost oturumu (.ghost-session.json) bulundu, Ghost profili sorgulanıyor...');
    try {
      const raw = readFileSync(ghostSessionPath, 'utf8');
      const session = parseSessionCache(raw);
      if (session) {
        const ghostToken = await refreshIdToken(apiKey, session.refreshToken);
        const ghostMeRes = await fetch(`${serverUrl}/me`, {
          headers: { Authorization: `Bearer ${ghostToken}` },
        });
        console.log(`Ghost /me: HTTP ${ghostMeRes.status}`);
        const ghostMeBody = await ghostMeRes.text();
        console.log('Ham Yanıt Ghost /me:', ghostMeBody);

        const ghostLbRes = await fetch(`${serverUrl}/leaderboard`, {
          headers: { Authorization: `Bearer ${ghostToken}` },
        });
        console.log(`Ghost /leaderboard: HTTP ${ghostLbRes.status}`);
        const ghostLbBody = await ghostLbRes.text();
        console.log('Ham Yanıt Ghost /leaderboard:', ghostLbBody);
      }
    } catch (err) {
      console.log('Ghost oturumu okunamadı / sorgulanamadı:', err);
    }
  }

  console.log('\n========================================================');
  console.log('Tanılama tamamlandı.');
}

main().catch((err) => {
  console.error('Hata:', err);
  process.exit(1);
});
