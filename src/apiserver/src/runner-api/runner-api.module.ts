import { Module } from '@nestjs/common';
import { TaskListsService } from '../task-lists/task-lists.service';
import { TasksService } from '../tasks/tasks.service';
import { RunnerApiController } from './runner-api.controller';
import { RunnerAuthGuard } from './runner-auth.guard';
import { RunnerTasksController } from './runner-tasks.controller';

@Module({
  controllers: [RunnerApiController, RunnerTasksController],
  // TasksService/TaskListsService only depend on the global PrismaService, so they can
  // be provided here directly (no need to import/export their feature modules).
  providers: [RunnerAuthGuard, TasksService, TaskListsService],
})
export class RunnerApiModule {}
