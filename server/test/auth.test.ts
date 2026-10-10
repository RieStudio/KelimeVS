import { describe, expect, it } from 'vitest';
import { verifyToken } from '../src/auth';

describe('verifyToken Authentication', () => {
  it('ALLOW_DEV_AUTH true iken "dev:<uid>" biçimindeki jetonları doğrular', () => {
    const env = { ALLOW_DEV_AUTH: 'true' };
    expect(verifyToken('dev:alice', env)).toBe('alice');
    expect(verifyToken('dev:bob', env)).toBe('bob');
    expect(verifyToken('dev:user_123', env)).toBe('user_123');
  });

  it('ALLOW_DEV_AUTH true değilse dev jetonları reddeder', () => {
    expect(verifyToken('dev:alice', {})).toBeNull();
    expect(verifyToken('dev:alice', { ALLOW_DEV_AUTH: 'false' })).toBeNull();
  });

  it('"dev:" öneki olmayan geçersiz jetonları reddeder', () => {
    const env = { ALLOW_DEV_AUTH: 'true' };
    expect(verifyToken('alice', env)).toBeNull();
    expect(verifyToken('token123', env)).toBeNull();
    expect(verifyToken('dev:', env)).toBeNull();
  });

  it('null veya boş jetonda null döner', () => {
    const env = { ALLOW_DEV_AUTH: 'true' };
    expect(verifyToken(null, env)).toBeNull();
    expect(verifyToken('', env)).toBeNull();
  });
});

