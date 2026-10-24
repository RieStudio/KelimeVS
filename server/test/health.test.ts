import { describe, expect, it, vi } from 'vitest';

vi.mock('cloudflare:workers', () => ({
  DurableObject: class {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  },
}));

import worker, { type Env } from '../src/index';

describe('GET /health Uç Noktası', () => {
  it('kimlik doğrulamasız 200 ok döner ve storage/DO kullanmaz', async () => {
    const mockEnv = {} as Env;
    const req = new Request('https://api.riestudio.com.tr/health', {
      method: 'GET',
    });

    const res = await worker.fetch(req, mockEnv);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toBe('ok');
    expect(res.headers.get('Content-Type')).toContain('text/plain');
  });
});

