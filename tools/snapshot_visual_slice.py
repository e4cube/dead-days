"""Cross-reference source projects, exported GLBs and original surface maps."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    entries=[]
    for glb in sorted((ROOT/'godot/assets').glob('*.glb')):
        source=ROOT/'art/source'/f'{glb.stem}.blend'
        assert source.exists(),glb.name
        entries.append({'id':glb.stem,'source':source.relative_to(ROOT).as_posix(),'source_sha256':sha(source),'glb':glb.relative_to(ROOT).as_posix(),'glb_sha256':sha(glb),'bytes':glb.stat().st_size,'provenance':'Original project generator; no third-party model'})
    material=ROOT/'godot/data/material_library_v1.json'
    maps=ROOT/'godot/assets/materials_v1/manifest.json'
    report={'version':1,'baseline':'076dc3241afb315ed3e9521acdfe4935908926f7','assets':entries,'materials':{'file':material.relative_to(ROOT).as_posix(),'sha256':sha(material),'maps_manifest':maps.relative_to(ROOT).as_posix(),'maps_manifest_sha256':sha(maps)},'external_runtime_assets':'Unchanged approved CC0 Poly Haven ground diffuse; art-library/index/LICENSE_LEDGER.md','references':'art/references/manifest.json — design-only; excluded from game resources','acceptance':'See docs/visual-slice-v1-report.md; inventory is not an aesthetic quality pass'}
    (ROOT/'art/source/visual-slice-v1-manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('VISUAL_SLICE_INVENTORY_OK',len(entries))
if __name__=='__main__':main()
