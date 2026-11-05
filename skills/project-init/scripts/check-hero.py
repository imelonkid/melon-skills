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
    if end.get('auto_release') is not False:
        errors.append('hero 端须 auto_release: false，由门户人工发起')
    if not end.get('paths') or not any((project / p / 'index.html').is_file() for p in end['paths']):
        errors.append('登记的 Hero 页面目录缺少 index.html')
    workflow = end.get('release')
    if not isinstance(workflow, str) or Path(workflow).name != workflow:
        return errors + ['Hero 发布入口文件名不合法']
    source = project / '.github/workflows' / workflow
    if not source.is_file():
        return errors + ['缺少登记的 Hero 发布表单']
    text = source.read_text()
    if not re.search(r'uses:\s*imelonkid/melon-ci/\.github/workflows/page-release\.yml@', text):
        errors.append('Hero 表单须调用独立 page-release')
    if re.search(r'\$\{\{\s*(secrets|vars)\.DEPLOY_', text):
        errors.append('Hero 表单不得使用 GitHub 主机部署凭据')
    if '__NAME__' in text:
        errors.append('Hero 表单仍含项目名占位符')
    return errors


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('project', type=Path)
    p.add_argument('ops', type=Path)
    p.add_argument('name')
    args = p.parse_args()
    try:
        errors = check(args.project, args.ops, args.name)
    except (OSError, ValueError, KeyError) as e:
        errors = [f'无法核对 Hero 登记：{e}']
    for error in errors:
        print(f'  ✗ {error}')
    if not errors:
        print('  ✓ Hero 表单与应用登记一致（配套上线能力仍须单独验收）')
    raise SystemExit(bool(errors))
