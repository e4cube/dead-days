extends RefCounted
## The same stable IDs are used by rules, saved records and imported accessory names.
const Materials=preload("res://scripts/material_library_v1.gd")
static var cache: Dictionary={}
static func definitions() -> Dictionary:
    if cache.is_empty():
        cache=JSON.parse_string(FileAccess.get_file_as_string("res://data/zombie_appearances.json")).types
    return cache

static func apply(instance: Node3D,id: String) -> void:
    var types:=definitions()
    assert(types.has(id),"Unknown zombie appearance")
    for mesh in instance.find_children("*","MeshInstance3D",true,false):
        var name:=str(mesh.name)
        if name.begins_with("DD_Variant_"):
            mesh.visible=name.begins_with("DD_Variant_"+id+"_")
        if not name.begins_with("DD_Zombie_Body"):
            continue
        for surface in mesh.mesh.get_surface_count():
            var original: Material=mesh.mesh.surface_get_material(surface)
            if original!=null and original.resource_name.trim_prefix("DD_")=="zshirt":
                mesh.set_surface_override_material(surface,Materials.material(types[id].shirt_material))
