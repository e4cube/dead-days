"""GameVado offline asset audit/index CLI. Python 3.11+, standard library only."""
import argparse
import hashlib
import json
import re
import sys
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

CATEGORIES = ('Characters', 'Environments', 'Props', 'Animations', 'Textures', 'UI', 'VFX', 'Audio')
FORMATS = ('GLB', 'GLTF', 'FBX', 'OBJ', 'BLEND', 'PNG', 'WEBP', 'SVG', 'WAV', 'OGG', 'JPG', 'EXR')
STATUSES = ('APPROVED', 'REVIEW_REQUIRED', 'BLOCKED')
LICENSES = {
    'CC0-1.0': 'https://creativecommons.org/publicdomain/zero/1.0/legalcode',
    'CC-BY-4.0': 'https://creativecommons.org/licenses/by/4.0/legalcode',
    'CC-BY-3.0': 'https://creativecommons.org/licenses/by/3.0/legalcode',
}

def sha256(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def local_file(folder, value):
    if not isinstance(value, str) or not value or '\\' in value or ':' in value:
        raise ValueError('expected portable relative path')
    p = (folder / value).resolve()
    if not p.is_relative_to(folder.resolve()) or not p.is_file():
        raise ValueError('missing file or path escapes asset directory: ' + value)
    return p

def https(value):
    if not isinstance(value, str):
        return False
    p = urlparse(value)
    return p.scheme == 'https' and bool(p.hostname) and not p.username and not p.password

def audit(meta, folder):
    """Never trust the declared approval alone; compute an effective decision."""
    errors, reasons = [], []
    if not isinstance(meta, dict):
        return 'REVIEW_REQUIRED', ['metadata must be an object'], []
    required = ('id', 'name', 'author', 'source_platform', 'source_url', 'license',
                'license_url', 'download_date', 'commercial_use', 'modification',
                'redistribution', 'attribution_required', 'attribution', 'styles',
                'category', 'tags', 'formats', 'files', 'evidence', 'review')
    for k in required:
        if k not in meta:
            errors.append('missing: ' + k)
    if type(meta.get('schema_version')) is not int or meta.get('schema_version') != 1:
        errors.append('schema_version must be 1')
    for k in ('id', 'name', 'author', 'source_platform', 'license'):
        if not isinstance(meta.get(k), str) or not meta.get(k, '').strip():
            errors.append('invalid text: ' + k)
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,79}', str(meta.get('id', ''))):
        errors.append('invalid id')
    if meta.get('id') != folder.name or meta.get('category') != folder.parent.name:
        errors.append('id/category must match directory')
    if meta.get('category') not in CATEGORIES:
        errors.append('invalid category')
    for k in ('source_url', 'license_url'):
        if not https(meta.get(k)):
            errors.append('invalid HTTPS URL: ' + k)
    try:
        if date.fromisoformat(meta.get('download_date', '')) > date.today():
            errors.append('future download date')
    except (TypeError, ValueError):
        errors.append('invalid download_date')
    for k in ('commercial_use', 'modification', 'redistribution', 'attribution_required'):
        if meta.get(k) is not None and type(meta.get(k)) is not bool:
            errors.append('expected boolean or null: ' + k)
    for k in ('styles', 'tags', 'formats'):
        v = meta.get(k)
        if not isinstance(v, list) or not v or any(not isinstance(x, str) or not x.strip() for x in v):
            errors.append('expected nonempty string list: ' + k)
    formats = meta.get('formats') if isinstance(meta.get('formats'), list) else []
    if any(x not in FORMATS for x in formats):
        errors.append('unsupported format')
    for key in ('files', 'evidence'):
        entries = meta.get(key)
        if not isinstance(entries, list) or not entries:
            errors.append('nonempty list required: ' + key)
            continue
        paths = set()
        for entry in entries:
            try:
                if not isinstance(entry, dict):
                    raise ValueError('entry must be object')
                path = local_file(folder, entry.get('path'))
                if path in paths:
                    raise ValueError('duplicate file')
                paths.add(path)
                if not re.fullmatch('[0-9a-f]{64}', str(entry.get('sha256', ''))) or sha256(path) != entry['sha256']:
                    raise ValueError('SHA256 mismatch: ' + entry.get('path', ''))
                if key == 'files':
                    if path.suffix[1:].upper() not in formats or path.stat().st_size == 0:
                        raise ValueError('file extension not declared or empty file')
                    if not https(entry.get('download_url')):
                        raise ValueError('file download_url required')
                else:
                    if entry.get('kind') not in ('source', 'license', 'review') or not https(entry.get('url')):
                        raise ValueError('invalid evidence kind/url')
                    date.fromisoformat(entry.get('captured_date', ''))
            except (OSError, TypeError, ValueError) as exc:
                errors.append(key + ': ' + str(exc))
    evidence = meta.get('evidence', [])
    evidence = evidence if isinstance(evidence, list) else []
    for kind, url in (('source', meta.get('source_url')), ('license', meta.get('license_url'))):
        if not any(isinstance(x, dict) and x.get('kind') == kind and x.get('url') == url for x in evidence):
            errors.append('missing matching ' + kind + ' evidence')
    review = meta.get('review', {})
    if not isinstance(review, dict):
        review = {}
        errors.append('review must be object')
    declared = review.get('status')
    if declared not in STATUSES:
        errors.append('invalid review status')
    lic = meta.get('license', '')
    if meta.get('source_platform') in ('Fab', 'Sketchfab'):
        reasons.append('phase 2 source disabled in V1')
    if not isinstance(lic, str):
        lic = 'UNKNOWN'
    if declared == 'BLOCKED' or '-NC' in lic.upper() or '-ND' in lic.upper() or lic.upper() == 'UNKNOWN' or any(meta.get(k) is False for k in ('commercial_use', 'modification', 'redistribution')):
        return 'BLOCKED', errors, ['restricted, unknown, denied permission, or explicitly blocked']
    if lic not in LICENSES:
        reasons.append('license needs individual assessment (GPL / SA / custom included)')
    elif meta.get('license_url') != LICENSES[lic]:
        errors.append('license URL does not match identifier')
    for k in ('commercial_use', 'modification', 'redistribution'):
        if meta.get(k) is not True:
            reasons.append('unconfirmed permission: ' + k)
    if not isinstance(review.get('reviewer'), str) or not review.get('reviewer', '').strip():
        reasons.append('reviewer missing')
    try:
        if date.fromisoformat(review.get('reviewed_date', '')) > date.today():
            raise ValueError()
    except (TypeError, ValueError):
        reasons.append('valid review date required')
    for k in ('source_verified', 'trademark_checked', 'likeness_checked', 'third_party_checked'):
        if review.get(k) is not True:
            reasons.append('review incomplete: ' + k)
    if not isinstance(review.get('notes'), str) or not review.get('notes', '').strip():
        reasons.append('risk review notes required')
    attribution = meta.get('attribution')
    if lic.startswith('CC-BY-'):
        if meta.get('attribution_required') is not True:
            reasons.append('CC BY requires attribution')
        if not isinstance(attribution, dict) or any(not isinstance(attribution.get(k), str) or not attribution.get(k, '').strip() for k in ('text', 'changes', 'notice', 'placement')):
            reasons.append('attribution text, changes, notice and placement required')
        elif any(str(meta.get(k, '')) not in attribution['text'] for k in ('name', 'author', 'source_url', 'license_url')):
            reasons.append('attribution must include title, author, source and license URL')
    elif meta.get('attribution_required') is not False:
        reasons.append('attribution obligation not confirmed')
    if declared != 'APPROVED':
        reasons.append('explicit approval required')
    return ('REVIEW_REQUIRED' if errors or reasons else 'APPROVED'), errors, reasons

def scan(root):
    rows, seen = [], set()
    for path in sorted((root / 'assets').glob('*/*/metadata.json')):
        try:
            meta = json.loads(path.read_text(encoding='utf-8'))
            status, errors, reasons = audit(meta, path.parent)
        except (OSError, ValueError) as exc:
            meta, status, errors, reasons = {}, 'REVIEW_REQUIRED', [str(exc)], []
        if not isinstance(meta, dict):
            meta = {}
        identity = meta.get('id') if isinstance(meta.get('id'), str) else None
        if identity in seen:
            status = 'REVIEW_REQUIRED'
            errors.append('duplicate asset id')
        seen.add(identity)
        rows.append({'metadata': path.relative_to(root).as_posix(), 'asset': meta,
                     'effective_status': status, 'errors': errors, 'reasons': reasons})
    # Duplicate ids invalidate every occurrence, including the first.
    ids = [r['asset'].get('id') for r in rows]
    for row in rows:
        if ids.count(row['asset'].get('id')) > 1:
            row['effective_status'] = 'REVIEW_REQUIRED'
            if 'duplicate asset id' not in row['errors']:
                row['errors'].append('duplicate asset id')
    # Detect unregistered files so copying an asset into the library cannot silently bypass review.
    registered = set()
    for row in rows:
        folder = (root / row['metadata']).parent
        entries = row['asset'].get('files', [])
        for entry in entries if isinstance(entries, list) else []:
            if isinstance(entry, dict) and isinstance(entry.get('path'), str):
                registered.add((folder / entry['path']).resolve())
    for path in sorted((root / 'assets').rglob('*')):
        if path.is_file() and path.suffix[1:].upper() in FORMATS and path.resolve() not in registered:
            rows.append({'metadata': path.relative_to(root).as_posix(), 'asset': {},
                         'effective_status': 'REVIEW_REQUIRED', 'errors': ['unregistered asset file'], 'reasons': []})
    return rows

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')

def build(root, rows):
    out = root / 'index'
    write_json(out / 'catalog.json', rows)
    approved = [r for r in rows if r['effective_status'] == 'APPROVED']
    write_json(out / 'approved.json', approved)
    credits = [r['asset']['attribution']['text'] + '\nChanges: ' + r['asset']['attribution']['changes'] + '\n' + r['asset']['attribution']['notice'] for r in approved if r['asset']['attribution_required']]
    (out / 'ATTRIBUTIONS.txt').write_text('\n\n'.join(credits) + '\n', encoding='utf-8', newline='\n')
    lines = ['# 素材授权台账', '', '自动计算结果不能代替证据审核。仅 APPROVED 可供后续项目接入；本命令不复制、不发布素材。', '', '| ID | 作者 | 许可 | 申报状态 | 有效状态 | 证据/元数据 | 问题 |', '|---|---|---|---|---|---|---|']
    def safe(v):
        return str(v).replace('|', '\\|').replace('\n', ' ')
    for row in rows:
        m = row['asset']
        cells = (m.get('id', '?'), m.get('author', '?'), m.get('license', '?'),
                 m.get('review', {}).get('status', '?') if isinstance(m.get('review'), dict) else '?',
                 row['effective_status'], '../' + row['metadata'], '; '.join(row['errors'] + row['reasons']) or '通过')
        lines.append('| ' + ' | '.join(safe(x) for x in cells) + ' |')
    (out / 'LICENSE_LEDGER.md').write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    sub = p.add_subparsers(dest='command', required=True)
    sub.add_parser('check')
    sub.add_parser('build')
    s = sub.add_parser('search')
    for arg in ('style', 'category', 'license', 'format', 'query'):
        s.add_argument('--' + arg)
    s.add_argument('--status', choices=STATUSES, default='APPROVED')
    args = p.parse_args()
    rows = scan(args.root.resolve())
    if args.command == 'build':
        build(args.root.resolve(), rows)
    elif args.command == 'search':
        def matches(r):
            m = r['asset']
            if r['effective_status'] != args.status:
                return False
            for arg, key in (('style', 'styles'), ('category', 'category'), ('license', 'license'), ('format', 'formats')):
                val = getattr(args, arg)
                target = m.get(key, [])
                target = target if isinstance(target, list) else [target]
                if val and val.casefold() not in [str(x).casefold() for x in target]:
                    return False
            return not args.query or args.query.casefold() in json.dumps(m, ensure_ascii=False).casefold()
        print(json.dumps([r for r in rows if matches(r)], ensure_ascii=False, indent=2))
        return 0
    print(json.dumps({'assets': len(rows), 'approved': sum(r['effective_status'] == 'APPROVED' for r in rows),
                      'errors': [{'metadata': r['metadata'], 'errors': r['errors'], 'reasons': r['reasons']} for r in rows if r['errors'] or (isinstance(r['asset'].get('review'), dict) and r['asset']['review'].get('status') == 'APPROVED' and r['effective_status'] != 'APPROVED')]}, ensure_ascii=False, indent=2))
    return int(any(r['errors'] or (isinstance(r['asset'].get('review'), dict) and r['asset']['review'].get('status') == 'APPROVED' and r['effective_status'] != 'APPROVED') for r in rows))

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.exit(main())
