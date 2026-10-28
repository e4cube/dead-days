extends SceneTree
var game
var failures:=0
func check(ok: bool,text: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL: ",text)
func press(text: String) -> void:
    for node in game.expedition.window.find_children("*","Button",true,false):
        if node.text==text:
            node.pressed.emit()
            return
    check(false,"button missing "+text)
func shot(name: String) -> void:
    for i in 4: await process_frame
    if DisplayServer.get_name()!="headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/connected-gameplay/"+name+".png"))
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/connected_ui_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[] # UI/geometry fixture, not combat evidence.
    game.new_run()
    game.set_physics_process(false)
    # Explicit placement fixture: test authoritative UI transactions in the authored market.
    game.player.position=Vector3(57.5,.12,-17.4)
    game.player.velocity=Vector3.ZERO
    game.model.discover(game.player.position)
    game.update_camera(0)
    await physics_frame
    check(game.nearby().get("id")=="market_produce_a","market target reachable")
    game.open_storage()
    check(game.expedition.is_open() and game.expedition.kind=="storage","shared storage UI opens")
    game.expedition.selected="water"
    press("尽可能取出所选")
    check(game.model.state.inventory.get("water",0)==2 and game.model.state.containers.market_produce_a.water==0,"batch take conserves finite water")
    press("存入 1 件")
    check(game.model.state.inventory.water==1 and game.model.state.containers.market_produce_a.water==1,"deposit one conserves water")
    await shot("01-market-storage")
    game.expedition.close()
    game.open_panel("inventory")
    game.expedition.selected="water"
    game.expedition.show_detail()
    check("单件重量" in game.expedition.details.text and "饮水" in game.expedition.details.text,"item information explains weight and effect")
    press("使用 / 装备 / 装填")
    check(game.model.state.inventory.water==0 and game.model.state.stats.thirst>65,"item action consumes and restores")
    await shot("02-backpack")
    game.expedition.close()
    game.open_panel("map")
    var map=game.expedition.map_view
    for i in 3: await process_frame # Containers need layout before coordinate conversion.
    var original:=Vector2(57.5,-17.4)
    check(map.to_world(map.to_screen(original)).distance_to(original)<.001,"map coordinate roundtrip")
    check(game.model.mark(Vector3(57.5,0,-17.4),"带水回家"),"map note accepted")
    map.queue_redraw()
    await shot("03-world-map")
    root.content_scale_size=Vector2i(1152,720)
    await shot("04-map-720")
    root.content_scale_size=Vector2i(1920,1080)
    game.expedition.close()
    check(game.save_run(),"save new-area state")
    game.continue_run()
    game.set_physics_process(false)
    check(game.model.state.exploration.markers.size()==1,"map note restored")
    check(game.model.state.containers.market_produce_a.water==1,"partial stock restored")
    check(game.player.position.distance_to(Vector3(57.5,.12,-17.4))<1,"market position restored")
    game.open_panel("map")
    await shot("05-map-restored")
    game.queue_free()
    await process_frame
    print("CONNECTED_UI_OK" if failures==0 else "CONNECTED_UI_FAILED")
    quit(0 if failures==0 else 1)
