extends RefCounted
## Scene-independent authoritative state. UI never mutates inventory directly.
var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var state: Dictionary = {}

func start() -> void:
    state = {"schema": 1, "day": 1, "minutes": 360.0,
        "position": [-7.0, 0.0, 2.0], "stats": {"health": 100.0, "hunger": 65.0, "thirst": 65.0, "stamina": 100.0},
        "inventory": {}, "doors": {}, "containers": {}, "visited": [], "events": []}
    for b in rules.buildings:
        state.doors[b.id] = false
        state.containers[b.id] = b.container.duplicate(true)
    event("started", "第1天清晨，在街区外醒来。")

func event(kind: String, message: String, mood: String = "平静", payload: Dictionary = {}) -> void:
    state.events.append({"id": state.events.size() + 1, "kind": kind, "day": state.day,
        "minutes": state.minutes, "text": message, "mood": mood, "payload": payload.duplicate(true)})

func weight() -> float:
    var total := 0.0
    for id in state.inventory:
        total += rules.items[id].weight * state.inventory[id]
    return total

func toggle_door(id: String) -> void:
    state.doors[id] = not state.doors[id]
    event("door", ("打开" if state.doors[id] else "关上") + building_name(id) + "的门。", "平静", {"building": id, "open": state.doors[id]})

func building_name(id: String) -> String:
    for b in rules.buildings:
        if b.id == id:
            return b.name
    return id

func enter(id: String) -> void:
    if id not in state.visited:
        state.visited.append(id)
        event("entered", "第一次进入" + building_name(id) + "。", "希望", {"building": id})

func loot(id: String) -> int:
    var count := 0
    var taken := {}
    for item in state.containers[id]:
        var n := 0
        while state.containers[id][item] > 0 and weight() + rules.items[item].weight <= rules.capacity + 0.0001:
            state.inventory[item] = state.inventory.get(item, 0) + 1
            state.containers[id][item] -= 1
            count += 1
            n += 1
        if n > 0:
            taken[item] = n
    if count > 0:
        event("looted", "从" + building_name(id) + "柜子获得 " + str(count) + " 件物资。", "希望", {"building": id, "items": taken})
    return count

func use_item(id: String) -> bool:
    if not rules.items.has(id) or state.inventory.get(id, 0) <= 0:
        return false
    var rule: Dictionary = rules.items[id]
    if state.stats[rule.stat] >= 100.0:
        return false
    state.inventory[id] -= 1
    state.stats[rule.stat] = minf(100.0, state.stats[rule.stat] + rule.restore)
    event("used", "使用了" + rule.name + "。", "平静", {"item": id})
    return true

func manual(text: String, mood: String) -> void:
    if not text.strip_edges().is_empty():
        event("manual", text.strip_edges().left(500), mood)

func markdown() -> String:
    var output := "# Dead Days 生存日志\n\n"
    for e in state.events:
        output += "- 第%d天 %02d:%02d [%s] %s\n" % [e.day, int(e.minutes) / 60, int(e.minutes) % 60, e.mood, e.text.replace("\n", " ")]
    return output

func valid(candidate: Variant) -> bool:
    if not candidate is Dictionary:
        return false
    for key in ["schema", "day", "minutes", "position", "stats", "inventory", "doors", "containers", "visited", "events"]:
        if not candidate.has(key):
            return false
    if candidate.schema != 1 or not candidate.day is float and not candidate.day is int or candidate.day < 1:
        return false
    if not (candidate.minutes is float or candidate.minutes is int) or not is_finite(candidate.minutes) or candidate.minutes < 0 or candidate.minutes >= 1440:
        return false
    if not candidate.position is Array or candidate.position.size() != 3:
        return false
    for n in candidate.position:
        if not (n is float or n is int) or not is_finite(n) or abs(n) > 1000:
            return false
    if not candidate.stats is Dictionary or not candidate.inventory is Dictionary or not candidate.doors is Dictionary or not candidate.containers is Dictionary or not candidate.visited is Array or not candidate.events is Array:
        return false
    for id in ["health", "hunger", "thirst", "stamina"]:
        if not candidate.stats.has(id) or not (candidate.stats[id] is float or candidate.stats[id] is int):
            return false
        if not is_finite(candidate.stats[id]) or candidate.stats[id] < 0 or candidate.stats[id] > 100:
            return false
    if not valid_items(candidate.inventory):
        return false
    var load_weight := 0.0
    for id in candidate.inventory:
        load_weight += rules.items[id].weight * candidate.inventory[id]
    if load_weight > rules.capacity + 0.0001:
        return false
    for b in rules.buildings:
        if not candidate.doors.has(b.id) or not candidate.doors[b.id] is bool or not candidate.containers.has(b.id) or not candidate.containers[b.id] is Dictionary or not valid_items(candidate.containers[b.id]):
            return false
    for id in candidate.visited:
        if not candidate.doors.has(id):
            return false
    for e in candidate.events:
        if not e is Dictionary:
            return false
        for key in ["id", "kind", "day", "minutes", "text", "mood", "payload"]:
            if not e.has(key):
                return false
        if not e.text is String or not e.kind is String or not e.mood is String or not e.payload is Dictionary:
            return false
        for key in ["id", "day", "minutes"]:
            if not (e[key] is float or e[key] is int) or not is_finite(e[key]):
                return false
    return true

func valid_items(items: Dictionary) -> bool:
    for id in items:
        var n: Variant = items[id]
        if not rules.items.has(id) or not (n is float or n is int) or not is_finite(n) or n < 0 or n != floor(n) or n > 10000:
            return false
    return true
