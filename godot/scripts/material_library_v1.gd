extends RefCounted
## Shared sRGB factors with the Blender pipeline. Cached per ID, never per instance.
static var library: Dictionary = {}
static var cache: Dictionary = {}
static func definitions() -> Dictionary:
    if library.is_empty():
        library=JSON.parse_string(FileAccess.get_file_as_string("res://data/material_library_v1.json"))
    return library
static func material(id: String) -> StandardMaterial3D:
    if not cache.has(id):
        var recipe: Dictionary=definitions().materials[id]
        var value:=StandardMaterial3D.new()
        value.resource_name="DD_PBR_"+id
        value.albedo_color=Color(recipe.color)
        value.roughness=recipe.roughness
        value.metallic=recipe.metallic
        var paths: Dictionary=definitions().textures
        var family: String=paths.families.get(recipe.category,"")
        if not family.is_empty():
            value.albedo_color=Color.WHITE
            value.albedo_texture=load("res://"+str(paths.base_color).replace("{id}",id))
            value.roughness_texture=load("res://"+str(paths.roughness).replace("{id}",id))
            value.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
            value.roughness=1.0
            value.normal_enabled=true
            value.normal_texture=load("res://"+str(paths.normal).replace("{family}",family))
            value.normal_scale=float(recipe.get("normal_strength",definitions().render.normal_strength))
            value.uv1_triplanar=true
            value.uv1_scale=Vector3.ONE/float(recipe.scale_m)
        cache[id]=value
    return cache[id]
static func apply(instance: Node3D) -> void:
    var aliases: Dictionary=definitions().aliases
    for mesh in instance.find_children("*","MeshInstance3D",true,false):
        if mesh.mesh==null:
            continue
        for i in mesh.mesh.get_surface_count():
            var imported: Material=mesh.mesh.surface_get_material(i)
            if imported==null:
                continue
            var name:=imported.resource_name.trim_prefix("DD_")
            if aliases.has(name):
                mesh.set_surface_override_material(i,material(aliases[name]))
