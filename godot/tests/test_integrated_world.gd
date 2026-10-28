extends SceneTree

var game
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
    game = load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/integrated_%d" % Time.get_ticks_usec())
    game.export_directory = game.store.directory + "/exports"
    game.model.rules.zombie_spawns=[] # Geometry/rest fixture; density/combat tested separately.
    game.new_run()
    await wait_frames(14)
    check(game.active, "integrated world starts")
    check(is_instance_valid(game.player), "player exists")
    check(is_instance_valid(game.commons_instance), "district commons attached")
    check(is_instance_valid(game.track_instance), "track attached")
    check(is_instance_valid(game.market_instance), "market attached")
    check(is_instance_valid(game.villa_instance), "villa attached")
    check(is_instance_valid(game.factory_instance), "factory attached")
    check(is_instance_valid(game.villa_upper), "two-storey upper group found")
    check(is_instance_valid(game.factory_roof), "factory cutaway found")

    var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
    var east := PhysicsRayQueryParameters3D.create(Vector3(33.0, 1.0, 3.0),
        Vector3(45.0, 1.0, 3.0))
    east.collision_mask = 1
    check(space.intersect_ray(east).is_empty(), "old east boundary is open to District 07")
    var west_gate := PhysicsRayQueryParameters3D.create(Vector3(39.0, 1.0, 3.0),
        Vector3(43.0, 1.0, 3.0))
    west_gate.collision_mask = 1
    check(space.intersect_ray(west_gate).is_empty(), "district west gate is passable")
    var factory_gate := PhysicsRayQueryParameters3D.create(Vector3(170.0, 1.0, 5.0),
        Vector3(170.0, 1.0, 1.0))
    factory_gate.collision_mask = 1
    check(space.intersect_ray(factory_gate).is_empty(), "factory gate is passable")
    var shop_door := PhysicsRayQueryParameters3D.create(Vector3(67.0, 1.0, -7.8),
        Vector3(67.0, 1.0, -10.6))
    shop_door.collision_mask = 1
    check(space.intersect_ray(shop_door).is_empty(), "market shop front is enterable")

    # Walk up the physical stair wedge, then verify the upper-level cutaway.
    game.set_physics_process(false)
    game.player.position = Vector3(110.40, .16, -17.90)
    game.player.velocity = Vector3.ZERO
    for i in 240:
        game.player.velocity = Vector3(0, -1.2, -3.0)
        game.player.move_and_slide()
        await physics_frame
    check(game.player.position.y > 2.7, "physical stair walk reaches the second floor")
    game.set_physics_process(true)
    game.player.position = Vector3(116.0, 3.70, -22.0)
    game.player.velocity = Vector3.ZERO
    game.update_cutaways()
    game.update_camera(0.0)
    check(game.villa_upper.visible, "upper floor visible upstairs")
    check(not game.villa_roof.visible, "villa roof cut away upstairs")

    var district_path: PackedVector3Array = game.navigation.path(
        Vector3(0, 0, 4), Vector3(90, 0, 4))
    check(district_path.size() > 0, "zombie navigation reaches District 07")
    var factory_path: PackedVector3Array = game.navigation.path(
        Vector3(0, 0, 4), Vector3(170, 0, 10))
    check(factory_path.size() > 0, "zombie navigation reaches the factory")

    # The upstairs bed is a real rest point, not a decorative prop.
    game.player.position = Vector3(119.55, 3.62, -24.78)
    game.player.velocity = Vector3.ZERO
    game.sync_position()
    await physics_frame
    check(game.closest_bed() == "villa_upstairs_bed", "upstairs bed is detected")
    game.request_rest("hour")
    check(game.model.state.rest.active, "upstairs bed starts rest")
    game.request_rest("hour")

    # Custom search points: villa, market and factory.
    for id in ["villa_fridge", "market_produce_a", "market_shop_counter", "factory_toolchest"]:
        check(game.model.rules.containers.any(func(c): return c.id == id),
            "custom container registered: " + id)
        check(game.model.state.containers.has(id), "custom container state: " + id)

    var looted := 0
    for check_data in [
        {"at": Vector3(115.95, .12, -25.20), "id": "villa_fridge"},
        {"at": Vector3(57.50, .12, -17.40), "id": "market_produce_a"},
        {"at": Vector3(67.00, .12, -25.20), "id": "market_shop_counter"},
        {"at": Vector3(163.65, .12, 18.80), "id": "factory_toolchest"},
    ]:
        game.player.position = check_data.at
        game.player.velocity = Vector3.ZERO
        game.model.state.inventory.clear()
        await physics_frame
        var target: Dictionary = game.nearby()
        check(str(target.get("id", "")) == check_data.id,
            "nearby search target: " + check_data.id + " got " + str(target))
        var before: float = game.model.weight()
        game.interact()
        if game.model.weight() > before:
            looted += 1
    check(looted == 4, "looted from villa, market, shop and factory")

    game.queue_free()
    await process_frame
    print("INTEGRATED_WORLD_OK" if failures == 0 else "INTEGRATED_WORLD_FAILED")
    quit(0 if failures == 0 else 1)
