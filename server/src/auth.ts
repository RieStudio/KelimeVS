export interface AuthEnv {
  readonly ALLOW_DEV_AUTH?: string;
}

/**
 * Kullanıcı kimliğini belirler.
 *
 * Geliştirme modunda:
 * - `ALLOW_DEV_AUTH === 'true'` ise "dev:<uid>" biçimindeki jetonlar kabul edilir.
 * - Geçerli ise doğrudan <uid> döner.
 *
 * TODO: Firebase ID token doğrulama (4.3b)
 */
export function verifyToken(token: string | null, env: AuthEnv): string | null {
  if (!token) return null;

  if (env.ALLOW_DEV_AUTH === 'true' && token.startsWith('dev:')) {
    const uid = token.slice(4).trim();
    if (uid.length > 0) {
      return uid;
    }
  }

  return null;
}
