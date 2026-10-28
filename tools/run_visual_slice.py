"""Run reproducible visual-slice tasks without shell quoting or production save writes."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from run_checks import fingerprint
ROOT=Path(__file__).resolve().parents[1]
def run(command, log, timeout=180):
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
    output=result.stdout+result.stderr
    log.parent.mkdir(parents=True,exist_ok=True)
    log.write_text(output,encoding='utf-8')
    print(log.name,result.returncode,flush=True)
    if result.returncode or 'Traceback' in output or 'SCRIPT ERROR' in output or '\nERROR:' in output:
        raise RuntimeError(str(log))
    return output
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('task',choices=['generate','import','capture']);args=p.parse_args()
    out=ROOT/'work/visual-slice'
    if args.task=='generate':
        for script in ['generate_assets','generate_house_details','generate_clinic_details','generate_shop_details','generate_street_art']:
            run(['D:/Blender/blender.exe','--background','--factory-startup','--python',str(ROOT/'tools'/f'{script}.py')],out/f'{script}.log')
    elif args.task=='import':
        run(['D:/GameDev/Godot_v4.7.2-stable_win64.exe','--headless','--path',str(ROOT/'godot'),'--editor','--import'],out/'import.log')
    else:
        before=fingerprint()
        try:
            run(['D:/GameDev/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT/'godot'),'--resolution','1920x1080','--script','res://tests/visual_slice_v1.gd'],out/'capture.log',240)
        finally:
            unchanged=before==fingerprint()
            (out/'save-safety.json').write_text(json.dumps({'protected_file_count':len(before),'unchanged':unchanged,'test_saves':'Isolated user://tests/visual_slice_* snapshots only'},indent=2),encoding='utf-8')
            assert unchanged,'Protected player files changed'
