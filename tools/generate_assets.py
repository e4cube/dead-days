"""Original low-poly asset pack. Blender --background --factory-startup --python tools/generate_assets.py.
All generated sources stay in art/source; only explicit GLB exports enter the engine.
Optional: -- --only player,zombie --output-root work/asset-preview
"""
from pathlib import Path
import argparse
import json
import math
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
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
    'wood': (0.34, .20, .10, 1), 'wood_light': (.56,.39,.22,1), 'steel': (.19,.25,.27,1),
    'cream': (.68,.61,.46,1), 'roof': (.15,.22,.24,1), 'glass': (.19,.35,.40,1),
    'cloth': (.24,.38,.38,1), 'white': (.74,.75,.65,1), 'home': (.58,.43,.28,1),
    'clinic': (.29,.48,.49,1), 'shop': (.64,.47,.20,1), 'cross': (.62,.23,.17,1),
    'skin': (.64,.45,.30,1), 'jacket': (.31,.38,.23,1), 'trousers': (.16,.23,.28,1),
    'boots': (.12,.13,.12,1), 'hair': (.14,.10,.07,1), 'eyes': (.07,.07,.06,1),
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
        material = bpy.data.materials.new('DD_' + name)
        # Palette values are display sRGB; glTF baseColorFactor is linear.
        linear = tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in color[:3]) + (color[3],)
        material.diffuse_color = linear
        shader = material.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = linear
        shader.inputs['Roughness'].default_value = .93
        MATS[name] = material

def box(name, at, size, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(MATS[material])
    if bevel:
        modifier = obj.modifiers.new('DD_Chamfer', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 1
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
    shirt = 'zshirt' if zombie else 'jacket'
    pants = 'zpants' if zombie else 'trousers'
    def part(name, at, size, material, bone, bevel=.02):
        obj = box('DD_'+name,at,size,material,bevel)
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
        parts.append(obj)
        return obj
    part('Torso',(0,0,1.22),(.52,.32,.42),shirt,'spine',.055)
    part('Belt',(0,0,1.01),(.38,.29,.10),'steel','pelvis',.01)
    part('Hips',(0,0,.92),(.35,.28,.18),pants,'pelvis')
    part('Neck',(0,0,1.45),(.13,.13,.13),skin,'head')
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=(0,-.005,1.61))
    head = bpy.context.object
    head.name='DD_Head'
    head.scale=(.23,.205,.215)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    head.data.materials.append(MATS[skin])
    head.vertex_groups.new(name='head').add(list(range(len(head.data.vertices))),1,'REPLACE')
    parts.append(head)
    part('Hair',(0,.015,1.77),(.36,.32,.10),'hair','head',.04)
    part('HairFringe',(-.07,-.14,1.74),(.22,.10,.10),'hair','head',.02)
    part('Nose',(0,-.208,1.60),(.065,.07,.07),skin,'head',.01)
    part('Mouth',(0,-.204,1.535),(.085,.012,.018),'zshirt' if zombie else 'wood','head',0)
    for side, sign in [('L',-1),('R',1)]:
        part('Eye_'+side,(sign*.085,-.193,1.65),(.038,.022,.024),'white' if zombie else 'eyes','head',0)
        part('Ear_'+side,(sign*.222,0,1.61),(.05,.075,.10),skin,'head',.01)
        part('UpperSleeve_'+side,(sign*.292,0,1.26),(.18,.24,.29),shirt,'upper_arm_'+side)
        part('Forearm_'+side,(sign*.35,0,.98),(.145,.16,.25),skin,'forearm_'+side)
        part('Hand_'+side,(sign*.36,-.015,.80),(.15,.18,.14),skin,'hand_'+side)
        part('Thigh_'+side,(sign*.14,0,.69),(.22,.25,.37),pants,'thigh_'+side)
        part('Shin_'+side,(sign*.14,0,.31),(.18,.21,.34),pants,'shin_'+side)
        part('Boot_'+side,(sign*.14,-.075,.085),(.20,.33,.17),'boots','foot_'+side)
    if zombie:
        part('TornPatch',(.12,-.154,1.25),(.14,.014,.18),skin,'spine',0)
        part('TornSleeve',(-.292,-.13,1.18),(.12,.035,.16),skin,'upper_arm_L',.01)
        part('KneeTear',(.14,-.135,.56),(.12,.025,.12),skin,'thigh_R',.01)
        part('CheekMark',(.14,-.175,1.58),(.06,.025,.075),'cross','head',0)
    else:
        part('Backpack',(0,.20,1.24),(.34,.17,.34),'wood','spine',.035)
        part('PackFlap',(0,.30,1.36),(.30,.06,.11),'jacket','spine',.02)
        part('JacketZip',(0,-.168,1.25),(.025,.018,.35),'steel','spine',0)
        part('Buckle',(0,-.158,1.01),(.09,.035,.065),'cream','pelvis',.008)
        for sign in [-1,1]:
            part('VestPocket',(sign*.12,-.17,1.15),(.15,.07,.15),'wood_light','spine',.015)
            part('PackStrap',(sign*.18,-.17,1.33),(.055,.035,.27),'wood','spine',.01)
            part('Collar',(sign*.09,-.12,1.43),(.14,.10,.065),'cream','spine',.012)
    body = join(parts,'DD_'+kind.capitalize()+'_Body')
    body.parent=rig
    body.modifiers.new('DD_Skin','ARMATURE').object=rig
    if not zombie:
        weapon=box('DD_Weapon_Club',(.36,-.28,.80),(.075,.62,.075),'wood_light',.015)
        weapon.vertex_groups.new(name='hand_R').add(list(range(len(weapon.data.vertices))),1,'REPLACE')
        weapon.parent=rig
        weapon.modifiers.new('DD_Skin','ARMATURE').object=rig
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
        box('DD_Bed_Frame',(0,0,.23),(1.1,1.8,.46),'wood',.025)
        box('DD_Bed_Mattress',(0,0,.5),(1.04,1.73,.14),'cloth',.045)
        box('DD_Bed_Pillow',(0,.55,.61),(.82,.38,.12),'white',.04)
        box('DD_Bed_Headboard',(0,.85,.50),(1.1,.10,.65),'wood_light',.02)
    elif kind=='cabinet':
        box('DD_Cabinet',(0,0,.5),(1.2,.7,1),'wood',.025)
        for x in [-.29,.29]:
            box('DD_Cabinet_Panel',(x,-.355,.5),(.54,.025,.88),'wood_light',.015)
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
    box('DD_Keep_Floor',(0,2.5,.02),(5.5,5,.04),'wood_light')
    box('DD_Keep_Back',(0,5,1.3),(5.7,.2,2.6),material)
    box('DD_Keep_West',(-2.75,2.5,1.3),(.2,5,2.6),material)
    box('DD_Hide_East',(2.75,2.5,1.3),(.2,5,2.6),material)
    box('DD_Cut_East',(2.75,2.5,.39),(.2,5,.78),material)
    for sign in [-1,1]:
        box('DD_Hide_Front_'+str(sign),(sign*1.85,0,1.3),(1.9,.2,2.6),material)
        box('DD_Cut_Front_'+str(sign),(sign*1.85,0,.39),(1.9,.2,.78),material)
        box('DD_Hide_Window_'+str(sign),(sign*1.80,-.112,1.55),(.90,.025,.70),'glass',.025)
        box('DD_Hide_Sill_'+str(sign),(sign*1.80,-.15,1.15),(1.05,.1,.07),'cream')
    if kind=='home':
        # Two sloped halves make a reusable gable roof.
        for sign in [-1,1]:
            obj=box('DD_Hide_Roof_'+str(sign),(sign*1.46,2.5,3.0),(3.08,5.55,.14),'roof')
            obj.rotation_euler.y=sign*math.radians(18)
        for y, front in [(-.101,True),(5.101,False)]:
            mesh=bpy.data.meshes.new('DD_Gable')
            mesh.from_pydata([(-2.85,y,2.6),(2.85,y,2.6),(0,y,3.49)],[],[(0,1,2) if front else (2,1,0)])
            obj=bpy.data.objects.new('DD_Hide_Gable_'+str(front),mesh)
            bpy.context.collection.objects.link(obj)
            mesh.materials.append(MATS[material])
        box('DD_Hide_Chimney',(1.6,3.8,3.25),(.44,.5,.95),'steel')
    else:
        box('DD_Hide_Roof',(0,2.5,2.76),(5.95,5.5,.24),'roof',.035)
        if kind=='clinic':
            box('DD_Hide_Sign',(0,-.13,2.35),(1.3,.08,.35),'white')
            box('DD_Hide_CrossV',(0,-.18,2.35),(.10,.035,.26),'cross')
            box('DD_Hide_CrossH',(0,-.18,2.35),(.32,.035,.09),'cross')
        else:
            for i in range(7):
                box('DD_Hide_Awning_'+str(i),(-2.4+i*.8,-.35,2.52),(.79,.8,.10),'cream' if i%2==0 else 'shop')
    return {'cutaway_prefixes':['DD_Hide_','DD_Cut_']}

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
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,
        export_texcoords=False,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,
        export_anim_slide_to_zero=True,export_optimize_animation_size=True)
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
    if not ARGS.only:
        (OUT/'manifest.json').write_text(json.dumps({'version':1,'blender':bpy.app.version_string,'assets':MANIFEST},indent=2)+'\n',encoding='utf-8')
    print('ASSET_PIPELINE_OK',bpy.app.version_string,len(MANIFEST))

if __name__ == "__main__":
    main()
