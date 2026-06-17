// Compact, URL-safe rendering of a 128-bit UUID as base62 (≤ 22 chars), used
// for short session/agent links. Bijective: `uuidToBase62` strips leading
// zeros, `base62ToUuid` re-pads to a full 32-hex UUID, so round-trips are exact
// regardless of how many high-order zero bits the id happens to have.
const ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const BASE = 62n;
const MAX = 1n << 128n; // exclusive upper bound for a 128-bit value

const UUID_RE =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/** Encode a canonical UUID string to base62 (case-sensitive, ≤ 22 chars). */
export function uuidToBase62(uuid: string): string {
  if (!UUID_RE.test(uuid)) throw new Error(`invalid uuid: ${uuid}`);
  let n = BigInt('0x' + uuid.replace(/-/g, ''));
  if (n === 0n) return '0';
  let out = '';
  while (n > 0n) {
    out = ALPHABET[Number(n % BASE)] + out;
    n /= BASE;
  }
  return out;
}

/** Decode a base62 string back to a canonical lowercase UUID. Throws on input
 *  that isn't valid base62 or that overflows 128 bits. */
export function base62ToUuid(s: string): string {
  if (!s) throw new Error('empty base62 id');
  let n = 0n;
  for (const ch of s) {
    const v = ALPHABET.indexOf(ch);
    if (v < 0) throw new Error(`invalid base62 char: ${ch}`);
    n = n * BASE + BigInt(v);
  }
  if (n >= MAX) throw new Error('base62 id out of 128-bit range');
  const hex = n.toString(16).padStart(32, '0');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join('-');
}

/** Accept either a canonical UUID or a base62 public id and return the UUID.
 *  Lets routes/links carry the short form while older raw-UUID links and
 *  internal callers keep working. Throws on input that is neither. */
export function toUuid(idOrPublicId: string): string {
  return UUID_RE.test(idOrPublicId) ? idOrPublicId.toLowerCase() : base62ToUuid(idOrPublicId);
}
