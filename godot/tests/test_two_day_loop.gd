extends SceneTree
## Two-day continuous-play acceptance for the sixth milestone. One save file is
## carried through the whole loop the roadmap describes: prepare at the base, walk
## to the market, loot, take a hit, retreat, store the haul, eat and drink, sleep
## through the night, and open the next day from disk with every number intact.
const World = preload("res://scripts/connected_model.gd")
const Rest = preload("res://scripts/rest.gd")
const Store = preload("res://scripts/save_store.gd")
const Timeline = preload("res://scripts/survival_time.gd")
const Market := Vector3(67.0, 0.0, -14.5)
## Inside the house, within reach of the bed: z=2 would be standing in the street.
const HOME := Vector3(-7.0, 0.0, -3.0)
const HAUL := ["market_produce_a", "market_produce_b", "market_shop_counter"]
var failures := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func total_in(items: Dictionary) -> int:
    var total := 0
    for id in items:
        total += int(items[id])
    return total

func count_event(model: RefCounted, kind: String) -> int:
    var total := 0
    for entry in model.state.events:
        if entry.kind == kind:
            total += 1
    return total

func at(model: RefCounted, position: Vector3) -> void:
    model.state.position = [position.x, position.y, position.z]

## Walk the clock forward to a wall time on the current day.
func advance_to(model: RefCounted, target: float) -> void:
    var guard := 0
    while model.state.minutes < target - 0.001 and model.state.stats.health > 0 and guard < 80:
        var remaining: float = target - model.state.minutes
        model.advance_time(minf(30.0, remaining / float(model.rules.time.minutes_per_second)))
        guard += 1

## Sleep until the bed's alarm, finishing the rest the way the scene does.
func sleep_through(model: RefCounted) -> void:
    check(Rest.begin(model, "home_bed", "night") == "", "the bed accepts a night sleep")
    var guard := 0
    while model.state.rest.active and guard < 400:
        model.advance_time(5.0, true)
        guard += 1
        if model.state.rest.active and Timeline.absolute(model) >= float(model.state.rest.target) - 0.001:
            Rest.finish(model)
    check(not model.state.rest.active, "the night actually ends")
    check(model.state.stats.health > 0, "the player is alive in the morning")

func _initialize() -> void:
    var directory := "user://tests/two_day_loop_%d" % Time.get_ticks_usec()
    var model = World.new()
    model.start()
    model.state.zombies = []

    # --- day 1, morning: 准备出发 ---
    check(model.state.day == 1, "the run starts on day one")
    check(model.base_id() == "home", "the street house is the base")
    check(model.set_base("home"), "the base can be confirmed")
    check(model.state.doors.home == false, "the door starts shut")
    check(model.valid(model.state), "the opening state validates")

    # --- 地图选点与赶路 ---
    at(model, Market)
    model.discover(Market)
    check("market_07" in model.state.exploration.discovered, "the market is discovered on arrival")
    model.advance_time(0.6)
    check("long_trip" in model.state.goals.done, "the walk out completes the travel objective")

    # --- 新区域搜刮 ---
    var carried_before: int = total_in(model.state.inventory)
    var got := 0
    for id in HAUL:
        got += model.loot(id)
    check(got > 0, "the market still has supplies to take")
    check(total_in(model.state.inventory) == carried_before + got, "looting neither creates nor destroys items")
    check(count_event(model, "looted") >= 1, "the haul is written into the log")

    # --- 遇敌与撤退 ---
    model.state.zombies = [model.make_zombie("probe", [Market.x + 2.0, 0.0, Market.z + 1.0])]
    var health_before: float = model.state.stats.health
    model.damage_player(18.0, "probe")
    check(model.state.stats.health < health_before, "an attack costs health")
    check(count_event(model, "injured") >= 1, "the hit is written into the log")
    model.state.zombies = []
    model.advance_time(6.0)

    # --- 回据点存物资 ---
    at(model, HOME)
    model.advance_time(0.6)
    check(model.base_at(HOME) == "home", "the player is back inside the base")

    # --- 饮食与治疗 ---
    model.state.stats.hunger = 55.0
    model.state.stats.thirst = 55.0
    model.state.stats.health = 72.0
    var ate := false
    var drank := false
    for id in ["food", "water", "bandage"]:
        if model.state.inventory.get(id, 0) > 0:
            if model.use_item(id):
                if id == "food":
                    ate = true
                elif id == "water":
                    drank = true
    check(ate, "a canned meal is eaten at the base")
    check(drank, "a bottle of water is drunk at the base")

    var stored := 0
    for id in ["food", "water", "bandage"]:
        var guard := 0
        while model.state.inventory.get(id, 0) > 0 and guard < 20:
            guard += 1
            if model.transfer_item("home", id, true):
                stored += 1
    check(stored > 0, "the haul is stored in the base cupboard")
    check(count_event(model, "stored") == stored, "each stored item is its own log line")
    check(model.state.inventory.get("food", 0) == 0, "nothing edible is left in the pack")

    # --- 手写日记与情绪 ---
    model.manual("今天从市集背回了水和绷带，回来的路上挨了一下。", "紧张")
    check(count_event(model, "manual") == 1, "a handwritten line is kept")

    # --- 安全睡眠 ---
    advance_to(model, 1080.0)
    check(model.state.stats.health > 0, "the player survives the evening")
    sleep_through(model)
    check(model.state.day == 2, "sleeping through the night opens day two")
    check(count_event(model, "daily_summary") == 1, "day one is summarised exactly once")
    var first: Dictionary = {}
    for entry in model.state.events:
        if entry.kind == "daily_summary":
            first = entry.payload
    check(int(first.get("summary_day", 0)) == 1, "the summary names day one")
    check(int(first.get("searches", 0)) >= 1, "the summary counts the searches")
    check(int(first.get("stored", 0)) > 0, "the summary counts what was carried home")
    check(int(first.get("manual", 0)) == 1, "the summary counts the handwritten line")
    check(int(first.get("goals", 0)) >= 1, "the summary counts the objectives finished that day")
    var summary_text := ""
    for entry in model.state.events:
        if entry.kind == "daily_summary":
            summary_text = entry.text
    check("个小目标" in summary_text, "the summary sentence mentions objectives when some were finished")
    check(count_event(model, "rest_finished") == 1, "the night is logged as finished")

    # --- 存档 ---
    check(not Store.new(directory).save(model).is_empty(), "the two-day run saves")
    var loaded = World.new()
    check(Store.new(directory).load_latest(loaded), "the two-day run reloads")
    check(loaded.state.day == 2, "the reloaded run is still on day two")
    check(loaded.valid(loaded.state), "the reloaded run validates")
    check(loaded.state.exploration.discovered == model.state.exploration.discovered,
        "discoveries survive the reload")
    check(loaded.state.containers.home == model.state.containers.home, "the cupboard survives the reload")
    # Compare after a JSON round trip: the save is JSON, so a live int and a
    # reloaded float are the same amount of rice, not two different values.
    check(loaded.state.inventory == JSON.parse_string(JSON.stringify(model.state.inventory)),
        "the pack survives the reload")
    check(loaded.state.goals.done == model.state.goals.done, "finished objectives survive the reload")
    check(loaded.pool_left() == 0, "a dry pool is still dry the next morning")

    # --- day 2: 出门、回来、再睡一夜 ---
    loaded.state.zombies = []
    at(loaded, Vector3(20.0, 0.0, 2.0))
    loaded.advance_time(0.6)
    check(loaded.state.day == 2, "the second outing stays on day two")
    at(loaded, HOME)
    advance_to(loaded, 1090.0)
    if loaded.state.minutes < 1080.0:
        # The clock may already be past dusk after the reload; step to the next night.
        advance_to(loaded, 1090.0)
    sleep_through(loaded)
    check(loaded.state.day == 3, "the second night opens day three")
    check(count_event(loaded, "daily_summary") == 2, "day two is summarised exactly once")

    # --- 一整轮之后仍然守恒 ---
    check(loaded.valid(loaded.state), "the two-day save still validates")
    check(loaded.state.stats.health > 0, "the player is still alive after two nights")
    for id in loaded.state.goals.done:
        check(not id.is_empty(), "no empty objective id was recorded")

    print("TWO_DAY_LOOP_OK" if failures == 0 else "TWO_DAY_LOOP_FAILED")
    quit(0 if failures == 0 else 1)
