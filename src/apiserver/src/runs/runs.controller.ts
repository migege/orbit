import {
  Controller,
  ForbiddenException,
  Get,
  MessageEvent,
  Param,
  Query,
  Sse,
  UseGuards,
} from '@nestjs/common';
import { concat, concatMap, from, map, Observable, switchMap, throwError } from 'rxjs';
import { AllowQueryToken } from '../auth/allow-query-token.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';

@UseGuards(JwtAuthGuard)
@Controller('runs')
export class RunsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  @Get(':id')
  async get(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    const run = await this.prisma.taskRun.findFirst({
      where: { id, task: { ownerId: user.userId } },
      include: {
        toolCalls: { orderBy: { startedAt: 'asc' } },
        llmUsage: true,
        task: { select: { id: true, title: true } },
        runner: { select: { id: true, name: true } },
      },
    });
    if (!run) throw new ForbiddenException('run not found');
    return run;
  }

  /** Replays historical run events, then streams live ones over SSE. */
  @AllowQueryToken()
  @Sse(':id/events')
  events(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Query('sinceSeq') sinceSeq?: string,
  ): Observable<MessageEvent> {
    // On reconnect, replay only events after sinceSeq (the client also dedups by
    // seq, but this avoids re-sending a long interactive transcript every time).
    const since = Number(sinceSeq);
    const seqFilter = Number.isFinite(since) && since > 0 ? { gt: since } : undefined;
    // Gate the stream on ownership BEFORE any event is read or the live hub is
    // subscribed, so a non-owner can never see another user's transcript
    // (assistant text, tool inputs, shell output, secrets surfaced by tools).
    return from(
      this.prisma.taskRun.findFirst({
        where: { id, task: { ownerId: user.userId } },
        select: { id: true },
      }),
    ).pipe(
      switchMap((run) => {
        if (!run) return throwError(() => new ForbiddenException('run not found'));
        const history$ = from(
          this.prisma.runEvent.findMany({
            where: { runId: id, ...(seqFilter ? { seq: seqFilter } : {}) },
            orderBy: { seq: 'asc' },
          }),
        ).pipe(concatMap((rows) => from(rows)));
        const live$ = this.realtime.streamForRun(id);
        return concat(history$, live$);
      }),
      map(
        (e: { seq: number; type: string; payload: unknown; ts?: string; createdAt?: Date }) =>
          ({
            data: {
              seq: e.seq,
              type: e.type,
              payload: e.payload,
              ts: e.ts ?? e.createdAt,
            },
          }) as MessageEvent,
      ),
    );
  }
}
