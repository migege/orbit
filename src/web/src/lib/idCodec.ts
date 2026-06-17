import { toUuid, uuidToBase62 } from '@orbit/shared';

/** UUID -> short base62 public id, for building shareable links. */
export const encodeId = uuidToBase62;

/** Route param (base62 public id or raw UUID) -> UUID. Falls back to the raw
 *  value if it isn't decodable, so a malformed link degrades to "not found"
 *  rather than crashing the view. */
export function decodeId(param: string | null | undefined): string | null {
  if (!param) return null;
  try {
    return toUuid(param);
  } catch {
    return param;
  }
}
