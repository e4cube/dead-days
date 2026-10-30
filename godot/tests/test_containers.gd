extends SceneTree
const Model = preload("res://scripts/survival.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",message)
func _initialize() -> void:
    var model = Model.new()
    model.start()
    check(model.state.schema==8 and model.valid(model.state),"new schema validates")
    var original: Dictionary = model.state.containers.home.duplicate(true)
    model.state.inventory={"water":5}
    check(model.loot("home_fridge")==0 and model.state.containers.home_fridge.water==2,"full backpack leaves supplies")
    model.state.inventory={}
    check(model.loot("home_fridge")==3,"fridge contains finite independent items")
    var events: int = model.state.events.size()
    check(model.loot("home_fridge")==0 and model.state.events.size()==events,"empty search cannot duplicate loot or story")
    check(model.state.containers.home==original,"fridge does not consume cabinet stock")
    check(model.state.events.back().payload.container=="home_fridge" and model.state.events.back().payload.building=="home","journal retains real container identity")
    var directory := "user://tests/containers_%d" % Time.get_ticks_usec()
    var store = Store.new(directory)
    check(not store.save(model).is_empty(),"save independent inventories")
    var loaded = Model.new()
    check(store.load_latest(loaded) and loaded.state==JSON.parse_string(JSON.stringify(model.state)),"exact schema4 roundtrip")
    var bad: Dictionary = model.state.duplicate(true)
    bad.containers.erase("home_fridge")
    check(not model.valid(bad),"schema4 missing inventory cannot refill by migration")
    bad=model.state.duplicate(true)
    bad.containers.home_fridge.water=-1
    check(not model.valid(bad),"negative furniture stock rejected")
    bad=model.state.duplicate(true)
    bad.containers.unknown={}
    check(not model.valid(bad),"unknown inventory rejected")
    bad=model.state.duplicate(true)
    bad.erase("rest")
    check(not model.valid(bad),"schema4 still requires valid rest and time")
    var old: Dictionary = model.state.duplicate(true)
    old.schema=3
    old.containers.erase("home_fridge")
    DirAccess.make_dir_recursive_absolute(directory+"/old")
    var path := directory+"/old/save_old.json"
    var file := FileAccess.open(path,FileAccess.WRITE)
    file.store_string(JSON.stringify(old))
    file.close()
    var bytes := FileAccess.get_file_as_bytes(path)
    check(Store.new(directory+"/old").load_latest(loaded),"schema3 furniture migration loads")
    check(loaded.state.schema==8 and loaded.state.containers.home==old.containers.home and loaded.state.inventory==JSON.parse_string(JSON.stringify(old.inventory)),"migration preserves existing stock and carried items")
    check(loaded.state.containers.home_fridge.water==2 and FileAccess.get_file_as_bytes(path)==bytes,"migration adds fridge in memory without rewriting source")
    loaded.state.inventory={}
    loaded.loot("home_fridge")
    var migrated = Store.new(directory+"/migrated")
    check(not migrated.save(loaded).is_empty() and migrated.load_latest(model) and model.loot("home_fridge")==0,"saved migrated fridge never refills")
    print("CONTAINERS_OK" if failures==0 else "CONTAINERS_FAILED")
    quit(0 if failures==0 else 1)
