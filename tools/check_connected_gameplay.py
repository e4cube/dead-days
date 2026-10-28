"""Run connected-world checks with bounded time, persistent logs and save fingerprints."""
from pathlib import Path
import argparse
import subprocess
import sys
from run_checks import fingerprint

ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--visual',action='store_true')
    parser.add_argument('--only',default='')
    args=parser.parse_args()
    out=ROOT/'work/connected-gameplay'
    out.mkdir(parents=True,exist_ok=True)
    before=fingerprint()
    tests=['test_connected_state','test_integrated_world','test_connected_ui','test_connected_density']
    if args.only: tests=[args.only]
    try:
        for test in tests:
            path=out/(test+'.log')
            command=['D:/GameDev/Godot_v4.7.2-stable_win64.exe']
            if not args.visual: command+=['--headless','--fixed-fps','60']
            elif test=='test_connected_route': command+=['--fixed-fps','60']
            command+=['--path',str(ROOT/'godot'),'--resolution','1920x1080','--script','res://tests/'+test+'.gd']
            with path.open('wb') as log:
                result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=log,timeout=300 if test=='test_connected_route' else 150)
            text=path.read_text(encoding='utf-8',errors='replace')
            print(test,result.returncode,flush=True)
            if result.returncode or 'SCRIPT ERROR' in text or '\nERROR:' in text or 'FAIL:' in text or '_OK' not in text:
                print(text[-6000:])
                raise RuntimeError(str(path))
    finally:
        assert fingerprint()==before,'Protected player saves changed'
    print('CONNECTED_GAMEPLAY_OK / protected player saves unchanged')
if __name__=='__main__': main()
