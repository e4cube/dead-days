extends SceneTree
var failures:=0
func check(value: bool,message: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var library=preload("res://scripts/material_library_v1.gd")
    var definitions: Dictionary=library.definitions()
    for alias in definitions.aliases:
        check(definitions.materials.has(definitions.aliases[alias]),"valid alias "+alias)
    for id in ["asphalt","concrete","old_wood","rust","metal","cloth","canvas","denim"]:
        var material: StandardMaterial3D=library.material(id)
        check(material==library.material(id),"shared material, not per-instance allocation "+id)
        check(material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null,"actual PBR maps "+id)
        check(material.normal_enabled and material.uv1_triplanar,"metre-scaled mapped surface "+id)
    check(library.material("metal").metallic>.7 and library.material("old_wood").metallic==0,"metal/wood response differs")
    var visual=load("res://scripts/character_visual.gd").new()
    root.add_child(visual)
    visual.setup("player")
    var canvas:=false
    for mesh in visual.instance.find_children("*","MeshInstance3D",true,false):
        for i in mesh.mesh.get_surface_count():
            var material: Material=mesh.get_surface_override_material(i)
            canvas=canvas or (material!=null and material.resource_name=="DD_PBR_canvas")
    check(canvas,"live skinned player actually wears canvas recipe")
    visual.queue_free()
    print("MATERIAL_LIBRARY_V1_OK" if failures==0 else "MATERIAL_LIBRARY_V1_FAILED")
    quit(0 if failures==0 else 1)
