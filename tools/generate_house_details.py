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
for x, width in [(-2.35,.7),(1.72,2.06)]:
    box('DD_Hide_Partition', (x,2.05,1.15),(width,.12,2.3),'cream')
    box('DD_Cut_Partition', (x,2.05,.28),(width,.12,.56),'cream')
box('DD_Hide_BedroomWall',(-.65,3.95,1.15),(.12,2.1,2.3),'cream')
box('DD_Cut_BedroomWall',(-.65,3.95,.28),(.12,2.1,.56),'cream')
for i in range(15):
    box('DD_Keep_Floorboard',(-2.55+i*.365,2.5,.048),(.35,4.9,.024),'wood_light')
# Living room, couch against west wall, rug and coffee table.
box('DD_Keep_Rug',(-1.5,.95,.075),(1.8,1.25,.025),'cloth',.02)
box('DD_Keep_SofaSeat',(-2.12,1,.42),(.75,1.55,.28),'cloth',.07)
box('DD_Keep_SofaBack',(-2.48,1,.68),(.18,1.7,.78),'cloth',.04)
for y in [.2,1.8]:
    box('DD_Keep_SofaArm',(-2.1,y,.56),(.85,.16,.54),'cloth',.03)
box('DD_Keep_CoffeeTable',(-1.15,1,.4),(.55,1,.09),'wood_light',.025)
for y in [.62,1.38]:
    box('DD_Keep_CoffeeLeg',(-1.15,y,.23),(.1,.1,.35),'wood')
# Kitchen counter, sink, hob, shelves and supplies.
box('DD_Keep_Kitchen',(2.25,3.25,.46),(.8,1.7,.92),'white',.025)
box('DD_Keep_Worktop',(2.25,3.25,.95),(.88,1.8,.08),'steel',.015)
box('DD_Keep_Sink',(2.25,3.65,1),(.55,.48,.025),'glass',.02)
for y in [2.8,3.08]:
    cylinder('DD_Keep_Hob',(2.25,y,1.01),.13,.025,'boots',12)
box('DD_Keep_Fridge',(2.12,4.5,.9),(.95,.75,1.8),'white',.035)
box('DD_Keep_FridgeHandle',(1.75,4.10,1),(.05,.06,.55),'steel')
box('DD_Keep_Bookcase',(-2.45,4.5,1),(.4,.65,1.8),'wood',.02)
for z in [.4,.9,1.4]:
    for y in [4.3,4.45,4.6]:
        box('DD_Keep_Book',(-2.2,y,z),(.16,.09,.28),'cloth' if y<4.5 else 'cream')
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
