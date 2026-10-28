"""Original low-poly asset pack. Blender --background --factory-startup --python tools/generate_assets.py.
All generated sources stay in art/source; only explicit GLB exports enter the engine.
Optional: -- --only player,zombie --output-root work/asset-preview
"""
from pathlib import Path
import argparse
import json
import math
import sys
import struct
import runpy
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MATERIAL_LIBRARY = json.loads((ROOT/'godot/data/material_library_v1.json').read_text(encoding='utf-8'))
SURFACES=runpy.run_path(str(ROOT/'tools/blender_materials_v1.py'))
PARSER = argparse.ArgumentParser()
PARSER.add_argument('--only', default='')
PARSER.add_argument('--output-root', default='')
ARGS = PARSER.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
BASE = (ROOT / ARGS.output_root).resolve() if ARGS.output_root else ROOT
if not BASE.is_relative_to(ROOT):
    raise RuntimeError('Generated files must stay inside this repository')
OUT = BASE / 'godot' / 'assets'
SOURCE = BASE / 'art' / 'source'
MANIFEST = {}
COLORS = {
    'wood': (0.34, .20, .10, 1), 'wood_light': (.48,.38,.25,1), 'steel': (.19,.25,.27,1),
    'rust': (.46,.29,.21,1), 'foundation': (.47,.46,.42,1),
    'safety_vest': (.61,.35,.20,1), 'hard_hat': (.69,.54,.25,1),
    'cream': (.68,.61,.46,1), 'roof': (.15,.22,.24,1), 'glass': (.19,.35,.40,1),
    'cloth': (.24,.38,.38,1), 'linen': (.67,.65,.54,1), 'white': (.74,.75,.65,1), 'home': (.50,.43,.33,1),
    'clinic': (.27,.39,.39,1), 'shop': (.52,.43,.28,1), 'cross': (.62,.23,.17,1),
    'skin': (.64,.45,.30,1), 'jacket': (.31,.38,.23,1), 'trousers': (.16,.23,.28,1),
    'boots': (.12,.13,.12,1), 'hair': (.14,.10,.07,1), 'eyes': (.07,.07,.06,1),
    'player_jacket': (.28,.32,.26,1), 'canvas': (.34,.30,.22,1),
    'hair_player': (.23,.17,.12,1), 'hair_highlight': (.29,.22,.15,1),
    'zskin': (.40,.47,.29,1), 'zshirt': (.37,.25,.21,1), 'zpants': (.22,.25,.20,1)
}
MATS = {}

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.scene.render.fps = 30
    MATS.clear()
    for name, color in COLORS.items():
        recipe = MATERIAL_LIBRARY['materials'].get(MATERIAL_LIBRARY['aliases'].get(name,''))
        if recipe:
            color=tuple(int(recipe['color'][i:i+2],16)/255 for i in (0,2,4))+(1,)
        material = bpy.data.materials.new('DD_' + name)
        # Palette values are display sRGB; glTF baseColorFactor is linear.
        linear = tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in color[:3]) + (color[3],)
        material.diffuse_color = linear
        shader = material.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = linear
        shader.inputs['Roughness'].default_value = recipe['roughness'] if recipe else .93
        shader.inputs['Metallic'].default_value = recipe['metallic'] if recipe else 0
        if recipe:
            SURFACES['apply'](material,dict(recipe,id=MATERIAL_LIBRARY['aliases'][name]),ROOT)
        MATS[name] = material

def box(name, at, size, material, bevel=0, bevel_segments=1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(MATS[material])
    if bevel:
        modifier = obj.modifiers.new('DD_Chamfer', 'BEVEL')
        modifier.width = bevel
        modifier.segments = bevel_segments
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj

def join(objects, name):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    # Mesh origins fixed at ground pivot, including skinned geometry.
    bpy.context.scene.cursor.location = (0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return obj

def character(kind):
    zombie = kind == 'zombie'
    arm_data = bpy.data.armatures.new('DD_Skeleton')
    rig = bpy.data.objects.new('DD_Rig', arm_data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bones = [('root',(0,0,0),(0,0,.2),None),('pelvis',(0,0,.88),(0,0,1.02),'root'),
        ('spine',(0,0,1.02),(0,0,1.42),'pelvis'),('head',(0,0,1.42),(0,0,1.78),'spine')]
    for side, sign in [('L',-1),('R',1)]:
        bones += [
            ('upper_arm_'+side,(sign*.25,0,1.4),(sign*.34,0,1.10),'spine'),
            ('forearm_'+side,(sign*.34,0,1.10),(sign*.36,0,.84),'upper_arm_'+side),
            ('hand_'+side,(sign*.36,0,.84),(sign*.36,-.02,.76),'forearm_'+side),
            ('thigh_'+side,(sign*.14,0,.9),(sign*.14,0,.48),'pelvis'),
            ('shin_'+side,(sign*.14,0,.48),(sign*.14,0,.12),'thigh_'+side),
            ('foot_'+side,(sign*.14,0,.12),(sign*.14,-.18,.08),'shin_'+side)]
    for name, head, tail, parent in bones:
        bone = arm_data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    parts = []
    skin = 'zskin' if zombie else 'skin'
    shirt = 'zshirt' if zombie else 'player_jacket'
    pants = 'zpants' if zombie else 'trousers'
    def part(name, at, size, material, bone, bevel=.02, detail=False):
        organic = name in ['Neck','Hips','Nose'] or name.startswith(('Ear_','UpperSleeve_','Forearm_','Hand_','Thigh_','Shin_','Collar','HairTuft'))
        if name=='Torso':
            rings=[(1.01,.18,.13),(1.08,.21,.15),(1.25,.255,.16),(1.37,.25,.14),(1.44,.15,.115)]
            vertices=[];faces=[]
            for z,rx,ry in rings:
                for i in range(16):
                    angle=i*math.tau/16
                    vertices.append((rx*math.cos(angle),ry*math.sin(angle),z))
            for j in range(len(rings)-1):
                for i in range(16):faces.append((j*16+i,j*16+(i+1)%16,(j+1)*16+(i+1)%16,(j+1)*16+i))
            faces += [tuple(reversed(range(16))),tuple(range(64,80))]
            mesh=bpy.data.meshes.new('DD_TailoredTorso');mesh.from_pydata(vertices,[],faces)
            obj=bpy.data.objects.new('DD_TailoredTorso',mesh);bpy.context.collection.objects.link(obj)
            mesh.materials.append(MATS[material])
            for face in mesh.polygons:face.use_smooth=True
        elif name=='Neck' or name.startswith(('UpperSleeve_','Forearm_','Thigh_','Shin_')):
            # Truncated limb sections retain volume at elbow/knee instead of bead ends.
            vertices=[];faces=[];segments=12
            for j,(z,radius) in enumerate([(-.56,.68),(-.32,.90),(0,1),(.32,.90),(.56,.72)]):
                for i in range(segments):
                    angle=i*math.tau/segments
                    vertices.append((at[0]+math.cos(angle)*size[0]*.5*radius,at[1]+math.sin(angle)*size[1]*.5*radius,at[2]+z*size[2]))
            for j in range(4):
                for i in range(segments):faces.append((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i))
            faces += [tuple(reversed(range(segments))),tuple(range(4*segments,5*segments))]
            mesh=bpy.data.meshes.new('DD_ArticulatedLimb');mesh.from_pydata(vertices,[],faces)
            obj=bpy.data.objects.new('DD_'+name,mesh);bpy.context.collection.objects.link(obj)
            mesh.materials.append(MATS[material])
            for face in mesh.polygons:face.use_smooth=True
        elif organic:
            bpy.ops.mesh.primitive_uv_sphere_add(segments=8 if zombie or detail else 12,ring_count=6 if zombie or detail else 8,radius=1,location=at)
            obj=bpy.context.object
            obj.name='DD_'+name
            size=tuple(v*(1.15 if i==2 and name.startswith(('UpperSleeve_','Forearm_','Thigh_','Shin_')) else 1) for i,v in enumerate(size))
            obj.scale=tuple(v*.5 for v in size)
            bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
            obj.data.materials.append(MATS[material])
            for face in obj.data.polygons: face.use_smooth=True
        else:
            obj = box('DD_'+name,at,size,material,.065 if name=='Backpack' else bevel,3 if not zombie and not detail else 1)
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
        parts.append(obj)
        return obj
    part('Torso',(0,0,1.22),(.52,.32,.42),shirt,'spine',.055)
    part('Belt',(0,0,1.01),(.38,.29,.10),'steel','pelvis',.01)
    part('Hips',(0,0,.92),(.35,.28,.18),pants,'pelvis')
    part('Neck',(0,0,1.47),(.14,.14,.16),skin,'head')
    if zombie:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,radius=1,location=(0,-.005,1.65))
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=16,radius=1,location=(0,-.005,1.65))
    head = bpy.context.object
    head.name='DD_Head'
    head.scale=(.125,.12,.135)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    head.data.materials.append(MATS[skin])
    for vertex in head.data.vertices:
        if vertex.co.z<-.07:
            vertex.co.x*=.90
    for face in head.data.polygons: face.use_smooth=True
    head.vertex_groups.new(name='head').add(list(range(len(head.data.vertices))),1,'REPLACE')
    parts.append(head)
    if zombie:
        part('HairTuft_Broken',(-.025,.015,1.775),(.19,.18,.06),'hair','head',.04)
    else:
        # Scalp follows the skull with a lower nape and an asymmetric hairline.
        vertices=[];faces=[]
        for ring in range(9):
            for i in range(24):
                phi=i*math.tau/24
                limit=1.48+.30*math.sin(phi)+.06*math.cos(phi*3)
                theta=.015+(limit-.015)*ring/8
                vertices.append((.131*math.sin(theta)*math.cos(phi),.008+.126*math.sin(theta)*math.sin(phi),1.65+.145*math.cos(theta)))
        for ring in range(8):
            for i in range(24):
                a=ring*24+i;b=ring*24+(i+1)%24
                faces.append((a,a+24,b+24,b))
        faces.append(tuple(range(24)))
        mesh=bpy.data.meshes.new('DD_SculptedHair')
        mesh.from_pydata(vertices,[],faces)
        hair=bpy.data.objects.new('DD_SculptedHair',mesh)
        bpy.context.collection.objects.link(hair)
        mesh.materials.append(MATS['hair_player'])
        mesh.materials.append(MATS['hair_highlight'])
        hair.vertex_groups.new(name='head').add(list(range(len(mesh.vertices))),1,'REPLACE')
        for i,face in enumerate(mesh.polygons):
            face.use_smooth=True
            face.material_index=0
        parts.append(hair)
    part('Nose',(0,-.121,1.645),(.045,.045,.05),skin,'head',.01)
    part('Mouth',(0,-.114,1.59),(.06,.012,.015),'zshirt' if zombie else 'wood','head',0)
    def garment_tube(name,rings,materials,face_material=None):
        # One connected surface through the joint; weights transition across rings.
        count=12;vertices=[];faces=[]
        for x,y,z,rx,ry,weights in rings:
            for i in range(count):
                angle=i*math.tau/count
                vertices.append((x+rx*math.cos(angle),y+ry*math.sin(angle),z))
        for j in range(len(rings)-1):
            for i in range(count):faces.append((j*count+i,(j+1)*count+i,(j+1)*count+(i+1)%count,j*count+(i+1)%count))
        faces += [tuple(range(count)),tuple(reversed(range((len(rings)-1)*count,len(rings)*count)))]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces)
        obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
        for material in materials:mesh.materials.append(MATS[material])
        bone_names=dict.fromkeys(bone for ring in rings for bone in ring[-1])
        groups={bone:obj.vertex_groups.new(name=bone) for bone in bone_names}
        for j,ring in enumerate(rings):
            assert abs(sum(ring[-1].values())-1)<1e-6
            for bone,weight in ring[-1].items():
                groups[bone].add(list(range(j*count,(j+1)*count)),weight,'REPLACE')
        for index,face in enumerate(mesh.polygons):
            face.use_smooth=index<(len(rings)-1)*count
            if face_material and index<(len(rings)-1)*count:
                face.material_index=face_material(index//count,index%count)
        parts.append(obj)
    def boot(side,sign):
        vertices=[];faces=[]
        # Toe, ball, heel and ankle sections replace the rectangular block shoe.
        outlines=[(.008,.095,-.235,.085),(.055,.098,-.24,.09),(.12,.087,-.18,.085),(.185,.072,-.055,.075)]
        for z,w,front,back in outlines:
            vertices += [(sign*.14+x,y,z) for x,y in [(-w*.7,front), (w*.7,front),(w,front+.05),(w,back-.035),(w*.7,back),(-w*.7,back),(-w,back-.035),(-w,front+.05)]]
        for j in range(3):
            for i in range(8):faces.append((j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i))
        faces += [tuple(reversed(range(8))),tuple(range(24,32))]
        mesh=bpy.data.meshes.new('DD_BootProfile');mesh.from_pydata(vertices,[],faces)
        obj=bpy.data.objects.new('DD_Boot_'+side,mesh);bpy.context.collection.objects.link(obj)
        mesh.materials.append(MATS['boots']);obj.vertex_groups.new(name='foot_'+side).add(list(range(len(vertices))),1,'REPLACE')
        parts.append(obj)
    for side, sign in [('L',-1),('R',1)]:
        part('Eye_'+side,(sign*.055,-.113,1.685),(.023,.012,.017),'white' if zombie else 'eyes','head',0)
        part('Ear_'+side,(sign*.126,0,1.65),(.035,.055,.075),skin,'head',.01)
        upper='upper_arm_'+side;fore='forearm_'+side;hand='hand_'+side
        garment_tube('DD_CoatSleeve_'+side,[
            (sign*.24,0,1.44,.065,.08,{'spine':.4,upper:.6}),
            (sign*.275,0,1.39,.10,.115,{'spine':.1,upper:.9}),
            (sign*.31,0,1.28,.095,.11,{upper:1}),
            (sign*.335,0,1.16,.083,.095,{upper:.9,fore:.1}),
            (sign*.34,0,1.10,.079,.09,{upper:.5,fore:.5}),
            (sign*.345,0,1.04,.074,.084,{upper:.1,fore:.9}),
            (sign*.355,0,.93,.068,.078,{fore:1}),
            (sign*.36,0,.84,.060,.068,{fore:.8,hand:.2})
        ],[shirt,skin,'cross'],lambda row,column: (2 if row==3 and column==8 else 1 if row>=4 else 0) if zombie else 0)
        part('Hand_'+side,(sign*.36,-.015,.80),(.10,.12,.16),skin,'hand_'+side)
        thigh='thigh_'+side;shin='shin_'+side;foot='foot_'+side
        garment_tube('DD_TrouserLeg_'+side,[
            (sign*.14,0,.92,.10,.12,{'pelvis':.5,thigh:.5}),
            (sign*.14,0,.83,.112,.126,{thigh:1}),
            (sign*.14,0,.67,.105,.12,{thigh:1}),
            (sign*.14,0,.54,.089,.10,{thigh:.85,shin:.15}),
            (sign*.14,0,.49,.083,.095,{thigh:.5,shin:.5}),
            (sign*.14,0,.44,.083,.10,{thigh:.1,shin:.9}),
            (sign*.14,0,.32,.086,.105,{shin:1}),
            (sign*.14,0,.18,.077,.098,{shin:1}),
            (sign*.14,0,.125,.076,.095,{shin:.8,foot:.2})
        ],[pants,skin],lambda row,column: 1 if zombie and side=='R' and row in [3,4] and column in [8,9] else 0)
        boot(side,sign)
    if zombie:
        part('TornPatch',(.12,-.154,1.25),(.14,.014,.18),skin,'spine',0)
        civilian_patch=parts.pop()
        part('CheekMark',(.085,-.113,1.625),(.035,.012,.05),'cross','head',0)
    else:
        part('Backpack',(0,.20,1.24),(.34,.17,.34),'canvas','spine',.035)
        part('PackFlap',(0,.30,1.36),(.30,.06,.11),'canvas','spine',.02)
        part('JacketZip',(0,-.168,1.25),(.025,.018,.35),'steel','spine',0)
        part('Buckle',(0,-.158,1.01),(.09,.035,.065),'cream','pelvis',.008)
        for sign in [-1,1]:
            part('VestPocket',(sign*.12,-.17,1.15),(.15,.07,.15),'canvas','spine',.015)
            # A continuous fabric ribbon wraps from chest over shoulder to pack.
            points=[(sign*.18,-.18,1.12),(sign*.20,-.18,1.34),(sign*.21,-.10,1.44),(sign*.21,.04,1.46),(sign*.20,.18,1.40),(sign*.17,.29,1.20)]
            vertices=[];faces=[]
            for x,y,z in points:
                vertices += [(x-.026,y-.012,z),(x+.026,y-.012,z),(x+.026,y+.012,z),(x-.026,y+.012,z)]
            for j in range(len(points)-1):
                for k in range(4):faces.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
            mesh=bpy.data.meshes.new('DD_WrappedStrap');mesh.from_pydata(vertices,[],faces)
            strap=bpy.data.objects.new('DD_WrappedStrap',mesh);bpy.context.collection.objects.link(strap)
            mesh.materials.append(MATS['canvas']);strap.vertex_groups.new(name='spine').add(list(range(len(vertices))),1,'REPLACE');parts.append(strap)
            part('Collar',(sign*.09,-.12,1.43),(.14,.10,.065),'canvas','spine',.012)
    if not zombie:
        runpy.run_path(str(ROOT/'tools/refine_survivor.py'))['refine'](parts, MATS, part)
    # Reference-sheet silhouette: enlarge skull, hair and facial landmarks together.
    # Work in world space so separate mesh origins do not pull features apart.
    # Neck stays anchored to the collar; rig and animation rest transforms stay intact.
    for obj in parts:
        if obj.name == 'DD_Neck' or 'head' not in obj.vertex_groups:
            continue
        inverse=obj.matrix_world.inverted()
        for vertex in obj.data.vertices:
            point=obj.matrix_world @ vertex.co
            point.x*=1.20
            point.y=-.005+(point.y+.005)*1.18
            point.z=1.63+(point.z-1.65)*1.15
            vertex.co=inverse @ point
    body = join(parts,'DD_'+kind.capitalize()+'_Body')
    if not zombie:
        # Resolve curved bevel n-gons deterministically before glTF's adaptive tessellation.
        modifier=body.modifiers.new('DD_FixedTriangles','TRIANGULATE')
        modifier.quad_method='FIXED'
        modifier.ngon_method='CLIP'
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    body.parent=rig
    body.modifiers.new('DD_Skin','ARMATURE').object=rig
    if zombie:
        # Both outfits live in the same editable rig; runtime selects visible geometry.
        outfits={'civilian':[civilian_patch],'worker':[],'police':[]}
        def outfit_part(style,name,at,size,material,bone,bevel=.01):
            part(name,at,size,material,bone,bevel)
            outfits[style].append(parts.pop())
        def cap(style,material,height):
            vertices=[(0,0,1.77+height)];faces=[]
            for ring in range(1,5):
                phi=ring*math.pi/8
                for i in range(16):
                    angle=i*math.tau/16
                    vertices.append((.177*math.sin(phi)*math.cos(angle),.161*math.sin(phi)*math.sin(angle),1.77+height*math.cos(phi)))
            for i in range(16):faces.append((0,1+i,1+(i+1)%16))
            for ring in range(3):
                for i in range(16):
                    a=1+ring*16+i;b=1+ring*16+(i+1)%16
                    faces.append((a,a+16,b+16,b))
            mesh=bpy.data.meshes.new('DD_ShapedHeadwear');mesh.from_pydata(vertices,[],faces)
            obj=bpy.data.objects.new('DD_Headwear',mesh);bpy.context.collection.objects.link(obj)
            mesh.materials.append(MATS[material])
            for face in mesh.polygons:face.use_smooth=True
            obj.vertex_groups.new(name='head').add(list(range(len(vertices))),1,'REPLACE')
            outfits[style].append(obj)
        def hat_band(style,material,rx,ry,z,height):
            vertices=[];faces=[]
            for level in [z-height/2,z+height/2]:
                for i in range(16):
                    angle=i*math.tau/16
                    vertices.append((rx*math.cos(angle),ry*math.sin(angle),level))
            for i in range(16):faces.append((i,(i+1)%16,(i+1)%16+16,i+16))
            faces += [tuple(reversed(range(16))),tuple(range(16,32))]
            mesh=bpy.data.meshes.new('DD_OvalHatBand');mesh.from_pydata(vertices,[],faces)
            obj=bpy.data.objects.new('DD_HatBand',mesh);bpy.context.collection.objects.link(obj)
            mesh.materials.append(MATS[material]);obj.vertex_groups.new(name='head').add(list(range(len(vertices))),1,'REPLACE')
            outfits[style].append(obj)
        cap('worker','hard_hat',.13)
        # A narrow rim and central rib give the helmet a workwear silhouette.
        hat_band('worker','hard_hat',.192,.177,1.77,.025)
        outfit_part('worker','HelmetRib',(0,0,1.865),(.025,.24,.035),'hard_hat','head',.01)
        part('Torso',(0,0,0),(1,1,1),'safety_vest','spine')
        vest=parts.pop();vest.scale.x=1.05;vest.scale.y=1.05
        outfits['worker'].append(vest)
        for sign in [-1,1]:
            vertices=[];faces=[]
            for z,rx,ry in [(1.08,.21,.15),(1.25,.255,.16),(1.37,.25,.14),(1.42,.18,.12)]:
                x=sign*.105;y=-ry*math.sqrt(1-(x/rx)**2)*1.05-.007
                vertices += [(x-.018,y,z),(x+.018,y,z)]
            for j in range(3):faces.append((j*2,j*2+1,j*2+3,j*2+2))
            mesh=bpy.data.meshes.new('DD_VestVisibilityStrip');mesh.from_pydata(vertices,[],faces)
            obj=bpy.data.objects.new('DD_VestStrip',mesh);bpy.context.collection.objects.link(obj)
            mesh.materials.append(MATS['linen']);obj.vertex_groups.new(name='spine').add(list(range(len(vertices))),1,'REPLACE')
            outfits['worker'].append(obj)
        cap('police','trousers',.075)
        hat_band('police','boots',.17,.155,1.765,.04)
        outfit_part('police','CapVisor',(0,-.18,1.76),(.29,.17,.02),'boots','head',.025)
        outfit_part('police','PlainBadge',(-.105,-.17,1.32),(.045,.015,.065),'hard_hat','spine',.008)
        outfit_part('police','DutyBelt',(0,0,1.025),(.42,.32,.055),'boots','spine',.008)
        for sign in [-1,1]:
            outfit_part('police','BeltPouch',(sign*.17,-.15,1.10),(.09,.07,.13),'boots','spine',.012)
        for style,objects in outfits.items():
            accessory=join(objects,'DD_Variant_'+style+'_Outfit')
            accessory.parent=rig
            accessory.modifiers.new('DD_Skin','ARMATURE').object=rig
    if not zombie:
        weapon=box('DD_Weapon_Club',(.36,-.28,.80),(.075,.62,.075),'wood_light',.015)
        weapon.vertex_groups.new(name='hand_R').add(list(range(len(weapon.data.vertices))),1,'REPLACE')
        weapon.parent=rig
        weapon.modifiers.new('DD_Skin','ARMATURE').object=rig
        # Separate skinned firearm mesh: visibility is controlled by real equipped state.
        pieces=[box('Slide',(.36,-.015,.71),(.055,.055,.24),'steel',.007),
                box('Grip',(.36,.015,.80),(.05,.11,.06),'boots',.008),
                box('TriggerGuard',(.36,-.025,.775),(.045,.075,.014),'steel',.004)]
        pistol=join(pieces,'DD_Weapon_Pistol')
        pistol.vertex_groups.new(name='hand_R').add(list(range(len(pistol.data.vertices))),1,'REPLACE')
        pistol.parent=rig
        pistol.modifiers.new('DD_Skin','ARMATURE').object=rig
    clips = {'stand':[0,7,15,22,30], 'move':[0,8,16,24,32], 'attack':[0,4,8,12,18],
             'hurt':[0,2,4,6], 'death':[0,6,14,22]}
    if zombie:
        clips['attack']=[0,6,13,16,22]
    else:
        clips['run']=[0,5,10,15,20]
    rig.animation_data_create()
    for name, frames in clips.items():
        action=bpy.data.actions.new(name)
        action.use_fake_user=True
        rig.animation_data.action=action
        for frame in frames:
            t=(frame-frames[0])/(frames[-1]-frames[0])
            for bone in rig.pose.bones:
                bone.rotation_mode='XYZ'
                bone.rotation_euler=(0,0,0)
                bone.location=(0,0,0)
            if zombie:
                rig.pose.bones['spine'].rotation_euler.x=.12
                rig.pose.bones['head'].rotation_euler.z=.10
                for side in ['L','R']:
                    rig.pose.bones['upper_arm_'+side].rotation_euler.x=-.35
            if name == 'stand':
                rig.pose.bones['spine'].rotation_euler.x += math.sin(t*math.tau)*.025
            elif name in ['move','run']:
                sprint = name == 'run'
                swing=math.cos(t*math.tau)*(.9 if sprint else (.42 if zombie else .6))
                for side, sign in [('L',-1),('R',1)]:
                    rig.pose.bones['thigh_'+side].rotation_euler.x=sign*swing
                    rig.pose.bones['shin_'+side].rotation_euler.x=max(0,-sign*swing)*(1.15 if sprint else .9)
                    rig.pose.bones['upper_arm_'+side].rotation_euler.x=(-.65 if zombie else 0)-sign*swing*.6
                rig.pose.bones['root'].location.z=abs(math.sin(t*math.tau))*(.06 if sprint else .025)
                if sprint:
                    rig.pose.bones['spine'].rotation_euler.x=.16
            elif name == 'attack':
                wind=({0:0,6:1.8,13:-1.4,16:-.8,22:0} if zombie else {0:-1.4,4:-1.0,8:.6,12:.3,18:0})[frame]
                rig.pose.bones['upper_arm_R'].rotation_euler.x=wind
                rig.pose.bones['forearm_R'].rotation_euler.x=-.25
                rig.pose.bones['spine'].rotation_euler.y=wind*.18
                if zombie:
                    rig.pose.bones['upper_arm_L'].rotation_euler.x=wind*.8
            elif name == 'hurt':
                rig.pose.bones['spine'].rotation_euler.x += math.sin(t*math.pi)*.4
                rig.pose.bones['head'].rotation_euler.x=-math.sin(t*math.pi)*.3
            elif name == 'death':
                rig.pose.bones['root'].rotation_euler.x=-min(1,t*1.4)*math.pi/2
                rig.pose.bones['root'].location.z=min(1,t*1.4)*.19
            for bone in rig.pose.bones:
                bone.keyframe_insert('rotation_euler',frame=frame,group=bone.name)
                bone.keyframe_insert('location',frame=frame,group=bone.name)
        # glTF samples all active armature actions in ACTIONS mode.
    rig.animation_data.action=bpy.data.actions['stand']
    bpy.context.scene.frame_set(0)
    return {'clips':list(clips),'bones':len(bones)}

def prop(kind):
    if kind=='door':
        # Hinge at left ground origin. Godot rotates this around its hinge, not the middle.
        box('DD_Door_Leaf',(.85,0,1),(1.7,.16,2),'wood',.025)
        for x in [.20,1.50]:
            box('DD_Door_Rail',(x,-.085,1),(.08,.035,1.8),'wood_light')
        box('DD_Door_Handle',(1.48,-.12,1.02),(.10,.08,.055),'steel',.01)
    elif kind=='bed':
        # Open under-frame with actual rails, slats and four supporting legs.
        for x in [-.505,.505]:
            box('DD_Bed_SideRail',(x,0,.345),(.09,1.70,.18),'wood',.014,2)
            for y in [-.77,.77]:
                box('DD_Bed_Leg',(x,y,.17),(.09,.10,.34),'wood',.012,2)
        for y in [-.85,.85]:
            box('DD_Bed_EndRail',(0,y,.345),(1.1,.10,.18),'wood',.014,2)
        for y in [-.66,-.44,-.22,0,.22,.44,.66]:
            box('DD_Bed_Slat',(0,y,.405),(.94,.10,.035),'wood_light')
        box('DD_Bed_Mattress',(0,0,.5),(1.04,1.66,.14),'linen',.045,3)
        box('DD_Bed_Blanket',(0,-.20,.577),(1.01,1.16,.035),'player_jacket',.015,2)
        box('DD_Bed_BlanketFold',(0,.34,.602),(1.0,.11,.035),'player_jacket',.012,2)
        box('DD_Bed_Pillow',(0,.59,.61),(.79,.34,.12),'linen',.045,3)
        for x in [-.505,.505]:
            box('DD_Bed_HeadPost',(x,.85,.48),(.09,.10,.69),'wood',.012,2)
        box('DD_Bed_Headboard',(0,.85,.63),(.94,.065,.33),'wood_light',.015,2)
    elif kind=='cabinet':
        for x in [-.565,.565]:
            box('DD_Cabinet_Side',(x,0,.5),(.07,.7,1),'wood',.012,2)
        for z in [.065,.965]:
            box('DD_Cabinet_Rail',(0,0,z),(1.12,.7,.07),'wood',.012,2)
        box('DD_Cabinet_Back',(0,.325,.5),(1.06,.05,.84),'wood_light')
        for x in [-.29,.29]:
            box('DD_Cabinet_Panel',(x,-.335,.5),(.54,.045,.86),'wood_light',.014,3)
            box('DD_Cabinet_Inset',(x,-.362,.5),(.43,.015,.72),'wood',.012,2)
            box('DD_Cabinet_Pull',(x+(.18 if x<0 else -.18),-.38,.56),(.04,.045,.16),'steel',.008)
    elif kind=='table':
        box('DD_Table_Top',(0,0,.72),(1.0,1.0,.09),'wood_light',.025)
        for x in [-.4,.4]:
            for y in [-.4,.4]:
                box('DD_Table_Leg',(x,y,.35),(.11,.11,.7),'wood',.012)
    elif kind=='loot_crate':
        parts=[box('DD_Prop_LootCrate',(0,0,.5),(1.2,.7,1),'wood_light')]
        for x in [-.40,.40]:
            parts.append(box('DD_Crate_Band',(x,-.335,.5),(.065,.025,.9),'steel'))
        join(parts,'DD_Prop_LootCrate')

def building(kind):
    material={'home':'home','clinic':'clinic','shop':'shop'}[kind]
    rules=json.loads((ROOT/'godot/data/rules.json').read_text(encoding='utf-8'))
    depth=next(float(b.get('depth',5)) for b in rules['buildings'] if b['id']==kind)
    box('DD_Keep_Floor',(0,depth/2,.02),(5.5,depth,.04),'wood_light')
    box('DD_Keep_Back',(0,depth,1.3),(5.7,.2,2.6),material)
    box('DD_Keep_West',(-2.75,depth/2,1.3),(.2,depth,2.6),material)
    box('DD_Hide_East',(2.75,depth/2,1.3),(.2,depth,2.6),material)
    box('DD_Cut_East',(2.75,depth/2,.39),(.2,depth,.78),material)
    for sign in [-1,1]:
        box('DD_Hide_Front_'+str(sign),(sign*1.85,0,1.3),(1.9,.2,2.6),material)
        box('DD_Cut_Front_'+str(sign),(sign*1.85,0,.39),(1.9,.2,.78),material)
        box('DD_Hide_Window_'+str(sign),(sign*1.80,-.112,1.55),(.90,.025,.70),'glass',.025)
        box('DD_Hide_Sill_'+str(sign),(sign*1.80,-.15,1.15),(1.05,.1,.07),'cream')
    if kind=='home':
        # Recess outline and casing distinguish glass, frame and masonry at play distance.
        for sign in [-1,1]:
            center=sign*1.8
            for x in [center-.49,center+.49]:
                box('DD_Hide_Front_WindowJamb',(x,-.143,1.55),(.07,.075,.83),'cream',.008)
            for z in [1.15,1.95]:
                box('DD_Hide_Front_WindowLintel',(center,-.143,z),(1.05,.075,.07),'cream',.008)
            box('DD_Hide_Front_WindowMullion',(center,-.149,1.55),(.035,.035,.70),'cream',.005)
        for x in [-.915,.915]:
            box('DD_Hide_Front_DoorCasing',(x,-.135,1.04),(.11,.12,2.08),'wood_light',.01)
        box('DD_Hide_Front_DoorLintel',(0,-.135,2.10),(1.94,.12,.12),'wood_light',.01)
        # Fascia and gutter sit along the two low eaves, not across the roof slope.
        for sign,side in [(-1,'West'),(1,'East')]:
            box('DD_Hide_'+side+'_Eave',(sign*2.91,depth/2,2.57),(.11,depth+.5,.16),'wood_light',.012)
            box('DD_Hide_'+side+'_Gutter',(sign*2.99,depth/2,2.59),(.10,depth+.48,.07),'steel',.012)
    if kind=='home':
        # Two sloped halves make a reusable gable roof.
        for sign in [-1,1]:
            obj=box('DD_Hide_Roof_'+str(sign),(sign*1.46,depth/2,3.0),(3.08,depth+.55,.14),'roof')
            obj.rotation_euler.y=sign*math.radians(18)
            for i in range(int(depth*2)+1):
                seam=box('DD_Hide_RoofSeam',(sign*1.46,i*.5,3.09),(3.08,.025,.035),'steel')
                seam.rotation_euler.y=sign*math.radians(18)
        box('DD_Hide_Ridge',(0,depth/2,3.51),(.12,depth+.6,.10),'steel',.015)
        for y, front in [(-.101,True),(depth+.101,False)]:
            mesh=bpy.data.meshes.new('DD_Gable')
            vertices=[(-2.85,y-.08,2.6),(2.85,y-.08,2.6),(0,y-.08,3.49),(-2.85,y+.08,2.6),(2.85,y+.08,2.6),(0,y+.08,3.49)]
            mesh.from_pydata(vertices,[],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)])
            obj=bpy.data.objects.new('DD_Hide_Gable_'+str(front),mesh)
            bpy.context.collection.objects.link(obj)
            mesh.materials.append(MATS[material])
        box('DD_Hide_Chimney',(1.6,3.8,3.25),(.44,.5,.95),'steel')
    else:
        box('DD_Hide_Roof',(0,2.5,2.76),(5.95,5.5,.24),'roof',.035)
        box('DD_Hide_RoofVent',(-1.5,3.6,3.02),(.75,.65,.30),'steel',.035)
        if kind=='clinic':
            box('DD_Hide_Sign',(0,-.13,2.35),(1.3,.08,.35),'white')
            box('DD_Hide_CrossV',(0,-.18,2.35),(.10,.035,.26),'cross')
            box('DD_Hide_CrossH',(0,-.18,2.35),(.32,.035,.09),'cross')
        else:
            for i in range(7):
                box('DD_Hide_Awning_'+str(i),(-2.4+i*.8,-.35,2.52),(.79,.8,.10),'cream' if i%2==0 else 'shop')
    for y, face in [(-.15,'Front'),(depth+.15,'Back')]:
        box('DD_Hide_'+face+'Fascia',(0,y,2.58),(5.85,.12,.15),'steel')
        for x in [-2.72,2.72]:
            box('DD_Hide_'+face+'Corner',(x,y,1.3),(.10,.10,2.6),'cream')
        # Irregular low plinth stones and repaired boards: actual editable geometry.
        for i in range(10):
            x=-2.57+i*.57
            if face=='Front' and abs(x)<1.0:
                continue
            box('DD_Hide_'+face+'Plinth',(x,y,.13),(.54,.06,.19+(i%3)*.025),'foundation' if kind=='home' else ('steel' if i%3 else 'wood_light'))
        for sign in [-1,1]:
            board=box('DD_Hide_'+face+'WindowRepair',(sign*1.8,y-.025 if face=='Front' else y+.025,1.5),(.97,.06,.105),'wood_light')
            board.rotation_euler.y=sign*.13
    return {'cutaway_prefixes':['DD_Hide_','DD_Cut_']}

def canonical_triangle_order(path):
    # Blender may enumerate smooth-face triangles in a different order between processes.
    # Sort only opaque triangle index triplets; positions, winding, weights and clips stay intact.
    data=bytearray(path.read_bytes())
    json_length=struct.unpack_from('<I',data,12)[0]
    document=json.loads(data[20:20+json_length])
    binary_start=28+json_length
    seen=set()
    normals=set()
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            normals.add(primitive['attributes']['NORMAL'])
            assert primitive.get('mode',4)==4
            index=primitive['indices']
            if index in seen:continue
            seen.add(index)
            accessor=document['accessors'][index]
            view=document['bufferViews'][accessor['bufferView']]
            assert accessor['type']=='SCALAR' and 'byteStride' not in view
            fmt={5121:'B',5123:'H',5125:'I'}[accessor['componentType']]
            count=accessor['count'];assert count%3==0
            start=binary_start+view.get('byteOffset',0)+accessor.get('byteOffset',0)
            values=struct.unpack_from('<'+fmt*count,data,start)
            triangles=sorted(tuple(values[i:i+3]) for i in range(0,count,3))
            struct.pack_into('<'+fmt*count,data,start,*(v for triangle in triangles for v in triangle))
    # Smooth bevel normal sums can differ by ~4e-5 across Blender processes.
    # A 0.01 component grid followed by normalization gives stable unit normals
    # with less than one degree of visual error; geometry and rig data are unchanged.
    for index in normals:
        accessor=document['accessors'][index];view=document['bufferViews'][accessor['bufferView']]
        assert accessor['type']=='VEC3' and accessor['componentType']==5126 and 'byteStride' not in view
        start=binary_start+view.get('byteOffset',0)+accessor.get('byteOffset',0)
        for i in range(accessor['count']):
            at=start+i*12
            n=[round(v*100)/100 for v in struct.unpack_from('<fff',data,at)]
            length=math.sqrt(sum(v*v for v in n))
            struct.pack_into('<fff',data,at,*(v/length for v in n))
    path.write_bytes(data)

def export(name, info):
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    triangles=0
    mesh_count=0
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH':
            obj.data.calc_loop_triangles()
            triangles+=len(obj.data.loop_triangles)
            mesh_count+=1
    bpy.context.scene['DD_asset']=name
    bpy.context.scene['DD_units']='meters; Blender Z-up, forward -Y; GLB/Godot Y-up, forward +Z'
    SURFACES['project_uvs']()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,
        export_texcoords=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,
        export_anim_slide_to_zero=True,export_optimize_animation_size=True)
    if name in ['player','zombie']:
        canonical_triangle_order(OUT/(name+'.glb'))
    SURFACES['canonical_uvs'](OUT/(name+'.glb'))
    entry={'file':name+'.glb','source':'art/source/'+name+'.blend','triangles':triangles,'meshes':mesh_count,**info}
    MANIFEST[name]=entry
    print('ASSET_OK',name,triangles,mesh_count)

def main():
    if not bpy.app.background:
        raise RuntimeError('Background mode required; interactive projects are never cleared')
    OUT.mkdir(parents=True,exist_ok=True)
    SOURCE.mkdir(parents=True,exist_ok=True)
    NAMES=['player','zombie','building_home','building_clinic','building_shop','door','bed','cabinet','table','loot_crate']
    SELECTED=ARGS.only.split(',') if ARGS.only else NAMES
    if any(name not in NAMES for name in SELECTED):
        raise RuntimeError('Unknown asset selection')
    for name in SELECTED:
        reset()
        if name in ['player','zombie']:
            info=character(name)
        elif name.startswith('building_'):
            info=building(name.removeprefix('building_'))
        else:
            prop(name)
            info={}
        export(name,info)
    manifest_path=OUT/'manifest.json'
    existing=json.loads(manifest_path.read_text(encoding='utf-8')) if ARGS.only and manifest_path.exists() else {'version':1,'blender':bpy.app.version_string,'assets':{}}
    existing['blender']=bpy.app.version_string
    existing['assets'].update(MANIFEST)
    manifest_path.write_text(json.dumps(existing,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ASSET_PIPELINE_OK',bpy.app.version_string,len(MANIFEST))

if __name__ == "__main__":
    main()
