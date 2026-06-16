import { HttpException, HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { MintedRunner } from '@orbit/shared';
import { generateToken, sha256 } from '../common/crypto.util';
import { PrismaService } from '../prisma/prisma.service';
import { CreateEnrollmentTokenDto, UpdateRunnerDto } from './dto';

// Three missed 30s heartbeats — a runner quieter than this reads as offline.
const OFFLINE_AFTER_MS = 90_000;
// Cap device-enrollment userCode lookups per user, so an authenticated insider
// cannot brute-force another user's pending enrollment code online.
const DEVICE_LOOKUP_WINDOW_MS = 5 * 60_000;
const DEVICE_LOOKUP_MAX = 20;

@Injectable()
export class RunnersService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly deviceLookups = new Map<string, number[]>();

  /** Throttle per-user userCode lookups to defeat online enumeration. */
  private rateLimitDeviceLookup(userId: string): void {
    const now = Date.now();
    const recent = (this.deviceLookups.get(userId) ?? []).filter(
      (t) => now - t < DEVICE_LOOKUP_WINDOW_MS,
    );
    if (recent.length >= DEVICE_LOOKUP_MAX) {
      throw new HttpException(
        'too many enrollment lookups, slow down',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    recent.push(now);
    this.deviceLookups.set(userId, recent);
  }

  async listRunners(ownerId: string) {
    const runners = await this.prisma.runner.findMany({
      where: { ownerId },
      orderBy: { enrolledAt: 'desc' },
      select: {
        id: true,
        name: true,
        displayName: true,
        hostname: true,
        labels: true,
        status: true,
        maxConcurrent: true,
        version: true,
        lastHeartbeatAt: true,
        enrolledAt: true,
      },
    });
    // A runner heartbeats every 30s; treat a missed window as offline so the UI
    // reflects dropouts without waiting for a background reaper.
    const staleBefore = Date.now() - OFFLINE_AFTER_MS;
    return runners.map((r) => ({
      ...r,
      online: r.status !== 'OFFLINE' && !!r.lastHeartbeatAt && r.lastHeartbeatAt.getTime() >= staleBefore,
    }));
  }

  async createEnrollmentToken(ownerId: string, dto: CreateEnrollmentTokenDto) {
    const raw = generateToken(24);
    const expiresAt = dto.ttlHours
      ? new Date(Date.now() + dto.ttlHours * 3600 * 1000)
      : null;
    const rec = await this.prisma.enrollmentToken.create({
      data: { ownerId, tokenHash: sha256(raw), label: dto.label, expiresAt },
    });
    // The raw token is shown exactly once — only its hash is persisted.
    return { id: rec.id, token: raw, label: rec.label, expiresAt: rec.expiresAt };
  }

  listEnrollmentTokens(ownerId: string) {
    return this.prisma.enrollmentToken.findMany({
      where: { ownerId },
      orderBy: { createdAt: 'desc' },
      select: { id: true, label: true, expiresAt: true, usedAt: true, createdAt: true },
    });
  }

  /** Details shown on the browser approval page for an `orbit register` session. */
  async getDeviceEnrollment(ownerId: string, userCode: string) {
    this.rateLimitDeviceLookup(ownerId);
    const s = await this.prisma.deviceEnrollment.findUnique({ where: { userCode } });
    if (!s || s.expiresAt < new Date()) {
      throw new NotFoundException('enrollment request not found or expired');
    }
    // Warn (don't block) if this user already runs a runner this enrollment would
    // mint — either the bare base name or any `<name>/<agentKey>` — so they don't
    // unknowingly register a duplicate.
    const nameConflict =
      (await this.prisma.runner.count({
        where: { ownerId, OR: [{ name: s.name }, { name: { startsWith: `${s.name}/` } }] },
      })) > 0;
    return {
      userCode: s.userCode,
      name: s.name,
      hostname: s.hostname,
      labels: s.labels,
      maxConcurrent: s.maxConcurrent,
      status: s.status,
      nameConflict,
      createdAt: s.createdAt,
    };
  }

  /** Approve a device session: create the runner under this user and stash its token. */
  async approveDeviceEnrollment(ownerId: string, userCode: string) {
    this.rateLimitDeviceLookup(ownerId);
    const s = await this.prisma.deviceEnrollment.findUnique({ where: { userCode } });
    if (!s || s.expiresAt < new Date()) {
      throw new NotFoundException('enrollment request not found or expired');
    }
    if (s.status === 'APPROVED') return { ok: true, name: s.name, replaced: false, count: s.agents.length || 1 };

    // One runner per requested agent, named `<name>/<agentKey>`; no agents -> a
    // single runner named `name`.
    const keys = s.agents.length ? s.agents : [''];
    const minted: MintedRunner[] = [];
    let replaced = false;
    for (const key of keys) {
      const runnerName = key ? `${s.name}/${key}` : s.name;
      const runnerToken = generateToken(32);
      const data = {
        hostname: s.hostname,
        labels: s.labels,
        maxConcurrent: s.maxConcurrent,
        version: s.version,
        tokenHash: sha256(runnerToken),
        status: 'ONLINE' as const,
        lastHeartbeatAt: new Date(),
      };
      // A runner of the same name for this user is replaced (its credential is
      // reissued) rather than duplicated, so re-registering a machine reuses its
      // identity and keeps its run history.
      const existing = await this.prisma.runner.findFirst({
        where: { ownerId, name: runnerName },
        orderBy: { enrolledAt: 'desc' },
      });
      const runner = existing
        ? await this.prisma.runner.update({ where: { id: existing.id }, data })
        : await this.prisma.runner.create({ data: { ...data, name: runnerName, ownerId } });
      if (existing) replaced = true;
      minted.push({ agentKey: key, runnerId: runner.id, runnerToken, name: runner.name });
    }

    await this.prisma.deviceEnrollment.update({
      where: { id: s.id },
      data: {
        status: 'APPROVED',
        runnerId: minted[0].runnerId,
        runnerToken: minted[0].runnerToken,
        runners: minted as unknown as Prisma.InputJsonValue,
        approvedById: ownerId,
        approvedAt: new Date(),
      },
    });
    return { ok: true, name: s.name, replaced, count: minted.length };
  }

  async updateRunner(ownerId: string, id: string, dto: UpdateRunnerDto) {
    const runner = await this.prisma.runner.findFirst({ where: { id, ownerId } });
    if (!runner) throw new NotFoundException('runner not found');
    const data: { displayName?: string | null } = {};
    if (dto.displayName !== undefined) {
      const trimmed = dto.displayName.trim();
      data.displayName = trimmed.length ? trimmed : null;
    }
    // Never echo back tokenHash.
    return this.prisma.runner.update({
      where: { id },
      data,
      select: { id: true, name: true, displayName: true },
    });
  }

  async removeRunner(ownerId: string, id: string) {
    const runner = await this.prisma.runner.findFirst({ where: { id, ownerId } });
    if (!runner) throw new NotFoundException('runner not found');
    await this.prisma.runner.delete({ where: { id } });
    return { ok: true };
  }
}
