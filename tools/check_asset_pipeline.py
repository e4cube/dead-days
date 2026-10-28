"""Rebuild assets into ignored work/ and compare GLB/manifest bytes without touching production sources."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--blender',required=True)
    args=parser.parse_args()
    (ROOT/"work").mkdir(exist_ok=True)
    maps=subprocess.run([sys.executable,'tools/generate_surface_maps.py','--output-root','work/map-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
    assert maps.returncode==0 and 'SURFACE_MAPS_OK' in maps.stdout,maps.stdout+maps.stderr
    records=json.loads((ROOT/'godot/assets/materials_v1/manifest.json').read_text(encoding='utf-8'))['maps']
    assert len({r['file'] for r in records})==len(records),'Duplicate map filenames'
    for record in records:
        path=ROOT/'godot/assets/materials_v1'/record['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],'Stale map manifest '+record['file']
    for path in (ROOT/'godot/assets/materials_v1').iterdir():
        if path.suffix not in ['.png','.json']:continue
        replay_map=ROOT/'work/map-replay/godot/assets/materials_v1'/path.name
        assert path.read_bytes()==replay_map.read_bytes(),'Non-reproducible surface map '+path.name
    result=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_assets.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    (ROOT/'work/asset-replay.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode or 'ASSET_PIPELINE_OK' not in result.stdout or 'Traceback' in result.stdout+result.stderr:
        raise RuntimeError('Blender generation failed: see work/asset-replay.log')
    details=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_house_details.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    assert details.returncode==0 and 'HOUSE_DETAIL_PIPELINE_OK' in details.stdout, details.stdout+details.stderr
    street=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_street_art.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    assert street.returncode==0 and 'STREET_ART_PIPELINE_OK' in street.stdout, street.stdout+street.stderr
    assets=ROOT/'godot/assets'
    clinic=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_clinic_details.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    assert clinic.returncode==0 and 'CLINIC_PIPELINE_OK' in clinic.stdout,clinic.stdout+clinic.stderr
    replay=ROOT/'work/asset-replay/godot/assets'
    shop=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_shop_details.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    assert shop.returncode==0 and 'SHOP_PIPELINE_OK' in shop.stdout,shop.stdout+shop.stderr
    for path in sorted(assets.glob('*.glb')):
        generated=replay/path.name
        assert generated.exists(), path.name
        assert hashlib.sha256(path.read_bytes()).digest()==hashlib.sha256(generated.read_bytes()).digest(), f'Non-reproducible GLB: {path.name}'
        assert (ROOT/'art/source'/f'{path.stem}.blend').stat().st_size>100, f'Missing Blender source: {path.name}'
    assert (assets/'manifest.json').read_bytes()==(replay/'manifest.json').read_bytes(), 'Manifest drift'
    assert (assets/'street_manifest.json').read_bytes()==(replay/'street_manifest.json').read_bytes(), 'Street manifest drift'
    print(f'ASSET_REPLAY_OK / {len(list(assets.glob("*.glb")))} GLBs and manifests byte-identical; source projects present')

if __name__=='__main__':
    main()
