extends SceneTree
var game
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)
func key(code: int) -> void:
    var e := InputEventKey.new()
    e.keycode = code
    e.pressed = true
    game._unhandled_key_input(e)
func walk(action: String, count: int) -> void:
    Input.action_press(action)
    for i in count:
        await physics_frame
    Input.action_release(action)
    await physics_frame
func shot(name: String) -> void:
    for i in 3:
        await process_frame
    if DisplayServer.get_name() != "headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/house-"+name+".png"))
func hidden_roof() -> bool:
    for mesh in game.building_visuals.home.find_children("*","MeshInstance3D",true,false):
        if str(mesh.name).begins_with("DD_Hide_Roof") and mesh.visible:
            return false
    return true
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/house_%d" % Time.get_ticks_usec())
    game.new_run()
    await physics_frame
    check(not hidden_roof(),"outside restores solid roof")
    await shot("outside")
    await walk("forward",24)
    key(KEY_E)
    await walk("forward",54)
    check(game.inside("home") and hidden_roof(),"walk inside reveals actual interior")
    key(KEY_E)
    check(game.model.state.inventory.get("food",0)==2,"real finite supplies looted")
    key(KEY_L)
    check(not game.world.get_node("HouseLamp").visible,"indoor switch turns lamp off")
    game.save_run()
    game.continue_run()
    check(not game.world.get_node("HouseLamp").visible,"light setting persists")
    key(KEY_L)
    await shot("interior")
    key(KEY_Q)
    check(absf(game.camera_yaw)>0.1,"camera orbit changes actual camera")
    await shot("rotated")
    key(KEY_V)
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    game._unhandled_input(wheel)
    check(game.camera.size==18,"mouse wheel zooms orthographic camera")
    await walk("back",60)
    check(not game.inside("home") and not hidden_roof(),"walk outside restores roof")
    await shot("exit")
    print("HOUSE_SLICE_OK" if failures==0 else "HOUSE_SLICE_FAILED")
    quit(0 if failures==0 else 1)
