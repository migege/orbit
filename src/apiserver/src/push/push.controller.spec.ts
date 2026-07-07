import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PushController } from './push.controller';
import type { AuthUser } from '../common/current-user.decorator';

const user: AuthUser = { userId: 'u1', email: 'a@b.c' };

function makePrisma() {
  const calls: { upsert: any[]; deleteMany: any[] } = { upsert: [], deleteMany: [] };
  const prisma = {
    calls,
    deviceToken: {
      upsert: async (args: any) => {
        calls.upsert.push(args);
        return {};
      },
      deleteMany: async (args: any) => {
        calls.deleteMany.push(args);
        return { count: 1 };
      },
    },
  };
  return prisma;
}

test('register upserts by token and scopes create/update to the current user', async () => {
  const prisma = makePrisma();
  const ctrl = new PushController(prisma as any);
  const res = await ctrl.register(user, {
    token: 'abc',
    bundleId: 'io.orbitd.app',
    environment: 'production',
  } as any);
  assert.deepEqual(res, { ok: true });
  const call = prisma.calls.upsert[0];
  assert.equal(call.where.token, 'abc');
  assert.equal(call.create.userId, 'u1');
  assert.equal(call.create.token, 'abc');
  assert.equal(call.create.environment, 'production');
  assert.equal(call.update.userId, 'u1');
});

test('register defaults platform=ios and environment=production when omitted', async () => {
  const prisma = makePrisma();
  const ctrl = new PushController(prisma as any);
  await ctrl.register(user, { token: 'abc', bundleId: 'io.orbitd.app' } as any);
  const call = prisma.calls.upsert[0];
  assert.equal(call.create.platform, 'ios');
  assert.equal(call.create.environment, 'production');
});

test('unregister deletes only the caller’s matching token', async () => {
  const prisma = makePrisma();
  const ctrl = new PushController(prisma as any);
  const res = await ctrl.unregister(user, { token: 'abc' } as any);
  assert.deepEqual(res, { ok: true });
  const call = prisma.calls.deleteMany[0];
  assert.equal(call.where.token, 'abc');
  assert.equal(call.where.userId, 'u1');
});
