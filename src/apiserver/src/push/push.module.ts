import { Module } from '@nestjs/common';
import { PushController } from './push.controller';

/** APNs push: device-token registration now (E2); the sender (PushService) lands in E3. */
@Module({
  controllers: [PushController],
})
export class PushModule {}
