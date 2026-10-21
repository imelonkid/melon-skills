import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { HealthModule } from './health/health.module.js';
import { PrismaModule } from './prisma/prisma.module.js';

// 模块化单体：按业务域加模块（src/<域>/<域>.module.ts），模块之间走服务接口、不跨模块直接查表
@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true }), ScheduleModule.forRoot(), PrismaModule, HealthModule],
})
export class AppModule {}
