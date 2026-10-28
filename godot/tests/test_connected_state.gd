extends SceneTree
const Connected=preload("res://scripts/connected_model.gd")
const Legacy=preload("res://scripts/survival.gd")
const Drops=preload("res://scripts/ground_drops.gd")
const Store=preload("res://scripts/save_store.gd")
var failures:=0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures+=1
        printerr("FAIL: ",message)
func _initialize() -> void:
    var model=Connected.new()
    model.start()
    check(model.valid(model.state),"new connected state valid before any scene assembly")
    var old=Legacy.new()
    old.start()
    old.state.containers.home.food=0
    old.state.zombies[0].health=0
    old.state.zombies[0].mode="dead"
    check(model.valid(old.state),"street snapshot accepted for explicit migration")
    model.restore(old.state)
    check(model.state.containers.home.food==0 and model.state.zombies[0].health==0,"migration preserves depletion and death")
    check(model.state.containers.has("factory_locker"),"migration adds new containers once")
    model.state.containers.factory_locker.ammo_9mm=0
    model.state.position=[119.55,3.62,-24.78]
    model.state.inventory.water=1
    var upper: String=Drops.put_one(model,"water",Vector3(119.55,3.62,-24.78),"")
    check(not upper.is_empty() and model.state.ground_drops[upper].position[1]==3.62,"upstairs drop stays upstairs")
    check(model.state.events.back().payload.position[1]==3.62,"drop journal records actual floor")
    model.state.inventory.water=1
    var lower: String=Drops.put_one(model,"water",Vector3(119.55,0,-24.78),"")
    check(lower!=upper,"floors do not merge")
    model.state.inventory.food=1
    check(not Drops.put_one(model,"food",Vector3(165,0,18),"").is_empty(),"factory drops inside expanded bounds")
    var store=Store.new("user://tests/connected_state_%d"%Time.get_ticks_usec())
    check(not store.save(model).is_empty(),"connected state saved")
    var fresh=Connected.new()
    var loaded: bool=store.load_latest(fresh)
    check(loaded,"fresh model reads connected save before scene build")
    if not loaded:
        quit(1)
        return
    check(fresh.state.position==JSON.parse_string(JSON.stringify(model.state.position)),"saved floor and position retained")
    check(fresh.state.containers.factory_locker.ammo_9mm==0,"empty stock remains empty")
    var broken=fresh.state.duplicate(true)
    broken.containers.erase("factory_locker")
    check(not fresh.valid(broken),"current revision missing container rejected")
    broken=fresh.state.duplicate(true)
    broken.world_id="another_world"
    check(not fresh.valid(broken),"foreign world rejected")
    check(not old.valid(fresh.state),"legacy world cannot silently consume connected save")
    print("CONNECTED_STATE_OK" if failures==0 else "CONNECTED_STATE_FAILED")
    quit(0 if failures==0 else 1)
