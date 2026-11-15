/**
 * Test Helper: Cloudflare Workers Durable Object ID Validation and Namespace Mocks.
 *
 * Gerçek Cloudflare Workers runtime'ında DurableObjectNamespace.idFromString(hexId)
 * metodu YALNIZCA 64 karakterlik onaltılık (hex) dize kabul eder.
 * UUID, kullanıcı ID'si (uid) veya rastgele bir isim verildiğinde TypeError('Invalid Durable Object ID') fırlatır.
 */

export function mockIdFromString(idString: string): { name: string; type: string; toString: () => string } {
  if (typeof idString !== 'string' || !/^[0-9a-fA-F]{64}$/.test(idString)) {
    throw new TypeError(`Invalid Durable Object ID: ${idString}`);
  }
  return {
    name: idString,
    type: 'string',
    toString: () => idString,
  };
}

export function createMockDONamespace<T = any>(
  resolver: (id: any) => T,
  overrides?: {
    idFromName?: (name: string) => any;
    idFromString?: (id: string) => any;
  }
) {
  return {
    idFromName: overrides?.idFromName ?? ((name: string) => ({ name, toString: () => name })),
    idFromString: overrides?.idFromString ?? mockIdFromString,
    get: (id: any) => resolver(id),
  };
}
