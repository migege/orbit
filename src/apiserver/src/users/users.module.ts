import { Module } from '@nestjs/common';
import { AdminAuthGuard } from './admin-auth.guard';
import { UsersController } from './users.controller';

@Module({
  controllers: [UsersController],
  providers: [AdminAuthGuard],
})
export class UsersModule {}
