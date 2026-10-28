extends RefCounted
static func apply(details: Node3D, layout: Dictionary) -> void:
    var definitions: Dictionary = layout.get("surface_profiles",{})
    var materials := {}
    for id in definitions:
        var shared: Dictionary=preload("res://scripts/material_library_v1.gd").definitions()
        var material := preload("res://scripts/material_library_v1.gd").material(shared.house_aliases[id])
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
