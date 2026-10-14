// 项目基线 v1 · 健康检查示例（Node 内置 http）。
// GET /health → 200 {"ok":true,"version":APP_VERSION}；依赖不可用时 503 {"ok":false,"error":…}
// version 取环境变量 APP_VERSION（镜像构建时由 tag 注入）；只检查能否正常服务，不检查外部服务；不需要登录、不返回配置
const VERSION = process.env.APP_VERSION || 'dev';

async function health(checkDb) {
  try {
    await checkDb();                      // 例：db.prepare('SELECT 1').get()
    return [200, { ok: true, version: VERSION }];
  } catch (e) {
    return [503, { ok: false, version: VERSION, error: String(e.message || e).slice(0, 200) }];
  }
}

// 在请求处理里：
//   if (req.method === 'GET' && url.pathname === '/health') {
//     const [code, body] = await health(() => db.prepare('SELECT 1').get());
//     res.writeHead(code, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify(body));
//   }
module.exports = { health, VERSION };
