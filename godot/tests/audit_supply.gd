extends SceneTree
## Read-only economy audit. Builds the real new-game state and counts what the
## whole map actually contains, then converts that into "how many days can one
## person live on this" using the same rules the game runs on.
##
## This is a measurement, not an acceptance test: it changes nothing and writes
## nothing. `tools/run_checks.py` does not include it.
const World = preload("res://scripts/connected_model.gd")

func _initialize() -> void:
    var model = World.new()
    model.start()
    model.state.zombies = []

    var totals := {}
    var containers := 0
    var empty := 0
    for id in model.state.containers:
        containers += 1
        var count := 0
        for item in model.state.containers[id]:
            var n := int(model.state.containers[id][item])
            if n <= 0:
                continue
            totals[item] = int(totals.get(item, 0)) + n
            count += n
        if count == 0:
            empty += 1

    var survival: Dictionary = model.rules.survival
    var hunger_rate := float(survival.hunger_per_minute)
    var thirst_rate := float(survival.thirst_per_minute)
    var sleep_factor := float(survival.sleep_metabolism)
    # A day is 16 waking hours plus 8 asleep at reduced metabolism.
    var day_hunger := hunger_rate * (16.0 * 60.0 + 8.0 * 60.0 * sleep_factor)
    var day_thirst := thirst_rate * (16.0 * 60.0 + 8.0 * 60.0 * sleep_factor)
    var items: Dictionary = model.rules.items
    var food_units := float(totals.get("food", 0)) * float(items.food.restore) + float(totals.get("hot_meal", 0)) * float(items.hot_meal.restore)
    var water_units := float(totals.get("water", 0)) * float(items.water.restore)

    print("containers %d (empty %d)" % [containers, empty])
    print("zombies %d" % model.state.zombies.size())
    var keys: Array = totals.keys()
    keys.sort()
    for id in keys:
        print("item %s %d" % [id, totals[id]])
    print("need_per_day hunger %.1f thirst %.1f" % [day_hunger, day_thirst])
    print("food_days %.1f water_days %.1f" % [food_units / day_hunger, water_units / day_thirst])
    # 绷带不再是血瓶：它只处理伤口。所以这里报的是"能处理多少处伤"，
    # 以及一处伤处理完之后那点恢复。
    var heal: float = float(model.rules.wounds.bandage_heal)
    print("first_aid bandage %d antiseptic %d suture %d antibiotic %d (%d wounds dressable, %d hp)" % [
        int(totals.get("bandage", 0)), int(totals.get("antiseptic", 0)),
        int(totals.get("suture_kit", 0)), int(totals.get("antibiotic", 0)),
        int(totals.get("bandage", 0)), int(totals.get("bandage", 0)) * int(heal)])
    print("door_repairs %d reinforces %d" % [
        int(totals.get("wood_plank", 0)) / 2, int(totals.get("wood_plank", 0)) / 3])
    print("SUPPLY_AUDIT_OK")
    quit(0)
