extends SceneTree
func _initialize():
    call_deferred("run")
func run():
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    var game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/appearance_preview_%d"%Time.get_ticks_usec())
    # Controlled lineup on the real street; not a natural AI encounter.
    for i in 3: game.model.rules.zombie_spawns[i].position=[-3.2+i*1.6,0,3]
    game.new_run()
    game.active=false
    game.player_visual.hide()
    var labels=preload("res://scripts/zombie_appearance.gd").definitions()
    for zombie in game.zombie_bodies:
        zombie.rotation.y=.15
        zombie.visual_root.sample("stand",.1)
        zombie.show_state_label=true
        zombie.state_label.show()
        zombie.state_label.text=labels[zombie.record.appearance].name
    game.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    game.camera.size=4.4
    game.camera.position=Vector3(-.5,3.2,5.7)
    game.camera.look_at(Vector3(-1.6,1.1,3))
    for child in game.get_children():
        if child is CanvasLayer: child.visible=false
    for i in 6: await process_frame
    assert(DisplayServer.get_name()!="headless")
    var image:=root.get_texture().get_image()
    assert(image.get_size()==Vector2i(1920,1080))
    assert(image.save_png(ProjectSettings.globalize_path("res://../work/visual-slice/zombie-appearances.png"))==OK)
    var file:=FileAccess.open("res://../work/visual-slice/zombie-capture-conditions.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"fixture":"Actual Godot street, paused controlled lineup; player hidden, HUD hidden; not natural encounter","resolution":[1920,1080],"camera":[-.5,3.2,5.7],"look_at":[-1.6,1.1,3],"orthographic_size":4.4,"minutes":game.model.state.minutes,"zombies":game.model.state.zombies},"  "))
    print("ZOMBIE_APPEARANCE_PREVIEW_OK")
    quit()
