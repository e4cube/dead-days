extends "res://tests/test_clinic_slice.gd"
const Model=preload("res://scripts/survival.gd")
const Damage=preload("res://scripts/door_damage.gd")
var captures: Array=[]
func photo(name: String):
    for i in 3: await process_frame
    if DisplayServer.get_name()!="headless":
        var image:=root.get_texture().get_image()
        check(image.get_size()==Vector2i(1920,1080),"fixed door viewport")
        image.save_png("res://../work/visual-slice/door-"+name+".png")
        captures.append({"file":"door-"+name+".png","door_health":game.model.state.door_health.duplicate(),"minutes":game.model.state.minutes,"fixture":"One zombie placed at entrance after actual player entrance; remembered interior target and 24hp weakened door. Production AI attacks/collision/navigation; not a natural encounter."})
func run():
    var m=Model.new()
    m.start()
    check(Damage.hit(m,"home",12,"test") and m.state.door_health.home==108,"closed door takes actual damage")
    m.toggle_door("home")
    check(not Damage.hit(m,"home",12,"test") and m.state.door_health.home==108,"open door immune to bashing")
    m.toggle_door("home")
    var store=load("res://scripts/save_store.gd").new("user://tests/door_rules_%d"%Time.get_ticks_usec())
    store.save(m)
    var restored=Model.new()
    check(store.load_latest(restored) and restored.state.door_health.home==108,"damaged door persists")
    var old: Dictionary=m.state.duplicate(true)
    old.erase("door_health")
    check(m.valid(old),"historical door state accepted")
    restored.restore(old)
    check(restored.state.door_health.home==120 and not restored.state.doors.home,"migration preserves closed door without changing old file")
    var bad: Dictionary=m.state.duplicate(true)
    bad.door_health.home=-1
    check(not m.valid(bad),"negative durability rejected")
    bad.door_health.home=0
    check(not m.valid(bad),"broken closed door rejected")
    check(Damage.hit(m,"home",200,"test"),"door can break")
    m.toggle_door("home")
    check(m.state.doors.home and m.valid(m.state),"broken door cannot reclose")
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/door_route_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[]
    game.new_run()
    await to_point(Vector2(-7,1.2))
    key(KEY_E)
    await to_point(Vector2(-7,-.85))
    key(KEY_E)
    await to_point(Vector2(-7,-2.25))
    check(not game.model.state.doors.home,"actual entry and closing door")
    key(KEY_E)
    key(KEY_4)
    check(game.model.state.combat.equipped=="club","loot and equip real home weapon for retreat")
    game.sync_position()
    var zombie: Dictionary=game.model.make_zombie("door_fixture",[-7,0,.85])
    zombie.mode="search"
    zombie.target=[-7,0,-2.25]
    zombie.memory=6.0
    game.model.state.zombies=[zombie]
    game.model.state.door_health.home=24.0
    game.build_world()
    var revision: int=game.navigation.revision
    for i in 100:
        await physics_frame
        if game.model.state.door_health.home<24: break
    check(game.model.state.door_health.home==12 and not game.model.state.doors.home,"remembered target causes timed bash, not immediate passage")
    check(not game.zombie_bodies[0].sees_player(),"closed door still blocks sight")
    game.save_run()
    game.continue_run()
    check(game.model.state.door_health.home==12,"mid-threat save does not repair door")
    await photo("01-bashing")
    for i in 240:
        await physics_frame
        if game.model.state.door_health.home==0: break
    check(game.model.state.door_health.home==0 and game.model.state.doors.home,"AI breaks weakened door")
    check(game.doors.home.collision_layer==0 and game.open_leaves.home.collision_layer==0,"broken leaf removes both collision positions")
    check(game.navigation.revision>revision,"breach rebuilds navigation")
    for i in 240:
        await physics_frame
        if game.zombie_bodies[0].position.z<-.4: break
    check(game.zombie_bodies[0].position.z<-.4,"zombie actually walks through breach")
    check(game.door_visuals.home.visible and is_equal_approx(game.door_visuals.home.rotation.x,PI*.5),"broken door remains as fallen Blender mesh")
    check(not game.Rest.reason(game.model,"home_bed").is_empty(),"unsafe home cannot be used for rest")
    await photo("02-breached")
    # Clear the narrow doorway through actual combat before retreating. No actor teleport.
    await walk("back",12)
    Input.action_press("attack")
    for i in 300:
        await physics_frame
        if game.zombie_bodies[0].record.health<=0: break
    Input.action_release("attack")
    check(game.zombie_bodies[0].record.health==0 and game.model.state.stats.health>0,"real club attacks clear the breached doorway")
    await photo("03-clear-entry")
    Input.action_press("run")
    await to_point(Vector2(-7,2.8))
    await to_point(Vector2(-4,2.8))
    Input.action_release("run")
    check(not game.inside_any() and game.model.state.stats.health>0,"actual player input retreats through breached entrance")
    await photo("04-retreat")
    game.save_run()
    game.continue_run()
    check(Damage.broken(game.model,"home") and game.doors.home.collision_layer==0 and is_equal_approx(game.door_visuals.home.rotation.x,PI*.5),"breached collision and fallen door persist after load")
    if not captures.is_empty():
        var f:=FileAccess.open("res://../work/visual-slice/door-capture-conditions.json",FileAccess.WRITE)
        f.store_string(JSON.stringify({"resolution":[1920,1080],"captures":captures},"  "))
    game.queue_free()
    for i in 3: await process_frame
    if failures==0: print("DOOR_DAMAGE_OK")
    quit(0 if failures==0 else 1)
