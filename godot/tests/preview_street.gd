extends SceneTree
var game
func frames(count: int) -> void:
    for i in count:
        await physics_frame
func shot(name: String) -> void:
    for i in 3:
        await process_frame
    if DisplayServer.get_name() != "headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/"+name+".png"))
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    game=load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.new_run()
    Input.action_press("back")
    await frames(20)
    Input.action_release("back")
    Input.action_press("right")
    await frames(140)
    Input.action_release("right")
    await frames(2)
    if absf(game.player.position.x)>.3:
        printerr("FAIL: street art obstructs actual cross-street walking")
        quit(1)
        return
    var wheel := InputEventMouseButton.new()
    wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN
    wheel.pressed=true
    for i in 5:
        game._unhandled_input(wheel)
    await shot("street-day-gameplay")
    # Explicit lighting fixture, NOT a claim of an overnight playthrough.
    game.active=false
    game.model.state.minutes=1320
    game.update_lighting()
    game.refresh_hud()
    await shot("street-night-lighting-fixture")
    print("STREET_PREVIEW_OK")
    quit(0)
