import { Test } from '@nestjs/testing';
import { HealthController } from './health.controller.js';
import { PrismaService } from '../prisma/prisma.service.js';

/** /health：库能查 200 + version；查不了 503（单元测试不连库，用桩） */
function resStub() {
  const r = { code: 0, body: undefined as unknown, status: (c: number) => ((r.code = c), r), json: (b: unknown) => ((r.body = b), r) };
  return r;
}

async function controller(dbOk: boolean) {
  const prisma = { $queryRaw: () => (dbOk ? Promise.resolve([1]) : Promise.reject(new Error('down'))) };
  const mod = await Test.createTestingModule({
    controllers: [HealthController],
    providers: [{ provide: PrismaService, useValue: prisma }],
  }).compile();
  return mod.get(HealthController);
}

describe('HealthController', () => {
  it('数据库正常：200，带 APP_VERSION', async () => {
    process.env.APP_VERSION = 'v1.2.3';
    const res = resStub();
    await (await controller(true)).health(res as never);
    expect(res.code).toBe(200);
    expect(res.body).toEqual({ ok: true, version: 'v1.2.3' });
  });

  it('数据库不可用：503', async () => {
    const res = resStub();
    await (await controller(false)).health(res as never);
    expect(res.code).toBe(503);
    expect(res.body).toMatchObject({ ok: false });
  });
});
