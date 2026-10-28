"""Index saved real viewport evidence without substituting reference media."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'work/connected-gameplay'
def main():
    for test,marker in [('test_connected_state','CONNECTED_STATE_OK'),('test_integrated_world','INTEGRATED_WORLD_OK'),('test_connected_ui','CONNECTED_UI_OK'),('test_connected_density','CONNECTED_DENSITY_OK'),('test_connected_route','CONNECTED_ROUTE_OK')]:
        text=(OUT/(test+'.log')).read_text(encoding='utf-8',errors='replace')
        assert marker in text and 'FAIL:' not in text and 'SCRIPT ERROR' not in text,test
    assert 'ALL_CHECKS_OK' in (ROOT/'work/connected-legacy-regression.log').read_text(encoding='utf-8')
    evidence=[]
    for path in sorted(OUT.glob('*.png'))+sorted((ROOT/'work').glob('clinic-connected-route-*.png')):
        with Image.open(path) as picture: resolution=list(picture.size)
        route=path.name.startswith('clinic-connected-route')
        evidence.append({'file':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'resolution':resolution,'source': 'Actual Godot rendered input-driven return expedition, enemies disabled, fixed 60 step simulation' if route else 'Actual Godot viewport; UI placement/no-enemy fixtures or fixed-position real-AI density fixture in test_connected_ui.gd/test_connected_density.gd; not natural encounter footage'})
    (OUT/'evidence-manifest.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
    # Regression scripts also refresh tracked old-street evidence. Keep its hashes in sync.
    path=ROOT/'work/visual-slice/evidence-manifest.json'
    old=json.loads(path.read_text(encoding='utf-8'))
    for entry in old:
        image=ROOT/entry['file']
        entry['sha256']=hashlib.sha256(image.read_bytes()).hexdigest()
    path.write_text(json.dumps(old,indent=2)+'\n',encoding='utf-8')
    path=ROOT/'work/extension-evidence.json'
    previous=json.loads(path.read_text(encoding='utf-8'))
    for entry in previous: entry['sha256']=hashlib.sha256((ROOT/entry['file']).read_bytes()).hexdigest()
    path.write_text(json.dumps(previous,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('CONNECTED_EVIDENCE_OK',len(evidence))
if __name__=='__main__':main()
