extends RefCounted
const Timeline = preload("res://scripts/survival_time.gd")
const Rest = preload("res://scripts/rest.gd")
## Scene-independent authoritative state. UI never mutates inventory directly.
var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var state: Dictionary = {}

func start() -> void:
    state = {"schema": 2, "day": 1, "minutes": float(rules.time.start_minutes),
        "position": [-7.0, 0.0, 2.0], "stats": {"health": 100.0, "hunger": 65.0, "thirst": 65.0, "stamina": 100.0},
        "inventory": {}, "doors": {}, "containers": {}, "visited": [], "events": []}
    for b in rules.buildings:
        state.doors[b.id] = false
        state.containers[b.id] = b.container.duplicate(true)
    add_threat_state()
    add_time_state()
    add_furniture_state()
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
    if not state.containers.has(id):
        return 0
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
        event("looted", "从" + container_name(id) + "获得 " + str(count) + " 件物资。", "希望", {"building": container_building(id), "container": id, "items": taken})
    return count

func container_name(id: String) -> String:
    for definition in rules.get("containers",[]):
        if definition.id == id:
            return definition.name
    return building_name(id) + "柜子"

func container_building(id: String) -> String:
    for definition in rules.get("containers",[]):
        if definition.id == id:
            return definition.building
    return id

func container_summary(id: String) -> String:
    var items := PackedStringArray()
    for item in state.containers.get(id,{}):
        var count: int = state.containers[id][item]
        if count > 0:
            items.append("%s×%d" % [rules.items[item].name,count])
    return " / ".join(items) if not items.is_empty() else "已空"

func transfer_item(container: String, item: String, deposit: bool) -> bool:
    if state.stats.health <= 0 or state.rest.active or not state.containers.has(container) or not rules.items.has(item):
        return false
    var source: Dictionary = state.inventory if deposit else state.containers[container]
    var destination: Dictionary = state.containers[container] if deposit else state.inventory
    if source.get(item,0) <= 0 or destination.get(item,0) >= 10000:
        return false
    if not deposit and weight()+float(rules.items[item].weight) > float(rules.capacity)+.0001:
        return false
    source[item] -= 1
    destination[item] = destination.get(item,0)+1
    if deposit and state.combat.equipped == item and state.inventory[item] == 0:
        state.combat.equipped = "fists"
    event("stored" if deposit else "retrieved", ("存入" if deposit else "取回") + rules.items[item].name + " ×1 / " + container_name(container), "平静", {"container": container,"building":container_building(container),"item":item,"count":1})
    return true

func add_furniture_state() -> void:
    for definition in rules.get("containers",[]):
        if not state.containers.has(definition.id):
            state.containers[definition.id] = definition.contents.duplicate(true)
    state.schema = 4

func use_item(id: String) -> bool:
    if not rules.items.has(id) or state.inventory.get(id, 0) <= 0:
        return false
    if state.stats.health <= 0 or state.rest.active:
        return false
    var rule: Dictionary = rules.items[id]
    if rule.get("kind", "") == "weapon":
        state.combat.equipped = id
        event("equipped", "装备了" + rule.name + "。", "平静", {"item": id})
        return true
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
    if (candidate.schema != 1 and candidate.schema != 2 and candidate.schema != 3 and candidate.schema != 4) or not number(candidate.day, 1, 1000000) or candidate.day != floor(candidate.day):
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
    for definition in rules.get("containers",[]):
        if candidate.schema == 4 and not candidate.containers.has(definition.id):
            return false
        if candidate.containers.has(definition.id) and (not candidate.containers[definition.id] is Dictionary or not valid_items(candidate.containers[definition.id])):
            return false
    for id in candidate.containers:
        var known := false
        for definition in rules.buildings:
            known = known or definition.id == id
        for definition in rules.get("containers",[]):
            known = known or definition.id == id
        if not known:
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
        if e.kind == "looted" and (not e.payload.get("items") is Dictionary or not valid_items(e.payload.items)):
            return false
        if e.kind == "injured" and not number(e.payload.get("damage"), 0, 100):
            return false
        if e.kind in ["stored","retrieved"] and (not rules.items.has(e.payload.get("item", "")) or not integer(e.payload.get("count"),1,10000) or not candidate.containers.has(e.payload.get("container",""))):
            return false
    if candidate.has("house_light") and not candidate.house_light is bool:
        return false
    if candidate.schema >= 2 and not valid_threats(candidate):
        return false
    return candidate.schema < 3 or valid_time(candidate)

func valid_items(items: Dictionary) -> bool:
    for id in items:
        var n: Variant = items[id]
        if not rules.items.has(id) or not (n is float or n is int) or not is_finite(n) or n < 0 or n != floor(n) or n > 10000:
            return false
    return true


func add_threat_state(protect_spawn: bool = false) -> void:
    state.schema = 2
    state.combat = {"equipped": "fists", "attack_cd": 0.0, "hurt_cd": 0.0, "facing": PI}
    state.zombies = []
    state.noises = []
    state.noise_sequence = 0
    state.seen_horde = false
    for spawn in rules.zombie_spawns:
        if protect_spawn and Vector2(spawn.position[0] - state.position[0], spawn.position[2] - state.position[2]).length() < 4.0:
            continue
        state.zombies.append(make_zombie(spawn.id, spawn.position))

func make_zombie(id: String, pos: Array) -> Dictionary:
    return {"id": id, "position": pos.duplicate(), "health": rules.zombie.health,
        "mode": "wander", "target": pos.duplicate(), "heading": PI,
        "memory": 0.0, "alert_left": 0.0, "attack_cd": 0.0, "windup": 0.0,
        "last_noise": 0, "patrol_left": 0.0, "patrol_index": 0, "had_target": false}

func restore(candidate: Dictionary) -> void:
    state = candidate.duplicate(true)
    if state.schema == 1:
        add_threat_state(true)
        # Old peaceful saves are preserved on disk; migration only adds threat state in memory.
        event("migrated", "旧街区存档已载入；街道东端出现了僵尸。", "恐惧")
    if state.schema == 2:
        add_time_state()
        event("migrated", "生存时钟和室内休息规则已接入；原有世界状态保留。", "平静")
    if state.schema == 3:
        add_furniture_state()
        event("migrated", "住宅冰箱已接入独立库存；原有物资和世界状态保留。", "平静")

func noise(pos: Vector3, radius: float, kind: String) -> void:
    state.noise_sequence += 1
    state.noises.append({"id": state.noise_sequence, "position": [pos.x, pos.y, pos.z],
        "radius": radius, "ttl": rules.noise.ttl, "kind": kind})

func tick_combat(delta: float) -> void:
    state.combat.attack_cd = maxf(0, state.combat.attack_cd - delta)
    state.combat.hurt_cd = maxf(0, state.combat.hurt_cd - delta)
    for i in range(state.noises.size() - 1, -1, -1):
        state.noises[i].ttl -= delta
        if state.noises[i].ttl <= 0:
            state.noises.remove_at(i)

func begin_attack() -> bool:
    if state.stats.health <= 0 or state.rest.active or state.combat.attack_cd > 0:
        return false
    var weapon: Dictionary = rules.weapons[state.combat.equipped]
    if state.stats.stamina < weapon.stamina:
        return false
    state.stats.stamina -= weapon.stamina
    state.combat.attack_cd = weapon.cooldown
    return true

func damage_zombie(zombie: Dictionary, amount: float) -> bool:
    if zombie.health <= 0 or amount <= 0:
        return false
    zombie.health = maxf(0, zombie.health - amount)
    if zombie.health == 0:
        zombie.mode = "dead"
        zombie.windup = 0.0
        event("killed", "用" + rules.weapons[state.combat.equipped].name + "击倒了一只僵尸。", "疲惫", {"zombie": zombie.id})
    return true

func damage_player(amount: float, attacker: String) -> bool:
    if state.stats.health <= 0 or state.combat.hurt_cd > 0 or amount <= 0:
        return false
    var previous: float = state.stats.health
    state.stats.health = maxf(0, previous - amount)
    state.combat.hurt_cd = rules.combat.hurt_immunity
    event("injured", "被僵尸击中，损失 %.0f 点生命。" % (previous - state.stats.health), "恐惧", {"attacker": attacker, "damage": previous - state.stats.health})
    if previous >= 25 and state.stats.health < 25 and state.stats.health > 0:
        event("near_death", "伤势危重，必须摆脱追击并寻找医疗物资。", "绝望")
    if state.stats.health <= 0:
        event("died", "这段生存记录在街区中结束了。", "绝望")
    return true

func number(value: Variant, low: float, high: float) -> bool:
    return (value is float or value is int) and is_finite(value) and value >= low and value <= high

func valid_position(pos: Variant) -> bool:
    if not pos is Array or pos.size() != 3:
        return false
    for n in pos:
        if not number(n, -1000, 1000):
            return false
    return true

func valid_threats(candidate: Dictionary) -> bool:
    for key in ["combat", "zombies", "noises", "noise_sequence", "seen_horde"]:
        if not candidate.has(key):
            return false
    if not candidate.combat is Dictionary or not candidate.zombies is Array or not candidate.noises is Array or not candidate.seen_horde is bool or not integer(candidate.noise_sequence, 0, 1e12):
        return false
    var combat: Dictionary = candidate.combat
    if not combat.get("equipped") is String or not rules.weapons.has(combat.equipped):
        return false
    if combat.equipped != "fists" and candidate.inventory.get(combat.equipped, 0) < 1:
        return false
    for key in ["attack_cd", "hurt_cd"]:
        if not number(combat.get(key), 0, 10):
            return false
    if not number(combat.get("facing"), -1000, 1000) or candidate.zombies.size() > 100 or candidate.noises.size() > 100:
        return false
    var ids := {}
    for z in candidate.zombies:
        if not z is Dictionary or not z.get("id") is String or ids.has(z.id):
            return false
        ids[z.id] = true
        if not valid_position(z.get("position")) or not valid_position(z.get("target")):
            return false
        if not number(z.get("health"), 0, rules.zombie.health) or z.get("mode") not in ["wander", "alert", "chase", "search", "dead"]:
            return false
        if (z.health == 0) != (z.mode == "dead") or not z.get("had_target") is bool:
            return false
        var limits := {"memory": rules.zombie.search_seconds, "alert_left": rules.zombie.alert_seconds,
            "attack_cd": rules.zombie.attack_cooldown, "windup": rules.zombie.attack_windup, "patrol_left": rules.zombie.patrol_seconds}
        for key in limits:
            if not number(z.get(key), 0, limits[key]):
                return false
        if not integer(z.get("patrol_index"), 0, 1e12) or not integer(z.get("last_noise"), 0, candidate.noise_sequence):
            return false
        if not number(z.get("heading"), -1000, 1000):
            return false
    var noise_ids := {}
    for n in candidate.noises:
        if not n is Dictionary or not valid_position(n.get("position")) or not n.get("kind") is String:
            return false
        if not integer(n.get("id"), 1, candidate.noise_sequence) or not number(n.get("ttl"), 0, rules.noise.ttl) or not number(n.get("radius"), 0, 100) or noise_ids.has(n.id):
            return false
        noise_ids[n.id] = true
    return true


func integer(value: Variant, low: float, high: float) -> bool:
    return number(value, low, high) and value == floor(value)


func add_time_state() -> void:
    state.schema = 3
    state.calendar = {"last_summary_day": int(state.day) - 1}
    state.rest = Rest.empty()

func advance_time(seconds: float, sleeping: bool = false) -> void:
    Timeline.advance(self, seconds, sleeping)

func environment_damage(amount: float) -> void:
    if amount <= 0 or state.stats.health <= 0:
        return
    var previous: float = state.stats.health
    state.stats.health = maxf(0, previous - amount)
    if previous >= 25 and state.stats.health < 25 and state.stats.health > 0:
        event("near_death", "饥渴让身体濒临极限。", "绝望", {"cause": "needs"})
    if state.stats.health <= 0:
        event("died", "生存记录因饥饿或脱水而结束。", "绝望", {"cause": "needs"})

func valid_time(candidate: Dictionary) -> bool:
    if not candidate.get("calendar") is Dictionary or not candidate.get("rest") is Dictionary:
        return false
    if not integer(candidate.calendar.get("last_summary_day"), 0, candidate.day - 1) or candidate.calendar.last_summary_day != candidate.day - 1:
        return false
    var rest: Dictionary = candidate.rest
    if not rest.get("active") is bool or not rest.get("kind") is String or not rest.get("bed") is String:
        return false
    var now: float = (candidate.day - 1) * 1440.0 + candidate.minutes
    if not number(rest.get("start"), 0, now) or not number(rest.get("target"), 0, now + 1440.0):
        return false
    if rest.active:
        if rest.kind not in ["hour", "night"] or Rest.bed(self, rest.bed).is_empty() or rest.target <= now or rest.target - rest.start > 1440.0:
            return false
    elif rest.kind != "" or rest.bed != "" or rest.start != 0 or rest.target != 0:
        return false
    return true
