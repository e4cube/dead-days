extends SceneTree
## Runs actual menu buttons, key events and CharacterBody3D physics; no teleporting into rooms.
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

func walk(action: String, frames: int) -> void:
    Input.action_press(action)
    for i in frames:
        await physics_frame
    Input.action_release(action)
    await physics_frame

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/play_%d" % Time.get_ticks_usec())
    game.export_directory = game.store.directory + "/exports"
    check(game.menu.visible and not game.active, "starts at menu")
    game.menu.get_child(1).pressed.emit()
    await physics_frame
    check(game.active, "menu new game")
    await walk("forward", 50)
    check(game.player.position.z > 0.25, "closed door blocks passage")
    key(KEY_E)
    check(game.model.state.doors.home, "interaction opens door")
    await walk("forward", 45)
    check(game.inside("home"), "physical movement enters room")
    check("home" in game.model.state.visited, "entry produces event")
    key(KEY_E)
    check(game.model.state.inventory.get("food", 0) == 2, "container looted via E")
    key(KEY_I)
    check(game.panel.visible and "罐头" in game.journal_text.text, "inventory shows actual items")
    game.inventory_actions.get_child(0).pressed.emit()
    key(KEY_I)
    check(game.model.state.inventory.food == 1 and game.model.state.stats.hunger == 95, "use through inventory button")
    key(KEY_J)
    game.entry.text = "我进屋找到了罐头。"
    game.mood.select(3)
    game.write_button.pressed.emit()
    check(game.model.state.events.back().kind == "manual", "manual journal button")
    check("第一次进入住宅" in game.journal_text.text and "获得 3 件" in game.journal_text.text, "event-grounded journal visible")
    game.export_button.pressed.emit()
    var exports := DirAccess.open(game.export_directory).get_files()
    check(exports.size() == 1, "Markdown file exported")
    check("我进屋找到了罐头" in FileAccess.get_file_as_string(game.export_directory.path_join(exports[0])), "manual note in actual export")
    key(KEY_J)
    # Leave room, close door and walk to the clinic carrying remaining supplies.
    await walk("back", 50)
    key(KEY_E)
    check(not game.model.state.doors.home, "door closes from outside")
    await walk("back", 20)
    await walk("right", 140)
    check(absf(game.player.position.x) < 0.4 and game.model.state.inventory.food == 1, "carry inventory to another building")
    await walk("forward", 20)
    key(KEY_E)
    check(game.model.state.doors.clinic, "clinic door opens")
    await walk("forward", 45)
    check(game.inside("clinic"), "enter second building")
    key(KEY_E)
    check(game.model.state.inventory.get("bandage", 0) == 3, "second container unique contents")
    game.sync_position()
    var expected: Dictionary = game.model.state.duplicate(true)
    key(KEY_ESCAPE)
    check(not game.active and game.menu.visible, "save exit to menu")
    game.menu.get_child(2).pressed.emit()
    # Compare immediately before another physics tick modifies stamina or settles position.
    check(game.active and game.model.state == JSON.parse_string(JSON.stringify(expected)), "continue restores entire state")
    await process_frame
    await process_frame
    if not DisplayServer.get_name() == "headless":
        var image := root.get_texture().get_image()
        image.save_png(ProjectSettings.globalize_path("res://../work/playthrough.png"))
    print("PLAYTHROUGH_OK" if failures == 0 else "PLAYTHROUGH_FAILED")
    game.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
