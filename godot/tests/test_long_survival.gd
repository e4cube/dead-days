extends SceneTree
## Ten-day survival acceptance: one save, one player, ten nights, real entry
## points only (transfer/loot/use/craft/sleep/save). The point is the economy —
## can a competent player live a week and a half on what the map actually holds,
## and does the world stay finite while they do it?
##
## The route is written against real container ids dumped from the live state
## (`audit_containers.gd`), so a rename in data breaks this test instead of
## silently changing what "survived ten days" means.
const World = preload("res://scripts/connected_model.gd")
const Rest = preload("res://scripts/rest.gd")
const Crafting = preload("res://scripts/crafting.gd")
const DoorDamage = preload("res://scripts/door_damage.gd")
const Store = preload("res://scripts/save_store.gd")
const Timeline = preload("res://scripts/survival_time.gd")

const HOME := Vector3(-7.0, 0.0, -3.0)
## 门在 z=0 那一面，修门必须站过去，和睡觉的位置不是同一个点。
const DOOR := Vector3(-7.0, 0.0, -0.6)
const MARKET := Vector3(67.0, 0.0, -14.5)
const DAYS := 10
## 一天的出门顺序：水源排前面，锤子必须在第 4 天之前到手。
const ROUTE := ["factory_workbench", "market_produce_a", "villa_shed",
    "market_shop_counter", "shop", "villa_fridge", "pantry_home_fridge",
    "pantry_home", "east_home_fridge", "villa_cabinet", "factory_parts_crate",
    "end_home_fridge", "market_produce_b", "market_fabric", "clinic",
    "east_home", "market_hardware_stall", "factory_gate_stack"]
## 据点里可以存放的地方，按顺序尝试。对照组只认住宅自己的柜子和冰箱。
const STOCK := ["home", "home_fridge", "villa_cabinet", "clinic"]
const HOME_ONLY := ["home", "home_fridge"]

var failures := 0
var log_lines: Array = []
var stock_ids: Array = STOCK

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func at(model: RefCounted, position: Vector3) -> void:
    model.state.position = [position.x, position.y, position.z]

func total(model: RefCounted) -> int:
    var count := 0
    for id in model.state.containers:
        for item in model.state.containers[id]:
            count += int(model.state.containers[id][item])
    for item in model.state.inventory:
        count += int(model.state.inventory[item])
    return count

func stock(model: RefCounted, item: String) -> int:
    var count := 0
    for id in stock_ids:
        count += int(model.state.containers.get(id, {}).get(item, 0))
    return count

## Take from the base shelf into the pack. Fails honestly when 5 kg is already full.
func fetch(model: RefCounted, item: String, want: int) -> int:
    var got := 0
    for id in stock_ids:
        while got < want and int(model.state.containers.get(id, {}).get(item, 0)) > 0:
            if not model.transfer_item(id, item, false):
                return got
            got += 1
        if got >= want:
            break
    return got

func deposit_all(model: RefCounted) -> int:
    var moved := 0
    for item in model.state.inventory.keys():
        var guard := 0
        while int(model.state.inventory.get(item, 0)) > 0 and guard < 40:
            guard += 1
            var placed := false
            for id in stock_ids:
                if model.transfer_item(id, item, true):
                    moved += 1
                    placed = true
                    break
            if not placed:
                break
    return moved

## One outing: walk out, take what the target holds, walk back and put it away.
func trip(model: RefCounted, target: String) -> int:
    at(model, MARKET)
    model.discover(MARKET)
    model.advance_time(0.5)
    var taken: int = model.loot(target)
    at(model, HOME)
    model.advance_time(0.5)
    deposit_all(model)
    return taken

func eat_to(model: RefCounted, stat: String, floor_value: float, item: String) -> int:
    var used := 0
    while model.state.stats[stat] < floor_value and int(model.state.inventory.get(item, 0)) > 0:
        if not model.use_item(item):
            break
        used += 1
    return used

func advance_to(model: RefCounted, target: float) -> void:
    var guard := 0
    while model.state.minutes < target - 0.001 and model.state.stats.health > 0 and guard < 400:
        model.advance_time(minf(20.0, (target - model.state.minutes) / 2.0))
        guard += 1

func sleep_through(model: RefCounted) -> void:
    check(Rest.begin(model, "home_bed", "night") == "", "the bed takes a night sleep")
    var guard := 0
    while model.state.rest.active and guard < 600:
        model.advance_time(5.0, true)
        guard += 1
        if model.state.rest.active and Timeline.absolute(model) >= float(model.state.rest.target) - 0.001:
            Rest.finish(model)
    check(not model.state.rest.active, "the night ends")
    check(model.state.stats.health > 0, "the player wakes up alive")

func count_event(model: RefCounted, kind: String) -> int:
    var total_count := 0
    for entry in model.state.events:
        if entry.kind == kind:
            total_count += 1
    return total_count

func _initialize() -> void:
    var directory := "user://tests/long_survival_%d" % Time.get_ticks_usec()
    var model = World.new()
    model.start()
    model.state.zombies = []
    check(model.set_base("home"), "the street house is the base")
    check(model.state.doors.home == false, "the door starts shut")

    var opening_total := total(model)
    var opening_water := stock(model, "water") + int(model.state.inventory.get("water", 0))
    var opening_food := stock(model, "food") + int(model.state.inventory.get("food", 0))
    var route_index := 0
    var repairs := 0
    var reinforces := 0
    var meals := 0
    var door_broken_day := 0

    for day in range(1, DAYS + 1):
        check(model.state.day == day, "day %d starts on schedule" % day)
        check(model.state.stats.health > 0, "day %d starts with a living player" % day)

        # --- 早上：吃当天的第一顿，然后把剩下的放回柜子，空手出门 ---
        fetch(model, "water", 2)
        fetch(model, "food", 1)
        eat_to(model, "thirst", 45.0, "water")
        eat_to(model, "hunger", 60.0, "food")
        deposit_all(model)

        # --- 出门：每天一趟，按固定路线，不无脑搬空地图 ---
        var target: String = ROUTE[route_index % ROUTE.size()]
        route_index += 1
        trip(model, target)

        # --- 傍晚：再吃一顿，剩余归档 ---
        fetch(model, "water", 2)
        fetch(model, "food", 2)
        eat_to(model, "thirst", 45.0, "water")
        eat_to(model, "hunger", 60.0, "food")
        deposit_all(model)

        # --- 第 4 夜门口被撞：门耐久必须真的挡事，也必须真的能修 ---
        if day == 4:
            for hit in range(20):
                if DoorDamage.broken(model, "home"):
                    break
                DoorDamage.hit(model, "home", 12.0, "probe")
            check(DoorDamage.broken(model, "home"), "ten hits break an unreinforced door")
            check(model.state.doors.home, "a breached door swings open")
            check(Rest.reason(model, "home_bed") == "房门已损坏，需寻找另一处安全休息点",
                "a breached entrance is not a bed: " + Rest.reason(model, "home_bed"))
            door_broken_day = day
            check(model.state.doors.home, "a breached door cannot even be closed until it is repaired")
            check(Rest.reason(model, "home_bed") == "房门已损坏，需寻找另一处安全休息点",
                "a breached entrance is not a bed: " + Rest.reason(model, "home_bed"))
            # 修门要站到门口，而不是站在床边。
            at(model, DOOR)
            fetch(model, "hammer", 1)
            fetch(model, "wood_plank", 2)
            check(Crafting.begin(model, "repair_door", "home") == "",
                "the broken door can be repaired: " + Crafting.reason(model, "repair_door", "home")
                + " inv=" + str(model.state.inventory))
            check(Crafting.tick(model, 20.0), "the repair takes its twenty minutes")
            check(DoorDamage.health(model, "home") == 120.0, "the door is whole again")
            repairs += 1
            at(model, HOME)
            check(Rest.reason(model, "home_bed") == "先关上房门再休息", "a rebuilt door still stands open")
            at(model, DOOR)
            model.toggle_door("home")
            at(model, HOME)
            check(Rest.reason(model, "home_bed") == "", "the rebuilt door can be shut again")
            at(model, DOOR)
            fetch(model, "wood_plank", 3)
            fetch(model, "metal_scrap", 1)
            check(Crafting.begin(model, "reinforce_door", "home") == "", "one layer of boards goes on")
            check(Crafting.tick(model, 45.0), "reinforcement finishes")
            check(DoorDamage.level(model, "home") == 1 and DoorDamage.max_health(model, "home") == 170.0,
                "the reinforced door raises its own ceiling")
            reinforces += 1
            at(model, HOME)

        # --- 第 6 天：做一顿热餐，证明烹饪在经济里真的有用 ---
        if day == 6:
            fetch(model, "food", 1)
            fetch(model, "water", 1)
            check(Crafting.reason(model, "cook_meal") == "", "cooking is available in the base")
            check(Crafting.begin(model, "cook_meal") == "", "cooking starts")
            check(Crafting.tick(model, 15.0), "cooking finishes")
            check(int(model.state.inventory.get("hot_meal", 0)) == 1, "one hot meal comes out")
            meals += 1
            model.state.stats.hunger = 20.0
            check(model.use_item("hot_meal"), "the hot meal is eaten")
            check(model.state.stats.hunger > 70.0, "a hot meal is worth more than a cold can")

        # --- 傍晚归位，夜里睡觉 ---
        deposit_all(model)
        advance_to(model, 1080.0)
        check(model.state.stats.health > 0, "day %d survives until dusk" % day)
        sleep_through(model)

        log_lines.append("day %2d | water %2d | food %2d | health %3.0f | goal %d" % [
            day, stock(model, "water"), stock(model, "food"),
            model.state.stats.health, model.state.goals.done.size()])

        # --- 第 5 夜存一次档，读回来必须是同一个世界 ---
        if day == 5:
            check(not Store.new(directory).save(model).is_empty(), "the mid-run save writes")
            var reloaded = World.new()
            check(Store.new(directory).load_latest(reloaded), "the mid-run save reloads")
            check(reloaded.state.day == 6, "the reloaded run stands on day six")
            check(reloaded.valid(reloaded.state), "the reloaded run validates")
            check(stock(reloaded, "water") == stock(model, "water"), "the water count survives the reload")
            check(DoorDamage.level(reloaded, "home") == 1, "the reinforced door survives the reload")
            for id in model.state.goals.done:
                check(id in reloaded.state.goals.done, "objective %s survives the reload" % id)

    # --- 十天之后 ---
    check(model.state.day == DAYS + 1, "ten nights put the run on day eleven")
    check(count_event(model, "daily_summary") == DAYS, "every night is summarised exactly once")
    check(model.state.stats.health > 0, "the player is alive after ten days")
    check(repairs == 1 and reinforces == 1, "the door was repaired once and reinforced once")
    check(meals == 1, "exactly one meal was cooked")
    check(door_broken_day == 4, "the door was breached on day four")

    var ending_total := total(model)
    var consumed := opening_total - ending_total
    check(consumed > 0, "ten days actually consume supplies, got %d" % consumed)
    check(ending_total > 0, "the map is not looted dry in ten days")
    var left_water := stock(model, "water")
    var left_food := stock(model, "food")
    # 地图上只有 21 瓶水：十天后不该还剩一半以上，也不该已经见底。
    check(left_water <= 10, "ten days of drinking really eats into the water supply, got %d" % left_water)
    check(left_water + left_food > 0, "the run does not end with an empty world")
    var days_left := minf(float(left_water) * 35.0 / 45.4, float(left_food) * 30.0 / 32.4)
    check(days_left > 2.0, "a survivor keeps a few days of margin, got %.1f" % days_left)
    check(days_left < 20.0, "the world does not hand out twenty free days, got %.1f" % days_left)

    check("long_trip" in model.state.goals.done, "the ten-day run completed the long-trip objective")

    # --- 对照组：不出门的人会渴死 ---
    stock_ids = HOME_ONLY
    var shut_in = World.new()
    shut_in.start()
    shut_in.state.zombies = []
    shut_in.set_base("home")
    at(shut_in, HOME)
    var days_alive := 0
    for day in range(1, 7):
        fetch_shut_in(shut_in)
        deposit_all(shut_in)
        advance_to(shut_in, 1080.0)
        if shut_in.state.stats.health <= 0:
            break
        if Rest.begin(shut_in, "home_bed", "night") != "":
            break
        var guard := 0
        while shut_in.state.rest.active and guard < 600:
            shut_in.advance_time(5.0, true)
            guard += 1
            if shut_in.state.rest.active and Timeline.absolute(shut_in) >= float(shut_in.state.rest.target) - 0.001:
                Rest.finish(shut_in)
        days_alive = day
        if shut_in.state.stats.health <= 0:
            break
    check(shut_in.state.stats.health <= 0, "staying home without going out is fatal, got %d days" % days_alive)
    check(days_alive <= 4, "dehydration ends the shut-in inside four days, got %d" % days_alive)
    check(count_event(shut_in, "died") >= 1, "the death is written into the journal")

    for line in log_lines:
        print(line)
    print("supply left: water %d food %d, margin %.1f days" % [left_water, left_food, days_left])
    print("LONG_SURVIVAL_OK" if failures == 0 else "LONG_SURVIVAL_FAILED")
    quit(0 if failures == 0 else 1)

## 对照组只吃家里那点存货：拿完就再没有别的来源。
func fetch_shut_in(model: RefCounted) -> void:
    for item in ["water", "food"]:
        fetch(model, item, 2)
        var guard := 0
        while int(model.state.inventory.get(item, 0)) > 0 and guard < 5:
            guard += 1
            if model.state.stats["thirst" if item == "water" else "hunger"] >= 90.0:
                break
            if not model.use_item(item):
                break
