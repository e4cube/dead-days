extends SceneTree
var game
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",message)
func key(code: int) -> void:
    var event := InputEventKey.new()
    event.keycode=code
    event.pressed=true
    game._unhandled_key_input(event)
func walk(action: String, count: int) -> void:
    Input.action_press(action)
    for i in count:
        await physics_frame
    Input.action_release(action)
    await physics_frame
func to_point(goal: Vector2) -> void:
    for i in 900:
        var difference: Vector2 = goal-Vector2(game.player.position.x,game.player.position.z)
        for action in ["left","right","forward","back"]:
            Input.action_release(action)
        if difference.length()<.075:
            await physics_frame
            return
        preload("res://tests/movement_driver.gd").drive(game,difference)
        await physics_frame
    for action in ["left","right","forward","back"]:
        Input.action_release(action)
    check(false,"clinic waypoint blocked "+str(goal)+" at "+str(game.player.position))
func shot(name: String) -> void:
    for i in 3:
        await process_frame
    if DisplayServer.get_name()!="headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/clinic-"+name+".png"))
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    game=load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/clinic_%d"%Time.get_ticks_usec())
    game.new_run()
    await walk("back",20)
    await walk("right",140)
    await to_point(Vector2(0,1.1))
    key(KEY_E)
    await walk("forward",45)
    check(game.inside("clinic"),"walk from initial spawn into clinic")
    await to_point(Vector2(0,-1.9))
    key(KEY_E)
    check(game.model.state.inventory.get("bandage",0)==3 and game.model.state.containers.clinic.bandage==0,"medicine is finite real inventory")
    game.update_cutaways()
    for mesh in game.clinic_details.get_meta("medicine_boxes"):
        check(not mesh.visible,"empty medicine stock removes visible supply boxes")
    # Explicit damage fixture; healing itself uses the production item/key transaction.
    # 绷带现在只处理伤口，所以 fixture 必须真的留下伤口（第三个参数是 opt-in）。
    game.model.damage_player(30,"clinic_test_fixture",true)
    var wounded: float = game.model.state.stats.health
    check(game.model.state.wounds.size()>=1,"the fixture left a wound to treat")
    key(KEY_3)
    var heal: float = float(game.model.rules.wounds.bandage_heal)
    check(game.model.state.stats.health==minf(100,wounded+heal) and game.model.state.inventory.bandage==2,"bandage dresses the wound, heals a little and is consumed")
    check(bool(game.model.state.wounds[0].dressed),"the wound records the dressing")
    key(KEY_B)
    check(game.panel.visible and game.storage_container=="clinic","clinic uses existing real storage panel")
    game.storage_buttons.bandage.store.pressed.emit()
    check(game.model.state.containers.clinic.bandage==1 and game.model.state.inventory.bandage==1,"bandage can be stored back in clinic")
    var visible_boxes := 0
    for mesh in game.clinic_details.get_meta("medicine_boxes"):
        if mesh.visible:
            visible_boxes+=1
    check(visible_boxes==1,"paused storage UI updates physical stock display")
    game.storage_buttons.bandage.take.pressed.emit()
    check(game.model.state.containers.clinic.bandage==0 and game.model.state.inventory.bandage==2,"retrieve conserves medicine")
    key(KEY_B)
    await shot("treatment")
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/clinic_layout.json"))
    check(game.clinic_details.find_children("*","MeshInstance3D",true,false).size()==layout.modules.size(),"every authored clinic module imported")
    for obstacle in layout.obstacles:
        var body: Node3D = game.world.get_node("ClinicObstacle_"+obstacle.id)
        var found := false
        for source in game.nav_sources:
            found=found or source.body==body
        check(found and body.collision_layer==1,"clinic furniture participates in navigation")
    await to_point(Vector2(0,-1.9))
    await to_point(Vector2(1.05,-1.9))
    await to_point(Vector2(1.05,-4.35))
    await to_point(Vector2(0,-4.35))
    check(game.player.position.z < -4,"rear medicine area physically reachable")
    await shot("rear")
    var layers: Array = []
    for source in game.nav_sources:
        layers.append(source.body.collision_layer)
    for i in 8:
        key(KEY_Q)
        for mesh in game.building_visuals.clinic.find_children("*","MeshInstance3D",true,false):
            if str(mesh.name).begins_with("DD_Hide_Roof"):
                check(not mesh.visible,"clinic roof remains cut away during orbit")
        var point: Vector2 = game.camera.unproject_position(game.player.position+Vector3.UP*1.5)
        check(game.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"clinic retains isometric composition")
        if i==3:
            await shot("reverse")
    for i in game.nav_sources.size():
        check(game.nav_sources[i].body.collision_layer==layers[i],"orbit keeps physical walls")
    game.save_run()
    game.continue_run()
    check(game.model.state.containers.clinic.bandage==0 and game.model.state.inventory.bandage==2,"medicine and usage survive continue without refill")
    await to_point(Vector2(1.05,-4.35))
    await to_point(Vector2(1.05,-1.9))
    await to_point(Vector2(0,-1.9))
    await to_point(Vector2(0,1.2))
    check(not game.inside("clinic"),"actual movement leaves furnished clinic")
    await shot("exit")
    print("CLINIC_SLICE_OK" if failures==0 else "CLINIC_SLICE_FAILED")
    quit(0 if failures==0 else 1)
