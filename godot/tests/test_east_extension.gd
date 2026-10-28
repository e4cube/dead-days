extends "res://tests/test_clinic_slice.gd"
func run():
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/extension_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[]
    game.new_run()
    var old=game.model.state.duplicate(true)
    old.world_revision=1
    for id in ["pantry_home","end_home"]:
        old.doors.erase(id)
        old.door_health.erase(id)
        old.door_level.erase(id)
        old.containers.erase(id)
        old.containers.erase(id+"_fridge")
    old.containers.east_home.ammo_9mm=0
    check(game.model.valid(old),"revision one snapshot accepted")
    game.model.restore(old)
    check(game.model.state.world_revision==2 and game.model.state.containers.east_home.ammo_9mm==0,"migration preserves depleted prior extension")
    await to_point(Vector2(-7,1.2))
    # Real inputs along the continuous road, no teleport into the new area.
    await to_point(Vector2(14,1.2))
    await to_point(Vector2(21,1.2))
    for id in ["pantry_home","end_home"]:
        var x: float=21 if id=="pantry_home" else 28
        await to_point(Vector2(x,1.2))
        key(KEY_E)
        check(game.model.state.doors[id],"new door opens "+id)
        await to_point(Vector2(x,-2.25))
        check(game.inside(id),"walk into "+id)
        var route=game.navigation.path(Vector3(x,0,2),game.player.position)
        check(not route.is_empty() and route[-1].distance_to(game.player.position)<.8,"navigation enters "+id)
        key(KEY_E)
        check(game.model.state.inventory.size()>0,"finite loot collected")
        key(KEY_L)
        check(game.model.light_enabled(id),"independent room light")
        var inventory=game.model.state.inventory.duplicate(true)
        check(game.save_run(),"new room save succeeds: "+game.store.last_error)
        game.continue_run()
        check(game.inside(id),"new room restored position "+str(game.player.position))
        check(game.model.state.inventory==JSON.parse_string(JSON.stringify(inventory)),"new room restored quantities")
        await shot("extension-"+id)
        # Deposit acquired stock so the next room can be tested at real capacity.
        key(KEY_B)
        for item in inventory:
            for n in inventory[item]: game.storage_transfer(item,true)
        key(KEY_B)
        await to_point(Vector2(x,1.2))
    check(game.player.position.x>27,"walked beyond the old boundary")
    await shot("extension-street")
    print("EAST_EXTENSION_OK" if failures==0 else "EAST_EXTENSION_FAILED")
    quit(0 if failures==0 else 1)
