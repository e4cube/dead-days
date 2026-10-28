extends "res://tests/test_clinic_slice.gd"
## Rendered gameplay walkthrough. Clock presets are explicit lighting fixtures.
var output := "res://../work/visual-slice/"
var captures: Array=[]
func sample_active_performance() -> void:
    for i in 60:
        await process_frame
    var samples: Array[float]=[]
    var start:=Time.get_ticks_usec()
    var previous:=start
    var minutes_before: float=game.model.state.minutes
    for i in 240:
        await process_frame
        var now:=Time.get_ticks_usec()
        samples.append((now-previous)/1000.0)
        previous=now
    samples.sort()
    var size:=root.get_texture().get_size()
    var record:={"godot":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"resolution":[size.x,size.y],"vsync":DisplayServer.window_get_vsync_mode(),"fixture":"Live simulation, stationary player at home exterior, 3 live zombies; 60 warmup frames + 240 process frames; no player movement during sample","mean_fps":240000000.0/(previous-start),"p95_frame_ms":samples[227],"minutes_advanced":game.model.state.minutes-minutes_before,"health":game.model.state.stats.health}
    check(record.minutes_advanced>0 and game.active,"performance sample really advances gameplay")
    var file:=FileAccess.open(output+"gameplay-performance.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(record,"  "))
func capture(name: String) -> void:
    for i in 5:
        await process_frame
    check(DisplayServer.get_name()!="headless","screenshots require real renderer")
    var image:=root.get_texture().get_image()
    check(image.get_width()==1920 and image.get_height()==1080,"fixed 1080p viewport")
    check(image.save_png(ProjectSettings.globalize_path(output+name+".png"))==OK,"capture "+name)
    var p: Vector3=game.player.position
    var c: Vector3=game.camera.position
    captures.append({"file":name+".png","viewport":[image.get_width(),image.get_height()],"day":game.model.state.day,"minutes":game.model.state.minutes,"player":[p.x,p.y,p.z],"camera":[c.x,c.y,c.z],"projection":game.camera.projection,"size":game.camera.size,"fov":game.camera.fov,"inventory":game.model.state.inventory.duplicate(true),"doors":game.model.state.doors.duplicate(true),"zombies":game.model.state.zombies.duplicate(true)})
func run() -> void:
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/visual_slice_%d"%Time.get_ticks_usec())
    game.new_run()
    await physics_frame
    # Start with live AI. Pause only for fixed-time stills/performance sampling.
    game.model.state.minutes=600
    game.update_lighting()
    game.refresh_hud()
    game.camera_zoom=18
    game.update_camera()
    game.active=false
    await capture("street-day")
    await capture("01-street-exploration")
    # Isolated initial player pose in the actual street, before live enemies approach.
    game.camera_zoom=4
    game.update_camera()
    await capture("character-closeup")
    var character_rotation: Vector3=game.player_visual.rotation
    game.player_visual.rotation.y+=PI
    await capture("character-front-refined")
    var portrait_transform: Transform3D=game.camera.transform
    var portrait_size: float=game.camera.size
    game.camera.position=game.player.position+Vector3(1.1,1.9,3.0)
    game.camera.look_at(game.player.position+Vector3(0,1.25,0))
    game.camera.size=2.1
    await capture("character-portrait-review")
    game.camera.transform=portrait_transform
    game.camera.size=portrait_size
    game.player_visual.rotation=character_rotation
    game.camera_zoom=18
    game.update_camera()
    game.model.state.minutes=1320
    game.update_lighting()
    game.refresh_hud()
    await capture("street-night")
    game.model.state.minutes=600
    game.update_lighting()
    game.refresh_hud()
    game.active=true
    await sample_active_performance()
    # Return to the explicit daytime capture fixture; no overnight claim.
    game.model.state.minutes=600
    game.update_lighting()
    await to_point(Vector2(-7,1.1))
    await capture("02-approach-house")
    key(KEY_E)
    check(game.model.state.doors.home,"door opened through interaction")
    await capture("03-open-door")
    await to_point(Vector2(-7,-1.8))
    check(game.inside("home"),"actual movement enters home")
    check(game.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"unified isometric indoor camera")
    var hidden:=false
    for mesh in game.building_visuals.home.find_children("DD_Hide_Roof*","MeshInstance3D",true,false):
        hidden=hidden or not mesh.visible
    check(hidden,"entering house actually removes roof occlusion")
    game.active=false
    game.camera_zoom=12
    game.update_camera()
    await capture("04-enter-house")
    await capture("house-interior")
    game.active=true
    await to_point(Vector2(-7,-2.25))
    key(KEY_E)
    check(game.model.state.inventory.get("food",0)>0,"cabinet transfers actual food")
    await capture("05-loot-cabinet")
    var light_before: bool=game.model.state.get("house_light",true)
    key(KEY_L)
    check(game.model.state.house_light!=light_before,"real indoor light switch")
    key(KEY_L)
    check(game.save_run(),"isolated test save written")
    var inventory: Dictionary=game.model.state.inventory.duplicate(true)
    game.continue_run()
    for id in inventory:
        check(int(game.model.state.inventory.get(id,0))==int(inventory[id]),"inventory restored: "+id)
    await to_point(Vector2(-7,-1.8))
    await to_point(Vector2(-7,1.2))
    check(not game.inside("home"),"actual movement exits home")
    game.camera_zoom=15
    game.update_camera()
    await capture("06-leave-house")
    await to_point(Vector2(-7,3.3))
    await to_point(Vector2(4,3.3))
    check(game.zombie_bodies.size()>0,"live zombies retained")
    Input.action_press("run")
    await walk("right",20)
    Input.action_release("run")
    var encountered:=false
    for i in 180:
        for zombie in game.zombie_bodies:
            encountered=encountered or (zombie.position.distance_to(game.player.position)<6 and zombie.record.mode in ["chase","alert","search"])
        if encountered:
            break
        await physics_frame
    check(encountered,"nearby live zombie actually senses player")
    await capture("07-encounter-zombie")
    game.active=false
    game.camera_zoom=4
    game.model.state.minutes=600
    game.update_lighting()
    game.refresh_hud()
    game.update_camera()
    # Fixed street still sampling: paused simulation, actual rendered frames.
    game.camera_zoom=18
    game.update_camera()
    for i in 60:
        await process_frame
    var durations: Array[float]=[]
    var start:=Time.get_ticks_usec()
    var previous:=start
    for i in 240:
        await process_frame
        var now:=Time.get_ticks_usec()
        durations.append((now-previous)/1000.0)
        previous=now
    durations.sort()
    var actual_size:=root.get_texture().get_size()
    var report:={"godot":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"resolution":[actual_size.x,actual_size.y],"vsync":DisplayServer.window_get_vsync_mode(),"fixture":"240 real process frames after 60 warmup; paused simulation, street after walkthrough; not gameplay FPS guarantee","mean_fps":240000000.0/(previous-start),"p95_frame_ms":durations[227],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"failures":failures}
    var file:=FileAccess.open(output+"performance.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  "))
    var conditions:=FileAccess.open(output+"capture-conditions.json",FileAccess.WRITE)
    conditions.store_string(JSON.stringify({"clock_presets":"Day 10:00; night 22:00; reset to 10:00 after active benchmark and for character closeup. Not an overnight run.","movement":"Actual input/physics, no player or zombie teleport","frames":captures},"  "))
    print("VISUAL_SLICE_V1_OK" if failures==0 else "VISUAL_SLICE_V1_FAILED")
    quit(0 if failures==0 else 1)
