"""验证 hero-pages 技能、文档索引同步、公开仓库脱敏与多站 melon-pages 兼容性。"""
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('hero', ROOT / 'skills/project-init/scripts/check-hero.py')
hero = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hero)


class HeroPagesSkillTests(unittest.TestCase):
    def test_skill_file_and_frontmatter(self):
        skill = ROOT / 'skills/hero-pages/SKILL.md'
        self.assertTrue(skill.is_file())
        text = skill.read_text(encoding='utf-8')
        self.assertRegex(text, r'^---\nname:\s*hero-pages\ndescription:\s*.+\n---')
        for keyword in (
            'imelonkid/melon-pages',
            'sites.yaml',
            'site/index.html',
            'site/shared/',
            'hero-pages.conf',
            '/.page-release.json',
            '64 MiB',
            '1280px',
            '728px',
            '390px',
            '京ICP备16017845号-2',
            'Made by melonkid',
        ):
            self.assertIn(keyword, text)

    def test_public_repo_safety(self):
        """确保公开仓库新增文档不含私有内网地址、服务器绝对路径或部署凭据。"""
        for rel in (
            'skills/hero-pages/SKILL.md',
            'site/hero-pages.html',
            'skills/project-init/SKILL.md',
            'skills/project-init/templates/BASELINE.md',
            'site/project-init.html',
        ):
            text = (ROOT / rel).read_text(encoding='utf-8')
            self.assertNotRegex(text, r'/www/sites/|/opt/1panel/www/sites/', msg=f'{rel} 含有服务器绝对部署路径')
            self.assertNotRegex(text, r'\b10\.\d+\.\d+\.\d+\b', msg=f'{rel} 含有内网 IP')

    def test_docs_and_index_registration(self):
        self.assertTrue((ROOT / 'site/hero-pages.html').is_file())
        self.assertIn("id: 'hero-pages'", (ROOT / 'site/site.js').read_text(encoding='utf-8'))
        self.assertIn('skills/hero-pages/SKILL.md', (ROOT / 'README.md').read_text(encoding='utf-8'))
        self.assertIn('site/hero-pages.html', (ROOT / 'index.html').read_text(encoding='utf-8'))

    def test_multisite_melon_pages_compatible_with_check_hero(self):
        """多站 melon-pages 结构与现有 check-hero.py 完全兼容。"""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project, ops = root / 'melon-pages', root / 'ops'
            (project / '.github/workflows').mkdir(parents=True)
            (project / 'site/memocat.melonkid.cn/assets').mkdir(parents=True)
            (project / 'site/index.html').write_text('<!doctype html><title>melon-pages</title>')
            (project / 'site/memocat.melonkid.cn/index.html').write_text('<!doctype html><title>MemoCat</title>')
            wf = (ROOT / 'skills/project-init/templates/page/release-page.yml').read_text().replace('__NAME__', 'melon-pages')
            (project / '.github/workflows/release-page.yml').write_text(wf)
            (ops / 'portal').mkdir(parents=True)
            end = json.loads((ROOT / 'skills/project-init/templates/page/hero-end.json').read_text().replace('__NAME__', 'melon-pages'))
            end['page']['service'] = 'melon-pages'
            (ops / 'portal/config.json').write_text(json.dumps({'services': [{'name': 'melon-pages', 'ends': [end]}]}))
            self.assertEqual(hero.check(project, ops, 'melon-pages'), [])
            self.assertEqual(hero.check_files(project), [])


if __name__ == '__main__':
    unittest.main()
