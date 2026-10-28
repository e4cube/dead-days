extends SceneTree
var game
var failures := 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func frames(n: int) -> void:
    for i in n:
        await physics_frame

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/visual_%d" % Time.get_ticks_usec())
    game.new_run()
    game.active = false
    await frames(2)
    var roof = game.building_visuals.home.find_children("DD_Hide_Roof*", "MeshInstance3D", true, false)[0]
    check(roof.visible, "outside has full building exterior")
    game.player.position = Vector3(-7, 0, -1.5)
    game.update_cutaways()
    check(not roof.visible, "inside hides roof for isometric camera")
    var other_roof = game.building_visuals.shop.find_children("DD_Hide_Roof*", "MeshInstance3D", true, false)[0]
    check(other_roof.visible, "other buildings retain exterior")
    game.model.state.doors.home = false
    game.apply_door("home")
    await frames(2)
    check(game.doors.home.collision_layer == 1 and game.open_leaves.home.collision_layer == 0, "closed door collision contract")
    check(game.line_clear(Vector3(-9,0,.9),Vector3(-7,0,.9)), "closed door leaves street side clear")
    game.model.state.doors.home = true
    game.apply_door("home")
    game.navigation.rebuild(game.nav_sources, game.model.rules.navigation)
    await frames(2)
    check(game.doors.home.collision_layer == 0 and game.open_leaves.home.collision_layer == 1, "open door has swept leaf collision")
    check(not game.line_clear(Vector3(-9,0,.9),Vector3(-7,0,.9)), "open visual leaf actually blocks physical ray")
    check(absf(game.door_visuals.home.rotation.y + PI / 2) < .001, "door visual turns around hinge")
    # Old snapshots that intersect a newly added table move to a nearby free point in memory only.
    game.model.state.position = [-5.3,0,-3.7]
    var original: String = game.store.save(game.model)
    check(not original.is_empty(), "fixture source saved")
    var bytes := FileAccess.get_file_as_bytes(original)
    game.continue_run()
    game.active = false
    check(game.player.position.distance_to(Vector3(-5.3,0,-3.7)) > .5, "new table cannot trap restored player")
    check(game.model.state.events.back().kind == "layout_adjusted", "layout correction is explained")
    check(FileAccess.get_file_as_bytes(original) == bytes, "layout correction never overwrites source save")
    game.model.state.combat.attack_cd = 0
    game.model.state.stats.stamina = 100
    game.active = true
    game.try_attack()
    game.update_player_visual(.1)
    check(game.player_visual.current_action == "attack", "actual accepted attack selects exported clip")
    game.model.damage_player(10,"visual_test")
    game.update_player_visual(.1)
    check(game.player_visual.current_action == "hurt", "real wound selects hurt clip")
    game.model.state.combat.hurt_cd = 0
    game.model.damage_player(100,"visual_test")
    game.update_player_visual(0)
    check(game.player_visual.current_action == "death", "real death selects terminal pose")
    game.model.damage_zombie(game.zombie_bodies[0].record, 100)
    game.zombie_bodies[0].update_visual(0)
    check(game.zombie_bodies[0].visual_root.current_action == "death" and game.zombie_bodies[0].collision_layer == 0, "corpse visual and mechanics agree")
    print("VISUAL_INTEGRATION_OK" if failures == 0 else "VISUAL_INTEGRATION_FAILED")
    game.queue_free()
    for i in 3: await process_frame
    quit(0 if failures == 0 else 1)
