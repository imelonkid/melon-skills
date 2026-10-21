import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import { currentTraceId, setResult } from '@imelonkid/common/server';
import type { Response } from 'express';
import { BizException, ErrorCodes } from './biz.exception.js';

/**
 * 统一错误响应 { code, message, data: null, traceId }：traceId 让用户截图报错时能带上追踪号。
 * 不在这里写日志——业务码与异常用 setResult 记下，由请求日志一并记成一条（未捕获异常是 error 级、带完整栈）。
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();
    const traceId = currentTraceId();
    const send = (status: number, code: number, message: string) =>
      res.status(status).json({ code, message, data: null, traceId });

    if (exception instanceof BizException) {
      setResult(res, exception.code); // 业务异常：HTTP 200 + 业务码
      return send(HttpStatus.OK, exception.code, exception.message);
    }
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse() as { message?: string | string[] };
      const message = Array.isArray(body?.message) ? body.message.join('; ') : (body?.message ?? exception.message);
      setResult(res, status);
      return send(status, status, message);
    }
    // 请求体解析错误（超大 413、JSON 坏了 400）是客户端的问题，按它自带的 4xx 回
    const e = exception as { status?: number; expose?: boolean };
    if (e?.expose && typeof e.status === 'number' && e.status >= 400 && e.status < 500) {
      setResult(res, e.status);
      return send(e.status, e.status, e.status === 413 ? '请求体太大' : '请求格式不对');
    }
    setResult(res, ErrorCodes.SYSTEM_BUSY, exception);
    return send(HttpStatus.INTERNAL_SERVER_ERROR, ErrorCodes.SYSTEM_BUSY, '系统繁忙，请稍后再试');
  }
}
