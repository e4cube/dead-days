extends SceneTree
## Scene-level check for the villa works: the new containers must actually be
## reachable, an installed gate must own real collision and a navigation block, and
## the pool surface must appear only after the supply is connected. The model rules
## are covered by test_sites_v1.gd; this one proves the scene reads them back.
const GATE := Vector3(106.1, 0.0, -2.5)
const VILLA_DOOR := Vector3(112.85, 0.0, -17.5)
const POOL := Vector3(123.3, 0.0, -10.8)
var game
var failures := 0

func check(ok: bool, text: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", text)

func frames(count: int) -> void:
    for i in count:
        await physics_frame

## Walk a ring around a point and report whether the container is reachable.
func reachable(id: String, around: Vector3, radius := 1.25) -> bool:
    for index in 8:
        var angle := TAU * float(index) / 8.0
        var at := around + Vector3(cos(angle), 0.0, sin(angle)) * radius
        game.teleport_player(Vector3(at.x, 0.12, at.z))
        await frames(2)
        if str(game.nearby().get("id", "")) == id:
            return true
    return false

func solid_at(point: Vector3) -> bool:
    var id: Vector2i = game.navigation.cell(point)
    return game.navigation.grid.is_point_solid(id)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    game = load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/sites_scene_%d" % Time.get_ticks_usec())
    game.model.rules.zombie_spawns = []
    game.new_run()
    await frames(4)

    check(not game.model.site_done("villa_gate"), "a new run starts without a gate")
    check(game.model.state.doors.has("villa_gate") == false, "no gate door before the work")
    check(not game.site_labels.is_empty(), "site labels exist in the scene")
    check(game.water_node != null and not game.water_node.visible, "the pool surface is hidden while dry")

    check(await reachable("factory_pipe_rack", Vector3(153.2, 1.0, 22.0)), "the pipe rack can be reached")
    check(await reachable("factory_gate_stack", Vector3(162.5, 1.0, 27.0)), "the gate stack can be reached")
    check(await reachable("market_hardware_stall", Vector3(73.4, 1.0, -17.4)), "the hardware stall can be reached")

    game.teleport_player(Vector3(106.1, 0.12, 1.6))
    await frames(2)
    check(str(game.nearby().get("id", "")) == "", "an unbuilt yard gate is not an interaction target from the street")
    check(not solid_at(GATE), "the open driveway is walkable before the gate")

    game.model.complete_site("villa_gate")
    game.sync_sites()
    await frames(3)
    var gate: Dictionary = game.gate_nodes.get("villa_gate", {})
    check(not gate.is_empty(), "the gate node exists in the scene")
    check(gate.get("body") != null and gate.body.collision_layer == 1, "a closed gate owns collision")
    check(solid_at(GATE), "a closed gate blocks the navigation grid")
    game.teleport_player(Vector3(106.1, 0.12, -1.35))
    await frames(2)
    check(str(game.nearby().get("id", "")) == "villa_gate", "the installed gate becomes an E target")
    check(game.site_hint("site", "villa_gate").contains("耐久"), "the gate hint shows durability")

    game.use_site("villa_gate")
    await frames(3)
    check(game.model.state.doors.villa_gate, "E opens the gate")
    check(gate.body.collision_layer == 0, "an open gate releases its collision")
    check(not solid_at(GATE), "an open gate reopens the navigation grid")
    game.use_site("villa_gate")
    await frames(3)
    check(not game.model.state.doors.villa_gate and gate.body.collision_layer == 1, "E closes it again")

    game.model.complete_site("villa_door")
    game.sync_sites()
    await frames(3)
    game.teleport_player(Vector3(112.85, 0.12, -16.3))
    await frames(2)
    check(str(game.nearby().get("id", "")) == "villa_door", "the villa front door is an E target")
    check(solid_at(VILLA_DOOR), "the front door blocks the doorway")

    game.model.complete_site("villa_water")
    game.sync_sites()
    await frames(3)
    check(game.water_node.visible, "the pool surface appears once the supply is connected")
    game.teleport_player(Vector3(123.3, 0.12, -7.7))
    await frames(2)
    check(str(game.nearby().get("id", "")) == "villa_water", "the pool is an E target")
    game.model.state.inventory = {}
    game.use_site("villa_water")
    await frames(2)
    check(game.model.state.inventory.get("water", 0) == 1, "E at the pool fills a bottle")
    check(game.model.pool_left() == 2, "the pool spends one unit")

    game.model.state.inventory = {}
    game.set_physics_process(false)
    print("SITES_SCENE_OK" if failures == 0 else "SITES_SCENE_FAILED")
    game.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
