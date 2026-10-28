"""Render original tracked baseline assets/code with the same capture harness/camera."""
from pathlib import Path
import io
import subprocess
import zipfile
from run_visual_slice import ROOT,run

target=ROOT/'work/visual-slice/baseline-project'
target.mkdir(parents=True,exist_ok=True)
archive=subprocess.check_output(['git','archive','--format=zip','076dc3241afb315ed3e9521acdfe4935908926f7','godot'],cwd=ROOT)
with zipfile.ZipFile(io.BytesIO(archive)) as z: z.extractall(target)
# Align only camera/cutaway/input profile for meaningful old/new asset comparison.
baseline_game=target/'godot/scripts/game.gd'
original=baseline_game.read_text(encoding='utf-8')
current=(ROOT/'godot/scripts/game.gd').read_text(encoding='utf-8')
for function,next_function in [('update_camera','nearby'),('update_cutaways','safe_position')]:
    begin='func '+function+'(';end='func '+next_function+'('
    a=original.index(begin);b=original.index(end,a)
    c=current.index(begin);d=current.index(end,c)
    original=original[:a]+current[c:d]+original[b:]
original=original.replace('var camera_inside := false','var camera_inside := false\nvar isometric_camera := true')
before,physics=original.split('func _physics_process(delta: float) -> void:',1)
physics=physics.replace('var indoors := inside("home") or inside("clinic") or inside("shop")','var indoors := not isometric_camera and (inside("home") or inside("clinic") or inside("shop"))',1)
baseline_game.write_text(before+'func _physics_process(delta: float) -> void:'+physics,encoding='utf-8')
(target/'godot/tests/movement_driver.gd').write_bytes((ROOT/'godot/tests/movement_driver.gd').read_bytes())
for name in ['visual_slice_v1.tscn']:
    (target/'godot'/name).write_bytes((ROOT/'godot'/name).read_bytes())
(target/'godot/scripts/visual_slice_game.gd').write_text('extends "res://scripts/game.gd"\nvar visual_slice_v1:=true\nfunc _init() -> void:\n    camera_zoom=15\n',encoding='utf-8')
capture=(ROOT/'godot/tests/visual_slice_v1.gd').read_text(encoding='utf-8')
capture=capture.replace('res://../work/visual-slice/',str(ROOT/'work/visual-slice/before').replace('\\','/')+'/')
(target/'godot/tests/visual_slice_v1.gd').write_text(capture,encoding='utf-8')
godot='D:/GameDev/Godot_v4.7.2-stable_win64.exe'
run([godot,'--headless','--path',str(target/'godot'),'--editor','--import'],ROOT/'work/visual-slice/before/import.log')
run([godot,'--path',str(target/'godot'),'--resolution','1920x1080','--script','res://tests/visual_slice_v1.gd'],ROOT/'work/visual-slice/before/capture.log',240)
