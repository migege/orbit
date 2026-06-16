import { Global, Module } from '@nestjs/common';
import { RealtimeService } from './realtime.service';
import { ReaperService } from './reaper.service';

@Global()
@Module({
  providers: [RealtimeService, ReaperService],
  exports: [RealtimeService],
})
export class RealtimeModule {}
