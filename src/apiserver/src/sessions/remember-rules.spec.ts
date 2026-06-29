import assert from 'node:assert/strict';
import { test } from 'node:test';
import { normalizeStoredRememberRules } from './remember-rules';

test('an array of rules -> rememberRules plus the primary rememberRule', () => {
  const stored = [
    { toolName: 'Bash', ruleContent: 'cd:*' },
    { toolName: 'Bash', ruleContent: 'git add:*' },
  ];
  const out = normalizeStoredRememberRules(stored);
  assert.deepEqual(out.rememberRules, stored);
  assert.deepEqual(out.rememberRule, stored[0]);
});

test('a legacy lone object -> wrapped into a one-element array (old rows still resolve)', () => {
  const stored = { toolName: 'Bash', ruleContent: 'cd:*' };
  const out = normalizeStoredRememberRules(stored);
  assert.deepEqual(out.rememberRules, [stored]);
  assert.deepEqual(out.rememberRule, stored);
});

test('null -> both fields omitted', () => {
  assert.deepEqual(normalizeStoredRememberRules(null), {});
});

test('an empty array -> both fields omitted', () => {
  assert.deepEqual(normalizeStoredRememberRules([]), {});
});
