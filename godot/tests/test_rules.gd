extends SceneTree
const Model = preload("res://scripts/survival.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func _initialize() -> void:
    var model = Model.new()
    model.start()
    check(model.valid(model.state), "initial state valid")
    check(model.loot("home") == 3, "loot transfers real quantities")
    check(model.loot("home") == 0, "no duplicate loot")
    check(model.use_item("food"), "food consumed")
    check(model.state.inventory.food == 1 and model.state.stats.hunger == 95, "nutrition and quantity")
    check(not model.use_item("bandage"), "missing item rejected")
    model.loot("shop")
    check(model.weight() <= model.rules.capacity, "weight limit")
    check(model.state.containers.shop.water > 0, "overflow remains in world")
    model.toggle_door("home")
    model.enter("home")
    model.enter("home")
    model.manual("柜子里有食物。", "希望")
    check(model.state.visited.size() == 1, "entry event once")
    check("希望" in model.markdown(), "mood exported")
    var directory := "user://tests/rules_%d" % Time.get_ticks_usec()
    var store = Store.new(directory)
    var first: String = store.save(model)
    check(not first.is_empty(), "save succeeds")
    var original := FileAccess.get_file_as_bytes(first)
    var second: String = store.save(model)
    check(first != second and original == FileAccess.get_file_as_bytes(first), "immutable saves")
    var loaded = Model.new()
    check(store.load_latest(loaded), "load succeeds")
    check(loaded.state == JSON.parse_string(JSON.stringify(model.state)), "complete state roundtrip")
    var file := FileAccess.open(directory + "/save_zz_corrupt.json", FileAccess.WRITE)
    file.store_string("{truncated")
    file.close()
    check(store.load_latest(loaded), "corrupt latest fallback")
    var before: Dictionary = loaded.state.duplicate(true)
    check(not Store.new(directory + "/missing").load_latest(loaded), "missing save fails")
    check(loaded.state == before, "failed load preserves session")
    for field in ["minutes", "position", "inventory", "stats", "events", "doors"]:
        var bad: Dictionary = model.state.duplicate(true)
        bad[field] = "invalid"
        check(not model.valid(bad), "reject invalid " + field)
    var bad: Dictionary = model.state.duplicate(true)
    bad.inventory.food = -1
    check(not model.valid(bad), "negative count rejected")
    bad = model.state.duplicate(true)
    bad.inventory.food = 100
    check(not model.valid(bad), "overweight rejected")
    print("RULES_OK" if failures == 0 else "RULES_FAILED")
    quit(0 if failures == 0 else 1)
