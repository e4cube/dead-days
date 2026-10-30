extends SceneTree
## Villa works acceptance: the yard gate and the villa front door are assembled from
## materials hauled back from the factory and the market, then behave like any other
## door. The pool stays dry until the municipal supply is connected, and even then it
## gives a fixed number of bottles per day instead of an unlimited well.
const Model = preload("res://scripts/survival.gd")
const World = preload("res://scripts/connected_model.gd")
const Crafting = preload("res://scripts/crafting.gd")
const DoorDamage = preload("res://scripts/door_damage.gd")
const Store = preload("res://scripts/save_store.gd")
const GATE := Vector3(106.1, 0.0, -2.5)
const VILLA_DOOR := Vector3(112.85, 0.0, -17.5)
const POOL := Vector3(123.3, 0.0, -10.8)
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
func _initialize() -> void:
    fresh()
    hauling()
    yard_gate()
    villa_front_door()
    pool_water()
    interruption()
    migration()
    persistence()
    print("SITES_V1_OK" if failures == 0 else "SITES_V1_FAILED")
    quit(0 if failures == 0 else 1)

func fresh() -> void:
    var model = world()
    check(model.state.schema == 8, "villa works bring the save to schema 8")
    check(model.sites().size() == 3, "three authored works are declared")
    check(not model.site_done("villa_gate") and not model.state.doors.has("villa_gate"),
        "the yard starts without a gate")
    check(not model.site_done("villa_door") and not model.state.doors.has("villa_door"),
        "the villa front starts without a door")
    check(model.state.pool.day == 1 and model.state.pool.left == 0, "the pool starts dry")
    check(model.pool_left() == 0 and model.draw_pool_water() == false, "a dry pool gives no water")
    check(model.valid(model.state), "fresh state with works validates")
    check(model.base_at(Vector3(106.1, 0.0, -8.0)) == "villa_07", "the yard belongs to the villa base")
    check(model.building_name("villa_gate") == "别墅院子", "a gate reads as the villa yard")
    check(model.building_name("villa_door") == "别墅", "the front door reads as the villa")
    check(model.door_anchor("villa_gate").distance_to(GATE) < 0.01, "the gate carries its own anchor")
    check(model.barrier_at(GATE + Vector3(0, 0, -4), GATE + Vector3(0, 0, 4)).is_empty(),
        "no gate means no barrier")
    var street = Model.new()
    street.start()
    check(street.sites().is_empty() and street.state.schema == 8, "the street scene has no works but keeps the schema")
    check(street.valid(street.state), "a street save without works stays valid")

func hauling() -> void:
    var model = world()
    check(model.state.containers.has("factory_pipe_rack"), "the factory stocks pipes and hardware")
    check(model.state.containers.factory_pipe_rack.pipe == 2 and model.state.containers.factory_pipe_rack.valve_kit == 2,
        "one factory trip covers the pool")
    check(model.state.containers.has("factory_gate_stack") and model.state.containers.has("market_hardware_stall"),
        "gate panels exist at both the factory and the market")
    check(model.state.containers.market_hardware_stall.gate_panel == 1, "the market sells exactly one gate panel")
    var gate_load: float = model.rules.items.gate_panel.weight + model.rules.items.metal_scrap.weight + model.rules.items.hammer.weight
    check(gate_load <= float(model.rules.capacity), "the gate fits in one backpack load")
    var water_load: float = model.rules.items.pipe.weight * 2.0 + model.rules.items.valve_kit.weight * 2.0 + model.rules.items.hammer.weight
    check(water_load <= float(model.rules.capacity), "pipes, hardware and hammer fit in one load")
    model.state.inventory = {"gate_panel": 1, "metal_scrap": 1, "hammer": 1}
    check(model.weight() <= float(model.rules.capacity), "hauled gate materials stay under capacity")

func yard_gate() -> void:
    var model = world()
    at(model, Vector3(106.1, 0.0, 0.5))
    check(Crafting.reason(model, "install_villa_gate") == "需要站到院子门旁",
        "installing is refused from across the yard")
    model.state.inventory = {"gate_panel": 1, "metal_scrap": 1, "hammer": 1}
    at(model, Vector3(106.1, 0.0, -1.7))
    check(Crafting.reason(model, "install_villa_gate") == "", "installing is offered at the pillars")
    check(Crafting.begin(model, "install_villa_gate") == "", "installing starts")
    check(model.state.inventory.gate_panel == 0 and model.state.inventory.hammer == 1,
        "the panel is spent and the hammer kept")
    check(model.state.craft.door == "", "a site craft records no door")
    check(not Crafting.tick(model, 20.0) and not model.site_done("villa_gate"), "partial work leaves no gate")
    check(Crafting.tick(model, 20.0), "the gate finishes")
    check(model.site_done("villa_gate") and model.state.doors.has("villa_gate"), "the installed gate owns a door")
    check(model.state.doors.villa_gate == false, "the new gate starts closed")
    check(DoorDamage.health(model, "villa_gate") == 120.0 and DoorDamage.level(model, "villa_gate") == 0,
        "the gate starts at the base durability")
    check(model.valid(model.state), "an installed gate keeps the save valid")
    check(model.barrier_at(Vector3(106.1, 0, -8), Vector3(106.1, 0, 4)).get("id", "") == "villa_gate",
        "a closed gate is a barrier")
    check(model.barrier_at(Vector3(106.1, 0, -8), Vector3(106.1, 0, 4)).goal.z < GATE.z,
        "the barrier goal sits on the side the zombie stands on")
    check(model.barrier_at(Vector3(106.1, 0, 6), Vector3(106.1, 0, 9)).is_empty(),
        "both ends outside the yard are not a barrier")
    check(model.barrier_at(Vector3(90.0, 0, -8), Vector3(90.0, 0, 4)).is_empty(),
        "a crossing far from the gate is not blocked")
    model.toggle_door("villa_gate")
    check(model.barrier_at(Vector3(106.1, 0, -8), Vector3(106.1, 0, 4)).is_empty(), "an open gate lets zombies through")
    model.toggle_door("villa_gate")
    check(DoorDamage.hit(model, "villa_gate", 120.0, "probe"), "zombies can batter the gate")
    check(model.state.doors.villa_gate and model.barrier_at(Vector3(106.1, 0, -8), Vector3(106.1, 0, 4)).is_empty(),
        "a breached gate stops blocking")
    model.state.inventory = {"wood_plank": 2, "hammer": 1}
    check(Crafting.begin(model, "repair_door", "villa_gate") == "" and Crafting.tick(model, 20.0), "the gate can be rebuilt")
    check(DoorDamage.health(model, "villa_gate") == 120.0, "rebuilding restores the gate")
    model.state.inventory = {"wood_plank": 3, "metal_scrap": 1, "hammer": 1}
    check(Crafting.begin(model, "reinforce_door", "villa_gate") == "" and Crafting.tick(model, 45.0), "the gate can be reinforced")
    check(DoorDamage.max_health(model, "villa_gate") == 170.0, "reinforcement raises the gate ceiling")
    check(Crafting.reason(model, "install_villa_gate") == "这项工事已经做完", "the gate is only installed once")
    check(model.valid(model.state), "a repaired and reinforced gate still validates")

func villa_front_door() -> void:
    var model = world()
    at(model, VILLA_DOOR + Vector3(0, 0, 0.6))
    model.state.inventory = {"wood_plank": 2, "metal_scrap": 1, "hammer": 1}
    check(Crafting.reason(model, "install_villa_door") == "", "the front opening accepts a door")
    check(Crafting.begin(model, "install_villa_door") == "" and Crafting.tick(model, 30.0), "the front door is hung")
    check(model.site_done("villa_door") and model.state.doors.has("villa_door"), "the villa front now has a door")
    check(DoorDamage.health(model, "villa_door") == 120.0, "the front door starts intact")
    check(model.barrier_at(Vector3(112.85, 0, -20), Vector3(112.85, 0, -14)).get("id", "") == "villa_door",
        "the front door blocks the way from the house into the yard")
    check(model.valid(model.state), "a hung front door validates")

func pool_water() -> void:
    var model = world()
    at(model, POOL + Vector3(0, 0, 4.5))
    model.state.inventory = {"pipe": 2, "valve_kit": 2, "hammer": 1}
    check(Crafting.reason(model, "connect_villa_water") == "需要站到泳池供水旁",
        "piping work needs the pool in reach")
    at(model, POOL + Vector3(0, 0, 2.6))
    check(Crafting.reason(model, "connect_villa_water") == "", "standing at the pool allows the work")
    check(Crafting.begin(model, "connect_villa_water") == "", "the supply work starts")
    check(model.state.inventory.pipe == 0 and model.state.inventory.valve_kit == 0, "pipes and hardware are spent")
    check(not Crafting.tick(model, 30.0) and not model.site_done("villa_water"), "the pool stays dry mid-work")
    check(Crafting.tick(model, 30.0), "the supply is connected")
    check(model.site_done("villa_water"), "the flag records the connection")
    check(model.pool_left() == 3, "a fresh pool holds three bottles")
    check(model.draw_pool_water() and model.state.inventory.water == 1, "the pool fills a bottle")
    check(model.pool_left() == 2, "a bottle costs one unit")
    check(model.draw_pool_water() and model.draw_pool_water(), "two more bottles come out")
    check(model.pool_left() == 0 and not model.draw_pool_water(), "the daily pool runs dry")
    check(model.pool_reason() == "今天的水接完了，明天再来", "an empty pool explains itself")
    model.state.calendar.last_summary_day = 1
    model.state.day = 2
    check(model.pool_left() == 3, "the pool refills with the new day")
    model.refresh_pool()
    check(model.state.pool.left == 3 and model.state.pool.day == 2, "the counter resets once per day")
    model.state.inventory = {"water": 5}
    check(model.pool_reason() == "背包负重不足，先放下东西", "a full pack refuses more water")
    check(model.valid(model.state), "pool state validates")

func interruption() -> void:
    var model = world()
    at(model, POOL + Vector3(0, 0, 2.4))
    model.state.inventory = {"pipe": 2, "valve_kit": 2, "hammer": 1}
    check(Crafting.begin(model, "connect_villa_water") == "", "work starts before the horde")
    model.state.zombies = [model.make_zombie("probe", [123.3, 0.0, -8.0])]
    var blocked: String = Crafting.danger(model, POOL + Vector3(0, 0, 2.4))
    check(not blocked.is_empty(), "a zombie at the pool is real danger")
    Crafting.cancel(model, blocked, true)
    check(model.state.inventory.pipe == 2 and model.state.inventory.valve_kit == 2,
        "danger refunds the hauled materials")
    check(not model.site_done("villa_water"), "an interrupted supply stays dry")
    check(Crafting.reason(model, "connect_villa_water") == "附近有僵尸，无法安心做手上的活",
        "danger also blocks a fresh start")

func migration() -> void:
    var model = world()
    var directory := "user://tests/sites_v1_old_%d" % Time.get_ticks_usec()
    var old: Dictionary = model.state.duplicate(true)
    old.schema = 5
    old.erase("base_works")
    old.erase("pool")
    check(model.valid(old), "a schema 5 snapshot is still accepted")
    var keep: Dictionary = model.state
    model.state = old
    check(not Store.new(directory).save(model).is_empty(), "the legacy snapshot writes")
    model.state = keep
    var loaded = World.new()
    check(Store.new(directory).load_latest(loaded), "the legacy snapshot loads")
    check(loaded.state.schema == 8, "loading upgrades to schema 8")
    check(loaded.state.base_works.has("villa_gate") and not loaded.site_done("villa_gate"),
        "works are filled in as not done")
    check(loaded.state.pool.left == 0 and loaded.pool_left() == 0, "the pool stays dry after migration")
    check(loaded.valid(loaded.state), "the migrated state validates")
    var broken: Dictionary = loaded.state.duplicate(true)
    broken.base_works.erase("villa_door")
    check(not loaded.valid(broken), "a save that forgets a work is rejected")
    broken = loaded.state.duplicate(true)
    broken.base_works.villa_gate = true
    check(not loaded.valid(broken), "an installed gate without its door is rejected")
    broken = loaded.state.duplicate(true)
    broken.pool.left = 9
    check(not loaded.valid(broken), "more water than the pool can hold is rejected")

func persistence() -> void:
    var directory := "user://tests/sites_v1_%d" % Time.get_ticks_usec()
    var model = world()
    at(model, Vector3(106.1, 0.0, -1.7))
    model.state.inventory = {"gate_panel": 1, "metal_scrap": 1, "hammer": 1}
    check(Crafting.begin(model, "install_villa_gate") == "" and Crafting.tick(model, 40.0), "gate fixture installs")
    at(model, POOL + Vector3(0, 0, 2.4))
    model.state.inventory = {"pipe": 2, "valve_kit": 2, "hammer": 1}
    check(Crafting.begin(model, "connect_villa_water") == "" and Crafting.tick(model, 60.0), "supply fixture connects")
    model.state.inventory = {}
    check(model.draw_pool_water(), "one bottle is drawn before saving")
    check(not Store.new(directory).save(model).is_empty(), "installed works save")
    var loaded = World.new()
    check(Store.new(directory).load_latest(loaded), "installed works reload")
    check(loaded.site_done("villa_gate") and loaded.state.doors.has("villa_gate"), "the gate survives a reload")
    check(loaded.site_done("villa_water") and loaded.pool_left() == 2, "the pool level survives a reload")
    check(loaded.valid(loaded.state), "a reloaded base validates")
