extends "res://tests/test_clinic_slice.gd"
var captures: Array=[]
func photo(name: String):
    game.refresh_hud()
    for i in 4: await process_frame
    if DisplayServer.get_name()!="headless":
        var image:=root.get_texture().get_image()
        check(image.get_size()==Vector2i(1920,1080),"fixed drop viewport")
        image.save_png(ProjectSettings.globalize_path("res://../work/visual-slice/drops-"+name+".png"))
        captures.append({"file":"drops-"+name+".png","position":[game.player.position.x,game.player.position.y,game.player.position.z],"minutes":game.model.state.minutes,"inventory":game.model.state.inventory.duplicate(true),"ground_drops":game.model.state.ground_drops.duplicate(true),"fixture":"Enemies disabled; actual movement and production UI callbacks; reused crate marker"})
func run():
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/drop_route_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[]
    game.new_run()
    await to_point(Vector2(-7,1.2))
    key(KEY_E)
    await to_point(Vector2(-7,-2.25))
    key(KEY_E)
    check(game.model.state.inventory.get("water",0)>0,"walk inside and loot finite supplies")
    await to_point(Vector2(-7,2.5))
    key(KEY_I)
    await photo("01-backpack")
    var count: int=game.model.state.inventory.water
    game.drop_buttons.water.pressed.emit()
    check(game.model.state.inventory.water==count-1,"real backpack button drops one water")
    key(KEY_I)
    var id: String=game.model.state.ground_drops.keys()[0]
    check(game.ground_visuals[id].visible,"actual world marker visible")
    await photo("02-ground")
    game.save_run()
    game.continue_run()
    check(game.model.state.containers[id].water==1 and game.ground_visuals[id].visible,"save continue rebuilds occupied ground marker")
    await photo("03-restored")
    await to_point(Vector2(-5,2.5))
    check(game.nearby().get("id","")!=id,"cannot pick up distant pile")
    await to_point(Vector2(-7,2.5))
    key(KEY_B)
    check(game.storage_container==id and game.panel.visible,"ground stock opens existing storage UI")
    game.storage_transfer("water",false)
    check(game.model.state.inventory.water==count,"taking last item restores original count")
    game.storage_transfer("water",true)
    check(game.model.state.containers[id].water==1,"empty selected pile accepts returning item")
    key(KEY_B)
    key(KEY_E)
    game.refresh_hud()
    check(game.model.state.inventory.water==count and not game.ground_visuals[id].visible,"E recovers remaining stock and hides empty marker")
    game.save_run()
    game.continue_run()
    check(game.model.state.containers[id].water==0 and not game.ground_visuals.has(id),"empty pile does not respawn after load")
    await photo("04-recovered")
    if not captures.is_empty():
        var f:=FileAccess.open("res://../work/visual-slice/drops-capture-conditions.json",FileAccess.WRITE)
        f.store_string(JSON.stringify({"resolution":[1920,1080],"captures":captures},"  "))
        f.close()
    if failures==0: print("GROUND_DROP_PLAYTHROUGH_OK")
    quit(0 if failures==0 else 1)
