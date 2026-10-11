import { authenticateRequest, type AuthEnv } from './auth';
import { Matchmaker } from './matchmaker';
import { MatchRoom } from './matchRoom';

export { Matchmaker, MatchRoom };

export interface Env extends AuthEnv {
  readonly MATCHMAKER: DurableObjectNamespace<Matchmaker>;
  readonly MATCH_ROOM: DurableObjectNamespace<MatchRoom>;
  readonly FAST_TIMERS?: string;
  readonly CONTENT_SOURCE?: string;
  readonly FIREBASE_DATABASE_URL?: string;
  readonly FIREBASE_SERVICE_ACCOUNT_B64?: string;
  readonly CONTENT_TTL_SECONDS?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const pathname = url.pathname;

    // Sağlık kontrolü rotası
    if (request.method === 'GET' && pathname === '/health') {
      return new Response('ok', {
        status: 200,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
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
