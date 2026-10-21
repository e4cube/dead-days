extends SceneTree
const Rest = preload("res://scripts/rest.gd")
var game
var failures := 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func frames(n: int) -> void:
    for i in n:
        await physics_frame

func fixture(zombies: Array) -> void:
    game.model.rules.zombie_spawns = zombies
    game.new_run()
    game.active = false
    game.player.position = Vector3(-8.5, 0, -2)
    game.sync_position()
    game.model.state.minutes = 1080
    await frames(2)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/rest_safety_%d" % Time.get_ticks_usec())
    await fixture([{"id": "approach", "position": [-8.5, 0, 4.0]}])
    var z = game.zombie_bodies[0]
    z.record.target = [-8.5, 0, 0.8]
    z.record.patrol_left = 4
    game.request_rest("night")
    check(game.model.state.rest.active, "rest begins before wandering threat reaches safety radius")
    var start: float = game.model.state.minutes
    for i in 120:
        game.advance_rest(1.0 / 60.0)
        await physics_frame
        if not game.model.state.rest.active:
            break
    check(not game.model.state.rest.active and game.model.state.day == 1 and game.model.state.minutes < start + 10, "real moving threat interrupts before any jump to dawn")
    check(z.position.z < 3.1, "enemy actually moves in accelerated rest world")
    check(game.model.state.events.back().kind == "sleep_danger", "actual danger produces sleep incident log")
    var before: float = game.model.state.minutes
    game.request_rest("night")
    check(not game.model.state.rest.active and game.model.state.minutes == before, "cannot immediately sleep away nearby threat")
    await fixture([])
    game.model.state.doors.home = true
    game.apply_door("home")
    game.request_rest("night")
    check(not game.model.state.rest.active, "open door blocks physical bedroom rest")
    game.model.state.doors.home = false
    game.apply_door("home")
    game.request_rest("night")
    check(game.model.state.rest.active, "safe fixture begins")
    game.model.state.doors.home = true
    game.apply_door("home")
    before = game.model.state.minutes
    game.advance_rest(1.0 / 60.0)
    check(not game.model.state.rest.active and game.model.state.minutes == before, "safety rechecked before each time step")
    await fixture([])
    game.request_rest("hour")
    game.active = true
    var paused: float = game.model.state.minutes
    game.open_panel("journal")
    await frames(12)
    check(game.model.state.minutes == paused and game.model.state.rest.active, "journal pauses time and sleep together")
    game.close_panel()
    Input.action_press("left")
    await frames(2)
    Input.action_release("left")
    check(not game.model.state.rest.active and game.model.state.minutes < paused + 1, "movement wakes player without fast-forward exploitation")
    print("REST_SAFETY_OK" if failures == 0 else "REST_SAFETY_FAILED")
    game.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
