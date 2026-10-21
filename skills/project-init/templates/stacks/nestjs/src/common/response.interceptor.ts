import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { currentTraceId, setResult } from '@imelonkid/common/server';
import { Observable, map } from 'rxjs';

/** 统一响应体 { code: 0, message, data, traceId }；业务码用 setResult 记下给请求日志用 */
@Injectable()
export class ResponseInterceptor implements NestInterceptor {
  intercept(ctx: ExecutionContext, next: CallHandler): Observable<unknown> {
    return next.handle().pipe(
      map((data) => {
        setResult(ctx.switchToHttp().getResponse(), 0);
        return { code: 0, message: 'ok', data: data ?? null, traceId: currentTraceId() };
      }),
    );
  }
}
