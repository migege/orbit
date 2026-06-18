import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { CreatorType, Prisma, TaskComment } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTaskCommentDto, CreateTaskDto, UpdateTaskDto } from './dto';

/** A polymorphic actor (user or agent) that authored a task or comment. */
export type Creator = { type: CreatorType; id: string };

@Injectable()
export class TasksService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * A task may only be assigned to an agent the same user owns — otherwise a user
   * could point a task at another tenant's agent (cross-tenant routing). Mirrors
   * AgentsService.assertOwnedRunner / SessionsService.assertOwnedRefs.
   */
  private async assertOwnedAgent(ownerId: string, agentId?: string | null): Promise<void> {
    if (!agentId) return;
    const agent = await this.prisma.agent.findFirst({
      where: { id: agentId, ownerId },
      select: { id: true },
    });
    if (!agent) throw new ForbiddenException('agent not found');
  }

  /** A task may only be filed under a list the same user owns (cf. assertOwnedAgent). */
  private async assertOwnedList(ownerId: string, listId?: string | null): Promise<void> {
    if (!listId) return;
    const list = await this.prisma.taskList.findFirst({
      where: { id: listId, ownerId },
      select: { id: true },
    });
    if (!list) throw new ForbiddenException('task list not found');
  }

  /**
   * Validate an agent belongs to the owner and return it as a task/comment creator.
   * Used by the runner MCP path to attribute work to the acting agent. Returns
   * undefined when no agent id is supplied so callers fall back to USER attribution.
   */
  async resolveAgentCreator(ownerId: string, agentId?: string): Promise<Creator | undefined> {
    if (!agentId) return undefined;
    const agent = await this.prisma.agent.findFirst({
      where: { id: agentId, ownerId },
      select: { id: true },
    });
    if (!agent) throw new ForbiddenException('agent not found');
    return { type: CreatorType.AGENT, id: agent.id };
  }

  async create(ownerId: string, dto: CreateTaskDto, creator?: Creator) {
    if (!dto.title) throw new BadRequestException('title is required');
    await this.assertOwnedAgent(ownerId, dto.assigneeId);
    await this.assertOwnedList(ownerId, dto.listId);
    return this.prisma.task.create({
      data: {
        title: dto.title,
        description: dto.description,
        ownerId,
        // Defaults to the human (user-facing API); the runner path passes the agent.
        creatorType: creator?.type ?? CreatorType.USER,
        creatorId: creator?.id ?? ownerId,
        assigneeId: dto.assigneeId,
        listId: dto.listId,
        dueDate: dto.dueDate ? new Date(dto.dueDate) : undefined,
      },
    });
  }

  list(ownerId: string) {
    return this.prisma.task.findMany({
      where: { ownerId },
      orderBy: { createdAt: 'desc' },
      include: {
        assignee: { select: { id: true, name: true, model: true } },
        _count: { select: { comments: true } },
      },
    });
  }

  async get(ownerId: string, id: string) {
    const task = await this.prisma.task.findFirst({
      where: { id, ownerId },
      include: {
        assignee: { select: { id: true, name: true, model: true } },
        // author is polymorphic (no FK), so names are resolved separately below.
        comments: { orderBy: { createdAt: 'asc' } },
        sessions: { select: { id: true, title: true, status: true } },
      },
    });
    if (!task) throw new NotFoundException('task not found');
    return { ...task, comments: await this.resolveCommentAuthors(task.comments) };
  }

  /**
   * Resolve each comment's polymorphic author (USER|AGENT) to a display name in one
   * batched pass (no FK to include). Returns the comments with an added authorName.
   */
  private async resolveCommentAuthors(comments: TaskComment[]) {
    if (comments.length === 0) return [];
    const userIds = comments.filter((c) => c.authorType === CreatorType.USER).map((c) => c.authorId);
    const agentIds = comments.filter((c) => c.authorType === CreatorType.AGENT).map((c) => c.authorId);
    const [users, agents] = await Promise.all([
      userIds.length
        ? this.prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true } })
        : [],
      agentIds.length
        ? this.prisma.agent.findMany({ where: { id: { in: agentIds } }, select: { id: true, name: true } })
        : [],
    ]);
    const names = new Map<string, string>();
    for (const u of users) names.set(u.id, u.name);
    for (const a of agents) names.set(a.id, a.name);
    return comments.map((c) => ({ ...c, authorName: names.get(c.authorId) ?? null }));
  }

  async update(ownerId: string, id: string, dto: UpdateTaskDto) {
    await this.get(ownerId, id);
    if (dto.assigneeId) await this.assertOwnedAgent(ownerId, dto.assigneeId);
    if (dto.listId) await this.assertOwnedList(ownerId, dto.listId);
    const data: Prisma.TaskUpdateInput = {
      title: dto.title,
      description: dto.description,
      status: dto.status,
      dueDate: dto.dueDate === null ? null : dto.dueDate ? new Date(dto.dueDate) : undefined,
    };
    // assigneeId is a relation FK: connect to (re)assign, disconnect to clear.
    if (dto.assigneeId !== undefined) {
      data.assignee = dto.assigneeId ? { connect: { id: dto.assigneeId } } : { disconnect: true };
    }
    // listId is a relation FK: connect to (re)assign, disconnect to detach.
    if (dto.listId !== undefined) {
      data.list = dto.listId ? { connect: { id: dto.listId } } : { disconnect: true };
    }
    return this.prisma.task.update({ where: { id }, data });
  }

  async remove(ownerId: string, id: string) {
    await this.get(ownerId, id);
    await this.prisma.task.delete({ where: { id } });
    return { ok: true };
  }

  async addComment(ownerId: string, id: string, dto: CreateTaskCommentDto, author?: Creator) {
    await this.get(ownerId, id);
    if (!dto.body) throw new BadRequestException('body is required');
    return this.prisma.taskComment.create({
      data: {
        taskId: id,
        // Defaults to the human (user-facing API); the runner path passes the agent.
        authorType: author?.type ?? CreatorType.USER,
        authorId: author?.id ?? ownerId,
        body: dto.body,
      },
    });
  }

  async removeComment(ownerId: string, id: string, commentId: string) {
    await this.get(ownerId, id);
    const comment = await this.prisma.taskComment.findFirst({
      where: { id: commentId, taskId: id },
      select: { id: true },
    });
    if (!comment) throw new NotFoundException('comment not found');
    await this.prisma.taskComment.delete({ where: { id: commentId } });
    return { ok: true };
  }
}
