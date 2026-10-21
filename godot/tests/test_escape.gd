extends SceneTree
## No player/enemy teleportation: approach noise -> pursuit -> house -> closed door -> lose target -> save/continue.
var game
var failures := 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func key(code: int) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    game._unhandled_key_input(event)

func frames(count: int) -> void:
    for i in count:
        await physics_frame

func walk(action: String, count: int, sprint: bool = false) -> void:
    Input.action_press(action)
    if sprint:
        Input.action_press("run")
    await frames(count)
    Input.action_release(action)
    Input.action_release("run")
    await physics_frame

func has_event(kind: String) -> bool:
    for event in game.model.state.events:
        if event.kind == kind:
            return true
    return false

func screenshot(name: String) -> void:
    if DisplayServer.get_name() != "headless":
        await process_frame
        await process_frame
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/" + name + ".png"))

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/escape_%d" % Time.get_ticks_usec())
    # Two deterministic blind-facing street enemies; geometry, player spawn and rules are unchanged.
    game.model.rules.zombie_spawns = [{"id": "pursuer", "position": [-7, 0, 7]}, {"id": "follower", "position": [-5.8, 0, 7]}]
    game.menu.get_child(1).pressed.emit()
    # Make both face away before the first physics update. This isolates hearing from vision.
    for actor in game.zombie_bodies:
        actor.rotation.y = 0
        actor.record.heading = 0
    await frames(2)
    check(game.zombie_bodies[0].record.mode == "wander", "unseen player is not automatically tracked")
    await walk("forward", 12, true)
    check(game.model.state.noise_sequence > 0, "sprinting emits real position sound")
    check(game.zombie_bodies[0].record.last_noise > 0, "blind-facing zombie heard sprint")
    await frames(65)
    var chasing := false
    for actor in game.zombie_bodies:
        chasing = chasing or actor.record.mode == "chase"
    check(chasing, "investigation leads to visual chase")
    await screenshot("c1-pursuit")
    key(KEY_E)
    check(game.model.state.doors.home, "open house during pursuit")
    await walk("forward", 25, true)
    check(game.inside("home"), "physically enter house while pursued")
    key(KEY_E)
    check(not game.model.state.doors.home, "close door from inside")
    await walk("forward", 16)
    key(KEY_E)
    check(game.model.state.inventory.get("club", 0) == 1, "loot melee weapon in house")
    key(KEY_4)
    check(game.model.state.combat.equipped == "club", "equip from actual inventory")
    var hp: float = game.model.state.stats.health
    var heard_target: Array = game.zombie_bodies[0].record.target.duplicate()
    await frames(90)
    check(game.zombie_bodies[0].record.mode == "search", "closed door turns pursuit into search")
    check(not game.zombie_bodies[0].sees_player(), "closed door blocks actual sight")
    check(game.zombie_bodies[0].record.target == heard_target, "hidden movement does not update last known target")
    check(game.zombie_bodies[0].position.z > 0.3, "closed door stops zombie physical passage")
    # Save while memory and noise cooldowns are live, not only after everything is idle.
    game.sync_position()
    var expected: Dictionary = JSON.parse_string(JSON.stringify(game.model.state))
    key(KEY_ESCAPE)
    check(not game.active, "save pursued world and return to menu")
    game.menu.get_child(2).pressed.emit()
    check(game.model.state == expected, "continue restores enemies, memory, doors, weapon and player state")
    var lost := false
    # Bound the wait by search memory + lifetime of any sound already in the snapshot.
    for i in 540:
        await physics_frame
        lost = true
        for actor in game.zombie_bodies:
            lost = lost and actor.record.mode == "wander"
        if lost:
            break
    check(lost, "finite search expires without omniscient tracking")
    check(game.model.state.stats.health == hp, "wall blocks attacks during search")
    check(has_event("first_zombies") and has_event("escaped"), "journal records actual discovery and lost pursuit")
    var escapes := 0
    for event in game.model.state.events:
        if event.kind == "escaped":
            escapes += 1
    check(escapes == 1, "one group escape event instead of duplicate zombie prose")
    key(KEY_J)
    check("停止了追击" in game.journal_text.text, "escape appears in visible journal")
    await screenshot("c1-journal")
    key(KEY_J)
    await screenshot("c1-escape")
    print("ESCAPE_PLAYTHROUGH_OK" if failures == 0 else "ESCAPE_PLAYTHROUGH_FAILED")
    game.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
