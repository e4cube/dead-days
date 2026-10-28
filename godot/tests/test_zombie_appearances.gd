extends SceneTree
const Model=preload("res://scripts/survival.gd")
const Store=preload("res://scripts/save_store.gd")
const Visual=preload("res://scripts/character_visual.gd")
const Looks=preload("res://scripts/zombie_appearance.gd")
var failures:=0
func check(value: bool,message: String):
    if not value:
        failures+=1
        printerr("FAIL: ",message)
func _initialize():
    call_deferred("run")
func run():
    var model=Model.new()
    model.start()
    var ids: Array=[]
    for record in model.state.zombies: ids.append(record.appearance)
    check(ids==["civilian","worker","police"],"new world carries three explicit appearances")
    model.state.zombies[1].health=0
    model.state.zombies[1].mode="dead"
    var store=Store.new("user://tests/appearance_%d"%Time.get_ticks_usec())
    check(not store.save(model).is_empty(),"variant death state saved")
    var restored=Model.new()
    check(store.load_latest(restored),"variant snapshot restored")
    check(restored.state.zombies[1].appearance=="worker" and restored.state.zombies[1].mode=="dead","dead worker does not change skin or respawn")
    var bad=model.state.duplicate(true)
    bad.zombies[0].appearance="unknown"
    check(not model.valid(bad),"unknown skin IDs rejected")
    var old=model.state.duplicate(true)
    for record in old.zombies: record.erase("appearance")
    check(model.valid(old),"historical appearance-free records accepted")
    restored.restore(old)
    check(restored.state.zombies[1].appearance=="civilian" and restored.state.zombies[1].health==0,"historical migration retains death and assigns original outfit")
    var visual=Visual.new()
    root.add_child(visual)
    visual.setup("zombie")
    for id in Looks.definitions():
        visual.set_appearance(id)
        var visible_outfits:=0
        for mesh in visual.instance.find_children("DD_Variant_*","MeshInstance3D",true,false):
            check(mesh.visible==str(mesh.name).begins_with("DD_Variant_"+id+"_"),"outfit visibility exclusive "+id)
            if mesh.visible: visible_outfits+=1
        check(visible_outfits==1,"one outfit mesh per clothed variant")
        for clip in ["stand","move","attack","hurt","death"]:
            visual.trigger(clip)
            visual.sample(clip,.13)
            check(visual.current_action==clip,"shared animation available "+id+"/"+clip)
    visual.queue_free()
    print("ZOMBIE_APPEARANCES_OK" if failures==0 else "ZOMBIE_APPEARANCES_FAILED")
    quit(0 if failures==0 else 1)
