import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { timingSafeEqual } from 'crypto';

/**
 * Guards operator-only endpoints (e.g. provisioning users) with a shared
 * secret from the ADMIN_TOKEN env var. Accept it as a Bearer token or an
 * `x-admin-token` header. If ADMIN_TOKEN is unset the endpoint stays closed.
 */
@Injectable()
export class AdminAuthGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const expected = this.config.get<string>('ADMIN_TOKEN');
    if (!expected) {
      throw new UnauthorizedException('admin endpoints are disabled (ADMIN_TOKEN not set)');
    }

    const req = context.switchToHttp().getRequest();
    const header: string | undefined = req.headers['authorization'];
    const token =
      header && header.startsWith('Bearer ')
        ? header.slice('Bearer '.length)
        : (req.headers['x-admin-token'] as string | undefined);

    if (!token || !safeEqual(token, expected)) {
      throw new UnauthorizedException('invalid admin token');
    }
    return true;
  }
}

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}
