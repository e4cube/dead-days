extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/ground_%d" % Time.get_ticks_usec())
    game.new_run()
    game.active = false
    var ground: StaticBody3D = game.world.get_node("OutdoorGround")
    var meshes := ground.find_children("*", "MeshInstance3D", true, false)
    var material: StandardMaterial3D = meshes[0].material_override
    check(material.albedo_texture != null and material.albedo_texture.get_width() == 1024, "reviewed 1K map actually loads")
    check(material.uv1_triplanar and material.uv1_world_triplanar, "world projection prevents stretched box UVs")
    check(material.normal_enabled == false and material.roughness == 1.0, "base-color-only source does not invent PBR maps")
    var collider: CollisionShape3D = ground.find_children("*", "CollisionShape3D", true, false)[0]
    check(collider.shape.size == Vector3(27,.5,19) and ground.position == Vector3(0,-.25,-1), "original walkable collider is unchanged")
    for building in game.building_visuals.values():
        for mesh in building.find_children("*", "MeshInstance3D", true, false):
            check(mesh.material_override != material, "building surfaces retain original materials")
    game.model.state.minutes = 720
    game.update_lighting()
    for i in 4:
        await process_frame
    if DisplayServer.get_name() != "headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/gamevado-ground-day.png"))
    game.model.state.minutes = 1320
    game.update_lighting()
    for i in 4:
        await process_frame
    if DisplayServer.get_name() != "headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/gamevado-ground-night.png"))
    print("GAMEVADO_GROUND_OK" if failures == 0 else "GAMEVADO_GROUND_FAILED")
    quit(0 if failures == 0 else 1)
