extends "res://tests/test_clinic_slice.gd"
func travel(goal: Vector3) -> void:
    print("ROUTE_GOAL ",goal)
    var path: PackedVector3Array=game.navigation.path(game.player.position,goal)
    check(not path.is_empty(),"continuous route exists to "+str(goal))
    for point in path:
        await to_point(Vector2(point.x,point.z))
    print("ROUTE_REACHED ",game.player.position)
func run() -> void:
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/connected_route_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[] # Geometry and logistics run; separate density test covers AI.
    game.new_run()
    await travel(Vector3(28,0,3))
    await travel(Vector3(43,0,3))
    await shot("connected-route-01-road")
    await travel(Vector3(67,0,-24))
    check(game.nearby().get("id")=="market_shop_counter","walked to actual shop counter")
    key(KEY_E)
    check(game.model.weight()>0,"real input loots supplies")
    await shot("connected-route-02-market")
    await travel(Vector3(43,0,3))
    await travel(Vector3(-7,0,1.2))
    key(KEY_E)
    await travel(Vector3(-7,0,-2.2))
    await to_point(Vector2(-7,-2.25))
    key(KEY_B)
    check(game.expedition.is_open(),"home uses same storage panel")
    var contents: Dictionary=game.model.state.inventory.duplicate(true)
    for item in contents:
        game.expedition.selected=item
        game.expedition.transfer(true,10000)
    check(game.model.weight()==0,"returned supplies deposited in home")
    await shot("connected-route-03-home")
    game.expedition.close()
    check(game.save_run(),"returned expedition saves")
    game.continue_run()
    check(game.inside("home") and game.model.weight()==0,"home and inventory restored")
    check("market_07" in game.model.state.exploration.discovered,"journey discovery restored")
    print("CONNECTED_ROUTE_OK" if failures==0 else "CONNECTED_ROUTE_FAILED")
    quit(0 if failures==0 else 1)
