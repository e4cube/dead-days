extends SceneTree
const Model = preload("res://scripts/survival.gd")
const Timeline = preload("res://scripts/survival_time.gd")
const Rest = preload("res://scripts/rest.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func fresh():
    var model = Model.new()
    model.start()
    return model

func event_count(model: RefCounted, kind: String) -> int:
    var result := 0
    for e in model.state.events:
        if e.kind == kind:
            result += 1
    return result

func _initialize() -> void:
    var model = fresh()
    model.advance_time(30)
    check(absf(model.state.minutes - 540) < 0.00001, "single clock converts simulation seconds to game minutes")
    check(absf(model.state.stats.hunger - 63.5) < 0.00001 and absf(model.state.stats.thirst - 62.9) < 0.00001, "awake needs use game time")
    var partitioned = fresh()
    model = fresh()
    model.state.stats.health = 50
    partitioned.state.stats.health = 50
    model.advance_time(850, true)
    for i in 100:
        partitioned.advance_time(8.5, true)
    for id in ["health", "hunger", "thirst"]:
        check(absf(model.state.stats[id] - partitioned.state.stats[id]) < 0.00001, "step partition invariant " + id)
    check(absf(Timeline.absolute(model) - Timeline.absolute(partitioned)) < 0.00001, "partition invariant cross-day clock")
    check(event_count(model, "daily_summary") == 1 and model.state.calendar.last_summary_day == 1, "one midnight summary")
    model = fresh()
    Timeline.summarize(model, 1)
    check(event_count(model, "daily_summary") == 0, "cannot summarize an unfinished future day")
    model.state.minutes = 1439.5
    model.state.stats.hunger = 0.0125
    model.advance_time(0.25)
    for event in model.state.events:
        if event.kind == "need_empty":
            check(event.day == 2 and event.minutes == 0, "midnight physiology events use canonical next-day time")
    model = fresh()
    model.state.stats.hunger = 0.5
    model.state.stats.thirst = 100
    model.advance_time(20)
    check(absf(model.state.stats.health - 95) < 0.00001, "starvation damage only after actual depletion")
    check(event_count(model, "need_empty") == 1, "depletion event comes from crossing threshold")
    model.state.stats.health = 1
    model.state.stats.hunger = 0
    model.state.stats.thirst = 0
    model.advance_time(5)
    check(model.state.stats.health == 0 and event_count(model, "died") == 1, "needs can kill once")
    var death_clock: float = model.state.minutes
    model.advance_time(100)
    check(model.state.minutes == death_clock and event_count(model, "died") == 1, "death freezes survival time without duplicate prose")
    model = fresh()
    model.state.stats.health = 50
    model.state.stats.hunger = 20
    model.advance_time(30, true)
    check(model.state.stats.health == 50, "unfed sleep does not invent healing")
    model = fresh()
    model.enter("home")
    model.loot("home")
    model.use_item("food")
    model.manual("搜到食物，今天有希望。", "希望")
    model.damage_player(10, "test")
    model.damage_zombie(model.state.zombies[0], 100)
    model.state.minutes = 1439.5
    model.advance_time(0.5)
    check(model.state.day == 2 and absf(model.state.minutes - 0.5) < 0.00001, "midnight preserves overflow minutes")
    var summary: Dictionary = model.state.events.back().payload
    check(summary.get("looted") == 4 and summary.get("kills") == 1 and summary.get("damage") == 10 and summary.get("used") == 1 and summary.get("manual") == 1, "summary reflects actual events")
    var n: int = model.state.events.size()
    Timeline.summarize(model, 1)
    check(model.state.events.size() == n, "summary marker prevents duplicates")
    model = fresh()
    model.state.position = [-8.5, 0, -2]
    check(not Rest.begin(model, "home_bed", "night").is_empty() and not model.state.rest.active, "daytime cannot skip straight to next dawn")
    model.state.minutes = 1080
    model.state.doors.home = true
    check(not Rest.begin(model, "home_bed", "night").is_empty(), "open room is unsafe")
    model.state.doors.home = false
    model.state.position = [-8.5, 0, -float(model.rules.buildings[0].get("depth",5)) - .1]
    check(not Rest.inside(model,"home",Vector3(model.state.position[0],0,model.state.position[2])), "expanded rear boundary remains outdoors")
    check(not Rest.begin(model, "home_bed", "night").is_empty(), "cannot sleep through back wall from outdoors")
    model.state.position = [-8.5, 0, -2]
    model.state.zombies[0].position = [-8.5, 0, 2]
    check(not Rest.begin(model, "home_bed", "night").is_empty(), "nearby enemy blocks rest even behind closed door")
    model.state.zombies[0].position = [7, 0, 6]
    check(Rest.begin(model, "home_bed", "night").is_empty(), "closed indoor bed away from danger permits sleep")
    check(model.state.rest.target == 1800, "night target is next dawn")
    model.loot("home")
    check(not model.use_item("food") and not model.begin_attack(), "sleep cannot coexist with consumption or attacks")
    model.advance_time(100, true)
    var root_dir := "user://tests/time_%d" % Time.get_ticks_usec()
    var store = Store.new(root_dir)
    check(not store.save(model).is_empty(), "save in-progress sleep")
    var loaded = fresh()
    check(store.load_latest(loaded) and loaded.state == JSON.parse_string(JSON.stringify(model.state)), "sleep target clock and needs roundtrip")
    var remaining: float = (loaded.state.rest.target - Timeline.absolute(loaded)) / loaded.rules.time.minutes_per_second
    loaded.advance_time(remaining, true)
    Rest.finish(loaded)
    check(loaded.state.day == 2 and absf(loaded.state.minutes - 360) < 0.00001, "rest can reach second dawn")
    check(loaded.valid(loaded.state) and event_count(loaded, "daily_summary") == 1, "completed rest is valid and summarized")
    for field in ["calendar", "rest"]:
        var bad: Dictionary = loaded.state.duplicate(true)
        bad[field] = "invalid"
        check(not loaded.valid(bad), "reject malformed " + field)
    var bad: Dictionary = model.state.duplicate(true)
    bad.rest.target = 1
    check(not model.valid(bad), "reject expired active sleep snapshot")
    bad = loaded.state.duplicate(true)
    bad.events[0].kind = "looted"
    bad.events[0].payload = {"items": "broken"}
    check(not loaded.valid(bad), "corrupt daily input payload rejected before runtime")
    # C1 snapshot migration preserves state and disk bytes.
    var old = fresh().state
    old.schema = 2
    old.erase("rest")
    old.erase("calendar")
    DirAccess.make_dir_recursive_absolute(root_dir + "/c1")
    var path := root_dir + "/c1/save_old.json"
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(old))
    file.close()
    var bytes := FileAccess.get_file_as_bytes(path)
    check(Store.new(root_dir + "/c1").load_latest(loaded), "schema2 loads")
    check(loaded.state.schema == 4 and loaded.state.zombies == JSON.parse_string(JSON.stringify(old.zombies)) and loaded.valid(loaded.state), "schema2 enemies preserved by migration")
    check(FileAccess.get_file_as_bytes(path) == bytes, "migration leaves source snapshot immutable")
    print("TIME_RULES_OK" if failures == 0 else "TIME_RULES_FAILED")
    quit(0 if failures == 0 else 1)
