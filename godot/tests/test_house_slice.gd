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
func walk_to(local: Vector2) -> void:
    var goal: Vector2 = Vector2(game.house_details.position.x,game.house_details.position.z) + local
    for i in 360:
        var difference: Vector2 = goal - Vector2(game.player.position.x,game.player.position.z)
        for action in ["left","right","forward","back"]:
            Input.action_release(action)
        if difference.length() < .035:
            await physics_frame
            return
        if absf(difference.x) > .025:
            Input.action_press("right" if difference.x > 0 else "left")
        else:
            Input.action_press("back" if difference.y > 0 else "forward")
        await physics_frame
    for action in ["left","right","forward","back"]:
        Input.action_release(action)
    check(false,"walk waypoint unreachable: " + str(local) + " from " + str(game.player.position))
func hidden_roof() -> bool:
    for mesh in game.building_visuals.home.find_children("*","MeshInstance3D",true,false):
        if str(mesh.name).begins_with("DD_Hide_Roof") and mesh.visible:
            return false
    return true
func check_layout() -> void:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house_layout.json"))
    var origin: Vector3 = game.house_details.position
    var meshes: Array = game.house_details.find_children("*", "MeshInstance3D", true, false)
    check(meshes.size() == layout.modules.size(), "every authored module imported")
    for module in layout.modules:
        var at: Array = module.position
        var expected := origin + Vector3(at[0],at[1],at[2])
        var found := false
        for mesh in meshes:
            if mesh.global_transform.origin.distance_to(expected) < 0.001 and str(mesh.name).begins_with(module.name):
                found = true
                if module.kind == "box":
                    var size: Array = module.size
                    check(mesh.get_aabb().size.is_equal_approx(Vector3(size[0],size[1],size[2])), "render bounds match authored dimensions " + module.name)
                break
        check(found, "GLB placement agrees with shared layout " + module.name)
    for obstacle in layout.obstacles:
        var body: Node3D = game.world.get_node("HouseObstacle_" + obstacle.id)
        var at: Array = obstacle.position
        var size: Array = obstacle.size
        check(body.position.is_equal_approx(origin + Vector3(at[0],at[1],at[2])), "collider placement " + obstacle.id)
        check(body.get_child(1).shape.size.is_equal_approx(Vector3(size[0],size[1],size[2])), "collider dimensions " + obstacle.id)
        var registered := false
        for source in game.nav_sources:
            if source.body == body:
                registered = true
        check(registered, "layout collider registered with navigation " + obstacle.id)
func check_orbit_walls() -> void:
    var viewport := root.get_visible_rect().size
    var actor: Vector2 = game.camera.unproject_position(game.player.position+Vector3.UP)
    check(actor.x>viewport.x*.12 and actor.x<viewport.x*.88 and actor.y>viewport.y*.16 and actor.y<viewport.y*.84,"actor stays clear of edge UI during indoor orbit")
    for x in [-2.6,2.6]:
        for z in [-6.8,-.2]:
            var screen: Vector2 = game.camera.unproject_position(game.house_details.position+Vector3(x,.1,z))
            check(screen.x>0 and screen.x<viewport.x and screen.y>viewport.y*.12 and screen.y<viewport.y*.87,"whole house floor fits indoor composition")
    var view: Vector3 = game.camera.position - game.player.position
    for mesh in game.building_visuals.home.find_children("*", "MeshInstance3D", true, false):
        var name := str(mesh.name)
        if name.begins_with("DD_Hide_Front"):
            check(mesh.visible == (view.z < 0), "front wall follows orbit")
        elif name == "DD_Hide_East":
            check(mesh.visible == (view.x < 0), "east wall follows orbit")
        elif name == "DD_Keep_Back":
            check(mesh.visible == (view.z > 0), "back wall follows orbit")
        elif name == "DD_Keep_West":
            check(mesh.visible == (view.x > 0), "west wall follows orbit")
    for mesh in game.house_details.find_children("*", "MeshInstance3D", true, false):
        if str(mesh.name) == "DD_Cut_Back":
            check(mesh.visible == (view.z <= 0), "back low wall preserves thickness")
        elif str(mesh.name) == "DD_Cut_West":
            check(mesh.visible == (view.x <= 0), "west low wall preserves thickness")
        elif str(mesh.name).begins_with("DD_Hide_BackPicture"):
            check(mesh.visible == (view.z > 0), "wall picture hides with supporting wall")
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/house_%d" % Time.get_ticks_usec())
    game.new_run()
    await physics_frame
    check_layout()
    check(not hidden_roof(),"outside restores solid roof")
    await shot("outside")
    await walk("forward",24)
    key(KEY_E)
    await walk("forward",54)
    check(game.inside("home") and hidden_roof(),"walk inside reveals actual interior")
    for child in game.world.get_children():
        if child is Label3D:
            check(not child.visible,"indoor framing removes permanent floating labels")
    key(KEY_E)
    check(game.model.state.inventory.get("food",0)==2,"real finite supplies looted")
    key(KEY_L)
    check(not game.world.get_node("HouseLamp").visible,"indoor switch turns lamp off")
    game.save_run()
    game.continue_run()
    check(not game.world.get_node("HouseLamp").visible,"light setting persists")
    key(KEY_L)
    await shot("interior")
    # Explicit night rendering fixture; real overnight progression is tested separately.
    var previous_minutes: float = game.model.state.minutes
    game.active=false
    game.model.state.minutes=1320
    game.update_lighting()
    game.refresh_hud()
    await shot("night-lit-fixture")
    # Resume to use the actual switch rather than setting the light directly.
    game.active=true
    key(KEY_L)
    check(not game.world.get_node("HouseLamp").visible,"night switch uses same real indoor control")
    game.save_run()
    game.continue_run()
    game.active=false
    game.refresh_hud()
    await shot("night-dark-fixture")
    check(not game.world.get_node("HouseLamp").visible and game.model.state.minutes>=1320,"dark night state survives save continue")
    game.active=true
    key(KEY_L)
    game.model.state.minutes=previous_minutes
    game.update_lighting()
    game.refresh_hud()
    # Walk through the bedroom side aisle and the kitchen rear passage.
    # All movement uses production input/physics; no teleporting into the extension.
    await walk_to(Vector2(0,-2.25))
    await walk_to(Vector2(-2.25,-2.25))
    await walk_to(Vector2(-2.25,-5.5))
    await walk_to(Vector2(-1.3,-5.5))
    check(game.inside("home") and game.player.position.z < -5 and game.player.position.x < -7.5, "bedroom extension physically accessible")
    check(not game.container_line_clear("home_fridge",game.furniture_container_position(game.model.rules.containers[0])),"bedroom partition occludes fridge search")
    await shot("bedroom")
    await walk_to(Vector2(-2.25,-5.5))
    await walk_to(Vector2(-2.25,-2.25))
    await walk_to(Vector2(0,-2.25))
    await walk_to(Vector2(0,-4.2))
    check(game.closest_bed().is_empty(),"bedroom partition prevents using bed from kitchen")
    await walk_to(Vector2(0,-6.1))
    await walk_to(Vector2(1,-6.1))
    check(game.inside("home") and game.player.position.z < -5.8 and game.player.position.x > -6.4, "kitchen rear passage physically accessible")
    check(hidden_roof(),"extension remains interior for roof occlusion")
    check(game.nearby().get("id")=="home_fridge","reachable fridge identified independently")
    var cabinet: Dictionary = game.model.state.containers.home.duplicate(true)
    key(KEY_E)
    check(game.model.state.containers.home_fridge.food==0 and game.model.state.containers.home_fridge.water==1,"backpack limit leaves one water in fridge")
    check(game.model.state.containers.home==cabinet,"kitchen interaction does not loot another container")
    game.save_run()
    game.continue_run()
    check(game.model.state.containers.home_fridge.water==1,"fridge remainder survives graphical save continue")
    await shot("fridge-partial")
    key(KEY_2)
    key(KEY_E)
    check(game.model.state.containers.home_fridge.water==0 and game.model.weight()<=game.model.rules.capacity,"using water frees room for remaining supplies")
    var carried: Dictionary = game.model.state.inventory.duplicate(true)
    key(KEY_E)
    check(game.model.state.inventory==carried,"empty fridge cannot duplicate inventory")
    key(KEY_4)
    key(KEY_B)
    check(game.panel.visible and game.panel_kind=="storage","B opens live storage panel")
    var paused_time: float = game.model.state.minutes
    for i in 10:
        await physics_frame
    check(game.model.state.minutes==paused_time,"storage panel follows world pause policy")
    game.storage_container="home"
    var rejected_inventory: Dictionary = game.model.state.inventory.duplicate(true)
    game.storage_transfer("club",true)
    check(game.model.state.inventory==rejected_inventory,"stale container target cannot remotely transfer")
    game.storage_container="home_fridge"
    var before_store: float = game.model.weight()
    game.storage_buttons.club.store.pressed.emit()
    check(game.model.state.containers.home_fridge.club==1 and game.model.state.combat.equipped=="fists","real UI stores and unequips weapon")
    check(game.model.weight()<before_store and game.storage_buttons.club.store.disabled,"storage UI refreshes live counts")
    check(("负重 %.1f" % game.model.weight()) in game.hud.text and "木棍×1" in game.hint.text,"paused HUD and container hint refresh after transfer")
    await shot("storage")
    for i in 3:
        game.storage_buttons.food.store.pressed.emit()
    game.storage_buttons.water.store.pressed.emit()
    check(game.storage_buttons.water.store.disabled,"full container disables an overweight deposit")
    var unchanged: Dictionary = game.model.state.inventory.duplicate(true)
    game.storage_buttons.water.store.pressed.emit()
    check(game.model.state.inventory==unchanged and game.model.container_weight("home_fridge")<4.0001,"model rechecks even a manually emitted disabled button")
    check("3.9 / 4.0 kg" in game.journal_text.text,"capacity shown from live rule and inventory")
    await shot("storage-full")
    key(KEY_B)
    key(KEY_F5)
    game.continue_run()
    check(game.model.state.containers.home_fridge.club==1 and game.model.state.inventory.club==0,"deposited weapon survives save continue")
    check(game.model.state.containers.home_fridge.food==3 and game.model.state.containers.home_fridge.water==1,"full stored supplies survive continue")
    key(KEY_B)
    game.storage_buttons.club.take.pressed.emit()
    check(game.model.state.inventory.club==1 and game.model.state.containers.home_fridge.club==0,"real UI retrieves one item")
    key(KEY_B)
    await shot("kitchen")
    await walk_to(Vector2(0,-6.1))
    await walk_to(Vector2(0,-1.9))
    var initial_position: Vector3 = game.player.position
    var layers: Array = []
    for source in game.nav_sources:
        layers.append(source.body.collision_layer)
    for i in 8:
        key(KEY_Q)
        check_orbit_walls()
        check(hidden_roof(), "roof stays hidden throughout orbit")
        if i == 3:
            var hidden_crowns := 0
            for crown in game.world.get_meta("tree_crowns"):
                if not crown.mesh.visible:
                    hidden_crowns+=1
            check(hidden_crowns>0,"reverse camera removes foreground foliage over rooms")
            check(hidden_crowns<game.world.get_meta("tree_crowns").size(),"background canopy remains visible")
            await shot("reverse")
    check(game.player.position.is_equal_approx(initial_position), "camera orbit does not move actor")
    for i in game.nav_sources.size():
        check(game.nav_sources[i].body.collision_layer == layers[i], "visual cutaway preserves physical walls")
    key(KEY_Q)
    check(absf(game.camera_yaw)>0.1,"camera orbit changes actual camera")
    await shot("rotated")
    key(KEY_V)
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    game._unhandled_input(wheel)
    check(game.camera_zoom==18 and is_equal_approx(game.camera.size,18*.62),"wheel preserves chosen zoom with indoor framing scale")
    await walk("back",60)
    check(not game.inside("home") and not hidden_roof(),"walk outside restores roof")
    for crown in game.world.get_meta("tree_crowns"):
        check(crown.mesh.visible,"all foliage restores outside without changing trunk collisions")
    for child in game.world.get_children():
        if child is Label3D:
            check(child.visible,"outdoor location labels return on exit")
    check(absf(game.camera.size-game.camera_zoom)<.15,"exit smoothly restores selected outdoor zoom")
    await shot("exit")
    print("HOUSE_SLICE_OK" if failures==0 else "HOUSE_SLICE_FAILED")
    quit(0 if failures==0 else 1)
