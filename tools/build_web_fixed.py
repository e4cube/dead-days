import subprocess
from pathlib import Path
engine='D:/GameDev/Godot_v4.7.2-stable_win64.exe'
# The Godot exporter refuses to write into a folder that does not exist yet.
Path('web').mkdir(exist_ok=True)
for args in [['--headless','--path','godot','--editor','--import','--quit'],['--headless','--path','godot','--script','res://tests/test_rules.gd'],['--headless','--path','godot','--script','res://compress_web_assets.gd'],['--headless','--path','godot','--export-release','Web Validation','../web/index.html']]:
 p=subprocess.run([engine]+args,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
 print(p.stdout+p.stderr,flush=True)
 if p.returncode or 'SCRIPT ERROR' in p.stdout+p.stderr:raise RuntimeError(str(args))
# compress_web_assets.gd re-saves every .scn in place with FLAG_COMPRESS, which
# drops the embedded PortableCompressedTexture2D pixels: the desktop build then
# draws those surfaces as the magenta checkerboard. The export above already
# consumed the compressed files, so rebuild the cache from the .glb sources now
# and leave the desktop build with intact maps.
imported=Path('godot/.godot/imported')
stale=list(imported.glob('*.scn'))
for p in stale:
 p.unlink()
 stamp=p.with_suffix('')
 if stamp.exists():stamp.unlink()
p=subprocess.run([engine,'--headless','--path','godot','--import','--quit'],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
print(p.stdout+p.stderr,flush=True)
if p.returncode:raise RuntimeError('rebuild after web compression failed')
print(f'WEB_CACHE_REBUILT / {len(stale)} compressed scenes discarded, desktop maps restored')
print('FIXED_WEB_BUILD_OK')
