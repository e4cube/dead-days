"""Shared recipe application and metre-scaled UV projection for explicit GLB maps."""
import bpy
import json,struct,math
LIBRARIES={}
def canonical_uvs(path):
    # glTF exporter introduces ~1e-7 UV differences between Blender processes.
    # A 1e-4 UV grid is <=0.052 texel at 512px. Preserve geometry/skin/animation.
    data=bytearray(path.read_bytes());length=struct.unpack_from('<I',data,12)[0]
    document=json.loads(data[20:20+length]);start=28+length;seen=set()
    for mesh in document.get('meshes',[]):
        for primitive in mesh['primitives']:
            for name,index in primitive['attributes'].items():
                if not name.startswith('TEXCOORD_') or index in seen:continue
                seen.add(index);accessor=document['accessors'][index]
                view=document['bufferViews'][accessor['bufferView']]
                assert accessor['componentType']==5126 and accessor['type']=='VEC2' and 'byteStride' not in view
                offset=start+view.get('byteOffset',0)+accessor.get('byteOffset',0)
                for i in range(accessor['count']*2):
                    value=struct.unpack_from('<f',data,offset+i*4)[0]
                    # Bias exact decimal half-grid ties away from exporter float jitter.
                    struct.pack_into('<f',data,offset+i*4,math.floor(value*10000+.51)/10000)
    path.write_bytes(data)
def apply(material,recipe,root):
    material['dd_recipe']=recipe.get('id','')
    material['dd_scale_m']=recipe['scale_m']
    category=recipe['category']
    if root not in LIBRARIES:
        LIBRARIES[root]=json.loads((root/'godot/data/material_library_v1.json').read_text(encoding='utf-8'))
    library=LIBRARIES[root];paths=library['textures']
    family=paths['families'].get(category)
    if not family:return
    nodes=material.node_tree.nodes;links=material.node_tree.links
    shader=nodes.get('Principled BSDF')
    for channel in ['base','roughness','normal']:
        node=nodes.new('ShaderNodeTexImage')
        key='base_color' if channel=='base' else channel
        relative=paths[key].format(id=recipe['id'],family=family)
        node.image=bpy.data.images.load(str(root/'godot'/relative),check_existing=True)
        node.image.pack()
        if channel=='base':
            shader.inputs['Base Color'].default_value=(1,1,1,1)
            links.new(node.outputs['Color'],shader.inputs['Base Color'])
        else:
            node.image.colorspace_settings.name='Non-Color'
            if channel=='roughness':links.new(node.outputs['Color'],shader.inputs['Roughness'])
            else:
                normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=recipe.get('normal_strength',library['render']['normal_strength'])
                links.new(node.outputs['Color'],normal.inputs['Color'])
                links.new(normal.outputs['Normal'],shader.inputs['Normal'])
def project_uvs():
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH':continue
        uv=obj.data.uv_layers.active or obj.data.uv_layers.new(name='DD_MetreUV')
        for polygon in obj.data.polygons:
            mat=obj.data.materials[polygon.material_index] if obj.data.materials else None
            scale=float(mat.get('dd_scale_m',1)) if mat else 1
            axis=max(range(3),key=lambda i:round(abs(polygon.normal[i]),4))
            a,b=[i for i in range(3) if i!=axis]
            for index in polygon.loop_indices:
                point=obj.data.vertices[obj.data.loops[index].vertex_index].co
                uv.data[index].uv=(round(point[a]/scale,5),round(point[b]/scale,5))
