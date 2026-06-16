import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { ALLOW_QUERY_TOKEN } from './allow-query-token.decorator';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();
    const header: string | undefined = req.headers['authorization'];

    let token: string | undefined;
    if (header && header.startsWith('Bearer ')) {
      token = header.slice('Bearer '.length);
    } else if (typeof req.query?.access_token === 'string') {
      // EventSource (SSE) cannot set headers — accept a query-param token, but
      // ONLY on routes that opt in via @AllowQueryToken (the SSE stream). Other
      // routes require the header so bearer tokens don't leak into access logs.
      const allowQuery = this.reflector.getAllAndOverride<boolean>(ALLOW_QUERY_TOKEN, [
        context.getHandler(),
        context.getClass(),
      ]);
      if (allowQuery) token = req.query.access_token;
    }
    if (!token) throw new UnauthorizedException('missing bearer token');

    try {
      const payload = await this.jwt.verifyAsync(token);
      req.user = { userId: payload.sub, email: payload.email };
      return true;
    } catch {
      throw new UnauthorizedException('invalid token');
    }
  }
}
