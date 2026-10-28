extends SceneTree
## Base-building acceptance: one place can be claimed as home, its door can be
## repaired and reinforced, and the recipes that improve survival cannot create
## or destroy materials while they run.
const Model = preload("res://scripts/survival.gd")
const World = preload("res://scripts/connected_model.gd")
const Crafting = preload("res://scripts/crafting.gd")
const DoorDamage = preload("res://scripts/door_damage.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)
func calm(model: RefCounted) -> void:
    model.state.zombies = []
func _initialize() -> void:
    shelters()
    doors()
    recipes()
    interruption()
    guardrails()
    persistence()
    print("BASE_V1_OK" if failures == 0 else "BASE_V1_FAILED")
    quit(0 if failures == 0 else 1)

func shelters() -> void:
    var model = Model.new()
    model.start()
    calm(model)
    check(model.base_at(Vector3(-7.0, 0, -2.0)) == "home", "street house interior resolves to home")
    check(model.base_at(Vector3(0.0, 0, 4.0)) == "", "open street is not a shelter")
    var world = World.new()
    world.start()
    calm(world)
    check(world.base_at(Vector3(115.0, 1.0, -20.0)) == "villa_07", "authored villa interior is claimable")
    check(world.base_at(Vector3(115.0, 3.62, -20.0)) == "villa_07", "villa upper floor belongs to the same shelter")
    check(world.base_at(Vector3(165.0, 1.0, 22.0)) == "factory_07", "factory floor is claimable")
    world.state.position = [115.0, 1.0, -20.0]
    check(world.set_base("villa_07") and world.in_base(), "villa can become the base and counts as inside")
    world.state.position = [-7.0, 0.0, -2.0]
    check(not world.in_base(), "home stops counting once the villa is the base")
    check(world.set_base("home") and world.in_base(), "the base can be moved back to home")
    check(world.valid(world.state), "changed base still validates")

func doors() -> void:
    var model = Model.new()
    model.start()
    calm(model)
    check(DoorDamage.max_health(model, "home") == 120.0, "ceiling starts from the rules value")
    check(DoorDamage.level(model, "home") == 0, "no reinforcement by default")
    model.state.position = [-7.0, 0.0, 0.0]
    model.state.inventory = {"wood_plank": 3, "metal_scrap": 1, "hammer": 1}
    check(model.weight() <= float(model.rules.capacity), "door fixture fits in the backpack")
    model.state.door_health.home = 30.0
    check(Crafting.reason(model, "repair_door", "home") == "", "repair is offered on a damaged door")
    check(Crafting.begin(model, "repair_door", "home") == "", "repair starts")
    check(model.state.inventory.get("wood_plank", 0) == 1 and model.state.inventory.get("hammer", 0) == 1,
        "repair spends planks, keeps the reusable hammer")
    check(not Crafting.tick(model, 5.0) and DoorDamage.health(model, "home") == 30.0,
        "partial work leaves the door untouched")
    check(Crafting.tick(model, 20.0), "repair completes")
    check(DoorDamage.health(model, "home") == 120.0, "repair restores the current ceiling")
    check(not Crafting.active(model) and model.state.craft.spent.is_empty(), "finished craft clears its record")
    check(model.valid(model.state), "state stays save-valid after a repair")
    model.state.inventory = {"wood_plank": 3, "metal_scrap": 1, "hammer": 1}
    check(Crafting.begin(model, "reinforce_door", "home") == "", "reinforcement starts")
    check(Crafting.tick(model, 45.0), "reinforcement completes")
    check(DoorDamage.max_health(model, "home") == 170.0 and DoorDamage.health(model, "home") == 170.0,
        "one layer raises the ceiling and the current points together")
    model.state.inventory = {"wood_plank": 3, "metal_scrap": 1, "hammer": 1}
    check(Crafting.begin(model, "reinforce_door", "home") == "" and Crafting.tick(model, 45.0), "second layer completes")
    check(DoorDamage.max_health(model, "home") == 220.0, "second layer adds another step")
    model.state.inventory = {"wood_plank": 3, "metal_scrap": 1, "hammer": 1}
    check(Crafting.reason(model, "reinforce_door", "home") == "加固已到上限", "reinforcement stops at the configured limit")
    model.state.door_health.home = 0.0
    model.state.doors.home = true
    check(Crafting.reason(model, "reinforce_door", "home") == "门已损坏，先修复再加固", "breached door must be repaired first")
    model.state.inventory = {"wood_plank": 2, "hammer": 1}
    check(Crafting.begin(model, "repair_door", "home") == "" and Crafting.tick(model, 20.0), "breached door can be repaired")
    check(DoorDamage.health(model, "home") == 220.0 and model.state.doors.home, "a rebuilt door stays open until closed by hand")
    model.toggle_door("home")
    check(not model.state.doors.home, "repaired door closes again")
    check(model.valid(model.state), "reinforced door survives validation")

func recipes() -> void:
    var model = Model.new()
    model.start()
    calm(model)
    model.state.position = [-7.0, 0.0, -2.0]
    model.state.inventory = {"food": 2, "water": 2, "cloth": 4}
    check(Crafting.reason(model, "cook_meal") == "", "cooking is available inside the base")
    check(Crafting.begin(model, "cook_meal") == "", "cooking starts")
    check(model.state.inventory.food == 1 and model.state.inventory.water == 1, "ingredients are taken up front")
    check(Crafting.reason(model, "cook_meal") == "已经在制作中", "a second craft is refused while one runs")
    Crafting.cancel(model, "主动停手")
    check(model.state.inventory.food == 2 and model.state.inventory.water == 2, "cancel refunds every ingredient exactly once")
    check(not Crafting.active(model) and model.state.craft.spent.is_empty(), "cancel clears the craft record")
    check(Crafting.begin(model, "cook_meal") == "" and Crafting.tick(model, 15.0), "cooking completes")
    check(model.state.inventory.get("hot_meal", 0) == 1, "cooked meal lands in the backpack")
    check(model.state.events.back().kind == "crafted", "completion is journalled")
    var before: float = model.state.stats.hunger
    check(model.use_item("hot_meal") and model.state.stats.hunger > before, "cooked meal restores more than a raw can")
    check(Crafting.begin(model, "make_bandage") == "" and Crafting.tick(model, 10.0), "bandage recipe completes")
    check(model.state.inventory.get("bandage", 0) == 1 and model.state.inventory.get("cloth", 0) == 2,
        "bandage recipe consumes exactly two strips")
    check(model.valid(model.state), "crafted items keep the save valid")

func interruption() -> void:
    var model = Model.new()
    model.start()
    calm(model)
    model.state.position = [-7.0, 0.0, -2.0]
    model.state.inventory = {"food": 1, "water": 1}
    check(Crafting.begin(model, "cook_meal") == "", "work starts before the horde arrives")
    model.state.zombies = [model.make_zombie("probe", [-8.0, 0.0, 0.5])]
    var blocked: String = Crafting.danger(model, Vector3(-7.0, 0, -2.0))
    check(not blocked.is_empty(), "an adjacent zombie is real danger")
    Crafting.cancel(model, blocked, true)
    check(model.state.inventory.food == 1 and model.state.inventory.water == 1, "danger interruption refunds ingredients")
    check(model.state.events.back().kind == "craft_interrupted", "interruption is journalled")
    check(Crafting.reason(model, "cook_meal") == "附近有僵尸，无法安心做手上的活", "danger also blocks a fresh start")
    model.state.zombies = []
    check(Crafting.reason(model, "cook_meal") == "", "clearing the horde makes the base usable again")

func guardrails() -> void:
    var model = Model.new()
    model.start()
    calm(model)
    model.state.position = [0.0, 0.0, 4.0]
    model.state.inventory = {"food": 1, "water": 1}
    check(Crafting.reason(model, "cook_meal") == "只能在据点内制作", "cooking needs the base")
    model.state.inventory = {"wood_plank": 2, "hammer": 1}
    model.state.door_health.home = 40.0
    check(Crafting.reason(model, "repair_door", "home") == "需要站到门旁", "door work is refused from across the street")
    model.state.position = [-7.0, 0.0, 0.6]
    check(Crafting.reason(model, "repair_door", "home") == "", "door work is allowed at arm's length")
    model.state.inventory = {"wood_plank": 1, "hammer": 1}
    check(Crafting.reason(model, "repair_door", "home") == "材料不足：木板 1/2", "missing material names the shortfall")
    model.state.inventory = {"wood_plank": 2}
    check(Crafting.reason(model, "repair_door", "home") == "缺少工具：锤子", "missing tool names the tool")
    model.state.inventory = {"wood_plank": 2, "hammer": 1}
    model.state.door_health.home = 120.0
    check(Crafting.reason(model, "repair_door", "home") == "这扇门不需要修复", "an intact door needs no repair")

func persistence() -> void:
    var directory := "user://tests/base_v1_%d" % Time.get_ticks_usec()
    var model = Model.new()
    model.start()
    calm(model)
    model.state.position = [-7.0, 0.0, 0.0]
    model.state.inventory = {"wood_plank": 3, "metal_scrap": 1, "hammer": 1}
    check(Crafting.begin(model, "reinforce_door", "home") == "" and Crafting.tick(model, 45.0), "fixture reinforcement completes")
    check(not Store.new(directory).save(model).is_empty(), "reinforced base saves")
    var loaded = Model.new()
    check(Store.new(directory).load_latest(loaded), "reinforced base reloads")
    check(DoorDamage.level(loaded, "home") == 1 and DoorDamage.max_health(loaded, "home") == 170.0,
        "reinforcement survives a reload")
    loaded.state.zombies = []
    loaded.state.position = [-7.0, 0.0, -2.0]
    loaded.state.inventory = {"food": 2, "water": 2}
    check(Crafting.begin(loaded, "cook_meal") == "", "work starts before saving")
    check(loaded.valid(loaded.state), "an in-progress craft is a valid save")
    var mid := directory + "_mid"
    check(not Store.new(mid).save(loaded).is_empty(), "mid-craft save writes")
    var resumed = Model.new()
    check(Store.new(mid).load_latest(resumed) and Crafting.active(resumed), "craft resumes after loading")
    check(Crafting.tick(resumed, 15.0) and resumed.state.inventory.get("hot_meal", 0) == 1,
        "resumed craft still produces its product")
    check(resumed.state.inventory.food == 1 and resumed.state.inventory.water == 1,
        "resumed craft never duplicates ingredients")
