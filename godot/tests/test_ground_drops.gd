extends SceneTree
const Model=preload("res://scripts/survival.gd")
const Drops=preload("res://scripts/ground_drops.gd")
var failures:=0
func check(ok: bool,message: String):
    if not ok:
        failures+=1
        printerr("FAIL: ",message)
func totals(m) -> Dictionary:
    var result: Dictionary=m.state.inventory.duplicate()
    for stock in m.state.containers.values():
        for item in stock: result[item]=result.get(item,0)+stock[item]
    result.ammo_9mm=result.get("ammo_9mm",0)+Model.Firearms.loaded(m)
    return result
func _initialize():
    var m=Model.new()
    m.start()
    m.loot("home")
    var initial:=totals(m)
    var weight: float=m.weight()
    var id:=Drops.put_one(m,"water",Vector3(-7,0,2),"")
    check(not id.is_empty(),"drop owned water")
    check(is_equal_approx(m.weight(),weight-1),"dropped water removes carried weight")
    check(totals(m)==initial and m.valid(m.state),"drop conserves all world stock and validates")
    var store=preload("res://scripts/save_store.gd").new("user://tests/drops_%d"%Time.get_ticks_usec())
    check(not store.save(m).is_empty(),"save occupied pile")
    var restored=Model.new()
    check(store.load_latest(restored),"load occupied pile")
    check(restored.state.ground_drops[id].position==[ -7.0,0.0,2.0 ] and restored.state.ground_drops[id].room=="" and restored.state.containers[id].water==1 and totals(restored)==initial,"metadata and stock survive load")
    m=restored
    check(m.loot(id)==1,"recover real dropped item")
    check(m.state.events[-1].kind=="recovered","recovery does not farm world loot summaries")
    for i in 100:
        check(Drops.put_one(m,"water",Vector3(-7+i%2,0,2),"")==id,"reuse empty stable slot")
        check(m.loot(id)==1 and totals(m)==initial and m.valid(m.state),"repeated transactions conserve inventory")
    check(Drops.put_one(m,"water",Vector3(100,0,0),"").is_empty(),"out of bounds rejected")
    check(Drops.put_one(m,"water",Vector3.ZERO,"missing").is_empty(),"unknown room rejected")
    check(totals(m)==initial,"failed drops preserve stock")
    Drops.put_one(m,"water",Vector3(-7,0,2),"")
    var bad: Dictionary=m.state.duplicate(true)
    bad.ground_drops[id].position=[999,0,0]
    check(not m.valid(bad),"invalid saved position rejected")
    bad=m.state.duplicate(true)
    bad.containers.erase(id)
    check(not m.valid(bad),"orphan pile rejected")
    bad=m.state.duplicate(true)
    bad.containers[id].water=11
    check(not m.valid(bad),"overweight pile rejected")
    var old=Model.new()
    old.start()
    old.state.erase("ground_drops")
    old.state.erase("drop_sequence")
    check(old.valid(old.state),"old snapshot remains valid")
    old.restore(old.state.duplicate(true))
    check(old.state.ground_drops.is_empty(),"old snapshot migrates without spawned loot")
    check(m.transfer_item("shop","pistol",false),"obtain finite pistol")
    check(m.transfer_item("shop","ammo_9mm",false),"obtain finite round")
    m.use_item("pistol")
    Model.Firearms.begin_reload(m)
    check(Drops.put_one(m,"pistol",Vector3.ZERO,"").is_empty(),"reloading gun cannot drop")
    m.tick_combat(2)
    check(Drops.put_one(m,"pistol",Vector3.ZERO,"").is_empty(),"loaded gun cannot drop")
    Model.Firearms.unload(m)
    check(not Drops.put_one(m,"pistol",Vector3.ZERO,"").is_empty(),"unloaded gun can drop")
    check(m.state.combat.equipped=="fists" and totals(m)==initial and m.valid(m.state),"gun drop conserves finite ammunition and unequips")
    var limited=Model.new()
    limited.start()
    limited.loot("home")
    var stock:=totals(limited)
    limited.rules.ground_drops.max_places=0
    check(Drops.put_one(limited,"water",Vector3.ZERO,"").is_empty() and totals(limited)==stock,"slot limit does not lose stock")
    limited.rules.ground_drops.max_places=64
    limited.rules.ground_drops.capacity=.5
    check(Drops.put_one(limited,"water",Vector3.ZERO,"").is_empty() and totals(limited)==stock,"capacity failure does not lose stock")
    limited.rules.ground_drops.capacity=10
    var merged:=Drops.put_one(limited,"water",Vector3.ZERO,"")
    check(Drops.put_one(limited,"food",Vector3(.2,0,0),"")==merged and limited.state.ground_drops.size()==1,"nearby stock merges into one place")
    check(totals(limited)==stock and limited.valid(limited.state),"merged stocks conserve world items")
    if failures==0: print("GROUND_DROPS_OK")
    quit(0 if failures==0 else 1)
