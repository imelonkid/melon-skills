/**
 * 业务错误码按域分段：1xxxx 通用、2xxxx 起各业务域各占一段（在这里登记，不在代码里写裸数字）。
 * 业务异常返回 HTTP 200 + 业务码（见 AllExceptionsFilter）；参数校验、未登录等走 HTTP 状态码。
 */
export const ErrorCodes = {
  SYSTEM_BUSY: 10000,
  COMMON_ERROR: 10001,
  UNAUTHORIZED: 10401,
  FORBIDDEN: 10403,
  NOT_FOUND: 10404,
} as const;

export class BizException extends Error {
  constructor(
    public readonly code: number,
    message: string,
  ) {
    super(message);
  }
}
