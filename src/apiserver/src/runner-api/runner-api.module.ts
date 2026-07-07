import { Module } from '@nestjs/common';
import { SessionsModule } from '../sessions/sessions.module';
import { TaskListsService } from '../task-lists/task-lists.service';
import { TasksService } from '../tasks/tasks.service';
import { RunnerApiController } from './runner-api.controller';
import { RunnerAuthGuard } from './runner-auth.guard';
import { RunnerTasksController } from './runner-tasks.controller';
import { PushModule } from '../push/push.module';

@Module({
  // TasksService now depends on SessionsService (to spawn agents from @-mentions in
  // task comments), so SessionsModule must be imported to provide it. TaskListsService
  // still only needs the global PrismaService. PushModule provides PushService so the
  // approval-create handler can notify the session owner's iOS devices.
  imports: [SessionsModule, PushModule],
  controllers: [RunnerApiController, RunnerTasksController],
  providers: [RunnerAuthGuard, TasksService, TaskListsService],
})
export class RunnerApiModule {}
