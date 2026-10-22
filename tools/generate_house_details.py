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
# Branching silhouette and a restrained olive palette instead of blue-green balls.
for name,color in [('leaf_shadow',(.25,.31,.18,1)),('leaf_mid',(.36,.41,.24,1)),('leaf_sun',(.45,.48,.29,1))]:
    mat=bpy.data.materials.new('DD_'+name)
    linear=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in color[:3])+(1,)
    mat.diffuse_color=linear
    mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=linear
    mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.95
    kit['MATS'][name]=mat
from mathutils import Vector
for x,y,z in [(.65,.1,2.45),(-.6,-.25,2.3),(0,.55,2.6)]:
    start=Vector((0,0,1.5)); end=Vector((x,y,z))
    branch=cylinder('DD_Branch',(start+end)/2,.07,(end-start).length,'wood',6)
    branch.rotation_euler=(end-start).to_track_quat('Z','Y').to_euler()
for i,(x,y,z,r) in enumerate([(0,0,2.85,.90),(.68,.15,2.45,.65),(-.65,-.2,2.3,.72),(0,.62,2.6,.65),(.28,-.56,2.5,.62),(-.3,.15,3.18,.55)]):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=r,location=(x,y,z))
    obj=bpy.context.object
    obj.name='DD_Crown'
    obj.scale=(1,.85,1.05 if i%2 else .90)
    obj.rotation_euler.z=i*.7
    obj.data.materials.append(kit['MATS'][['leaf_mid','leaf_shadow','leaf_sun'][i%3]])
save('tree_oak')
print('HOUSE_DETAIL_PIPELINE_OK')
