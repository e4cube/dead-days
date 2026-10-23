"""Re-audit source metadata and ensure engine copies match reviewed bytes. No downloads."""
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gamevado_library', ROOT / 'art-library/scripts/library.py')
library = importlib.util.module_from_spec(spec)
spec.loader.exec_module(library)

def main():
    rows = library.scan(ROOT / 'art-library')
    mappings = json.loads((ROOT / 'art-library/projects/dead-days-runtime.json').read_text(encoding='utf-8'))
    by_id = {r['asset'].get('id'): r for r in rows}
    for mapping in mappings['assets']:
        row = by_id[mapping['id']]
        if row['effective_status'] != 'APPROVED':
            raise ValueError('Asset no longer approved: ' + mapping['id'])
        source = next(f for f in row['asset']['files'] if f['path'] == mapping['source_file'])
        runtime = library.local_file(ROOT / 'godot', mapping['runtime_file'])
        if library.sha256(runtime) != source['sha256']:
            raise ValueError('Runtime asset differs from reviewed source: ' + str(runtime))
    library.build(ROOT / 'art-library', rows)
    print('GAMEVADO_ASSETS_OK')

if __name__ == '__main__':
    main()
