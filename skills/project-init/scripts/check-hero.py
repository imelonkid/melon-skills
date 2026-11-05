#!/usr/bin/env python3
"""只读检查 Hero 的文件与现有门户登记关联，不访问网络或主机。"""
import argparse
import json
from pathlib import Path
import re


def check(project, ops, name):
    errors = []
    config = json.loads((ops / 'portal/config.json').read_text())
    app = next((s for s in config['services'] if s['name'] == name), None)
    end = next((e for e in (app or {}).get('ends', []) if e['end'] == 'hero'), None)
    if end is None:
        return ['运维侧应用未登记 hero 端']
    if end.get('prefix') != 'page-v' or end.get('pipelines', {}).get('release', {}).get('use') != 'page-release':
        errors.append('hero 端须使用 page-v 与 page-release')
    page = end.get('page')
    if not isinstance(page, dict) or any(not isinstance(page.get(k), str) or not page[k] or '__NAME__' in page[k] for k in ('service', 'project', 'source')):
        errors.append('hero 端缺少已填写的 page 服务/项目/来源登记')
    if end.get('rollback') != 'internal:page-rollback' or end.get('pipelines', {}).get('rollback', {}).get('use') != 'page-rollback':
        errors.append('hero 回滚须使用已登记的内网 page-rollback')
    if end.get('auto_release') is not False:
        errors.append('hero 端须 auto_release: false，由门户人工发起')
    if not end.get('paths') or not any((project / p / 'index.html').is_file() for p in end['paths']):
        errors.append('登记的 Hero 页面目录缺少 index.html')
    workflow = end.get('release')
    if not isinstance(workflow, str) or Path(workflow).name != workflow:
        return errors + ['Hero 发布入口文件名不合法']
    return errors + check_files(project, workflow)


def check_files(project, workflow='release-page.yml'):
    errors = []
    source = project / '.github/workflows' / workflow
    if not source.is_file():
        return ['缺少登记的 Hero 发布表单']
    text = source.read_text()
    if not re.search(r'uses:\s*imelonkid/melon-ci/\.github/workflows/page-release\.yml@', text):
        errors.append('Hero 表单须调用独立 page-release')
    if re.search(r'\$\{\{\s*(secrets|vars)\.DEPLOY_', text):
        errors.append('Hero 表单不得使用 GitHub 主机部署凭据')
    if '__NAME__' in text:
        errors.append('Hero 表单仍含项目名占位符')
    match = re.search(r'^\s*page-dir:\s*([A-Za-z0-9_./-]+)\s*$', text, re.M)
    if re.search(r'^\s*page-dir:', text, re.M) and not match:
        errors.append('Hero 表单须固定页面相对目录')
    page_dir = match.group(1) if match else 'site'  # 可复用工作流的默认目录
    if not (project / page_dir / 'index.html').is_file():
        errors.append('Hero 表单指定的页面目录缺少 index.html')
    return errors


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('project', type=Path)
    p.add_argument('ops', type=Path)
    p.add_argument('name')
    p.add_argument('--files-only', action='store_true')
    args = p.parse_args()
    try:
        errors = check_files(args.project) if args.files_only else check(args.project, args.ops, args.name)
    except (OSError, ValueError, KeyError) as e:
        errors = [f'无法核对 Hero 登记：{e}']
    for error in errors:
        print(f'  ✗ {error}')
    if not errors:
        print('  ✓ Hero 文件检查通过；尚未核对私有登记' if args.files_only else '  ✓ Hero 表单与应用登记一致（配套上线能力仍须单独验收）')
    raise SystemExit(bool(errors))
