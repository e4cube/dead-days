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
    check(model.loot("home") == 4, "loot transfers real quantities")
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
    # Schema 2: active combat/noise and dead enemies round-trip, not just initial spawns.
    model.state.zombies[0].mode = "search"
    model.state.zombies[0].memory = 3.2
    model.state.zombies[0].windup = 0.2
    model.state.zombies[0].target = [-7, 0, -1]
    model.state.zombies[1].health = 0
    model.state.zombies[1].mode = "dead"
    model.state.zombies[1].windup = 0
    model.state.combat.attack_cd = 0.4
    model.noise(Vector3(-7, 0, 1), 10, "running")
    var combat_store = Store.new(directory + "/combat")
    check(not combat_store.save(model).is_empty(), "save active threat state")
    check(combat_store.load_latest(loaded) and loaded.state == JSON.parse_string(JSON.stringify(model.state)), "AI memory, windup, death and live sound restore")
    for key in ["combat", "zombies", "noises", "seen_horde"]:
        bad = model.state.duplicate(true)
        bad[key] = "invalid"
        check(not model.valid(bad), "reject invalid threat field " + key)
    bad = model.state.duplicate(true)
    bad.zombies[0].mode = "telepathy"
    check(not model.valid(bad), "unknown AI mode rejected")
    bad = model.state.duplicate(true)
    bad.zombies[0].health = 0
    check(not model.valid(bad), "dead health requires dead mode")
    bad = model.state.duplicate(true)
    bad.zombies[1].id = bad.zombies[0].id
    check(not model.valid(bad), "duplicate zombie IDs rejected")
    bad = model.state.duplicate(true)
    bad.schema = 99
    check(not model.valid(bad), "future schema rejected")
    # Last release's saves migrate in memory; their on-disk bytes remain unchanged.
    var old: Dictionary = model.state.duplicate(true)
    old.schema = 1
    for key in ["combat", "zombies", "noises", "noise_sequence", "seen_horde"]:
        old.erase(key)
    var legacy_dir := directory + "/schema1"
    DirAccess.make_dir_recursive_absolute(legacy_dir)
    var old_file := legacy_dir + "/save_old.json"
    file = FileAccess.open(old_file, FileAccess.WRITE)
    file.store_string(JSON.stringify(old))
    file.close()
    var old_bytes := FileAccess.get_file_as_bytes(old_file)
    check(Store.new(legacy_dir).load_latest(loaded), "schema 1 continues to load")
    check(loaded.state.schema == 8 and loaded.state.inventory == JSON.parse_string(JSON.stringify(old.inventory)) and loaded.state.doors == old.doors, "migration preserves player world")
    check(FileAccess.get_file_as_bytes(old_file) == old_bytes, "migration never rewrites old snapshot")
    check(loaded.valid(loaded.state), "migrated state can be saved again")
    model.state.stats.health = 24
    model.state.combat.hurt_cd = 0
    model.damage_player(30, "test")
    check(model.state.stats.health == 0 and not model.use_item("food") and not model.begin_attack(), "death prevents healing resurrection and combat")
    print("RULES_OK" if failures == 0 else "RULES_FAILED")
    quit(0 if failures == 0 else 1)
