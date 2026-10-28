extends SceneTree
var failures:=0
func check(ok: bool, message: String):
    if not ok:
        failures+=1
        printerr("FAIL: ",message)
func _initialize(): call_deferred("run")
func run():
    var game=load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/door_intent_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[{"id":"intent_fixture","position":[-7,0,.85]}]
    game.new_run()
    game.active=false
    # Explicit geometry fixture: manual ticks isolate attack commitment from real-time input.
    game.player.position=Vector3(-7,0,-.85)
    game.sync_position()
    var enemy=game.zombie_bodies[0]
    enemy.record.mode="search"
    enemy.record.memory=6.0
    enemy.record.target=[-7,0,-.85]
    await physics_frame
    enemy.tick(.01)
    check(enemy.record.attack_door=="home" and enemy.record.windup>0,"attack commits to remembered door")
    check(game.save_run(),"mid-windup intent is saveable")
    game.continue_run()
    game.active=false
    enemy=game.zombie_bodies[0]
    check(enemy.record.attack_door=="home" and enemy.record.windup>0 and game.model.state.door_health.home==120,"load preserves unfinished windup without early damage")
    game.model.toggle_door("home")
    game.apply_door("home")
    game.player.position=Vector3(-7,0,.2)
    await physics_frame
    var hp: float=game.model.state.stats.health
    enemy.tick(.5)
    check(game.model.state.stats.health==hp and game.model.state.door_health.home==120,"opening during windup cancels impact instead of redirecting strike to nearby player")
    check(enemy.record.attack_door=="" and enemy.record.attack_cd>0,"missed swing still consumes cooldown")
    game.continue_run()
    game.active=false
    enemy=game.zombie_bodies[0]
    await physics_frame
    enemy.tick(.5)
    check(game.model.state.door_health.home==108,"restored committed attack lands exactly once")
    var remembered: Array=enemy.record.target.duplicate()
    enemy.record.windup=0
    enemy.record.attack_door=""
    enemy.record.memory=0
    enemy.record.mode="wander"
    check(enemy.blocked_door().is_empty(),"wandering never bashes remembered door")
    enemy.record.mode="search"
    enemy.record.memory=6
    enemy.record.target=[-7,0,3]
    check(enemy.blocked_door().is_empty(),"same-side target does not provoke door bashing")
    enemy.record.target=remembered
    enemy.record.memory=.05
    var before: float=game.model.state.door_health.home
    enemy.tick(.1)
    check(enemy.record.mode=="wander" and game.model.state.door_health.home==before,"expired memory stops door attack")
    var m=game.model
    m.state.zombies=[]
    m.state.position=[-8.35,0,-3.5]
    m.DoorDamage.hit(m,"home",120,"fixture")
    check("损坏" in game.Rest.reason(m,"home_bed"),"broken door specifically prevents otherwise safe bedside rest")
    var bad: Dictionary=m.state.duplicate(true)
    bad.door_health.home=121
    check(not m.valid(bad),"excess durability rejected")
    game.queue_free()
    for i in 3: await process_frame
    if failures==0: print("DOOR_ATTACK_INTENT_OK")
    quit(0 if failures==0 else 1)
