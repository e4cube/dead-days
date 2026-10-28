extends SceneTree
## Wiring check for the base panel: the C key must reach the shared expedition UI,
## the door recipe must spend real materials, and the work must advance through
## the live scene loop instead of completing inside the menu.
var game
var failures := 0
func check(ok: bool, text: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", text)
func craft_buttons() -> Array:
    var result := []
    for node in game.expedition.window.find_children("*", "Button", true, false):
        if node.text == "制作":
            result.append(node)
    return result
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    game = load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/base_ui_%d" % Time.get_ticks_usec())
    game.model.rules.zombie_spawns = [] # UI fixture, not a combat claim.
    game.new_run()
    game.player.position = Vector3(-7.0, 0.0, 0.9)
    game.sync_position()
    await physics_frame
    check(game.craft_door() == "home", "front door is the current door target")
    game.model.state.inventory = {"wood_plank": 2, "hammer": 1}
    game.model.state.door_health.home = 40.0
    game.open_craft()
    check(game.expedition.is_open() and game.expedition.kind == "craft", "C opens the shared base panel")
    var buttons := craft_buttons()
    check(buttons.size() >= 2, "door recipes are listed next to the door")
    check(not buttons[0].disabled, "repair is offered while the door is damaged")
    buttons[0].pressed.emit()
    await process_frame
    check(not game.expedition.is_open(), "starting work closes the panel so the world keeps running")
    check(game.model.state.craft.active and game.model.state.craft.recipe == "repair_door", "model records the running repair")
    check(game.model.state.inventory.get("wood_plank", 0) == 0 and game.model.state.inventory.get("hammer", 0) == 1,
        "planks are spent and the hammer is kept")
    for index in 40:
        game.advance_craft(0.25)
    check(not game.model.state.craft.active, "work finishes on its own")
    check(game.model.DoorDamage.health(game.model, "home") == 120.0, "repair restores the door through the live scene")
    check(game.model.state.events.back().kind == "door_repaired", "repair is journalled")
    game.player.position = Vector3(-7.0, 0.0, -2.0)
    game.sync_position()
    game.open_craft()
    check(game.expedition.is_open() and game.expedition.kind == "craft", "base panel opens indoors too")
    var indoor := craft_buttons()
    check(indoor.size() == 2, "only the indoor recipes are listed away from the door")
    check(indoor[0].disabled, "cooking is blocked without ingredients and says why")
    check(indoor[0].tooltip_text == "材料不足：罐头 0/1", "blocked cooking explains the missing ingredient")
    game.expedition.close()
    print("BASE_UI_OK" if failures == 0 else "BASE_UI_FAILED")
    game.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
