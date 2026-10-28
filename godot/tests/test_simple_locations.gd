extends SceneTree
## Structural test for the three lightweight standalone locations only.

var failures := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func wait_frames(count: int) -> void:
    for i in count:
        await physics_frame

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/simple_locations.json"))
    var ids := ["track_field", "market_square", "villa_courtyard"]
    check(data.get("locations", {}).size() == ids.size(), "three locations are declared")
    for id in ids:
        check(data.locations.has(id), "layout exists: " + id)
        if not data.locations.has(id):
            continue
        var info: Dictionary = data.locations[id]
        check(info.asset == id, "asset id matches layout: " + id)
        check(info.triangles > 2000 and info.triangles < 40000, "bounded triangle budget: " + id)
        check(info.colliders.size() >= 10, "explicit collision set: " + id)
        var packed: PackedScene = load("res://assets/" + id + ".glb")
        check(packed != null, "imported GLB: " + id)
        if packed == null:
            continue
        var instance: Node3D = packed.instantiate()
        root.add_child(instance)
        await process_frame
        var meshes := instance.find_children("*", "MeshInstance3D", true, false)
        check(meshes.size() >= 1, "renderable static mesh per location: " + id)
        check(instance.find_children("*", "CollisionObject3D", true, false).is_empty(),
            "GLB owns no duplicate collision: " + id)
        var triangles := 0
        for mesh in meshes:
            for surface in mesh.mesh.get_surface_count():
                var arrays: Array = mesh.mesh.surface_get_arrays(surface)
                var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
                triangles += indices.size() / 3 if indices.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size() / 3
        check(triangles == int(info.triangles), "triangle count matches layout: " + id)
        instance.queue_free()
        await process_frame

        var scene = load("res://locations/" + id + ".tscn").instantiate()
        check(scene.location_id == id, "scene location id: " + id)
        root.add_child(scene)
        await wait_frames(8)
        check(is_instance_valid(scene.player), "player exists: " + id)
        check(is_instance_valid(scene.camera), "camera exists: " + id)
        check(scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic camera: " + id)
        var extra: int = info.get("ramps", []).size()
        if info.has("stair_wedge"):
            extra += 1
        check(scene.collider_bodies.size() == info.colliders.size() + extra + 1,
            "all colliders, ramps and ground: " + id)
        check(scene.player.is_on_floor(), "player settles on ground: " + id)
        var spawn: Array = info.spawn
        check(scene.player.position.distance_to(Vector3(spawn[0], spawn[1], spawn[2])) < .4,
            "player spawns at authored point: " + id)
        scene.reset_player()
        await wait_frames(2)
        check(scene.player.position.distance_to(Vector3(spawn[0], spawn[1], spawn[2])) < .4,
            "reset returns to spawn: " + id)
        scene.queue_free()
        await process_frame
    print("SIMPLE_LOCATIONS_OK" if failures == 0 else "SIMPLE_LOCATIONS_FAILED")
    quit(0 if failures == 0 else 1)
