import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { base62ToUuid, toUuid, uuidToBase62 } from './codec';

const NIL = '00000000-0000-0000-0000-000000000000';
const MAX = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

describe('uuid <-> base62', () => {
  it('round-trips a known uuid', () => {
    const u = '915d27d1-b92f-4cc6-819f-174ff5be13a9';
    expect(base62ToUuid(uuidToBase62(u))).toBe(u);
  });

  it('round-trips the nil and max uuids', () => {
    expect(uuidToBase62(NIL)).toBe('0');
    expect(base62ToUuid('0')).toBe(NIL);
    expect(base62ToUuid(uuidToBase62(MAX))).toBe(MAX);
  });

  it('round-trips many random uuids and stays within 22 chars', () => {
    for (let i = 0; i < 2000; i++) {
      const u = randomUUID();
      const enc = uuidToBase62(u);
      expect(enc).toMatch(/^[0-9A-Za-z]+$/);
      expect(enc.length).toBeLessThanOrEqual(22);
      expect(base62ToUuid(enc)).toBe(u);
    }
  });

  it('normalizes uppercase input to a lowercase canonical uuid', () => {
    const u = '915D27D1-B92F-4CC6-819F-174FF5BE13A9';
    expect(base62ToUuid(uuidToBase62(u))).toBe(u.toLowerCase());
  });

  it('is case-sensitive (distinct codes differ)', () => {
    // 'A' (10) and 'a' (36) are distinct symbols.
    expect(base62ToUuid('A')).not.toBe(base62ToUuid('a'));
  });

  it('toUuid accepts both a raw uuid and a base62 id', () => {
    const u = '915d27d1-b92f-4cc6-819f-174ff5be13a9';
    expect(toUuid(u)).toBe(u);
    expect(toUuid('915D27D1-B92F-4CC6-819F-174FF5BE13A9')).toBe(u); // lowercased
    expect(toUuid(uuidToBase62(u))).toBe(u);
    expect(() => toUuid('!!not-valid!!')).toThrow();
  });

  it('rejects invalid input', () => {
    expect(() => uuidToBase62('not-a-uuid')).toThrow();
    expect(() => base62ToUuid('')).toThrow();
    expect(() => base62ToUuid('abc-def')).toThrow(); // '-' not in alphabet
    // 23 'z' chars overflow 128 bits.
    expect(() => base62ToUuid('z'.repeat(23))).toThrow();
  });
});
