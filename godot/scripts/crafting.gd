extends RefCounted
## Base crafting: every recipe lives in data/crafting.json, so prerequisites,
## duration and products stay in one place instead of spreading through the UI.
##
## A craft is a real elapsed-time action, not an instant menu result. Materials
## are taken when the work starts and the progress only advances through the same
## clock the rest of the world uses. Any interruption refunds the spent materials
## exactly once, so a cancelled or failed craft can never duplicate or vanish them.
const Timeline = preload("res://scripts/survival_time.gd")
const DoorDamage = preload("res://scripts/door_damage.gd")

static var _definitions: Dictionary = {}

static func definitions() -> Dictionary:
    if _definitions.is_empty():
        _definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/crafting.json"))
    return _definitions

static func entries() -> Array:
    return definitions().get("recipes", [])

static func recipe(id: String) -> Dictionary:
    for entry in entries():
        if str(entry.get("id", "")) == id:
            return entry
    return {}

static func empty() -> Dictionary:
    return {"active": false, "recipe": "", "minutes_left": 0.0, "door": "", "spent": {}}

static func active(model: RefCounted) -> bool:
    return bool(model.state.get("craft", {}).get("active", false))

## Shared danger test: the same radius that interrupts work also refuses a start,
## so pressing the button next to a horde never skips the risk.
static func danger(model: RefCounted, position: Vector3) -> String:
    var radius := float(definitions().get("danger_radius", 3.0))
    for zombie in model.state.zombies:
        if float(zombie.health) <= 0:
            continue
        var at := Vector3(zombie.position[0], 0, zombie.position[2])
        var goal := Vector3(zombie.target[0], 0, zombie.target[2])
        if at.distance_to(position) <= radius:
            return "附近有僵尸，无法安心做手上的活"
        if str(zombie.mode) in ["alert", "chase", "search"] and goal.distance_to(position) <= radius:
            return "附近有僵尸，无法安心做手上的活"
    return ""

## Street doors hang at z=0 in front of their building. Returning INF for an
## unknown door keeps the reach test closed instead of silently allowing it.
static func door_position(model: RefCounted, id: String) -> Vector3:
    for building in model.rules.buildings:
        if str(building.id) == id:
            return Vector3(float(building.x), 0.0, 0.0)
    return Vector3.INF

static func reason(model: RefCounted, id: String, door_id: String = "") -> String:
    var entry := recipe(id)
    if entry.is_empty():
        return "未知配方"
    if model.state.stats.health <= 0:
        return "身体状况无法劳作"
    if model.state.rest.active:
        return "正在休息"
    if active(model):
        return "已经在制作中"
    for tool in entry.get("tools", []):
        if model.state.inventory.get(tool, 0) <= 0:
            return "缺少工具：" + str(model.rules.items[tool].name)
    for item in entry.get("inputs", {}):
        var need := int(entry.inputs[item])
        if model.state.inventory.get(item, 0) < need:
            return "材料不足：%s %d/%d" % [model.rules.items[item].name, model.state.inventory.get(item, 0), need]
    if bool(entry.get("requires_base", false)):
        if not model.has_method("in_base") or not model.in_base():
            return "只能在据点内制作"
    if str(entry.get("target", "item")) == "door":
        if door_id.is_empty() or not model.state.doors.has(door_id):
            return "需要站到门旁"
        var anchor := door_position(model, door_id)
        var reach := Vector2(float(model.state.position[0]) - anchor.x, float(model.state.position[2]) - anchor.z).length()
        if reach > float(model.rules.interaction_range):
            return "需要站到门旁"
        if id == "repair_door":
            if DoorDamage.health(model, door_id) >= DoorDamage.max_health(model, door_id) - 0.001:
                return "这扇门不需要修复"
        else:
            if DoorDamage.broken(model, door_id):
                return "门已损坏，先修复再加固"
            if DoorDamage.level(model, door_id) >= DoorDamage.limit(model):
                return "加固已到上限"
    if not danger(model, Vector3(model.state.position[0], model.state.position[1], model.state.position[2])).is_empty():
        return "附近有僵尸，无法安心做手上的活"
    if entry.has("outputs"):
        var delta := 0.0
        for item in entry.outputs:
            delta += float(model.rules.items[item].weight) * int(entry.outputs[item])
        for item in entry.get("inputs", {}):
            delta -= float(model.rules.items[item].weight) * int(entry.inputs[item])
        if model.weight() + delta > float(model.rules.capacity) + 0.0001:
            return "背包负重不足，无法完成制作"
    return ""

static func begin(model: RefCounted, id: String, door_id: String = "") -> String:
    var blocked := reason(model, id, door_id)
    if not blocked.is_empty():
        return blocked
    var entry := recipe(id)
    var spent := {}
    for item in entry.get("inputs", {}):
        var count := int(entry.inputs[item])
        model.state.inventory[item] = int(model.state.inventory.get(item, 0)) - count
        spent[item] = count
    model.state.craft = {"active": true, "recipe": id, "minutes_left": float(entry.minutes),
        "door": door_id, "spent": spent}
    var where := "" if door_id.is_empty() else "（" + str(model.building_name(door_id)) + "的门）"
    model.event("craft_started", "开始%s%s，预计 %d 分钟。" % [str(entry.name), where, int(entry.minutes)],
        "平静", {"recipe": id, "door": door_id, "minutes": entry.minutes})
    return ""

## Returns true on the step that finishes the work.
static func tick(model: RefCounted, minutes: float) -> bool:
    if not active(model) or minutes <= 0:
        return false
    model.state.craft.minutes_left = maxf(0, float(model.state.craft.minutes_left) - minutes)
    if float(model.state.craft.minutes_left) > 0.0001:
        return false
    finish(model)
    return true

static func finish(model: RefCounted) -> void:
    var entry := recipe(str(model.state.get("craft", {}).get("recipe", "")))
    var door := str(model.state.get("craft", {}).get("door", ""))
    model.state.craft = empty()
    if entry.is_empty():
        return
    if str(entry.get("target", "item")) == "door":
        if str(entry.id) == "repair_door":
            DoorDamage.repair(model, door)
        else:
            DoorDamage.reinforce(model, door)
        return
    var outputs: Dictionary = entry.get("outputs", {})
    var names := PackedStringArray()
    for item in outputs:
        model.state.inventory[item] = int(model.state.inventory.get(item, 0)) + int(outputs[item])
        names.append("%s×%d" % [model.rules.items[item].name, int(outputs[item])])
    model.event("crafted", "完成%s，得到%s。" % [str(entry.name), "、".join(names)], "希望",
        {"recipe": entry.id, "outputs": outputs.duplicate(true)})

static func cancel(model: RefCounted, why: String, danger: bool = false) -> void:
    if not active(model):
        return
    var craft: Dictionary = model.state.get("craft", {}).duplicate(true)
    model.state.craft = empty()
    var refunded := {}
    for item in craft.get("spent", {}):
        var count := int(craft.spent[item])
        model.state.inventory[item] = int(model.state.inventory.get(item, 0)) + count
        refunded[item] = count
    model.event("craft_interrupted", "制作中断：%s；材料已退还。" % why,
        "恐惧" if danger else "疲惫",
        {"recipe": str(craft.get("recipe", "")), "reason": why, "refunded": refunded})

## Text for the HUD and the panel: remaining minutes are rounded up so the last
## partial minute never reads as zero while work is still running.
static func progress(model: RefCounted) -> String:
    if not active(model):
        return ""
    var entry := recipe(str(model.state.craft.get("recipe", "")))
    return "%s 剩余 %d 分钟" % [str(entry.get("name", "")), int(ceil(float(model.state.craft.minutes_left)))]
