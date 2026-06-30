import type { PermissionRule } from '@orbit/shared';

/** The "remember same kind" rules a stored approval maps to. The schemaless
 *  `remember_rule` JSON column holds an array (current) or a lone object (legacy rows
 *  written before the array form); normalize both to an array. We return the array for
 *  current runners and the primary rule under the deprecated `rememberRule` so a runner
 *  that predates the array form still remembers at least that one until it self-updates. */
export function normalizeStoredRememberRules(stored: unknown): {
  rememberRules?: PermissionRule[];
  rememberRule?: PermissionRule;
} {
  const rules = Array.isArray(stored)
    ? (stored as PermissionRule[])
    : stored
      ? [stored as PermissionRule]
      : [];
  return rules.length ? { rememberRules: rules, rememberRule: rules[0] } : {};
}
