'use strict';
/**
 * 版本与客户端兼容（示例为 Node；其他语言照同样的约定实现）。GET /api/health 返回这些字段：
 *
 *   version    服务端版本 = 镜像里的 APP_VERSION（= tag server-vX.Y.Z，deploy.sh 烘进镜像）
 *   apiVersion 接口有不兼容改动时 +1
 *   minClient  各端最低版本（X.Y.Z）。客户端低于它就提示升级。
 *              鸿蒙 / App Store 发出去收不回来，所以服务端至少兼容上一个 API 版本；
 *              只有在确实不兼容、且新版客户端已经上架之后，才提高这里的值。
 */
const VERSION = process.env.APP_VERSION || `dev-${require('../package.json').version}`;
const MIN_CLIENT = { desktop: '0.1.0', harmony: '0.1.0' };
module.exports = { VERSION, MIN_CLIENT };
