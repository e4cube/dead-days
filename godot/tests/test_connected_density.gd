extends SceneTree
var game
var failures:=0
func check(ok: bool,text: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL: ",text)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/connected_density_%d"%Time.get_ticks_usec())
    game.new_run()
    game.set_physics_process(false)
    var count: int=game.model.state.zombies.size()
    check(count>=80 and count<=100,"bounded increased population")
    check(game.zombie_bodies.size()==count,"every record has a real actor")
    var high_value:=0
    for spawn in game.model.world_definition.enemy_spawns:
        if spawn.region in ["market","factory"]: high_value+=1
    check(high_value>count*.55,"majority guards rich areas")
    game.tick_world(.05,false)
    check(game.simulated_near<count/2 and game.simulated_far==0,"far population does not all tick at full rate")
    var enemy=game.zombie_bodies[-1]
    var old_position: Vector3=enemy.position
    game.model.noise(enemy.position,8,"gunshot")
    game.tick_world(.05,false)
    check(enemy.record.mode!="wander","distant audible event wakes real actor")
    enemy.take_hit(10000)
    check(enemy.record.health==0,"real damage kills actor")
    var dead_id: String=enemy.record.id
    check(game.save_run(),"dense world saves")
    game.continue_run()
    game.set_physics_process(false)
    check(game.model.state.zombies.size()==count,"load neither duplicates nor respawns population")
    var found:=false
    for zombie in game.model.state.zombies:
        if zombie.id==dead_id: found=zombie.health==0
    check(found,"death persists")
    # Fixed market observation fixture for repeatable render sampling, not a natural encounter recording.
    game.player.position=Vector3(63,.12,-8)
    game.player.velocity=Vector3.ZERO
    game.update_camera(0)
    var intervals:=[]
    var stamp:=Time.get_ticks_usec()
    for i in 180:
        await process_frame
        var now:=Time.get_ticks_usec()
        if i>=60: intervals.append((now-stamp)/1000.0)
        stamp=now
        game.tick_world(1.0/60.0,false)
        game.update_cutaways()
        game.refresh_hud()
    intervals.sort()
    var total:=0.0
    for value in intervals: total+=value
    var result={"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"actors":count,"full_rate_last_tick":game.simulated_near,"mean_fps":1000.0/(total/intervals.size()),"p95_ms":intervals[int(intervals.size()*.95)],"fixture":"Market stationary player, manual fixed 1/60 simulation step per real process frame, 60 warmup + 120 samples; not a free-play performance guarantee","headless":DisplayServer.get_name()=="headless","viewport":[1920,1080],"window_size":[root.size.x,root.size.y],"vsync":DisplayServer.window_get_vsync_mode()}
    var file=FileAccess.open("res://../work/connected-gameplay/density-performance.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "))
    file.close()
    if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/connected-gameplay/06-market-density.png"))
    game.queue_free()
    await process_frame
    print("CONNECTED_DENSITY_OK" if failures==0 else "CONNECTED_DENSITY_FAILED")
    quit(0 if failures==0 else 1)
