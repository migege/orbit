import http2 from 'node:http2';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as jwt from 'jsonwebtoken';
import { PrismaService } from '../prisma/prisma.service';

const APNS_HOST_PROD = 'api.push.apple.com';
const APNS_HOST_SANDBOX = 'api.sandbox.push.apple.com';

/**
 * Sends "needs your reply" pushes to a user's registered iOS devices via APNs, using token-based
 * auth: a short-lived ES256 JWT signed with the team's .p8 key (cached ~50 min; APNs allows reuse
 * up to 1h). Best-effort — a push failure never affects the approval flow. Disabled (no-op) unless
 * APNS_KEY / APNS_KEY_ID / APNS_TEAM_ID are configured, so the server runs fine before the
 * credential is set and pushes light up the moment it is.
 */
@Injectable()
export class PushService {
  private readonly log = new Logger(PushService.name);
  private readonly keyId?: string;
  private readonly teamId?: string;
  private readonly bundleId: string;
  private readonly p8?: string;
  private cached?: { token: string; iat: number };

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    this.keyId = config.get<string>('APNS_KEY_ID');
    this.teamId = config.get<string>('APNS_TEAM_ID');
    this.bundleId = config.get<string>('APNS_BUNDLE_ID') ?? 'io.orbitd.app';
    const b64 = config.get<string>('APNS_KEY'); // base64 of the AuthKey_XXXX.p8
    this.p8 = b64 ? Buffer.from(b64, 'base64').toString('utf8') : undefined;
    if (!this.enabled) {
      this.log.warn('APNs not configured (APNS_KEY/APNS_KEY_ID/APNS_TEAM_ID) — pushes disabled');
    }
  }

  private get enabled(): boolean {
    return Boolean(this.keyId && this.teamId && this.p8);
  }

  /**
   * Tell the session's owner a tool approval is pending. Fire-and-forget: callers `void` this so a
   * slow/failed APNs round-trip never blocks the runner request that created the approval.
   */
  async notifyApprovalRequest(sessionId: string, toolName: string): Promise<void> {
    if (!this.enabled) return;
    try {
      const session = await this.prisma.session.findUnique({
        where: { id: sessionId },
        select: { title: true, ownerId: true },
      });
      if (!session) return;
      const tokens = await this.prisma.deviceToken.findMany({ where: { userId: session.ownerId } });
      if (tokens.length === 0) return;

      // App-icon badge = the owner's total pending approvals across all their sessions, so it stays
      // accurate even when several sessions need a reply. iOS sets it from the push automatically.
      const badge = await this.prisma.approval.count({
        where: { status: 'PENDING', session: { ownerId: session.ownerId } },
      });

      const auth = this.authToken();
      if (!auth) return;
      const body = JSON.stringify({
        aps: {
          alert: { title: session.title || 'Orbit', body: `Needs your reply · ${toolName}` },
          sound: 'default',
          badge,
          category: 'ORBIT_APPROVAL', // matches OrbitKit Notifications.approvalCategory
          'thread-id': sessionId,
        },
        sessionID: sessionId, // OrbitKit Notifications.keySession — routes the tap to this session
        kind: 'approval',
      });

      await Promise.all(
        tokens.map(async (t) => {
          const host = t.environment === 'sandbox' ? APNS_HOST_SANDBOX : APNS_HOST_PROD;
          const res = await this.send(host, t.token, body, auth);
          if (res.status === 410 || res.reason === 'BadDeviceToken' || res.reason === 'Unregistered') {
            // APNs says this token is dead — drop it so we stop pushing to it.
            await this.prisma.deviceToken.deleteMany({ where: { token: t.token } }).catch(() => {});
          } else if (res.status >= 400) {
            this.log.warn(`APNs ${res.status} ${res.reason ?? ''} for ${t.token.slice(0, 8)}…`);
          }
        }),
      );
    } catch (err) {
      this.log.warn(`push notify failed: ${(err as Error).message}`);
    }
  }

  /** Cached provider JWT (ES256, kid=keyId, iss=teamId). Refreshed well before APNs's 1h limit. */
  private authToken(): string | null {
    if (!this.enabled) return null;
    const now = Math.floor(Date.now() / 1000);
    if (this.cached && now - this.cached.iat < 3000) return this.cached.token;
    const token = jwt.sign({ iss: this.teamId, iat: now }, this.p8 as string, {
      algorithm: 'ES256',
      keyid: this.keyId,
    });
    this.cached = { token, iat: now };
    return token;
  }

  /** One APNs POST over a fresh HTTP/2 connection (approval events are infrequent — no pool). */
  private send(
    host: string,
    deviceToken: string,
    body: string,
    auth: string,
  ): Promise<{ status: number; reason?: string }> {
    return new Promise((resolve) => {
      const client = http2.connect(`https://${host}`);
      const done = (r: { status: number; reason?: string }) => {
        try {
          client.close();
        } catch {
          /* already closed */
        }
        resolve(r);
      };
      client.on('error', () => done({ status: 0 }));
      const req = client.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${auth}`,
        'apns-topic': this.bundleId,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      });
      let status = 0;
      let data = '';
      req.on('response', (h) => {
        status = Number(h[':status']) || 0;
      });
      req.on('data', (d) => {
        data += d;
      });
      req.on('end', () => {
        let reason: string | undefined;
        try {
          reason = data ? (JSON.parse(data).reason as string) : undefined;
        } catch {
          /* no JSON body */
        }
        done({ status, reason });
      });
      req.on('error', () => done({ status: 0 }));
      req.setTimeout(10_000, () => {
        try {
          req.close();
        } catch {
          /* ignore */
        }
        done({ status: 0 });
      });
      req.end(body);
    });
  }
}
