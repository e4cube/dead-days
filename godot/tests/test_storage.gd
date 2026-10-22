extends SceneTree
const Model = preload("res://scripts/survival.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",message)
func totals(model: RefCounted) -> Dictionary:
    var result := {}
    for item in model.rules.items:
        result[item] = model.state.inventory.get(item,0)
        for contents in model.state.containers.values():
            result[item] += contents.get(item,0)
    return result
func _initialize() -> void:
    var model = Model.new()
    model.start()
    model.state.inventory={"club":1,"food":2,"water":1}
    model.use_item("club")
    var original := totals(model)
    check(model.transfer_item("home","club",true),"equipped weapon can be stored")
    check(model.state.combat.equipped=="fists" and model.valid(model.state),"last weapon storage unequips safely")
    check(model.transfer_item("home","club",false) and model.state.combat.equipped=="fists","retrieval requires explicit re-equip")
    var random := RandomNumberGenerator.new()
    random.seed=20261022
    var items: Array = model.rules.items.keys()
    for i in 200:
        model.transfer_item("home_fridge" if i%2 else "home",items[random.randi_range(0,items.size()-1)],random.randf()<.5)
        check(totals(model)==original and model.weight()<=model.rules.capacity+.0001 and model.valid(model.state),"transfer conserves items, capacity and valid save")
    var store = Store.new("user://tests/storage_%d" % Time.get_ticks_usec())
    check(not store.save(model).is_empty(),"stored items save")
    var loaded = Model.new()
    check(store.load_latest(loaded) and loaded.state==JSON.parse_string(JSON.stringify(model.state)),"stored inventories restore exactly")
    model.start()
    model.state.inventory={"water":5}
    var before := totals(model)
    check(not model.transfer_item("home_fridge","water",false) and totals(model)==before,"full backpack rejects withdrawal atomically")
    model.state.stats.health=0
    check(not model.transfer_item("home","water",true),"dead actor cannot store")
    model.state.stats.health=100
    model.state.rest.active=true
    check(not model.transfer_item("home","water",true),"sleeping actor cannot store")
    model.start()
    model.state.inventory={"food":1}
    model.transfer_item("home","food",true)
    model.transfer_item("home","food",false)
    model.advance_time(480)
    var summary: Dictionary = model.state.events.back().payload
    check(summary.get("stored")==1 and summary.get("retrieved")==1 and summary.looted==0,"daily summary separates storage from looting")
    check(not model.transfer_item("unknown","food",true) and not model.transfer_item("home","unknown",true),"invalid transfer identities rejected")
    var bad: Dictionary = model.state.duplicate(true)
    for event in bad.events:
        if event.kind=="stored":
            event.payload.count=-1
    check(not model.valid(bad),"invalid storage event rejected")
    print("STORAGE_OK" if failures==0 else "STORAGE_FAILED")
    quit(0 if failures==0 else 1)
