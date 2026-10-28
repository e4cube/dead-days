"""Editable clinic kit; shared layout is authoritative for visible furniture and collision."""
import json
import runpy
from pathlib import Path
import bpy

if not bpy.app.background:
    raise RuntimeError('Background mode required')
kit=runpy.run_path(str(Path(__file__).with_name('generate_assets.py')))
kit['reset']()
layout=json.loads((kit['ROOT']/'godot/data/clinic_layout.json').read_text(encoding='utf-8'))
assert layout['version']==1
for module in layout['modules']:
    x,y,z=module['position'];w,h,d=module['size']
    kit['box'](module['name'],(x,-z,y),(w,d,h),module['material'])
base=kit['BASE']
(base/'art/source').mkdir(parents=True,exist_ok=True)
(base/'godot/assets').mkdir(parents=True,exist_ok=True)
kit['SURFACES']['project_uvs']()
bpy.ops.wm.save_as_mainfile(filepath=str(base/'art/source/clinic_details.blend'))
bpy.ops.export_scene.gltf(filepath=str(base/'godot/assets/clinic_details.glb'),export_format='GLB',export_yup=True,export_texcoords=True)
kit['SURFACES']['canonical_uvs'](base/'godot/assets/clinic_details.glb')
print('CLINIC_PIPELINE_OK',flush=True)
