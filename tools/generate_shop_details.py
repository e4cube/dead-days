"""Editable shop kit; shared layout is authoritative for visible furniture and collision."""
import json
import runpy
from pathlib import Path
import bpy

if not bpy.app.background:
    raise RuntimeError('Background mode required')
kit=runpy.run_path(str(Path(__file__).with_name('generate_assets.py')))
kit['reset']()
layout=json.loads((kit['ROOT']/'godot/data/shop_layout.json').read_text(encoding='utf-8'))
assert layout['version']==1
for module in layout['modules']:
    x,y,z=module['position']
    if module.get('kind','box')=='cylinder':
        bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=module['radius'],depth=module['depth'],location=(x,-z,y))
        obj=bpy.context.object;obj.name=module['name'];obj.data.materials.append(kit['MATS'][module['material']])
        for face in obj.data.polygons:
            if len(face.vertices)==4:face.use_smooth=True
    else:
        w,h,d=module['size']
        kit['box'](module['name'],(x,-z,y),(w,d,h),module['material'])
base=kit['BASE']
(base/'art/source').mkdir(parents=True,exist_ok=True)
(base/'godot/assets').mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(base/'art/source/shop_details.blend'))
bpy.ops.export_scene.gltf(filepath=str(base/'godot/assets/shop_details.glb'),export_format='GLB',export_yup=True,export_texcoords=False)
print('SHOP_PIPELINE_OK',flush=True)
