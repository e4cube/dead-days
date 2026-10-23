import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('library', ROOT / 'scripts/library.py')
lib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lib)

class AuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.folder = self.root / 'assets/Textures/sample'
        self.folder.mkdir(parents=True)
        self.meta = copy.deepcopy(json.loads((ROOT / 'templates/metadata.json').read_text(encoding='utf-8')))
        self.meta.update(id='sample', name='Sample', author='Fixture Author', source_platform='Fixture',
                         source_url='https://example.com/sample', license='CC0-1.0',
                         license_url=lib.LICENSES['CC0-1.0'], download_date='2026-01-01',
                         commercial_use=True, modification=True, redistribution=True,
                         attribution_required=False, styles=['pixel'], tags=['test'], formats=['SVG'])
        (self.folder / 'sample.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        self.meta['files'] = [{'path':'sample.svg', 'sha256':lib.sha256(self.folder / 'sample.svg'),
                              'download_url':'https://example.com/sample.svg'}]
        self.meta['evidence'] = []
        for kind, url in [('source', self.meta['source_url']), ('license', self.meta['license_url'])]:
            path = self.folder / (kind + '.txt')
            path.write_text('Test fixture evidence, not a real license approval.')
            self.meta['evidence'].append({'path':path.name,'sha256':lib.sha256(path), 'url':url,
                                          'kind':kind,'captured_date':'2026-01-01'})
        self.meta['review'] = dict(status='APPROVED', reviewer='Test fixture', reviewed_date='2026-01-01',
            source_verified=True, trademark_checked=True, likeness_checked=True, third_party_checked=True, notes='Fixture only')

    def status(self):
        return lib.audit(self.meta, self.folder)[0]

    def save(self):
        lib.write_json(self.folder / 'metadata.json', self.meta)

    def test_valid_cc0(self):
        self.assertEqual(self.status(), 'APPROVED')

    def test_phase_two_is_not_automatically_enabled(self):
        self.meta['source_platform'] = 'Fab'
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_schema_version_is_required(self):
        self.meta['schema_version'] = 2
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_approval_is_not_inferred(self):
        self.meta['review']['status'] = 'REVIEW_REQUIRED'
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_all_risk_checks_required(self):
        for field in ('source_verified','trademark_checked','likeness_checked','third_party_checked'):
            with self.subTest(field=field):
                self.meta['review'][field] = False
                self.assertEqual(self.status(), 'REVIEW_REQUIRED')
                self.meta['review'][field] = True

    def test_restricted_licenses(self):
        for lic in ('CC-BY-NC-4.0','CC-BY-ND-4.0','UNKNOWN'):
            with self.subTest(license=lic):
                self.meta['license'] = lic
                self.assertEqual(self.status(), 'BLOCKED')

    def test_copyleft_and_custom_need_assessment(self):
        for lic in ('GPL-3.0-only','CC-BY-SA-4.0','Custom','CC-BY-2.0'):
            self.meta['license'] = lic
            self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_unknown_permission(self):
        self.meta['commercial_use'] = None
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_denied_permission(self):
        self.meta['redistribution'] = False
        self.assertEqual(self.status(), 'BLOCKED')

    def test_string_boolean_is_invalid(self):
        self.meta['commercial_use'] = 'true'
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_tampered_asset(self):
        (self.folder / 'sample.svg').write_text('modified')
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_tampered_evidence(self):
        (self.folder / 'license.txt').write_text('tampered')
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_missing_evidence(self):
        self.meta['evidence'] = []
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_wrong_license_url(self):
        self.meta['license_url'] = 'https://example.com/fake'
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_path_traversal(self):
        for path in ('../outside.svg','C:/outside.svg','..\\outside.svg'):
            self.meta['files'][0]['path'] = path
            self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_missing_asset(self):
        (self.folder / 'sample.svg').unlink()
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_future_dates(self):
        self.meta['download_date'] = '2999-01-01'
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')

    def test_cc_by_requires_full_attribution(self):
        self.meta.update(license='CC-BY-4.0', license_url=lib.LICENSES['CC-BY-4.0'], attribution_required=True)
        self.meta['evidence'][1]['url'] = self.meta['license_url']
        self.assertEqual(self.status(), 'REVIEW_REQUIRED')
        self.meta['attribution'] = {'text':'Sample by Fixture Author https://example.com/sample ' + self.meta['license_url'],
            'changes':'Unmodified','notice':'Copyright Fixture Author','placement':'Credits screen'}
        self.assertEqual(self.status(), 'APPROVED')

    def test_explicit_block_survives(self):
        self.meta['review']['status'] = 'BLOCKED'
        self.assertEqual(self.status(), 'BLOCKED')

    def test_malformed_json_and_orphan(self):
        (self.folder / 'metadata.json').write_text('{')
        rows = lib.scan(self.root)
        self.assertTrue(all(r['effective_status'] != 'APPROVED' for r in rows))
        self.assertTrue(any('unregistered asset file' in r['errors'] for r in rows))

    def test_malformed_metadata_types(self):
        for key, value in [('review',[]), ('files',None), ('styles',3), ('id',[]), ('license',{})]:
            with self.subTest(key=key):
                broken = copy.deepcopy(self.meta)
                broken[key] = value
                lib.write_json(self.folder / 'metadata.json', broken)
                rows = lib.scan(self.root)
                self.assertTrue(all(r['effective_status'] != 'APPROVED' for r in rows))

    def test_duplicate_ids_invalidate_both(self):
        self.save()
        other = self.root / 'assets/UI/sample'
        other.mkdir(parents=True)
        lib.write_json(other / 'metadata.json', self.meta)
        rows = lib.scan(self.root)
        self.assertTrue(all(r['effective_status'] != 'APPROVED' for r in rows))

    def test_build_removes_stale_approved(self):
        self.save()
        lib.build(self.root, lib.scan(self.root))
        self.assertEqual(len(json.loads((self.root / 'index/approved.json').read_text())), 1)
        (self.folder / 'source.txt').unlink()
        lib.build(self.root, lib.scan(self.root))
        self.assertEqual(json.loads((self.root / 'index/approved.json').read_text()), [])

    def test_search_and_exit_code(self):
        self.save()
        cmd = [sys.executable, str(ROOT / 'scripts/library.py'), '--root', str(self.root)]
        result = subprocess.run(cmd + ['search','--style','pixel','--category','Textures','--license','CC0-1.0','--format','SVG'],capture_output=True,text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(json.loads(result.stdout)), 1)
        (self.folder / 'sample.svg').write_text('changed')
        result = subprocess.run(cmd + ['check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)

    def test_cli_json_is_utf8_on_windows(self):
        self.meta['name'] = '\u4e2d\u6587\u7d20\u6750'
        self.save()
        raw = subprocess.check_output([sys.executable, str(ROOT / 'scripts/library.py'), '--root', str(self.root), 'search'])
        self.assertEqual(json.loads(raw.decode('utf-8'))[0]['asset']['name'], self.meta['name'])

if __name__ == '__main__':
    unittest.main()
