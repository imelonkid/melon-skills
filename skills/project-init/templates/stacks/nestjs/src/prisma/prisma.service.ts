import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
import { PrismaClient } from '../generated/prisma/client.js';

/**
 * 数据库（MySQL 8 + Prisma 7，驱动适配器 @prisma/adapter-mariadb）。
 * 连接串 DATABASE_URL：mysql://<项目账号>:<密码>@<节点共享实例>:3306/<项目库>（每个项目独立库与账号，见项目基线「数据库部署」）。
 * 第一次查询时才连库：库暂时不可用也能启动，/health 报 503。
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleDestroy {
  constructor() {
    super({ adapter: new PrismaMariaDb(process.env.DATABASE_URL ?? '') });
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
