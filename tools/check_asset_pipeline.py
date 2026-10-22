"""Rebuild assets into ignored work/ and compare GLB/manifest bytes without touching production sources."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--blender',required=True)
    args=parser.parse_args()
    (ROOT/"work").mkdir(exist_ok=True)
    result=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_assets.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    (ROOT/'work/asset-replay.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode or 'ASSET_PIPELINE_OK' not in result.stdout or 'Traceback' in result.stdout+result.stderr:
        raise RuntimeError('Blender generation failed: see work/asset-replay.log')
    details=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_house_details.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    assert details.returncode==0 and 'HOUSE_DETAIL_PIPELINE_OK' in details.stdout, details.stdout+details.stderr
    street=subprocess.run([args.blender,'--background','--factory-startup','--python',str(ROOT/'tools/generate_street_art.py'),'--','--output-root','work/asset-replay'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    assert street.returncode==0 and 'STREET_ART_PIPELINE_OK' in street.stdout, street.stdout+street.stderr
    assets=ROOT/'godot/assets'
    replay=ROOT/'work/asset-replay/godot/assets'
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
