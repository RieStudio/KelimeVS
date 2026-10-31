import { authenticateRequest, type AuthEnv } from './auth';
import type { EnergyEnv } from './energy';
import { Matchmaker } from './matchmaker';
import { MatchRoom } from './matchRoom';
import { UserProfile } from './userProfile';
import { Leaderboard } from './leaderboard';
import { ReportStore } from './reportStore';

export { Matchmaker, MatchRoom, UserProfile, Leaderboard, ReportStore };

export interface Env extends AuthEnv, EnergyEnv {
  readonly MATCHMAKER: DurableObjectNamespace<Matchmaker>;
  readonly MATCH_ROOM: DurableObjectNamespace<MatchRoom>;
  readonly USER_PROFILE: DurableObjectNamespace<UserProfile>;
  readonly LEADERBOARD?: DurableObjectNamespace<Leaderboard>;
  readonly REPORT_STORE?: DurableObjectNamespace<ReportStore>;
  readonly ADMIN_TOKEN?: string;
  readonly MAX_REPORTS_PER_DAY?: string;
  readonly MAX_BLOCKS_PER_USER?: string;
  readonly FAST_TIMERS?: string;
  readonly TURN_GRACE_MS?: string;
  readonly CONTENT_SOURCE?: string;
  readonly FIREBASE_DATABASE_URL?: string;
  readonly FIREBASE_SERVICE_ACCOUNT_B64?: string;
  readonly CONTENT_TTL_SECONDS?: string;
  readonly CONTENT_VERSION_CHECK_SECONDS?: string;
  readonly START_COINS?: string;
  readonly WIN_COINS?: string;
  readonly LOSS_COINS?: string;
  readonly DISCONNECT_WIN_COINS?: string;
  readonly DISCONNECT_LOSS_COINS?: string;
  readonly DAILY_MATCH_COIN_CAP?: string;
  readonly EXTRA_TIME_COST?: string;
  readonly EXTRA_TIME_SECONDS?: string;
  readonly VISUAL_FRAMES_MIN_BUILD?: string;
  readonly RETIRED_FRAMES_BUILD?: string;
}

export function parseClientBuild(request: Request): number {
  const header = request.headers.get('x-app-build');
  if (!header) return 0;
  const parsed = parseInt(header.trim(), 10);
  if (!Number.isFinite(parsed) || parsed < 0) return 0;
  return parsed;
}

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, PUT, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
};

function isValidAdminToken(token: string, expected?: string): boolean {
  if (!expected || token.length === 0) return false;
  const enc = new TextEncoder();
  const aBuf = enc.encode(token);
  const bBuf = enc.encode(expected);
  if (aBuf.byteLength !== bBuf.byteLength) return false;

  let mismatch = 0;
  for (let i = 0; i < aBuf.byteLength; i++) {
    mismatch |= aBuf[i] ^ bBuf[i];
  }
  return mismatch === 0;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const pathname = url.pathname;

    // CORS preflight desteği
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: jsonHeaders,
      });
    }

    // Sağlık kontrolü rotası
    if (request.method === 'GET' && pathname === '/health') {
      return new Response('ok', {
        status: 200,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    // Profil sorgulama rotası: GET /me
    if (request.method === 'GET' && pathname === '/me') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      const clientBuild = parseClientBuild(request);

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        const profile = await profileStub.getProfile(uid, clientBuild);
        const serverNowMs = Date.now();
        const energyState = await profileStub.getEnergyState(uid, serverNowMs);
        return new Response(
          JSON.stringify({
            ...profile,
            serverNowMs,
            energy: energyState,
          }),
          {
            status: 200,
            headers: jsonHeaders,
          }
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            {
              status: 410,
              headers: jsonHeaders,
            }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Takma ad güncelleme rotası: PUT /me/nickname
    if (request.method === 'PUT' && pathname === '/me/nickname') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      let body: unknown;
      try {
        body = await request.json();
      } catch {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'Geçersiz JSON gövdesi' }),
          {
            status: 400,
            headers: jsonHeaders,
          }
        );
      }

      const nickname = (body as { nickname?: unknown })?.nickname;
      if (typeof nickname !== 'string') {
        return new Response(
          JSON.stringify({ error: 'invalid_nickname', message: 'nickname alanı dize olmalıdır' }),
          {
            status: 400,
            headers: jsonHeaders,
          }
        );
      }

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        const result = await profileStub.setNickname(nickname, uid);

        // Leaderboard tablosundaki eski takma adı da güncelle
        if (env.LEADERBOARD) {
          try {
            const leaderboardStub = env.LEADERBOARD.get(env.LEADERBOARD.idFromName('global'));
            await leaderboardStub.updateNickname(uid, result.nickname);
          } catch (lbErr) {
            console.error('Leaderboard updateNickname failed:', lbErr);
          }
        }

        return new Response(JSON.stringify(result), {
          status: 200,
          headers: jsonHeaders,
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            {
              status: 410,
              headers: jsonHeaders,
            }
          );
        }
        return new Response(
          JSON.stringify({ error: 'invalid_nickname', message: msg }),
          {
            status: 400,
            headers: jsonHeaders,
          }
        );
      }
    }

    // Avatar çerçevesi kuşanma rotası: PUT /me/frame
    if (request.method === 'PUT' && pathname === '/me/frame') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      let body: { frameId?: unknown; frame?: unknown };
      try {
        body = (await request.json()) as { frameId?: unknown; frame?: unknown };
      } catch {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'Geçersiz JSON gövdesi' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      const rawFrame =
        typeof body?.frameId === 'string' && body.frameId.trim().length > 0
          ? body.frameId
          : typeof body?.frame === 'string' && body.frame.trim().length > 0
            ? body.frame
            : null;

      if (!rawFrame) {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'frameId veya frame alanı dize olmalıdır' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      const frameId = rawFrame.trim().toLowerCase();

      const clientBuild = parseClientBuild(request);

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        const res = await profileStub.equipFrame(frameId, uid, clientBuild);
        if (!res.success) {
          if (res.error === 'item_retired') {
            return new Response(
              JSON.stringify({ error: 'item_retired', message: 'Bu çerçeve emekliye ayrılmıştır ve kuşanılamaz' }),
              { status: 400, headers: jsonHeaders }
            );
          }
          if (res.error === 'item_not_owned') {
            return new Response(
              JSON.stringify({ error: 'item_not_owned', message: 'Bu çerçeveye sahip değilsiniz' }),
              { status: 400, headers: jsonHeaders }
            );
          }
          return new Response(
            JSON.stringify({ error: 'invalid_frame', message: 'Geçersiz çerçeve kimliği' }),
            { status: 400, headers: jsonHeaders }
          );
        }

        // Leaderboard tablosundaki çerçeveyi de güncelle (hata verirse kuşanma başarısız sayılmaz)
        if (env.LEADERBOARD) {
          try {
            const leaderboardStub = env.LEADERBOARD.get(env.LEADERBOARD.idFromName('global'));
            await leaderboardStub.updateFrame(uid, frameId);
          } catch (lbErr) {
            console.error('Leaderboard updateFrame failed:', lbErr);
          }
        }

        return new Response(JSON.stringify(res), {
          status: 200,
          headers: jsonHeaders,
        });
      } catch (err) {
        console.error('PUT /me/frame error:', err);
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Mağaza katalog ve durum rotası: GET /store
    if (request.method === 'GET' && pathname === '/store') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      const clientBuild = parseClientBuild(request);

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        const storeData = await profileStub.getStoreState(uid, clientBuild);
        const serverNowMs = Date.now();
        const energyState = await profileStub.getEnergyState(uid, serverNowMs);
        return new Response(
          JSON.stringify({
            ...storeData,
            serverNowMs,
            energy: energyState,
          }),
          {
            status: 200,
            headers: jsonHeaders,
          }
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            {
              status: 410,
              headers: jsonHeaders,
            }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Mağazadan çerçeve satın alma: POST /store/purchase
    if (request.method === 'POST' && pathname === '/store/purchase') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      let body: { itemId?: unknown };
      try {
        body = (await request.json()) as { itemId?: unknown };
      } catch {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'Geçersiz JSON gövdesi' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      if (typeof body?.itemId !== 'string' || body.itemId.trim().length === 0) {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'itemId alanı dize olmalıdır' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      const clientBuild = parseClientBuild(request);

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        const res = await profileStub.purchaseItem(body.itemId.trim(), uid, clientBuild);
        if (!res.success) {
          if (res.error === 'item_retired') {
            return new Response(
              JSON.stringify({
                error: 'item_retired',
                message: 'Bu çerçeve emekliye ayrılmıştır ve artık satın alınamaz',
              }),
              { status: 400, headers: jsonHeaders }
            );
          }
          if (res.error === 'not_enough_coins') {
            return new Response(
              JSON.stringify({ error: 'not_enough_coins', message: 'Yetersiz jeton', coins: res.coins }),
              { status: 402, headers: jsonHeaders }
            );
          }
          if (res.error === 'already_owned') {
            return new Response(
              JSON.stringify({ error: 'already_owned', message: 'Bu çerçeveye zaten sahipsiniz' }),
              { status: 400, headers: jsonHeaders }
            );
          }
          if (res.error === 'unsupported_client_version') {
            return new Response(
              JSON.stringify({
                error: 'unsupported_client_version',
                message: 'Bu çerçeveyi satın almak için uygulamanızı güncelleyin',
              }),
              { status: 400, headers: jsonHeaders }
            );
          }
          return new Response(
            JSON.stringify({ error: 'invalid_item', message: 'Geçersiz çerçeve öğesi' }),
            { status: 400, headers: jsonHeaders }
          );
        }

        return new Response(JSON.stringify(res), {
          status: 200,
          headers: jsonHeaders,
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Enerji paketi satın alma: POST /store/energy
    if (request.method === 'POST' && pathname === '/store/energy') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      let body: { pack?: unknown };
      try {
        body = (await request.json()) as { pack?: unknown };
      } catch {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'Geçersiz JSON gövdesi' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      if (body?.pack !== 'one' && body?.pack !== 'full') {
        return new Response(
          JSON.stringify({ error: 'invalid_pack', message: "pack alanı 'one' veya 'full' olmalıdır" }),
          { status: 400, headers: jsonHeaders }
        );
      }

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        const res = await profileStub.purchaseEnergy({ pack: body.pack, uid });
        if (!res.success) {
          if (res.error === 'energy_disabled') {
            return new Response(
              JSON.stringify({ error: 'energy_disabled', message: 'Enerji sistemi şu anda aktif değil' }),
              { status: 400, headers: jsonHeaders }
            );
          }
          if (res.error === 'energy_full') {
            return new Response(
              JSON.stringify({ error: 'energy_full', message: 'Enerjiniz zaten dolu' }),
              { status: 400, headers: jsonHeaders }
            );
          }
          if (res.error === 'not_enough_coins') {
            return new Response(
              JSON.stringify({ error: 'not_enough_coins', message: 'Yetersiz jeton', coins: res.coins }),
              { status: 402, headers: jsonHeaders }
            );
          }
          return new Response(
            JSON.stringify({ error: 'invalid_pack', message: 'Geçersiz paket' }),
            { status: 400, headers: jsonHeaders }
          );
        }

        return new Response(JSON.stringify(res), {
          status: 200,
          headers: jsonHeaders,
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Hesap silme rotası: DELETE /me
    if (request.method === 'DELETE' && pathname === '/me') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      // 1. Eşleştirmedeyse kuyruktan çıkar ve açık soketi kapat
      if (env.MATCHMAKER) {
        try {
          const matchmaker = env.MATCHMAKER.get(env.MATCHMAKER.idFromName('global'));
          await matchmaker.removeFromQueue(uid);
        } catch (mmErr) {
          console.error('Matchmaker removeFromQueue failed:', mmErr);
        }
      }

      // 2. Leaderboard tablosundaki week_wins ve pair_wins kayıtlarını temizle
      if (env.LEADERBOARD) {
        try {
          const leaderboardStub = env.LEADERBOARD.get(env.LEADERBOARD.idFromName('global'));
          await leaderboardStub.deleteUserData(uid);
        } catch (lbErr) {
          console.error('Leaderboard deleteUserData failed:', lbErr);
        }
      }

      // 3. UserProfile DO verilerini temizle ve 24h tombstone kaydı bırak
      const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
      await profileStub.deleteProfile(uid);

      return new Response(JSON.stringify({ ok: true, deleted: true }), {
        status: 200,
        headers: jsonHeaders,
      });
    }

    // Liderlik tablosu rotası: GET /leaderboard
    if (request.method === 'GET' && pathname === '/leaderboard') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      if (!env.LEADERBOARD) {
        return new Response(JSON.stringify({ error: 'service_unavailable' }), {
          status: 503,
          headers: jsonHeaders,
        });
      }

      const leaderboardStub = env.LEADERBOARD.get(env.LEADERBOARD.idFromName('global'));
      const data = await leaderboardStub.getLeaderboard(uid);
      return new Response(JSON.stringify(data), {
        status: 200,
        headers: jsonHeaders,
      });
    }

    // Eşleştirme WebSocket yükseltmesi: /ws/matchmaking
    if (pathname === '/ws/matchmaking') {
      if (request.headers.get('Upgrade') !== 'websocket') {
        return new Response('Expected WebSocket Upgrade', { status: 400 });
      }

      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response('Unauthorized', { status: 401 });
      }

      const matchmaker = env.MATCHMAKER.get(env.MATCHMAKER.idFromName('global'));
      const forwardReq = new Request(request.url, request);
      forwardReq.headers.set('X-User-Id', uid);
      return matchmaker.fetch(forwardReq);
    }

    // Maç odası WebSocket yükseltmesi: /ws/match/:matchId
    const matchMatch = pathname.match(/^\/ws\/match\/([a-zA-Z0-9_-]+)$/);
    if (matchMatch) {
      const matchId = matchMatch[1];
      if (request.headers.get('Upgrade') !== 'websocket') {
        return new Response('Expected WebSocket Upgrade', { status: 400 });
      }

      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response('Unauthorized', { status: 401 });
      }

      const room = env.MATCH_ROOM.get(env.MATCH_ROOM.idFromName(matchId));
      const forwardReq = new Request(request.url, request);
      forwardReq.headers.set('X-User-Id', uid);
      return room.fetch(forwardReq);
    }

    // Oyuncu Bildirme rotası: POST /matches/:matchId/report
    const reportMatch = pathname.match(/^\/matches\/([a-zA-Z0-9_-]+)\/report$/);
    if (request.method === 'POST' && reportMatch) {
      const matchId = reportMatch[1];
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      // 3. Kural: Tombstone kontrolü (silinmiş hesap 410 alır)
      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        if (await profileStub.isDeleted()) {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
      } catch {}

      let body: any;
      try {
        body = await request.json();
      } catch {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'Geçersiz JSON gövdesi' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      const validReasons = [
        'inappropriate_nickname',
        'inappropriate_content',
        'cheating',
        'other',
      ];
      if (typeof body?.reason !== 'string' || !validReasons.includes(body.reason)) {
        return new Response(
          JSON.stringify({ error: 'invalid_reason', message: 'Geçersiz bildirim sebebi' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      if (!env.MATCH_ROOM) {
        return new Response(JSON.stringify({ error: 'service_unavailable' }), {
          status: 503,
          headers: jsonHeaders,
        });
      }

      const room = env.MATCH_ROOM.get(env.MATCH_ROOM.idFromName(matchId));
      const matchCtx = await room.getMatchReportContext(uid);

      if (matchCtx === null) {
        return new Response(
          JSON.stringify({
            error: 'match_expired',
            message: 'Maç süresi dolduğu için bildirim yapılamıyor. Bildirimler maç bittikten sonraki 10 dakika içinde yapılabilir.',
          }),
          { status: 410, headers: jsonHeaders }
        );
      }

      if (!matchCtx.ok) {
        return new Response(
          JSON.stringify({ error: 'forbidden', message: 'Bu maçın tarafı değilsin' }),
          { status: 403, headers: jsonHeaders }
        );
      }

      if (!env.REPORT_STORE) {
        return new Response(JSON.stringify({ error: 'service_unavailable' }), {
          status: 503,
          headers: jsonHeaders,
        });
      }

      const reportStore = env.REPORT_STORE.get(env.REPORT_STORE.idFromName('global'));
      const addRes = await reportStore.addReport({
        reporterUid: uid,
        reportedUid: matchCtx.context.reportedUid,
        matchId,
        reason: body.reason,
        reportedNickname: matchCtx.context.reportedNickname,
        answers: matchCtx.context.answers,
      });

      if (!addRes.ok) {
        if (addRes.error === 'already_reported') {
          return new Response(
            JSON.stringify({ error: 'already_reported', message: 'Bu maç için zaten bildirim yaptın.' }),
            { status: 409, headers: jsonHeaders }
          );
        }
        if (addRes.error === 'daily_limit_exceeded') {
          return new Response(
            JSON.stringify({ error: 'daily_limit_exceeded', message: 'Günlük bildirim sınırına ulaştın.' }),
            { status: 429, headers: jsonHeaders }
          );
        }
      }

      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: jsonHeaders,
      });
    }

    // Oyuncu Engelleme rotası: POST /matches/:matchId/block
    const blockMatch = pathname.match(/^\/matches\/([a-zA-Z0-9_-]+)\/block$/);
    if (request.method === 'POST' && blockMatch) {
      const matchId = blockMatch[1];
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      // 3. Kural: Tombstone kontrolü
      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        if (await profileStub.isDeleted()) {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
      } catch {}

      if (!env.MATCH_ROOM) {
        return new Response(JSON.stringify({ error: 'service_unavailable' }), {
          status: 503,
          headers: jsonHeaders,
        });
      }

      const room = env.MATCH_ROOM.get(env.MATCH_ROOM.idFromName(matchId));
      const matchCtx = await room.getMatchReportContext(uid);

      if (matchCtx === null) {
        return new Response(
          JSON.stringify({
            error: 'match_expired',
            message: 'Maç süresi dolduğu için engelleme yapılamıyor.',
          }),
          { status: 410, headers: jsonHeaders }
        );
      }

      if (!matchCtx.ok) {
        return new Response(
          JSON.stringify({ error: 'forbidden', message: 'Bu maçın tarafı değilsin' }),
          { status: 403, headers: jsonHeaders }
        );
      }

      const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
      const blockRes = await profileStub.blockUser({
        blockedUid: matchCtx.context.reportedUid,
        blockedNickname: matchCtx.context.reportedNickname,
        uid,
      });

      if (!blockRes.ok) {
        return new Response(
          JSON.stringify({ error: 'block_limit_reached', message: 'En fazla 100 oyuncu engelleyebilirsin.' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      return new Response(JSON.stringify({ ok: true, id: blockRes.id }), {
        status: 200,
        headers: jsonHeaders,
      });
    }

    // Engellenenleri Listeleme: GET /me/blocks
    if (request.method === 'GET' && pathname === '/me/blocks') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        if (await profileStub.isDeleted()) {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        const blocks = await profileStub.getBlockedUsers();
        return new Response(JSON.stringify(blocks), {
          status: 200,
          headers: jsonHeaders,
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Engeli Kaldırma: DELETE /me/blocks/:id
    const unblockMatch = pathname.match(/^\/me\/blocks\/([a-zA-Z0-9_-]+)$/);
    if (request.method === 'DELETE' && unblockMatch) {
      const blockId = unblockMatch[1];
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        if (await profileStub.isDeleted()) {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        const res = await profileStub.unblockUser(blockId);
        return new Response(JSON.stringify(res), {
          status: 200,
          headers: jsonHeaders,
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Enerji paketi satın alma: POST /store/energy
    if (request.method === 'POST' && pathname === '/store/energy') {
      const uid = await authenticateRequest(request, env);
      if (!uid) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      let body: { pack?: unknown };
      try {
        body = (await request.json()) as { pack?: unknown };
      } catch {
        return new Response(
          JSON.stringify({ error: 'bad_request', message: 'Geçersiz JSON gövdesi' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      if (body?.pack !== 'one' && body?.pack !== 'full') {
        return new Response(
          JSON.stringify({ error: 'invalid_pack', message: "pack alanı 'one' veya 'full' olmalıdır" }),
          { status: 400, headers: jsonHeaders }
        );
      }

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
        const res = await profileStub.purchaseEnergy({ pack: body.pack, uid });
        if (!res.success) {
          if (res.error === 'energy_disabled') {
            return new Response(
              JSON.stringify({ error: 'energy_disabled', message: 'Enerji sistemi şu anda aktif değil' }),
              { status: 400, headers: jsonHeaders }
            );
          }
          if (res.error === 'energy_full') {
            return new Response(
              JSON.stringify({ error: 'energy_full', message: 'Enerjiniz zaten dolu' }),
              { status: 400, headers: jsonHeaders }
            );
          }
          if (res.error === 'not_enough_coins') {
            return new Response(
              JSON.stringify({ error: 'not_enough_coins', message: 'Yetersiz jeton', coins: res.coins }),
              { status: 402, headers: jsonHeaders }
            );
          }
          return new Response(
            JSON.stringify({ error: 'invalid_pack', message: 'Geçersiz paket' }),
            { status: 400, headers: jsonHeaders }
          );
        }

        return new Response(JSON.stringify(res), {
          status: 200,
          headers: jsonHeaders,
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'account_deleted') {
          return new Response(
            JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
            { status: 410, headers: jsonHeaders }
          );
        }
        return new Response(JSON.stringify({ error: 'internal_error', message: msg }), {
          status: 500,
          headers: jsonHeaders,
        });
      }
    }

    // Yönetici Bildirimleri İnceleme: GET /admin/reports
    if (request.method === 'GET' && pathname === '/admin/reports') {
      const authHeader = request.headers.get('Authorization') ?? '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';

      if (!isValidAdminToken(token, env.ADMIN_TOKEN)) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      if (!env.REPORT_STORE) {
        return new Response(JSON.stringify({ error: 'service_unavailable' }), {
          status: 503,
          headers: jsonHeaders,
        });
      }

      const reportStore = env.REPORT_STORE.get(env.REPORT_STORE.idFromName('global'));
      const view = url.searchParams.get('view');

      if (view === 'summary') {
        const limit = parseInt(url.searchParams.get('limit') ?? '50', 10);
        const summary = await reportStore.getSummary(limit);
        return new Response(JSON.stringify({ summary }), {
          status: 200,
          headers: jsonHeaders,
        });
      }

      const limit = parseInt(url.searchParams.get('limit') ?? '50', 10);
      const offset = parseInt(url.searchParams.get('offset') ?? '0', 10);
      const reportedUid = url.searchParams.get('reportedUid') ?? undefined;

      const data = await reportStore.getReports({ limit, offset, reportedUid });
      return new Response(JSON.stringify(data), {
        status: 200,
        headers: jsonHeaders,
      });
    }

    // Yönetici Jeton / Çerçeve Tanımlama: POST /admin/grant
    if (request.method === 'POST' && pathname === '/admin/grant') {
      const authHeader = request.headers.get('Authorization') ?? '';
      const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';

      if (!isValidAdminToken(token, env.ADMIN_TOKEN)) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), {
          status: 401,
          headers: jsonHeaders,
        });
      }

      if (!env.USER_PROFILE) {
        return new Response(JSON.stringify({ error: 'service_unavailable' }), {
          status: 503,
          headers: jsonHeaders,
        });
      }

      const body = (await request.json().catch(() => ({}))) as {
        uid?: unknown;
        coins?: unknown;
        frameIds?: unknown;
        energy?: unknown;
      };

      const targetUid = typeof body.uid === 'string' ? body.uid.trim() : '';
      if (!targetUid) {
        return new Response(
          JSON.stringify({ error: 'invalid_request', message: 'uid is required' }),
          { status: 400, headers: jsonHeaders }
        );
      }

      try {
        const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(targetUid));
        const res = await profileStub.adminGrant({
          uid: targetUid,
          coins: typeof body.coins === 'number' ? body.coins : undefined,
          frameIds: Array.isArray(body.frameIds) ? (body.frameIds as string[]) : undefined,
          energy: typeof body.energy === 'number' ? body.energy : undefined,
        });

        if (!res.success) {
          if (res.error === 'account_deleted') {
            return new Response(
              JSON.stringify({ error: 'account_deleted', message: 'Hesap silinmiş' }),
              { status: 410, headers: jsonHeaders }
            );
          }
          return new Response(
            JSON.stringify({ error: 'bad_request', message: res.error }),
            { status: 400, headers: jsonHeaders }
          );
        }

        return new Response(
          JSON.stringify({
            success: true,
            uid: targetUid,
            coins: res.coins,
            grantedFrames: res.grantedFrames,
          }),
          { status: 200, headers: jsonHeaders }
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return new Response(
          JSON.stringify({ error: 'internal_error', message: msg }),
          { status: 500, headers: jsonHeaders }
        );
      }
    }

    return new Response('Not Found', { status: 404 });
  },
} satisfies ExportedHandler<Env>;
