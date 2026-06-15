#!/usr/bin/env node
// Add (or reset the password of) an Orbit user directly in the database.
//
// Self-registration was removed, so this is how accounts get provisioned.
// Password hashing mirrors src/apiserver/src/common/crypto.util.ts exactly
// (scrypt, 16-byte salt, 64-byte key, stored as `salt:key` hex).
//
// Usage:
//   node .claude/skills/add-user/add-user.mjs --email <email> [--name <name>] \
//        [--password <password>] [--force]
//
// - --name defaults to the email local-part.
// - --password omitted  -> a strong random password is generated and printed.
// - --force             -> reset the password of an existing user (otherwise
//                          adding a duplicate email fails loudly).
import { randomBytes, scryptSync } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, '../../..'); // .claude/skills/add-user -> repo root

// --- load .env (for DATABASE_URL) without pulling in a dependency ---------
function loadEnv(file) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    return;
  }
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = val;
  }
}
loadEnv(resolve(REPO_ROOT, '.env'));

// --- args -----------------------------------------------------------------
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next !== undefined && !next.startsWith('--')) {
      out[key] = next;
      i++;
    } else {
      out[key] = true;
    }
  }
  return out;
}
const args = parseArgs(process.argv.slice(2));

const email = typeof args.email === 'string' ? args.email.trim() : undefined;
if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error('error: a valid --email is required');
  console.error(
    'usage: node .claude/skills/add-user/add-user.mjs --email <email> [--name <name>] [--password <password>] [--force]',
  );
  process.exit(1);
}
const name =
  typeof args.name === 'string' && args.name.trim() ? args.name.trim() : email.split('@')[0];

let password = typeof args.password === 'string' ? args.password : undefined;
let generated = false;
if (!password) {
  password = randomBytes(12).toString('base64url');
  generated = true;
} else if (password.length < 6) {
  console.error('error: --password must be at least 6 characters');
  process.exit(1);
}

// --- scrypt hash (must match crypto.util.ts) ------------------------------
function hashPassword(pw) {
  const salt = randomBytes(16);
  const key = scryptSync(pw, salt, 64);
  return `${salt.toString('hex')}:${key.toString('hex')}`;
}

// --- create / reset -------------------------------------------------------
if (!process.env.DATABASE_URL) {
  console.error('error: DATABASE_URL is not set (checked process.env and .env)');
  process.exit(1);
}

let PrismaClient;
try {
  ({ PrismaClient } = await import('@prisma/client'));
} catch {
  console.error(
    'error: could not load @prisma/client. Run `npm install` and `npm run prisma:generate`.',
  );
  process.exit(1);
}

const prisma = new PrismaClient();
try {
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing && !args.force) {
    console.error(`error: user ${email} already exists (pass --force to reset their password)`);
    process.exit(1);
  }

  const passwordHash = hashPassword(password);
  const user = existing
    ? await prisma.user.update({ where: { email }, data: { passwordHash } })
    : await prisma.user.create({ data: { email, name, passwordHash } });

  console.log(`${existing ? 'Reset password for' : 'Created user'}: ${user.email} (id ${user.id})`);
  if (generated) console.log(`Generated password: ${password}`);
} catch (err) {
  console.error(`error: ${err?.message ?? err}`);
  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
