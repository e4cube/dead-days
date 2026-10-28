"""Keep embedded GLB maps in compressed imported scenes, not hundreds of extracted files.
Only relocates newly generated, Git-untracked PNGs bearing a known GLB prefix.
"""
from pathlib import Path
import shutil,subprocess
import argparse,time
parser=argparse.ArgumentParser();parser.add_argument('--fresh-cache',action='store_true');args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1]
assets=ROOT/'godot/assets'
stems=[p.stem+'_' for p in assets.glob('*.glb')]
tracked=set(subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True).splitlines())
backup=(ROOT/'work/visual-slice/extracted-import-backup').resolve()
assert backup.is_relative_to((ROOT/'work').resolve())
backup.mkdir(parents=True,exist_ok=True)
for p in assets.glob('*.glb.import'):
    text=p.read_text(encoding='utf-8')
    p.write_text(text.replace('gltf/embedded_image_handling=1','gltf/embedded_image_handling=2'),encoding='utf-8')
for p in assets.iterdir():
    if not p.is_file() or not any(p.name.startswith(s) for s in stems):continue
    if not (p.name.endswith('.png') or p.name.endswith('.png.import')):continue
    assert p.resolve().is_relative_to(assets.resolve())
    if p.relative_to(ROOT).as_posix() in tracked:continue
    target=backup/p.name
    if target.exists():continue
    shutil.move(str(p),str(target))
if args.fresh_cache:
    cache=(ROOT/'godot/.godot').resolve()
    destination=(ROOT/'work/visual-slice'/('import-cache-backup-'+str(time.time_ns()))).resolve()
    assert cache==ROOT/'godot/.godot' and destination.is_relative_to((ROOT/'work').resolve())
    if cache.exists():shutil.move(str(cache),str(destination))
print('VISUAL_IMPORT_CONFIG_OK')
