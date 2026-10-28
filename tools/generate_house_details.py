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
    kit['SURFACES']['project_uvs']()
    bpy.ops.wm.save_as_mainfile(filepath=str(root/'art/source'/f'{name}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(root/'godot/assets'/f'{name}.glb'), export_format='GLB', export_yup=True, export_texcoords=True)
    kit['SURFACES']['canonical_uvs'](root/'godot/assets'/f'{name}.glb')

# Local Godot coordinates: origin at house center front; Blender depth is +Y.
# Open archways retain real sight/collision openings. Prefixes follow roof contract.
import json
layout = json.loads((kit['ROOT']/'godot/data/house_layout.json').read_text(encoding='utf-8'))
if layout['version'] != 1:
    raise RuntimeError('Unsupported house layout version')
for name,color in layout.get('materials',{}).items():
    mat=bpy.data.materials.new('DD_'+name)
    linear=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in color[:3])+(1,)
    mat.diffuse_color=linear
    mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=linear
    mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.94
    kit['MATS'][name]=mat
for name,definition in layout.get('surface_profiles',{}).items():
    shared=kit['MATERIAL_LIBRARY']
    definition=dict(definition,**shared['materials'][shared['house_aliases'][name]])
    rgb=tuple(int(definition['color'][i:i+2],16)/255 for i in (0,2,4))
    linear=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb)+(1,)
    material=bpy.data.materials.new('DD_Surface_'+name)
    material.diffuse_color=linear
    shader=material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=linear
    shader.inputs['Roughness'].default_value=definition['roughness']
    shader.inputs['Metallic'].default_value=definition['metallic']
    kit['SURFACES']['apply'](material,dict(definition,id=shared['house_aliases'][name]),kit['ROOT'])
    kit['MATS']['surface_'+name]=material
for module in layout['modules']:
    x, y, z = module['position']
    at = (x, -z, y)  # Godot Y-up -> Blender Z-up.
    material='surface_'+module['surface'] if 'surface' in module else module['material']
    if module['kind'] == 'box':
        w, h, d = module['size']
        box(module['name'], at, (w,d,h), material, module.get('bevel',0),module.get('bevel_segments',1))
    elif module['kind'] == 'basin':
        w,h,d=module['size']
        vertices=[];faces=[]
        for rx,ry,z in [(w/2,d/2,h/2),(w/2-.04,d/2-.04,h/2),(w/2-.08,d/2-.08,-h/2)]:
            vertices += [(-rx,-ry,z),(rx,-ry,z),(rx,ry,z),(-rx,ry,z)]
        for j in range(2):
            for i in range(4):faces.append((j*4+i,j*4+(i+1)%4,(j+1)*4+(i+1)%4,(j+1)*4+i))
        faces.append((8,9,10,11))
        mesh=bpy.data.meshes.new(module['name']);mesh.from_pydata(vertices,[],faces)
        obj=bpy.data.objects.new(module['name'],mesh);bpy.context.collection.objects.link(obj)
        obj.location=at;mesh.materials.append(kit['MATS'][material])
    elif module['kind'] == 'tube':
        from mathutils import Vector
        points=[Vector((p[0],-p[2],p[1])) for p in module['points']]
        vertices=[];faces=[]
        for i,point in enumerate(points):
            tangent=(points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
            normal=Vector((0,1,0));side=tangent.cross(normal).normalized()
            for j in range(8):
                v=point+(normal*math.cos(j*math.tau/8)+side*math.sin(j*math.tau/8))*module['radius']
                vertices.append(tuple(v))
        for i in range(len(points)-1):
            for j in range(8):faces.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
        faces += [tuple(reversed(range(8))),tuple(range((len(points)-1)*8,len(points)*8))]
        mesh=bpy.data.meshes.new(module['name']);mesh.from_pydata(vertices,[],faces)
        obj=bpy.data.objects.new(module['name'],mesh);bpy.context.collection.objects.link(obj)
        obj.location=at;mesh.materials.append(kit['MATS'][material])
    elif module['kind'] == 'cylinder':
        cylinder(module['name'],at,module['radius'],module['depth'],material,module['vertices'])
    else:
        raise RuntimeError('Unknown primitive '+module['kind'])
save('house_details')

kit['reset']()
cylinder('DD_Trunk',(0,0,1.15),.14,2.3,'wood',7)
# Open foliage clusters use the shared foliage recipe (jacket is its legacy alias).
from mathutils import Vector
for x,y,z in [(.65,.1,2.45),(-.6,-.25,2.3),(0,.55,2.6)]:
    start=Vector((0,0,1.5)); end=Vector((x,y,z))
    branch=cylinder('DD_Branch',(start+end)/2,.07,(end-start).length,'wood',6)
    branch.rotation_euler=(end-start).to_track_quat('Z','Y').to_euler()
for i,(x,y,z,r) in enumerate([(0,0,2.85,.90),(.68,.15,2.45,.65),(-.65,-.2,2.3,.72),(0,.62,2.6,.65),(.28,-.56,2.5,.62),(-.3,.15,3.18,.55)]):
    vertices=[];faces=[]
    for j in range(48):
        # Deterministic branch-tip distribution, with gaps between folded leaf sprays.
        angle=j*2.399963+i*.71
        height=1-2*(j+.5)/48
        radial=math.sqrt(1-height*height)*r*(.76+.13*math.sin(j*1.7))
        center=Vector((x+math.cos(angle)*radial,y+math.sin(angle)*radial*.85,z+height*r*.78))
        axis=Vector((math.cos(angle),math.sin(angle),.2*math.sin(j))).normalized()
        across=Vector((-math.sin(angle),math.cos(angle),.25)).normalized()
        length=.17+.06*(.5+.5*math.sin(j*2.1+i))
        width=.085+.025*(.5+.5*math.cos(j*1.3))
        start=len(vertices)
        outline=[(-1,0,0),(-.65,-.7,0),(0,-1,0),(.65,-.7,0),(1,0,0),(.65,.7,0),(0,1,0),(-.65,.7,0),(0,0,.025)]
        for along,side,fold in outline:
            vertices.append(tuple(center+axis*along*length+across*side*width+Vector((0,0,fold))))
        front=[(j,(j+1)%8,8) for j in range(8)]
        # Explicit back faces avoid alpha sorting and remain portable in GLB.
        for face in front:
            faces.append(tuple(start+k for k in face))
            faces.append(tuple(start+k for k in reversed(face)))
    mesh=bpy.data.meshes.new('DD_LeafSprays');mesh.from_pydata(vertices,[],faces)
    obj=bpy.data.objects.new('DD_Crown',mesh);bpy.context.collection.objects.link(obj)
    mesh.materials.append(kit['MATS']['jacket'])
save('tree_oak')
print('HOUSE_DETAIL_PIPELINE_OK')
