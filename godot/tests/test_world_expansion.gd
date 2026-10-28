extends SceneTree
const Model=preload("res://scripts/survival.gd")
const Store=preload("res://scripts/save_store.gd")
var failures:=0
func check(value: bool,message: String):
    if not value:
        failures+=1
        printerr("FAIL: ",message)
func _initialize():
    var model=Model.new()
    model.start()
    check(model.valid(model.state) and model.state.world_revision==model.rules.world_revision,"new world revision valid")
    var old=model.state.duplicate(true)
    old.erase("world_revision")
    old.erase("door_health") # Historical fixture predates the durability ledger too.
    old.doors.erase("east_home")
    old.containers.erase("east_home")
    old.containers.erase("east_home_fridge")
    for id in ["pantry_home","end_home"]:
        old.doors.erase(id)
        old.containers.erase(id)
        old.containers.erase(id+"_fridge")
    old.containers.home.food=0
    old.containers.shop.ammo_9mm=0
    old.doors.home=true
    old.inventory={"pistol":1,"ammo_9mm":1}
    old.firearms.loaded=2
    old.zombies[1].health=0
    old.zombies[1].mode="dead"
    check(model.valid(old),"pre-expansion snapshot accepted without new building fields")
    var directory="user://tests/expansion_%d"%Time.get_ticks_usec()
    DirAccess.make_dir_recursive_absolute(directory)
    var path=directory+"/save_00000000000000000001_0000000001.json"
    var file=FileAccess.open(path,FileAccess.WRITE)
    file.store_string(JSON.stringify(old))
    file.close()
    old=JSON.parse_string(JSON.stringify(old))
    var bytes=FileAccess.get_file_as_bytes(path)
    var restored=Model.new()
    var store=Store.new(directory)
    check(store.load_latest(restored),"load real historical snapshot file")
    check(restored.state.world_revision==model.rules.world_revision and not restored.state.doors.east_home,"new area initialized once")
    check(restored.state.containers.home==old.containers.home and restored.state.containers.shop==old.containers.shop and restored.state.doors.home,"old loot and doors unchanged")
    check(restored.state.inventory==old.inventory and restored.state.firearms==old.firearms and restored.state.zombies==old.zombies,"ammo and enemy states untouched")
    check(restored.state.containers.east_home.ammo_9mm==12 and restored.state.containers.east_home_fridge.water==1,"only new finite containers initialized")
    check(FileAccess.get_file_as_bytes(path)==bytes,"migration never rewrites source snapshot")
    restored.state.containers.east_home.ammo_9mm=0
    var snapshot=restored.state.duplicate(true)
    restored.restore(snapshot)
    check(restored.state.containers.east_home.ammo_9mm==0,"repeated loads do not refill expanded stock")
    check(not store.save(restored).is_empty(),"expanded snapshot saves")
    var again=Model.new()
    check(store.load_latest(again) and again.state.containers.east_home.ammo_9mm==0,"depleted new room remains empty across disk load")
    var bad=again.state.duplicate(true)
    bad.doors.erase("east_home")
    check(not model.valid(bad),"current revision missing door rejected rather than replenished")
    bad=again.state.duplicate(true)
    bad.world_revision=model.rules.world_revision+1
    check(not model.valid(bad),"unknown future world revision rejected")
    print("WORLD_EXPANSION_OK" if failures==0 else "WORLD_EXPANSION_FAILED")
    quit(0 if failures==0 else 1)
