import { Controller, Get, Res } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response } from 'express';
import { PrismaService } from '../prisma/prisma.service.js';

/**
 * 健康检查（项目基线）：数据库能查 → 200 {ok:true, version}；否则 503 {ok:false, version}。
 * version = APP_VERSION（镜像构建时由 tag 注入）——门户 server-release 用它验收：版本 = 本次 tag 且健康、稳定 20 秒才算上线完成。
 * 不带全局前缀、不套统一响应体（直接写响应）；不需要登录、不返回配置。
 */
@ApiExcludeController()
@Controller()
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('health')
  async health(@Res() res: Response) {
    const ok = await this.prisma.$queryRaw`SELECT 1`.then(
      () => true,
      () => false,
    );
    res.status(ok ? 200 : 503).json({ ok, version: process.env.APP_VERSION || 'dev' });
  }
}
