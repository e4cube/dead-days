extends "res://tests/test_clinic_slice.gd"
func night_shot(id: String, suffix: String) -> void:
    game.update_lighting()
    game.refresh_hud()
    for i in 3:
        await process_frame
    if DisplayServer.get_name()!="headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/"+id+"-night-"+suffix+".png"))
func run() -> void:
    game=load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/lights_%d"%Time.get_ticks_usec())
    # Explicit night/no-threat fixture; navigation and key handling remain production code.
    game.model.rules.zombie_spawns=[]
    game.new_run()
    game.model.state.minutes=1320
    check(game.model.light_enabled("home") and not game.model.light_enabled("clinic") and not game.model.light_enabled("shop"),"legacy defaults retain home light and dark abandoned stores")
    var old: Dictionary = game.model.state.duplicate(true)
    old.house_light=false
    check(game.model.valid(old),"legacy house light remains valid without new fields")
    var invalid: Dictionary = old.duplicate(true)
    invalid.building_lights={"clinic":1}
    check(not game.model.valid(invalid),"numeric light flags rejected")
    invalid.building_lights={"unknown":true}
    check(not game.model.valid(invalid),"unknown building light rejected")
    invalid.building_lights=[]
    check(not game.model.valid(invalid),"non dictionary light data rejected")
    var old_path: String = game.store.save(game.model)
    var old_bytes := FileAccess.get_file_as_bytes(old_path)
    await to_point(Vector2(-7,1.2))
    await to_point(Vector2(0,1.2))
    key(KEY_E)
    await to_point(Vector2(0,-1.9))
    key(KEY_L)
    var lamps: Dictionary = game.world.get_meta("interior_lights")
    check(lamps.clinic.visible and not lamps.shop.visible,"clinic switch affects only current building")
    await night_shot("clinic","lit")
    game.save_run()
    game.continue_run()
    lamps=game.world.get_meta("interior_lights")
    check(lamps.clinic.visible and not lamps.shop.visible,"clinic light persists through actual continue")
    key(KEY_L)
    await night_shot("clinic","dark")
    await to_point(Vector2(0,1.2))
    key(KEY_E)
    await to_point(Vector2(7,1.2))
    key(KEY_E)
    await to_point(Vector2(7,-1.9))
    key(KEY_L)
    lamps=game.world.get_meta("interior_lights")
    check(lamps.shop.visible and not lamps.clinic.visible,"shop light independent of clinic state")
    await night_shot("shop","lit")
    game.save_run()
    game.continue_run()
    lamps=game.world.get_meta("interior_lights")
    check(lamps.shop.visible and not lamps.clinic.visible,"both light states roundtrip independently")
    key(KEY_L)
    await night_shot("shop","dark")
    check(FileAccess.get_file_as_bytes(old_path)==old_bytes,"older snapshot bytes never rewritten")
    print("INTERIOR_LIGHTS_OK" if failures==0 else "INTERIOR_LIGHTS_FAILED")
    quit(0 if failures==0 else 1)
