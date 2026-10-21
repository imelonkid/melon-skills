import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { clientLogsHandler, getLogger, installProcessHandlers, requestLogging } from '@imelonkid/common/server';
import type { Request } from 'express';
import { AppModule } from './app.module.js';
import { AllExceptionsFilter } from './common/all-exceptions.filter.js';
import { ResponseInterceptor } from './common/response.interceptor.js';

// 日志按运维仓库 docs/11-logging.md，实现来自公共包 @imelonkid/common
const logger = getLogger(); // stdout 一行一条 JSON；service = OTEL_SERVICE_NAME，version = APP_VERSION
installProcessHandlers(logger); // 未捕获异常落 error、退出前写完缓冲

type Authed = Request & { user?: { sub?: number | string; role?: string } };

const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: true });
app.useLogger(logger);
// 第一个中间件：追踪号（X-Request-Id，响应头回传）+ 一请求一条请求日志
app.use(
  requestLogging({
    identify: (req: Authed) => (req.user?.sub !== undefined ? { user_id: req.user.sub, role: req.user.role } : {}),
  }),
);
// 客户端错误上报（gzip、16KB 上限，挂在 JSON 解析之前、不经过登录）；运营后台走 admin 路径（内网入口只放行 /api/v1/admin/*）
app.use(['/api/v1/client-logs', '/api/v1/admin/client-logs'], clientLogsHandler());

app.setGlobalPrefix('api/v1', { exclude: ['health'] }); // /health 不带前缀（部署入口、门户验收、Gatus 探活）
app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
app.useGlobalInterceptors(new ResponseInterceptor());
app.useGlobalFilters(new AllExceptionsFilter());
app.enableShutdownHooks();

if (process.env.NODE_ENV !== 'production') {
  const doc = new DocumentBuilder().setTitle('__NAME__').setVersion(process.env.APP_VERSION || 'dev').build();
  SwaggerModule.setup('api/docs', app, () => SwaggerModule.createDocument(app, doc)); // 接口文档只在非生产环境
}

await app.listen(Number(process.env.PORT ?? 8080), process.env.HOST ?? '0.0.0.0');
