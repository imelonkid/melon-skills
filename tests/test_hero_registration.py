import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('hero', ROOT / 'skills/project-init/scripts/check-hero.py')
hero = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hero)


class RegistrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.project, self.ops = self.root / 'app', self.root / 'ops'
        (self.project / '.github/workflows').mkdir(parents=True)
        (self.project / 'site').mkdir()
        (self.project / 'site/index.html').write_text('Hero')
        (self.ops / 'portal').mkdir(parents=True)
        self.end = json.loads((ROOT / 'skills/project-init/templates/page/hero-end.json').read_text().replace('__NAME__', 'sample'))
        text = (ROOT / 'skills/project-init/templates/page/release-page.yml').read_text().replace('__NAME__', 'sample')
        (self.project / '.github/workflows/release-page.yml').write_text(text)

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self, apps=None):
        if apps is None:
            apps = [dict(name='sample', ends=[self.end])]
        (self.ops / 'portal/config.json').write_text(json.dumps(dict(services=apps)))
        return hero.check(self.project, self.ops, 'sample')

    def test_registered_application(self):
        self.assertEqual(self.run_check(), [])

    def test_other_application_does_not_authorize(self):
        self.assertTrue(self.run_check([dict(name='other', ends=[self.end])]))

    def test_must_use_page_pipeline(self):
        self.end['pipelines']['release']['use'] = 'server-release'
        self.assertTrue(self.run_check())

    def test_missing_workflow_and_homepage(self):
        (self.project / 'site/index.html').unlink()
        (self.project / '.github/workflows/release-page.yml').unlink()
        self.assertEqual(len(self.run_check()), 2)

    def test_ssh_credentials_rejected(self):
        p = self.project / '.github/workflows/release-page.yml'
        p.write_text(p.read_text() + '\n# ${{ secrets.DEPLOY_SSH_KEY }}\n')
        self.assertTrue(self.run_check())

    def test_custom_registered_form_filename(self):
        self.end['release'] = 'publish-hero.yml'
        (self.project / '.github/workflows/release-page.yml').rename(self.project / '.github/workflows/publish-hero.yml')
        self.assertEqual(self.run_check(), [])


if __name__ == '__main__':
    unittest.main()
