extends SceneTree
## Documentation screenshot for the save-slot menu. Writes snapshots into a
## throwaway slot root, never into the player's real saves.
const Model = preload("res://scripts/survival.gd")
const Slots = preload("res://scripts/save_slots.gd")
var game

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1152,720)
    var slots = Slots.new("user://tests/menu_preview_%d" % Time.get_ticks_usec())
    var model = Model.new()
    model.start()
    model.state.zombies = []
    model.state.minutes = 8.0 * 60.0 + 5.0
    model.state.stats.health = 88.0
    model.state.inventory = {"water": 2, "food": 1}
    slots.store(1).save(model)
    model.state.minutes = 19.0 * 60.0 + 40.0
    model.state.stats.health = 34.0
    slots.store(2).save(model)
    slots.backup(1, model)

    game=load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.slots = slots
    game.store = slots.store(1)
    game.refresh_menu_slots()
    for i in 8:
        await process_frame
    var image:=root.get_texture().get_image()
    var path:=ProjectSettings.globalize_path("res://../docs/shots/save-slots-menu.png")
    print("MENU_PREVIEW_SAVED ",image.save_png(path)==OK," ",path)
    quit()
