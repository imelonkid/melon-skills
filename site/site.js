// 唯一的 skill 清单：首页卡片和每页顶部菜单都从这里生成。新增 skill 先改这里。
const SKILLS = [
  { id: 'project-init', name: '项目初始化', summary: '按多云运维规范起一个新项目：git + GitHub、骨架、部署模板、服务注册、准入检查。', tags: ['git', 'docker', '规范'] },
  { id: 'server-ops', name: '服务器运维', summary: '多云服务器的巡检、排障、部署、基线收敛与灾备。坐标全部来自环境变量，事实在私有仓库。', tags: ['ssh', '监控', '基线'] },
  { id: 'article-review', name: '文章审阅', summary: '博客发布前的审阅：错别字、语病、文笔、标签与图片，产出可逐字对比的待审 commit。', tags: ['博客', 'Obsidian', '写作'] },
];
const REPO = 'https://github.com/imelonkid/melon-skills';

(function () {
  const here = document.body.dataset.page;            // 'home' 或 skill id
  const root = here === 'home' ? 'site/' : '';         // 首页在仓库根，skill 页在 site/
  const home = here === 'home' ? 'index.html' : '../index.html';

  // 菜单
  const nav = document.createElement('header');
  nav.className = 'nav';
  nav.innerHTML = `<div class="nav-in">
    <a class="brand" href="${home}"><i></i>melon-skills</a>
    <nav class="menu">
      <a href="${home}" class="${here === 'home' ? 'on' : ''}">首页</a>
      ${SKILLS.map(s => `<a href="${root}${s.id}.html" class="${here === s.id ? 'on' : ''}">${s.name}</a>`).join('')}
    </nav>
    <div class="tools">
      <button id="theme" title="切换明暗">◐</button>
      <a href="${REPO}" title="GitHub">GitHub</a>
    </div></div>`;
  document.body.prepend(nav);
  nav.querySelector('.menu .on')?.scrollIntoView({ inline: 'center', block: 'nearest' });

  // 首页卡片
  const cards = document.getElementById('cards');
  if (cards) cards.innerHTML = SKILLS.map(s => `
    <a class="card" href="${root}${s.id}.html">
      <span class="k">${s.id}</span><h3>${s.name}</h3><p>${s.summary}</p>
      <div class="chips">${s.tags.map(t => `<span class="chip">${t}</span>`).join('')}</div>
      <span class="more">查看介绍 →</span>
    </a>`).join('');
  const count = document.getElementById('count');
  if (count) count.textContent = SKILLS.length;

  // 明暗切换（只记在本机浏览器）
  const KEY = 'melon-skills-theme';
  try { const t = localStorage.getItem(KEY); if (t) document.documentElement.dataset.theme = t; } catch (e) {}
  document.getElementById('theme').onclick = () => {
    const dark = matchMedia('(prefers-color-scheme: dark)').matches;
    const cur = document.documentElement.dataset.theme || (dark ? 'dark' : 'light');
    const next = cur === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem(KEY, next); } catch (e) {}
  };

  // 代码块复制
  document.querySelectorAll('pre').forEach(pre => {
    const b = document.createElement('button');
    b.className = 'copy'; b.textContent = '复制';
    b.onclick = () => navigator.clipboard.writeText(pre.innerText.replace(/复制$/, '').trim())
      .then(() => { b.textContent = '已复制'; setTimeout(() => (b.textContent = '复制'), 1200); });
    pre.appendChild(b);
  });

  // 目录高亮
  const links = [...document.querySelectorAll('.toc a')];
  if (links.length) {
    const io = new IntersectionObserver(es => es.forEach(e => {
      if (e.isIntersecting) links.forEach(a => a.classList.toggle('on', a.hash === '#' + e.target.id));
    }), { rootMargin: '-70px 0px -70% 0px' });
    links.forEach(a => { const t = document.querySelector(a.hash); t && io.observe(t); });
  }
})();
