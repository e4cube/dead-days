extends SceneTree
## Production map/rules/spawns. Input-driven path into the house and bed, no player teleport or clock assignment.
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

func frames(n: int) -> void:
    for i in n:
        await physics_frame

func walk(action: String, n: int) -> void:
    Input.action_press(action)
    await frames(n)
    Input.action_release(action)
    await physics_frame

func finish_rest(max_frames: int) -> void:
    for i in max_frames:
        if not game.model.state.rest.active:
            return
        await physics_frame
    check(false, "rest completed within bounded frame count")

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
    game.store = load("res://scripts/save_store.gd").new("user://tests/sleep_play_%d" % Time.get_ticks_usec())
    game.export_directory = game.store.directory + "/exports"
    game.menu.get_child(1).pressed.emit()
    await walk("forward", 24)
    key(KEY_E)
    check(game.model.state.doors.home, "open home from street")
    await walk("forward", 42)
    key(KEY_E)
    check(game.inside("home") and not game.model.state.doors.home, "enter and secure bedroom")
    await walk("forward", 12)
    key(KEY_E)
    check(game.model.state.inventory.get("food", 0) == 2, "loot actual provisions")
    key(KEY_1)
    key(KEY_2)
    key(KEY_4)
    var goal := Vector2(-8.5,-1.9)
    for i in 300:
        for action in ["left","right","forward","back"]:
            Input.action_release(action)
        var difference: Vector2 = goal-Vector2(game.player.position.x,game.player.position.z)
        if difference.length()<.075:
            break
        preload("res://tests/movement_driver.gd").drive(game,difference)
        await physics_frame
    for action in ["left","right","forward","back"]:
        Input.action_release(action)
    check(game.closest_bed() == "home_bed", "walk to usable bed without teleport")
    var start: float = game.model.state.minutes
    key(KEY_T)
    check(not game.model.state.rest.active and game.model.state.minutes == start, "daytime sleep-to-dawn rejected without advancing time")
    var patrol_before: float = game.model.state.zombies[0].patrol_index
    var hunger_before: float = game.model.state.stats.hunger
    var thirst_before: float = game.model.state.stats.thirst
    # Daytime short rests move the real world toward evening; no artificial clock assignment.
    for i in 14:
        if game.model.state.minutes >= game.model.rules.time.night_full:
            break
        key(KEY_R)
        check(game.model.state.rest.active, "short rest starts safely")
        await finish_rest(240)
    check(game.model.state.minutes >= 1200 and game.Timeline.daylight(game.model) == 0, "short rests reach real night")
    check(game.sun.light_energy < 0.2, "night changes actual world light")
    check(game.model.state.zombies[0].patrol_index > patrol_before + 20, "zombie world simulation runs throughout rest")
    key(KEY_T)
    check(game.model.state.rest.active, "sleep until dawn now permitted")
    await frames(30)
    await screenshot("c2-night")
    game.sync_position()
    var expected: Dictionary = JSON.parse_string(JSON.stringify(game.model.state))
    key(KEY_F5)
    key(KEY_ESCAPE)
    check(not game.active and expected.rest.active, "save and exit mid-sleep")
    var saved_minutes: float = game.model.state.minutes
    await frames(20)
    check(game.model.state.minutes == saved_minutes, "menu does not advance rest")
    game.menu.get_child(2).pressed.emit()
    if game.model.state!=expected:
        for id in expected:
            if game.model.state.get(id)!=expected[id]:
                printerr("RESTORE_DIFF ",id," expected=",JSON.stringify(expected[id])," actual=",JSON.stringify(game.model.state.get(id)))
    check(game.model.state == expected, "continue restores in-progress rest clock target stats and enemies")
    await finish_rest(900)
    check(game.model.state.day == 2 and absf(game.model.state.minutes - 360) < 0.2, "wake at second-day dawn")
    check(game.model.state.stats.hunger < hunger_before - 15 and game.model.state.stats.thirst < thirst_before - 20, "rest consumes real nutrition and water")
    check(game.model.state.inventory.food == 1 and game.model.state.inventory.water == 0 and game.model.state.containers.home.food == 0, "supplies remain consumed and looted across night")
    var summaries := 0
    for event in game.model.state.events:
        if event.kind == "daily_summary":
            summaries += 1
            check(event.payload.looted == 4 and event.payload.entered == 1 and event.payload.used == 2 and event.payload.kills == 0, "day summary reflects actual playthrough")
    check(summaries == 1, "midnight summarized exactly once")
    await screenshot("c2-dawn")
    key(KEY_J)
    check("第1天总结" in game.journal_text.text and "睡到了黎明" in game.journal_text.text, "survival diary contains second-day outcome")
    await process_frame
    game.journal_text.get_v_scroll_bar().value = game.journal_text.get_v_scroll_bar().max_value
    await screenshot("c2-journal")
    game.export_button.pressed.emit()
    var files := DirAccess.open(game.export_directory).get_files()
    check(files.size() == 1 and "第1天总结" in FileAccess.get_file_as_string(game.export_directory.path_join(files[0])), "daily summary exported to real Markdown")
    key(KEY_J)
    game.sync_position()
    expected = JSON.parse_string(JSON.stringify(game.model.state))
    key(KEY_ESCAPE)
    game.menu.get_child(2).pressed.emit()
    check(game.model.state == expected and game.model.state.calendar.last_summary_day == 1, "second-day world resumes without duplicated summary")
    print("SLEEP_PLAYTHROUGH_OK" if failures == 0 else "SLEEP_PLAYTHROUGH_FAILED")
    game.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
