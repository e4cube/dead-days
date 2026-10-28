extends SceneTree

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
    var district: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/district_layout.json"))
    var modules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/simple_locations.json")).locations
    check(district.get("placements", []).size() == 4, "district contains three modules and commons")
    check(district.get("villa", {}).has("inside_bounds"), "villa declares interior bounds")
    check(district.get("villa", {}).has("cutaway"), "villa declares cutaway groups")
    var expected_colliders: int = 1 + int(district.commons_colliders.size())
    for placement in district.placements:
        var asset := str(placement.asset)
        if asset == "district_commons":
            continue
        check(modules.has(asset), "module layout exists: " + asset)
        if modules.has(asset):
            expected_colliders += modules[asset].colliders.size()
            expected_colliders += modules[asset].get("ramps", []).size()
            if modules[asset].has("stair_wedge"):
                expected_colliders += 1

    var scene = load("res://locations/district_07.tscn").instantiate()
    root.add_child(scene)
    await wait_frames(12)
    check(is_instance_valid(scene.player), "player exists")
    check(is_instance_valid(scene.camera), "camera exists")
    check(scene.collider_bodies.size() == expected_colliders, "district collision set")
    check(scene.player.is_on_floor(), "player lands on street")
    check(not scene.inside_villa(), "spawn is outside villa")
    check(is_instance_valid(scene.villa_instance), "villa module instantiated")
    check(is_instance_valid(scene.villa_roof), "villa roof group found")

    var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
    var clear_query := PhysicsRayQueryParameters3D.create(
        Vector3(22.8, .95, 22.5), Vector3(22.8, .95, 2.0))
    clear_query.collision_mask = 1
    check(space.intersect_ray(clear_query).is_empty(),
        "street -> villa gate -> front door is physically open")
    var blocked_query := PhysicsRayQueryParameters3D.create(
        Vector3(28.0, .95, 22.5), Vector3(28.0, .95, 2.0))
    blocked_query.collision_mask = 1
    check(not space.intersect_ray(blocked_query).is_empty(),
        "villa front glass blocks movement")

    # Enter the villa at its world-space living-room point.
    scene.teleport_player(Vector3(26.0, .12, .5))
    await wait_frames(14)
    check(scene.inside_villa(), "villa interior detected")
    check(not scene.villa_roof.visible, "villa roof cut away inside")
    check(not scene.villa_front.visible, "villa front wall cut away inside")
    check(not scene.villa_east.visible, "villa east wall cut away inside")
    check(not scene.villa_upper.visible, "upper floor hidden while downstairs")
    scene.teleport_player(Vector3(26.0, 3.70, .5))
    scene.player.velocity = Vector3.ZERO
    await wait_frames(10)
    check(scene.upper_state, "upper floor detected")
    check(scene.villa_upper.visible, "upper floor visible upstairs")
    check(not scene.villa_roof.visible, "roof remains cut away upstairs")

    scene.teleport_player(Vector3(20.40, .12, 4.10))
    var stair_event := InputEventKey.new()
    stair_event.keycode = KEY_E
    stair_event.pressed = true
    scene._unhandled_input(stair_event)
    await wait_frames(4)
    check(scene.player.position.y > 2.7, "district stairs E reaches the upper floor")
    scene._unhandled_input(stair_event)
    await wait_frames(4)
    check(scene.player.position.y < 1.2, "district stairs E returns to the ground floor")

    scene.teleport_player(Vector3(0.0, .12, 24.0))
    await wait_frames(10)
    check(not scene.inside_villa(), "street point is outside villa")
    check(scene.villa_roof.visible, "villa roof restored outside")

    scene.reset_player()
    await wait_frames(4)
    var spawn: Array = district.spawn
    check(scene.player.position.distance_to(Vector3(spawn[0], spawn[1], spawn[2])) < .5,
        "reset returns to district gate")

    scene.queue_free()
    await process_frame
    print("DISTRICT_07_OK" if failures == 0 else "DISTRICT_07_FAILED")
    quit(0 if failures == 0 else 1)
