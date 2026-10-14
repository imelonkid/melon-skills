// 唯一的 skill 清单：侧栏「页面」菜单和首页卡片都从这里生成。新增 skill 先改这里。
const SKILLS = [
  { id: 'project-init', name: '项目初始化', summary: '按 melon-ops 运维规范与项目基线起项目：GitHub 托管、自动定级、技术栈模板、容器与可观测达标、服务注册、上线准入检查。', tags: ['git', 'docker', '规范'] },
  { id: 'server-ops', name: '服务器运维', summary: '多云服务器的巡检、排障、部署、基线收敛与灾备。坐标全部来自环境变量，事实在私有仓库。', tags: ['ssh', '监控', '基线'] },
  { id: 'article-review', name: '文章审阅', summary: '博客发布前的审阅：错别字、语病、文笔、标签与图片，产出可逐字对比的待审 commit。', tags: ['博客', 'Obsidian', '写作'] },
];
const VERSION = 'v1.0 · 2026-10-12';

(function () {
  const here = document.body.dataset.page;               // 'home' 或 skill id
  const pre = here === 'home' ? 'site/' : '';             // 首页在仓库根，skill 页在 site/
  const home = here === 'home' ? 'index.html' : '../index.html';

  // 章节编号：给每个 section 的 h2 加 01、02…（hero 算 01）
  const secs = [...document.querySelectorAll('main > section[id]')];
  secs.forEach((s, i) => {
    const h = s.querySelector(':scope > h2');
    if (h && !h.querySelector('.no')) h.insertAdjacentHTML('afterbegin', `<span class="no">${String(i + 2).padStart(2, '0')}</span>`);
  });

  // 侧栏：页面菜单 + 本页目录
  const hero = document.querySelector('header.hero');
  const items = [hero && { id: hero.id, t: hero.dataset.toc || '概览' }, ...secs.map(s => ({ id: s.id, t: s.dataset.toc || s.querySelector('h2').lastChild.textContent.trim() }))].filter(Boolean);
  const nav = document.querySelector('nav.toc');
  nav.innerHTML = `
    <div class="brand">melon-skills</div>
    <div class="ver">${VERSION}</div>
    <div class="grp">页面</div>
    <ul class="pages">
      <li><a href="${home}" class="${here === 'home' ? 'cur' : ''}">首页<small>index</small></a></li>
      ${SKILLS.map(s => `<li><a href="${pre}${s.id}.html" class="${here === s.id ? 'cur' : ''}">${s.name}<small>${s.id}</small></a></li>`).join('')}
    </ul>
    <div class="grp">本页目录</div>
    <ol>${items.map(x => `<li><a href="#${x.id}">${x.t}</a></li>`).join('')}</ol>
    <button class="theme" id="theme">切换明暗</button>
    <div class="grp"><a href="https://github.com/imelonkid/melon-skills">GitHub ↗</a></div>`;

  // 首页卡片
  const box = document.getElementById('skills-list');
  if (box) box.innerHTML = SKILLS.map(s => `
    <a class="skill" href="${pre}${s.id}.html">
      <span class="id">${s.id}</span><h4>${s.name}</h4><p>${s.summary}</p>
      <span class="tags">${s.tags.map(t => `<span class="badge b-n">${t}</span>`).join('')}</span>
      <span class="more">查看介绍 →</span>
    </a>`).join('');
  document.querySelectorAll('[data-count]').forEach(e => (e.textContent = SKILLS.length));

  // 复制按钮
  document.querySelectorAll('pre').forEach(p => {
    const b = document.createElement('button'); b.className = 'copy'; b.textContent = '复制';
    b.onclick = () => { navigator.clipboard?.writeText(p.innerText.replace(/复制$/, '').trim()); b.textContent = '已复制'; setTimeout(() => (b.textContent = '复制'), 1200); };
    p.appendChild(b);
  });

  // 目录高亮
  const links = [...nav.querySelectorAll('ol a')];
  const io = new IntersectionObserver(es => es.forEach(e => {
    if (e.isIntersecting) links.forEach(a => a.classList.toggle('on', a.getAttribute('href') === '#' + e.target.id));
  }), { rootMargin: '-30% 0px -65% 0px' });
  document.querySelectorAll('main section[id], header.hero').forEach(s => io.observe(s));

  // 明暗切换（记住选择，与白皮书同一机制）
  const root = document.documentElement;
  document.getElementById('theme').onclick = () => {
    const dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    try { localStorage.setItem('ms-theme', root.dataset.theme); } catch (e) {}
  };
})();
