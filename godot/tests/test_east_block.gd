extends "res://tests/test_clinic_slice.gd"
var captures: Array=[]
func photo(name: String):
    game.refresh_hud()
    game.sync_position()
    for i in 4: await process_frame
    if DisplayServer.get_name()!="headless":
        var image:=root.get_texture().get_image()
        check(image.get_size()==Vector2i(1920,1080),"fixed expansion viewport")
        image.save_png(ProjectSettings.globalize_path("res://../work/visual-slice/east-"+name+".png"))
        captures.append({"file":"east-"+name+".png","player":game.model.state.position.duplicate(),"minutes":game.model.state.minutes,"camera":[game.camera.position.x,game.camera.position.y,game.camera.position.z],"size":game.camera.size,"inventory":game.model.state.inventory.duplicate(true),"doors":game.model.state.doors.duplicate(true),"fixture":"Actual input route and rest; enemies disabled to isolate extension geometry/interactions"})
func run():
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/east_block_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[]
    game.new_run()
    await to_point(Vector2(-7,1.2))
    await to_point(Vector2(14,1.2))
    check(game.player.position.x>13.5,"walk beyond previous boundary")
    await photo("01-street")
    key(KEY_E)
    check(game.model.state.doors.east_home,"open separate east door")
    await to_point(Vector2(14,-2.25))
    check(game.inside("east_home") and game.inside_any(),"actual entrance updates generic room detection")
    check(game.container_bodies.east_home_fridge!=game.container_bodies.home_fridge and game.container_bodies.east_home_fridge.position.x>14,"reused fridge has its own collision and interaction anchor")
    var hidden:=false
    for mesh in game.building_visuals.east_home.find_children("DD_Hide_Roof*","MeshInstance3D",true,false):
        hidden=hidden or not mesh.visible
    check(hidden,"reused roof cuts away")
    var route: PackedVector3Array=game.navigation.path(Vector3(17,0,2),game.player.position)
    check(not route.is_empty() and route[-1].distance_to(game.player.position)<.8,"navigation reaches the new interior")
    var original: Dictionary=game.model.state.containers.home.duplicate(true)
    key(KEY_E)
    check(game.model.state.inventory.ammo_9mm==12 and game.model.state.containers.east_home.ammo_9mm==0,"new finite stock collected")
    check(game.model.state.containers.home==original,"original home stock independent")
    key(KEY_L)
    check(game.world.get_node("HouseLamp_east_home").visible and game.model.light_enabled("home"),"new light works independently")
    await photo("02-interior")
    key(KEY_B)
    game.storage_transfer("food",true)
    key(KEY_B)
    check(game.model.state.containers.east_home.food==1 and game.model.state.containers.home==original,"storage returns food to the correct house")
    game.save_run()
    game.continue_run()
    check(game.inside("east_home") and game.model.state.containers.east_home.ammo_9mm==0 and game.world.get_node("HouseLamp_east_home").visible,"save continue retains position, loot and new light")
    await photo("03-restored")
    await to_point(Vector2(14,-.8))
    key(KEY_E)
    check(not game.model.state.doors.east_home,"close east door without altering home")
    await to_point(Vector2(14,-2.25))
    await to_point(Vector2(11.75,-2.25))
    await to_point(Vector2(11.75,-3.5))
    check(game.closest_bed()=="east_home_bed","new bed is reachable through real side aisle")
    key(KEY_R)
    check(game.model.state.rest.active,"safe rest in new house")
    await photo("04-rest")
    for i in 600:
        if not game.model.state.rest.active: break
        await physics_frame
    check(not game.model.state.rest.active,"one-hour rest finishes")
    await to_point(Vector2(11.75,-2.25))
    await to_point(Vector2(14,-2.25))
    await to_point(Vector2(14,-.8))
    key(KEY_E)
    await to_point(Vector2(14,1.2))
    var restored:=true
    for mesh in game.building_visuals.east_home.find_children("DD_Hide_Roof*","MeshInstance3D",true,false):
        restored=restored and mesh.visible
    check(restored and not game.inside_any(),"leaving restores exterior roof")
    await photo("05-leave")
    var file:=FileAccess.open("res://../work/visual-slice/east-capture-conditions.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(captures,"  "))
    print("EAST_BLOCK_OK" if failures==0 else "EAST_BLOCK_FAILED")
    quit(0 if failures==0 else 1)
