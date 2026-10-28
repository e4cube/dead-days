extends SceneTree
## Headless structural test for the standalone factory scene only.

var failures := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func frame_wait(count: int) -> void:
    for i in count:
        await physics_frame

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/factory_layout.json"))
    check(not layout.is_empty(), "factory layout is valid JSON")
    check(layout.triangles >= 60000, "factory has genuinely detailed geometry")
    check(layout.triangles <= 260000, "factory triangle budget remains bounded")
    check(layout.parts >= 900, "factory is assembled from many authored parts")
    check(layout.groups.size() >= 12, "factory exports separable thematic groups")
    check(layout.colliders.size() >= 45, "factory has a deliberate collision set")

    var instance: Node3D = load("res://assets/factory_grounds.glb").instantiate()
    root.add_child(instance)
    await process_frame
    var meshes := instance.find_children("*", "MeshInstance3D", true, false)
    check(meshes.size() == layout.groups.size(), "one mesh per authored group")
    check(instance.find_children("*", "CollisionObject3D", true, false).is_empty(),
        "GLB owns no duplicated gameplay collision")
    var triangles := 0
    for mesh in meshes:
        check(mesh.mesh != null and mesh.mesh.get_surface_count() > 0,
            "group has renderable surfaces: " + str(mesh.name))
        for surface in mesh.mesh.get_surface_count():
            var arrays: Array = mesh.mesh.surface_get_arrays(surface)
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            if indices.size() > 0:
                triangles += indices.size() / 3
            else:
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                triangles += vertices.size() / 3
        for material_index in mesh.mesh.get_surface_count():
            check(mesh.get_surface_override_material(material_index) != null or
                mesh.mesh.surface_get_material(material_index) != null,
                "surface has a material: " + str(mesh.name))
    check(triangles == int(layout.triangles), "layout triangle count matches imported GLB")
    instance.queue_free()
    await process_frame

    var scene = load("res://factory_grounds.tscn").instantiate()
    root.add_child(scene)
    await frame_wait(14)
    check(is_instance_valid(scene.player), "player is instantiated")
    check(is_instance_valid(scene.camera), "orthographic camera is active")
    check(scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "camera is orthographic")
    check(scene.blocker_bodies.size() == layout.colliders.size() + 1,
        "all authored colliders plus the ground are physical")
    check(scene.player.is_on_floor(), "survivor settles on the yard collision")
    check(not scene.inside(), "spawn is outside the hall")
    check(scene.roof.visible and scene.south_wall.visible, "exterior shows full shell")

    var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
    var clear_query := PhysicsRayQueryParameters3D.create(
        Vector3(2.0, .95, 13.8), Vector3(2.0, .95, 4.4))
    clear_query.collision_mask = 1
    check(space.intersect_ray(clear_query).is_empty(),
        "broken centre bay is actually walkable from gate to hall")
    var blocked_query := PhysicsRayQueryParameters3D.create(
        Vector3(-6.8, .95, 13.8), Vector3(-6.8, .95, -6.0))
    blocked_query.collision_mask = 1
    check(not space.intersect_ray(blocked_query).is_empty(),
        "closed loading-dock wall blocks movement")

    scene.teleport_player(Vector3(1.6, .12, .7))
    await frame_wait(20)
    check(scene.inside(), "interior bounds are detected")
    check(not scene.roof.visible and not scene.south_wall.visible and not scene.east_wall.visible,
        "roof and near walls cut away inside the hall")
    check(scene.camera.size < 16.0, "inside camera tightens to the authored interior size")

    scene.reset_player()
    await frame_wait(4)
    check(not scene.inside(), "reset returns to the gate")
    check(scene.roof.visible and scene.south_wall.visible and scene.east_wall.visible,
        "exterior shell is restored after reset")
    check(scene.player.position.distance_to(Vector3(layout.spawn[0], layout.spawn[1], layout.spawn[2])) < .5,
        "reset returns to the authored spawn")

    scene.queue_free()
    await process_frame
    print("FACTORY_SCENE_OK" if failures == 0 else "FACTORY_SCENE_FAILED")
    quit(0 if failures == 0 else 1)
