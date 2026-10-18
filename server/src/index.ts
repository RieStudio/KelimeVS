import { authenticateRequest, type AuthEnv } from './auth';
import { Matchmaker } from './matchmaker';
import { MatchRoom } from './matchRoom';
import { UserProfile } from './userProfile';
import { Leaderboard } from './leaderboard';

export { Matchmaker, MatchRoom, UserProfile, Leaderboard };

export interface Env extends AuthEnv {
  readonly MATCHMAKER: DurableObjectNamespace<Matchmaker>;
  readonly MATCH_ROOM: DurableObjectNamespace<MatchRoom>;
  readonly USER_PROFILE: DurableObjectNamespace<UserProfile>;
  readonly LEADERBOARD: DurableObjectNamespace<Leaderboard>;
  readonly FAST_TIMERS?: string;
  readonly CONTENT_SOURCE?: string;
  readonly FIREBASE_DATABASE_URL?: string;
  readonly FIREBASE_SERVICE_ACCOUNT_B64?: string;
  readonly CONTENT_TTL_SECONDS?: string;
  readonly START_COINS?: string;
  readonly WIN_COINS?: string;
  readonly LOSS_COINS?: string;
  readonly DISCONNECT_WIN_COINS?: string;
  readonly DISCONNECT_LOSS_COINS?: string;
  readonly DAILY_MATCH_COIN_CAP?: string;
}

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, PUT, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
};

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

      const profileStub = env.USER_PROFILE.get(env.USER_PROFILE.idFromName(uid));
      const profile = await profileStub.getProfile(uid);
      return new Response(JSON.stringify(profile), {
        status: 200,
        headers: jsonHeaders,
      });
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
        return new Response(
          JSON.stringify({ error: 'invalid_nickname', message: msg }),
          {
            status: 400,
            headers: jsonHeaders,
          }
        );
      }
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

    return new Response('Not Found', { status: 404 });
  },
} satisfies ExportedHandler<Env>;
