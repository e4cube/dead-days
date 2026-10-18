"""Run with Blender --background --factory-startup --python tools/generate_assets.py.
Pipeline proof only: 1.2 x 0.7 x 1.0 m loot crate, not the phase-C art pack.
"""
from pathlib import Path
import bpy

if not bpy.app.background:
    raise RuntimeError('Run in background mode to protect interactive Blender projects')
root = Path(__file__).resolve().parents[1]
out = root / 'godot' / 'assets'
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.5))
crate = bpy.context.object
crate.name = 'DD_Prop_LootCrate'
crate.dimensions = (1.2, 0.7, 1.0)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
material = bpy.data.materials.new('DD_Wood_Matte')
material.diffuse_color = (0.42, 0.24, 0.10, 1)
material.use_nodes = True
shader = material.node_tree.nodes.get('Principled BSDF')
shader.inputs['Base Color'].default_value = material.diffuse_color
shader.inputs['Roughness'].default_value = 1.0
crate.data.materials.append(material)
source = root / 'art' / 'source'
source.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(source / 'loot_crate.blend'))
bpy.ops.export_scene.gltf(filepath=str(out / 'loot_crate.glb'), export_format='GLB', use_selection=True, export_yup=True)
print('ASSET_PIPELINE_OK', bpy.app.version_string, crate.dimensions[:])
