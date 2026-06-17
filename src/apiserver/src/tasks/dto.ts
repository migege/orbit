import { IsDateString, IsIn, IsOptional, IsString, MinLength } from 'class-validator';
import { TaskStatus } from '@orbit/shared';

const TASK_STATUSES = Object.values(TaskStatus);

export class CreateTaskDto {
  @IsString()
  @MinLength(1)
  title!: string;

  @IsOptional() @IsString() description?: string;
  // The agent assigned to execute the task. Must be owned by the caller.
  @IsOptional() @IsString() assigneeId?: string;
  @IsOptional() @IsDateString() dueDate?: string;
}

export class UpdateTaskDto {
  @IsOptional() @IsString() @MinLength(1) title?: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsIn(TASK_STATUSES) status?: TaskStatus;
  // null clears the assignment; a string (re)assigns to that agent.
  @IsOptional() @IsString() assigneeId?: string | null;
  @IsOptional() @IsDateString() dueDate?: string | null;
}

export class CreateTaskCommentDto {
  @IsString()
  @MinLength(1)
  body!: string;
}
