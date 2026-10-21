"""Editable modular detail kit, sharing the existing Blender export contract.
Blender --background --factory-startup --python tools/generate_house_details.py
"""
import runpy
import sys
from pathlib import Path

# Load existing helpers without regenerating production assets.
kit = runpy.run_path(str(Path(__file__).with_name('generate_assets.py')))
kit['reset']()
box = kit['box']
import bpy
import math

def cylinder(name, at, radius, depth, material, vertices=8):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(kit['MATS'][material])
    return obj

def save(name):
    root = kit['BASE']
    (root/'art/source').mkdir(parents=True,exist_ok=True)
    (root/'godot/assets').mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(root/'art/source'/f'{name}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(root/'godot/assets'/f'{name}.glb'), export_format='GLB', export_yup=True, export_texcoords=False)

# Local Godot coordinates: origin at house center front; Blender depth is +Y.
# Open archways retain real sight/collision openings. Prefixes follow roof contract.
import json
layout = json.loads((kit['ROOT']/'godot/data/house_layout.json').read_text(encoding='utf-8'))
if layout['version'] != 1:
    raise RuntimeError('Unsupported house layout version')
for module in layout['modules']:
    x, y, z = module['position']
    at = (x, -z, y)  # Godot Y-up -> Blender Z-up.
    if module['kind'] == 'box':
        w, h, d = module['size']
        box(module['name'], at, (w,d,h), module['material'], module.get('bevel',0))
    elif module['kind'] == 'cylinder':
        cylinder(module['name'],at,module['radius'],module['depth'],module['material'],module['vertices'])
    else:
        raise RuntimeError('Unknown primitive '+module['kind'])
save('house_details')

kit['reset']()
cylinder('DD_Trunk',(0,0,1.15),.14,2.3,'wood',7)
for x,y,z,r in [(0,0,2.8,1.05),(.55,.15,2.4,.8),(-.5,-.2,2.3,.85),(0,.5,2.7,.75)]:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=r,location=(x,y,z))
    obj=bpy.context.object
    obj.name='DD_Crown'
    obj.data.materials.append(kit['MATS']['jacket' if x>=0 else 'cloth'])
save('tree_oak')
print('HOUSE_DETAIL_PIPELINE_OK')
