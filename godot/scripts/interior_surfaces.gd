extends RefCounted
const SurfaceShader = preload("res://shaders/interior_surface.gdshader")
static func apply(details: Node3D, layout: Dictionary) -> void:
    var definitions: Dictionary = layout.get("surface_profiles",{})
    var materials := {}
    for id in definitions:
        var d: Dictionary = definitions[id]
        var material := ShaderMaterial.new()
        material.shader=SurfaceShader
        material.resource_name="HouseSurface_"+id
        material.set_shader_parameter("base_color",Color(d.color))
        material.set_shader_parameter("surface_kind",int(d.kind))
        material.set_shader_parameter("base_roughness",float(d.roughness))
        material.set_shader_parameter("grain_axis",int(d.get("grain_axis",0)))
        materials[id]=material
    var modules: Array = layout.modules
    var meshes := details.find_children("*","MeshInstance3D",true,false)
    for i in modules.size():
        var module: Dictionary = modules[i]
        if not module.has("surface"):
            continue
        var p: Array = module.position
        for mesh in meshes:
            if str(mesh.name).begins_with(module.name) and mesh.position.distance_to(Vector3(p[0],p[1],p[2]))<.001:
                mesh.material_override=materials[module.surface]
                break
    details.set_meta("surface_materials",materials)
