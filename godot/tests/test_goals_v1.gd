extends SceneTree
## Objectives acceptance: every goal is read out of state the player already
## produces, finishes exactly once, and neither rewards nor invents anything. A
## goal can only complete when the world really changed, and a reload must not
## re-announce it.
const Model = preload("res://scripts/survival.gd")
const World = preload("res://scripts/connected_model.gd")
const Goals = preload("res://scripts/goals.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func calm(model: RefCounted) -> void:
    model.state.zombies = []

func at(model: RefCounted, position: Vector3) -> void:
    model.state.position = [position.x, position.y, position.z]

func world() -> RefCounted:
    var model = World.new()
    model.start()
    calm(model)
    return model

func street() -> RefCounted:
    var model = Model.new()
    model.start()
    calm(model)
    return model

func count(model: RefCounted, kind: String) -> int:
    var total := 0
    for entry in model.state.events:
        if entry.kind == kind:
            total += 1
    return total

## One game minute of real time is enough to pass the objective throttle.
func settle(model: RefCounted) -> void:
    model.advance_time(0.6)

func _initialize() -> void:
    fresh()
    stockpile()
    distance()
    works()
    throttle()
    migration()
    rejection()
    persistence()
    print("GOALS_V1_OK" if failures == 0 else "GOALS_V1_FAILED")
    quit(0 if failures == 0 else 1)

func fresh() -> void:
    var model = world()
    check(model.state.schema == 8, "objectives bring the save to schema 8")
    check(Goals.definitions().size() == 4, "four objectives are authored")
    check(model.state.goals.done.is_empty(), "nothing starts completed")
    check(float(model.state.goals.farthest) == 0.0, "a new game has not walked anywhere yet")
    check(model.valid(model.state), "fresh objective state validates")
    var text: String = Goals.summary(model)
    check("小目标" in text and "[ ] 储备饮水" in text, "the journal lists unfinished objectives")
    check(not "[完成]" in text, "no objective claims to be done at the start")
    var plain = street()
    check(plain.state.schema == 8 and plain.state.goals.done.is_empty(), "the street scene carries objectives too")
    check(plain.valid(plain.state), "a street save with objectives validates")

## Water only counts once it is actually inside a container belonging to the base:
## carrying bottles or dropping them in another house is not stockpiling.
func stockpile() -> void:
    var model = world()
    var before: int = Goals.stock_total(model, "water", "home")
    check(before == 3, "the home cupboard and fridge start with three bottles")
    model.state.inventory = {"water": 3}
    check(Goals.stock_total(model, "water", "home") == before, "carried water is not stored water")
    for i in range(3):
        model.transfer_item("home", "water", true)
    check(Goals.stock_total(model, "water", "home") == before + 3, "three bottles end up in the base")
    settle(model)
    check("stock_water" in model.state.goals.done, "stocking enough bottles completes the water goal")
    check(count(model, "goal_done") == 1, "the completion is written once")
    var text: String = Goals.summary(model)
    check("[完成] 储备饮水" in text, "the finished objective reads as done")

    model.state.inventory = {"bandage": 2}
    for i in range(2):
        model.transfer_item("home", "bandage", true)
    settle(model)
    check("bring_medicine" in model.state.goals.done, "two bandages complete the medical goal")

    # Two bottles at the villa would tip the count over the threshold if stock
    # from another house were counted, so this is a real discriminator.
    var villa = world()
    villa.state.inventory = {"water": 2}
    for i in range(2):
        villa.transfer_item("villa_fridge", "water", true)
    check(Goals.stock_total(villa, "water", "home") < 5, "the villa cupboard is not part of the home base")
    settle(villa)
    check(not "stock_water" in villa.state.goals.done, "stock at another house does not count")
    check(villa.set_base("villa_07"), "the villa can become the base")
    settle(villa)
    check("stock_water" in villa.state.goals.done, "the same stock counts once the villa is the base")

func distance() -> void:
    var model = world()
    check(float(model.state.goals.farthest) == 0.0, "no distance is recorded before the first tick")
    at(model, Vector3(20.0, 0.0, 2.0))
    settle(model)
    check(not "long_trip" in model.state.goals.done, "a short walk is not a long trip")
    check(float(model.state.goals.farthest) > 15.0, "the farthest sample follows the player")
    at(model, Vector3(70.0, 0.0, 2.0))
    settle(model)
    check("long_trip" in model.state.goals.done, "walking past the threshold completes the trip")
    # Coming home never takes the record back.
    at(model, Vector3(-7.0, 0.0, 2.0))
    settle(model)
    check("long_trip" in model.state.goals.done, "returning home does not undo the trip")
    check(float(model.state.goals.farthest) > 55.0, "the record keeps the deepest point")

func works() -> void:
    var model = world()
    check(not "seal_yard" in model.state.goals.done, "the yard starts unsealed")
    model.complete_site("villa_gate")
    settle(model)
    check("seal_yard" in model.state.goals.done, "installing the yard gate completes the work goal")
    check(count(model, "goal_done") == 1, "the work goal is announced once")

## The objective test is throttled, so a second pass inside the same minute must
## not append a duplicate entry to the journal.
func throttle() -> void:
    var model = world()
    model.state.inventory = {"water": 3}
    for i in range(3):
        model.transfer_item("home", "water", true)
    settle(model)
    var after: int = count(model, "goal_done")
    model.advance_time(0.2)
    model.advance_time(0.2)
    check(count(model, "goal_done") == after, "repeated checks do not repeat the entry")
    check(model.state.goals.done.count("stock_water") == 1, "a goal is never listed twice")

func migration() -> void:
    var model = world()
    var directory := "user://tests/goals_v1_old_%d" % Time.get_ticks_usec()
    var old: Dictionary = model.state.duplicate(true)
    old.schema = 6
    old.erase("goals")
    check(model.valid(old), "a schema 6 snapshot is still accepted")
    var keep: Dictionary = model.state
    model.state = old
    check(not Store.new(directory).save(model).is_empty(), "the legacy snapshot writes")
    model.state = keep
    var loaded = World.new()
    check(Store.new(directory).load_latest(loaded), "the legacy snapshot loads")
    check(loaded.state.schema == 8, "loading upgrades to schema 8")
    check(loaded.state.goals.done.is_empty(), "migration starts with no objective finished")
    check(loaded.valid(loaded.state), "the migrated state validates")
    # Same rule as the villa works: presence decides, never the version alone.
    var mixed: Dictionary = loaded.state.duplicate(true)
    mixed.schema = 7
    mixed.erase("goals")
    check(not loaded.valid(mixed), "a current-schema save without objectives is rejected")
    var repaired = World.new()
    repaired.restore(mixed)
    check(repaired.state.goals.has("done"), "restore fills the missing objective block")

func rejection() -> void:
    var model = world()
    var broken: Dictionary = model.state.duplicate(true)
    broken.goals.done = ["nope"]
    check(not model.valid(broken), "an unknown objective id is rejected")
    broken = model.state.duplicate(true)
    broken.goals.done = ["stock_water", "stock_water"]
    check(not model.valid(broken), "a duplicated objective is rejected")
    broken = model.state.duplicate(true)
    broken.goals.farthest = -1.0
    check(not model.valid(broken), "a negative distance is rejected")
    broken = model.state.duplicate(true)
    broken.goals.farthest = 2000.0
    check(not model.valid(broken), "a distance outside the world is rejected")
    broken = model.state.duplicate(true)
    broken.goals.checked_at = 90000.0
    check(not model.valid(broken), "a check stamped in the future is rejected")
    broken = model.state.duplicate(true)
    broken.goals = []
    check(not model.valid(broken), "an objective block that is not a dictionary is rejected")

func persistence() -> void:
    var directory := "user://tests/goals_v1_%d" % Time.get_ticks_usec()
    var model = world()
    model.state.inventory = {"water": 3}
    for i in range(3):
        model.transfer_item("home", "water", true)
    settle(model)
    check("stock_water" in model.state.goals.done, "the goal completes before saving")
    var events: int = count(model, "goal_done")
    check(not Store.new(directory).save(model).is_empty(), "the objective saves")
    var loaded = World.new()
    check(Store.new(directory).load_latest(loaded), "the objective reloads")
    check("stock_water" in loaded.state.goals.done, "a finished objective survives a reload")
    check(count(loaded, "goal_done") == events, "a reload does not re-announce the goal")
    check(float(loaded.state.goals.farthest) >= 0.0, "the distance record survives a reload")
    check(loaded.valid(loaded.state), "a reloaded save with objectives validates")
    settle(loaded)
    check(count(loaded, "goal_done") == events, "the next tick does not repeat the entry")
