extends "res://tests/test_clinic_slice.gd"
func visible_stock(prefix: String) -> int:
    var count := 0
    for mesh in game.shop_details.get_meta(prefix):
        if mesh.visible:
            count+=1
    return count
func shop_shot(name: String) -> void:
    for i in 3:
        await process_frame
    if DisplayServer.get_name()!="headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/shop-"+name+".png"))
func run() -> void:
    game=load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/shop_%d"%Time.get_ticks_usec())
    # Geometry/inventory fixture only: independent pursuit tests retain production spawns.
    game.model.rules.zombie_spawns=[]
    game.new_run()
    await to_point(Vector2(-7,1.2))
    await to_point(Vector2(7,1.2))
    key(KEY_E)
    await to_point(Vector2(7,-1.9))
    check(game.inside("shop"),"actual input reaches and enters shop from default spawn")
    check(visible_stock("FoodCan")==3 and visible_stock("WaterBody")==3,"initial display reflects finite stock")
    await shop_shot("stocked")
    key(KEY_E)
    game.refresh_hud()
    check(game.model.state.inventory.get("food",0)==3 and game.model.state.inventory.get("water",0)==3,"shop loot transfers real food and water")
    check(game.model.state.containers.shop.food==0 and game.model.state.containers.shop.water==0,"shop stock depleted once")
    check(visible_stock("FoodCan")==0 and visible_stock("WaterBody")==0,"empty shop removes stock visuals")
    key(KEY_E)
    check(game.model.state.inventory.food==3,"repeat search cannot replenish")
    key(KEY_B)
    check(game.panel.visible and game.storage_container=="shop","shop uses real storage UI")
    game.storage_buttons.food.store.pressed.emit()
    game.storage_buttons.water.store.pressed.emit()
    check(visible_stock("FoodCan")==1 and visible_stock("WaterBody")==1,"paused deposits restore each stock group")
    game.storage_buttons.food.take.pressed.emit()
    game.storage_buttons.water.take.pressed.emit()
    key(KEY_B)
    await shop_shot("looted")
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop_layout.json"))
    check(game.shop_details.find_children("*","MeshInstance3D",true,false).size()==layout.modules.size(),"shared shop modules imported")
    for obstacle in layout.obstacles:
        var body: Node3D = game.world.get_node("ShopObstacle_"+obstacle.id)
        var found := false
        for source in game.nav_sources:
            found=found or source.body==body
        check(found and body.collision_layer==1,"shelves and counter have navigation collision")
    await to_point(Vector2(8.05,-1.9))
    await to_point(Vector2(8.05,-4.35))
    await to_point(Vector2(7,-4.35))
    check(game.player.position.z < -4,"shop rear aisle physically accessible")
    for i in 8:
        key(KEY_Q)
        for mesh in game.building_visuals.shop.find_children("*","MeshInstance3D",true,false):
            if str(mesh.name).begins_with("DD_Hide_Roof"):
                check(not mesh.visible,"shop roof hidden in all orbit directions")
        if i==3:
            await shop_shot("reverse")
    game.save_run()
    game.continue_run()
    check(game.model.state.inventory.food==3 and game.model.state.inventory.water==3 and game.model.state.containers.shop.food==0 and visible_stock("FoodCan")==0,"save continue preserves looted supplies and display")
    await to_point(Vector2(8.05,-4.35))
    await to_point(Vector2(8.05,-1.9))
    await to_point(Vector2(7,-1.9))
    await to_point(Vector2(7,1.2))
    key(KEY_E)
    check(not game.inside("shop") and not game.model.state.doors.shop,"exit and close shop carrying supplies")
    await to_point(Vector2(0,1.2))
    key(KEY_E)
    await to_point(Vector2(0,-1.9))
    key(KEY_B)
    game.storage_buttons.food.store.pressed.emit()
    check(game.inside("clinic") and game.model.state.containers.clinic.food==1 and game.model.state.inventory.food==2,"carry shop supplies into clinic and deposit actual item")
    key(KEY_B)
    print("SHOP_SLICE_OK" if failures==0 else "SHOP_SLICE_FAILED")
    quit(0 if failures==0 else 1)
