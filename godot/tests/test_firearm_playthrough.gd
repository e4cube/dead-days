extends "res://tests/test_clinic_slice.gd"
var captures: Array=[]
func frames(n: int):
    for i in n: await physics_frame
func photo(name: String):
    game.refresh_hud()
    game.update_player_visual(0)
    await frames(3)
    if DisplayServer.get_name()!="headless":
        var image:=root.get_texture().get_image()
        check(image.get_size()==Vector2i(1920,1080),"actual firearm screenshot is 1080p")
        image.save_png(ProjectSettings.globalize_path("res://../work/visual-slice/firearm-"+name+".png"))
        captures.append({"file":"firearm-"+name+".png","size":[1920,1080],"minutes":game.model.state.minutes,"player":game.model.state.position.duplicate(),"camera":[game.camera.position.x,game.camera.position.y,game.camera.position.z],"projection":game.camera.projection,"camera_size":game.camera.size,"inventory":game.model.state.inventory.duplicate(true),"firearms":game.model.state.firearms.duplicate(true),"fixture":"Actual input route; controlled targets for wall and nearest-hit assertions, not a natural encounter"})
func target(id: String,at: Vector3):
    var record=game.model.make_zombie(id,[at.x,at.y,at.z])
    game.model.state.zombies.append(record)
    var zombie=load("res://scripts/zombie.gd").new()
    game.world.add_child(zombie)
    zombie.setup(game,record)
    game.zombie_bodies.append(zombie)
    return zombie
func run():
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/firearm_play_%d"%Time.get_ticks_usec())
    # Input route with no enemies; then explicit combat fixtures isolate occlusion/one-hit rules.
    game.model.rules.zombie_spawns=[]
    game.new_run()
    await to_point(Vector2(-7,1.2))
    await to_point(Vector2(7,1.2))
    key(KEY_E)
    await to_point(Vector2(7,-1.9))
    key(KEY_B)
    check(game.panel.visible and game.storage_container=="shop","actual movement reaches store stock")
    game.storage_transfer("pistol",false)
    for i in 12: game.storage_transfer("ammo_9mm",false)
    key(KEY_B)
    key(KEY_5)
    check(game.model.state.inventory.pistol==1 and game.model.state.inventory.ammo_9mm==12,"finite stock transferred")
    check(not game.try_attack(),"found gun is empty")
    await photo("01-found")
    key(KEY_F)
    check(not game.try_attack(),"cannot shoot while reloading")
    await frames(140)
    check(game.model.state.firearms.loaded==6 and game.model.state.inventory.ammo_9mm==6,"timed reload from actual inventory")
    game.save_run()
    check(game.store.load_latest(game.model),"reload result persists")
    await photo("02-loaded")
    await to_point(Vector2(7,-.8))
    key(KEY_E)
    check(not game.model.state.doors.shop,"close real door")
    await to_point(Vector2(7,-1.9))
    var first=target("gun_fixture_front",Vector3(7,0,3.6))
    await frames(2)
    game.player.rotation.y=0
    check(game.try_attack(),"blocked shot still consumes a real round")
    check(first.record.health==70 and game.model.state.firearms.loaded==5,"closed door stops bullet")
    check(game.model.state.noises.back().kind=="gunshot" and game.model.state.noises.back().radius==32,"gunfire emits configured sound")
    await frames(10)
    check(first.record.last_noise>0,"living AI hears actual gunshot behind door")
    first.set_physics_process(false)
    await photo("03-door-blocks")
    await to_point(Vector2(7,-.8))
    key(KEY_E)
    await to_point(Vector2(7,1.2))
    # Targets are frozen only for repeatable damage assertions, not presented as natural AI footage.
    first.position=Vector3(7,0,4)
    first.record.position=[7,0,4]
    var second=target("gun_fixture_rear",Vector3(7,0,5))
    second.set_physics_process(false)
    await frames(2)
    game.player.rotation.y=0
    check(game.try_attack(),"clear street shot fires")
    check(first.record.health==32 and second.record.health==70,"one bullet damages nearest target only")
    game.camera_zoom=7
    game.update_camera()
    await photo("04-street-shot")
    check(game.player_visual.firearm.visible and not game.player_visual.weapon.visible,"gun shown instead of club")
    game.save_run()
    check(game.store.load_latest(game.model) and game.model.state.firearms.loaded==4,"spent rounds survive reload")
    var file:=FileAccess.open("res://../work/visual-slice/firearms-capture-conditions.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(captures,"  "))
    print("FIREARM_PLAYTHROUGH_OK" if failures==0 else "FIREARM_PLAYTHROUGH_FAILED")
    quit(0 if failures==0 else 1)
