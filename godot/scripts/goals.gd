extends RefCounted
## Small objectives read straight out of the save: what is stored at the base, how
## far the player has actually walked, what they already built. Nothing here
## invents a story beat or hands out a reward, so an objective can never be "won"
## by a flag the world did not really change.
const PATH := "res://data/goals.json"

static var _cache: Dictionary = {}

static func definitions() -> Array:
    if _cache.is_empty():
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
        _cache = parsed if parsed is Dictionary else {"goals": []}
    return _cache.get("goals", [])

static func definition(id: String) -> Dictionary:
    for entry in definitions():
        if str(entry.id) == id:
            return entry
    return {}

static func empty() -> Dictionary:
    return {"done": [], "farthest": 0.0, "checked_at": -1.0}

## Old snapshots and freshly started worlds both pass through here, so the shape
## is repaired on presence rather than on the version number.
static func ensure(model: RefCounted) -> Dictionary:
    var current: Variant = model.state.get("goals")
    if not current is Dictionary:
        current = empty()
        model.state.goals = current
    for key in empty():
        if not current.has(key):
            current[key] = empty()[key]
    return current

## The base is a place, not a container: the villa's upper floor and its yard
## belong to the same shelter, so distance is measured from the zone centre.
static func home_center(model: RefCounted) -> Vector3:
    var target := str(model.base_id())
    for zone in model.zones():
        if str(zone.id) == target:
            var rect: Rect2 = zone.rect
            return Vector3(rect.get_center().x, 0.0, rect.get_center().y)
    return Vector3.ZERO

## Only containers that belong to the current base count, and loose ground piles
## never do: hauling something into the yard and dropping it is not stockpiling.
static func stock_total(model: RefCounted, item: String, base: String) -> int:
    var total := 0
    var drops: Dictionary = model.state.get("ground_drops", {})
    for id in model.state.containers:
        if drops.has(str(id)):
            continue
        if model.container_building(str(id)) != base:
            continue
        total += int(model.state.containers[id].get(item, 0))
    return total

static func progress(model: RefCounted, entry: Dictionary) -> Dictionary:
    var goals := ensure(model)
    match str(entry.get("kind", "")):
        "stock":
            return {"current": stock_total(model, str(entry.item), model.base_id()), "need": int(entry.count)}
        "distance":
            return {"current": int(float(goals.farthest)), "need": int(float(entry.meters))}
        "site":
            return {"current": 1 if model.site_done(str(entry.site)) else 0, "need": 1}
    return {"current": 0, "need": 1}

## Called from the time loop because that is the only place the model sees the
## player move. Distance is sampled every call; the objective test itself is
## throttled, since storing the same crate twice must not write two log entries.
static func check(model: RefCounted) -> Array:
    if model.state.stats.health <= 0:
        return []
    var goals := ensure(model)
    var position: Array = model.state.position
    var home := home_center(model)
    var distance := Vector2(float(position[0]) - home.x, float(position[2]) - home.z).length()
    if distance > float(goals.farthest):
        goals.farthest = distance
    var stamp := float(model.state.day - 1) * 1440.0 + float(model.state.minutes)
    if stamp - float(goals.checked_at) < 1.0:
        return []
    goals.checked_at = stamp
    var finished: Array = []
    for entry in definitions():
        var id := str(entry.id)
        if id in goals.done:
            continue
        var point := progress(model, entry)
        if int(point.current) >= int(point.need):
            goals.done.append(id)
            finished.append(id)
            model.event("goal_done", "完成了小目标「%s」。" % str(entry.name), "希望", {"goal": id})
    return finished

## A finished objective must name a real goal and may only be listed once; the
## distance sample can never be negative or ahead of the clock that took it.
static func valid(model: RefCounted, candidate: Dictionary) -> bool:
    var current: Variant = candidate.get("goals")
    if not current is Dictionary or not current.get("done") is Array:
        return false
    var farthest: Variant = current.get("farthest")
    if not (farthest is float or farthest is int) or not is_finite(farthest) or farthest < 0.0 or farthest > 1000.0:
        return false
    var checked: Variant = current.get("checked_at")
    if not (checked is float or checked is int) or not is_finite(checked) or checked < -1.0:
        return false
    var now := float(int(candidate.day) - 1) * 1440.0 + float(candidate.minutes)
    if float(checked) > now + 1.0:
        return false
    var seen: Array = []
    for id in current.done:
        if not id is String or definition(id).is_empty() or id in seen:
            return false
        seen.append(id)
    return true

## Plain text for the journal panel. Finished objectives stay on the list so the
## log keeps reading as a record of what was done instead of a checklist that
## silently empties itself.
static func summary(model: RefCounted) -> String:
    var goals := ensure(model)
    var lines := PackedStringArray(["小目标"])
    for entry in definitions():
        var id := str(entry.id)
        var point := progress(model, entry)
        if id in goals.done:
            lines.append("  [完成] %s  %d/%d" % [str(entry.name), int(point.current), int(point.need)])
        else:
            lines.append("  [ ] %s  %d/%d —— %s" % [str(entry.name), int(point.current), int(point.need), str(entry.text)])
    return "\n".join(lines) + "\n\n"
