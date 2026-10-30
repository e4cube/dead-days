import subprocess
from pathlib import Path
engine='D:/GameDev/Godot_v4.7.2-stable_win64.exe'
# The Godot exporter refuses to write into a folder that does not exist yet.
Path('web').mkdir(exist_ok=True)
for args in [['--headless','--path','godot','--editor','--import','--quit'],['--headless','--path','godot','--script','res://tests/test_rules.gd'],['--headless','--path','godot','--script','res://compress_web_assets.gd'],['--headless','--path','godot','--export-release','Web Validation','../web/index.html']]:
 p=subprocess.run([engine]+args,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
 print(p.stdout+p.stderr,flush=True)
 if p.returncode or 'SCRIPT ERROR' in p.stdout+p.stderr:raise RuntimeError(str(args))
print('FIXED_WEB_BUILD_OK')
