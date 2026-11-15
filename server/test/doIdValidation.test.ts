import { describe, expect, it } from 'vitest';
import { mockIdFromString, createMockDONamespace } from './testHelpers';

describe('Durable Object ID Validation & Test Helper (idFromString vs idFromName)', () => {
  it('mockIdFromString yalnızca 64 karakterlik hex ID kabul eder', () => {
    const valid64Hex = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    const result = mockIdFromString(valid64Hex);
    expect(result.name).toBe(valid64Hex);
    expect(result.toString()).toBe(valid64Hex);
  });

  it('UUID (matchId) ile idFromString çağrıldığında gerçek Cloudflare runtime gibi TypeError fırlatır', () => {
    const uuid = 'c28c89c8-d10a-4fb4-9c5c-7ee064973da2';
    expect(() => mockIdFromString(uuid)).toThrowError(TypeError);
    expect(() => mockIdFromString(uuid)).toThrowError('Invalid Durable Object ID: ' + uuid);
  });

  it('Özel adlar veya uid ile idFromString çağrıldığında TypeError fırlatır', () => {
    expect(() => mockIdFromString('global')).toThrowError('Invalid Durable Object ID: global');
    expect(() => mockIdFromString('user_12345')).toThrowError('Invalid Durable Object ID: user_12345');
    expect(() => mockIdFromString('')).toThrowError(TypeError);
    expect(() => mockIdFromString(123 as any)).toThrowError(TypeError);
  });

  it('createMockDONamespace sahtesi idFromString ve idFromName ayrımını runtime uyumlu uygular', () => {
    const instances = new Map<string, { status: string }>();
    instances.set('room_1', { status: 'active' });

    const ns = createMockDONamespace((id) => instances.get(id.name));

    // idFromName her türlü ismi kabul eder
    const doId = ns.idFromName('room_1');
    expect(doId.name).toBe('room_1');
    expect(ns.get(doId)).toEqual({ status: 'active' });

    // idFromString UUID veya geçersiz string verildiğinde sahte maskeleme yapmaz, hata fırlatır
    expect(() => ns.idFromString('room_1')).toThrowError(TypeError);
    expect(() => ns.idFromString('c28c89c8-d10a-4fb4-9c5c-7ee064973da2')).toThrowError(TypeError);
  });
});
