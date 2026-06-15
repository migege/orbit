import { Injectable, NotFoundException } from '@nestjs/common';
import { generateToken, sha256 } from '../common/crypto.util';
import { PrismaService } from '../prisma/prisma.service';
import { CreateEnrollmentTokenDto } from './dto';

// Three missed 30s heartbeats — a runner quieter than this reads as offline.
const OFFLINE_AFTER_MS = 90_000;

@Injectable()
export class RunnersService {
  constructor(private readonly prisma: PrismaService) {}

  async listRunners(ownerId: string) {
    const runners = await this.prisma.runner.findMany({
      where: { ownerId },
      orderBy: { enrolledAt: 'desc' },
      select: {
        id: true,
        name: true,
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
  async getDeviceEnrollment(_ownerId: string, userCode: string) {
    const s = await this.prisma.deviceEnrollment.findUnique({ where: { userCode } });
    if (!s || s.expiresAt < new Date()) {
      throw new NotFoundException('enrollment request not found or expired');
    }
    return {
      userCode: s.userCode,
      name: s.name,
      hostname: s.hostname,
      labels: s.labels,
      maxConcurrent: s.maxConcurrent,
      status: s.status,
      createdAt: s.createdAt,
    };
  }

  /** Approve a device session: create the runner under this user and stash its token. */
  async approveDeviceEnrollment(ownerId: string, userCode: string) {
    const s = await this.prisma.deviceEnrollment.findUnique({ where: { userCode } });
    if (!s || s.expiresAt < new Date()) {
      throw new NotFoundException('enrollment request not found or expired');
    }
    if (s.status === 'APPROVED') return { ok: true, name: s.name };

    const runnerToken = generateToken(32);
    const runner = await this.prisma.runner.create({
      data: {
        name: s.name,
        hostname: s.hostname,
        ownerId,
        labels: s.labels,
        maxConcurrent: s.maxConcurrent,
        version: s.version,
        tokenHash: sha256(runnerToken),
        status: 'ONLINE',
        lastHeartbeatAt: new Date(),
      },
    });
    await this.prisma.deviceEnrollment.update({
      where: { id: s.id },
      data: {
        status: 'APPROVED',
        runnerId: runner.id,
        runnerToken,
        approvedById: ownerId,
        approvedAt: new Date(),
      },
    });
    return { ok: true, name: runner.name };
  }

  async removeRunner(ownerId: string, id: string) {
    const runner = await this.prisma.runner.findFirst({ where: { id, ownerId } });
    if (!runner) throw new NotFoundException('runner not found');
    await this.prisma.runner.delete({ where: { id } });
    return { ok: true };
  }
}
