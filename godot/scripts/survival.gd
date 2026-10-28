extends RefCounted
const Timeline = preload("res://scripts/survival_time.gd")
const Rest = preload("res://scripts/rest.gd")
const Firearms = preload("res://scripts/firearms.gd")
const Appearance = preload("res://scripts/zombie_appearance.gd")
const GroundDrops=preload("res://scripts/ground_drops.gd")
const DoorDamage=preload("res://scripts/door_damage.gd")
const Crafting=preload("res://scripts/crafting.gd")
## Scene-independent authoritative state. UI never mutates inventory directly.
var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
var state: Dictionary = {}

func start() -> void:
    state = {"schema": 2, "day": 1, "minutes": float(rules.time.start_minutes),
        "position": [-7.0, 0.0, 2.0], "stats": {"health": 100.0, "hunger": 65.0, "thirst": 65.0, "stamina": 100.0},
        "inventory": {}, "doors": {}, "containers": {}, "visited": [], "events": []}
    state.world_revision=rules.world_revision
    for b in rules.buildings:
        state.doors[b.id] = false
        state.containers[b.id] = b.container.duplicate(true)
    add_threat_state()
    add_time_state()
    add_furniture_state()
    Firearms.ensure(self)
    GroundDrops.ensure(self)
    DoorDamage.ensure(self)
    add_base_state()
    add_site_state()
    event("started", "第1天清晨，在街区外醒来。")

func event(kind: String, message: String, mood: String = "平静", payload: Dictionary = {}) -> void:
    state.events.append({"id": state.events.size() + 1, "kind": kind, "day": state.day,
        "minutes": state.minutes, "text": message, "mood": mood, "payload": payload.duplicate(true)})

func weight() -> float:
    var total := Firearms.extra_weight(self,state)
    for id in state.inventory:
        total += rules.items[id].weight * state.inventory[id]
    return total

func toggle_door(id: String) -> void:
    if DoorDamage.broken(self,id): return
    state.doors[id] = not state.doors[id]
    event("door", ("打开" if state.doors[id] else "关上") + building_name(id) + "的门。", "平静", {"building": id, "open": state.doors[id]})

func building_name(id: String) -> String:
    for b in rules.buildings:
        if b.id == id:
            return b.name
    for definition in sites():
        if str(definition.id) == id:
            return str(definition.get("door_name", definition.get("name", id)))
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
        event("recovered" if state.ground_drops.has(id) else "looted", "从" + container_name(id) + "获得 " + str(count) + " 件物资。", "希望", {"building": container_building(id), "container": id, "items": taken})
    observe(id)
    return count

## Overridden by the connected-world model, which owns exploration records.
## Declared here so item transactions can call it without a dynamic lookup.
func observe(_container_id: String) -> void:
    pass

func container_name(id: String) -> String:
    if state.get("ground_drops",{}).has(id): return "落地物资"
    for definition in rules.get("containers",[]):
        if definition.id == id:
            return definition.name
    return building_name(id) + "柜子"

func container_building(id: String) -> String:
    if state.get("ground_drops",{}).has(id): return state.ground_drops[id].room
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

func container_weight(container: String) -> float:
    var total := 0.0
    for item in state.containers.get(container,{}):
        total += float(rules.items[item].weight)*float(state.containers[container][item])
    return total

func container_capacity(container: String) -> float:
    if state.get("ground_drops",{}).has(container): return float(rules.ground_drops.capacity)
    for definition in rules.get("containers",[]):
        if definition.id == container:
            return float(definition.get("capacity",rules.storage_default_capacity))
    for building in rules.buildings:
        if building.id == container:
            return float(building.get("storage_capacity",rules.storage_default_capacity))
    return 0.0

func transfer_reason(container: String, item: String, deposit: bool) -> String:
    if deposit and item=="pistol" and (Firearms.loaded(self)>0 or state.get("firearms",{}).get("reload_left",0)>0):
        return "请先装备手枪并按U卸弹，再存入枪支"
    if state.stats.health <= 0 or state.rest.active or not state.containers.has(container) or not rules.items.has(item):
        return "当前无法存取此物品"
    var source: Dictionary = state.inventory if deposit else state.containers[container]
    var destination: Dictionary = state.containers[container] if deposit else state.inventory
    if source.get(item,0) <= 0 or destination.get(item,0) >= 10000:
        return "来源没有物品或数量已达上限"
    if deposit and container_weight(container)+float(rules.items[item].weight) > container_capacity(container)+.0001:
        return "容器承重不足，物品留在背包"
    if not deposit and weight()+float(rules.items[item].weight) > float(rules.capacity)+.0001:
        return "背包负重不足，物品留在容器"
    return ""

func transfer_item(container: String, item: String, deposit: bool) -> bool:
    if not transfer_reason(container,item,deposit).is_empty():
        return false
    var source: Dictionary = state.inventory if deposit else state.containers[container]
    var destination: Dictionary = state.containers[container] if deposit else state.inventory
    source[item] -= 1
    destination[item] = destination.get(item,0)+1
    if deposit and state.combat.equipped == item and state.inventory[item] == 0:
        state.combat.equipped = "fists"
    event("stored" if deposit else "retrieved", ("存入" if deposit else "取回") + rules.items[item].name + " ×1 / " + container_name(container), "平静", {"container": container,"building":container_building(container),"item":item,"count":1})
    observe(container)
    return true

func add_furniture_state() -> void:
    for definition in rules.get("containers",[]):
        if not state.containers.has(definition.id):
            state.containers[definition.id] = definition.contents.duplicate(true)
    state.schema = 4

## Base ownership, craft progress and per-door reinforcement arrived together:
## all three describe what the player has done to their own shelter.
func add_base_state() -> void:
    state.schema = 5
    state.craft = Crafting.empty()
    if not state.has("door_level"): state.door_level = {}
    if not state.has("base"): state.base = "home"
    DoorDamage.ensure(self)

## Site works are base improvements that live in the authored world rather than in
## the street: a yard gate and a pool supply. Each one is remembered as a flag, and
## an installed gate also becomes a real door with its own durability, so it is
## repaired, reinforced and battered by exactly the same rules as a house entrance.
func add_site_state() -> void:
    state.schema = 6
    if not state.get("base_works") is Dictionary:
        state.base_works = {}
    for definition in sites():
        var id := str(definition.id)
        if not state.base_works.has(id):
            state.base_works[id] = false
    if not state.get("pool") is Dictionary:
        # A freshly claimed villa has no water: the counter only fills once the
        # supply work is finished.
        state.pool = {"day": int(state.day), "left": 0}
    DoorDamage.ensure(self)

func sites() -> Array:
    return rules.get("sites", [])

func site(id: String) -> Dictionary:
    for definition in sites():
        if str(definition.id) == id:
            return definition
    return {}

func site_done(id: String) -> bool:
    return bool(state.get("base_works", {}).get(id, false))

func site_position(id: String) -> Vector3:
    var definition := site(id)
    if definition.is_empty():
        return Vector3.INF
    var p: Array = definition.position
    return Vector3(float(p[0]), float(p[1]), float(p[2]))

## Footprint of a work on the ground plane. Gates are authored as a span across the
## x axis with a thickness, services carry an explicit rect.
func site_rect(id: String) -> Rect2:
    var definition := site(id)
    if definition.is_empty():
        return Rect2()
    if definition.has("rect"):
        var r: Array = definition.rect
        return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
    var p: Array = definition.position
    var span := float(definition.get("span", 1.0))
    var thickness := float(definition.get("thickness", 0.3))
    return Rect2(float(p[0]) - span * 0.5, float(p[2]) - thickness * 0.5, span, thickness)

## Planar distance to the footprint; zero when standing on it. Used both by the
## craft reach test and by the interaction prompt.
func site_distance(id: String, at: Vector3) -> float:
    var rect := site_rect(id)
    if rect.size.x <= 0.0:
        return INF
    var center := rect.get_center()
    var dx := maxf(0.0, absf(at.x - center.x) - rect.size.x * 0.5)
    var dz := maxf(0.0, absf(at.z - center.y) - rect.size.y * 0.5)
    return sqrt(dx * dx + dz * dz)

## The single anchor every door consumer asks for: street doors sit at z=0 in front
## of their building, an authored gate sits on its own line.
func door_anchor(id: String) -> Vector3:
    for building in rules.buildings:
        if str(building.id) == id:
            return Vector3(float(building.x), 0.0, 0.0)
    var definition := site(id)
    if not definition.is_empty() and str(definition.get("kind", "")) == "gate":
        return site_position(id)
    return Vector3.INF

func service_site() -> String:
    for definition in sites():
        if str(definition.get("kind", "")) == "service":
            return str(definition.id)
    return ""

func pool_capacity() -> int:
    for definition in sites():
        if str(definition.get("kind", "")) == "service":
            return int(definition.get("capacity", 3))
    return 0

## Water is rationed per calendar day, so the pool is a reason to come back rather
## than a free well: the counter resets the first time the day is observed.
func pool_left() -> int:
    var id := service_site()
    if id.is_empty() or not site_done(id):
        return 0
    var pool: Dictionary = state.get("pool", {})
    if int(pool.get("day", 0)) != int(state.day):
        return pool_capacity()
    return clampi(int(pool.get("left", 0)), 0, pool_capacity())

func refresh_pool() -> void:
    if not state.has("pool") or int(state.pool.get("day", 0)) == int(state.day):
        return
    state.pool = {"day": int(state.day), "left": pool_capacity()}

func pool_reason() -> String:
    var id := service_site()
    if id.is_empty():
        return "这里没有可用的供水"
    if not site_done(id):
        return "泳池还没有接上市政水管"
    if pool_left() <= 0:
        return "今天的水接完了，明天再来"
    if weight() + float(rules.items.water.weight) > float(rules.capacity) + 0.0001:
        return "背包负重不足，先放下东西"
    return ""

func draw_pool_water() -> bool:
    var blocked := pool_reason()
    if not blocked.is_empty():
        return false
    refresh_pool()
    state.pool.left = pool_left() - 1
    state.inventory["water"] = int(state.inventory.get("water", 0)) + 1
    event("water_drawn", "从泳池接了 1 份水，今天还剩 %d 份。" % pool_left(), "平静", {"left": pool_left()})
    return true

## Finishing a work is the only place that flips the flag. A gate additionally
## registers its own door, closed and at full health, so the yard is sealed the
## moment the hinges are on.
func complete_site(id: String) -> bool:
    var definition := site(id)
    if definition.is_empty() or site_done(id):
        return false
    state.base_works[id] = true
    if str(definition.get("kind", "")) == "gate":
        state.doors[id] = false
        state.door_health[id] = float(rules.door_damage.health)
        state.door_level[id] = 0
        event("site_built", "装好了" + building_name(id) + "的门，这一侧现在能关上了。", "希望",
            {"site": id, "door": id})
    else:
        state.pool = {"day": int(state.day), "left": int(pool_capacity())}
        event("site_built", "接通了" + str(definition.name) + "，市政水开始往泳池里灌。", "希望", {"site": id})
    return true

## A closed installed gate is a barrier in the open yard, not in a doorway: the
## zombie asks for the line it would have to break to reach its target.
func barrier_at(from: Vector3, to: Vector3) -> Dictionary:
    for definition in sites():
        if str(definition.get("kind", "")) != "gate":
            continue
        var id := str(definition.id)
        if not site_done(id) or not state.doors.has(id) or bool(state.doors[id]):
            continue
        if DoorDamage.broken(self, id):
            continue
        var anchor := site_position(id)
        if (from.z < anchor.z) == (to.z < anchor.z):
            continue
        if absf(from.x - anchor.x) > float(definition.get("span", 0.0)) * 0.5 + 1.0:
            continue
        var side := -1.0 if from.z < anchor.z else 1.0
        return {"id": id, "goal": Vector3(anchor.x, 0.0, anchor.z + side * 0.9)}
    return {}

func expand_world_state() -> void:
    var previous: int=state.get("world_revision",0)
    if previous>=int(rules.world_revision):
        return
    for building in rules.buildings:
        if int(building.get("introduced_revision",0))>previous:
            if not state.doors.has(building.id): state.doors[building.id]=false
            if not state.containers.has(building.id): state.containers[building.id]=building.container.duplicate(true)
    for container in rules.containers:
        if int(container.get("introduced_revision",0))>previous and not state.containers.has(container.id):
            state.containers[container.id]=container.contents.duplicate(true)
    state.world_revision=rules.world_revision
    event("world_expanded","街道东段开放了新的可探索地点，原有物资状态保留。","希望",{"revision":state.world_revision})

func light_enabled(id: String) -> bool:
    if id=="home":
        return state.get("house_light",true)
    return state.get("building_lights",{}).get(id,false)

func switch_light(id: String) -> bool:
    var known:=false
    for building in rules.buildings: known=known or building.id==id
    if not known or state.stats.health<=0 or state.rest.active:
        return false
    var enabled := not light_enabled(id)
    if id=="home":
        state.house_light=enabled
    else:
        if not state.has("building_lights"):
            state.building_lights={}
        state.building_lights[id]=enabled
    event("light",("打开" if enabled else "关闭")+building_name(id)+"照明。","平静",{"building":id,"enabled":enabled})
    return true

func use_item(id: String) -> bool:
    if not rules.items.has(id) or state.inventory.get(id, 0) <= 0:
        return false
    if state.stats.health <= 0 or state.rest.active:
        return false
    var rule: Dictionary = rules.items[id]
    if rule.get("kind", "") == "weapon":
        Firearms.ensure(self)
        state.firearms.reload_left=0.0
        state.combat.equipped = id
        event("equipped", "装备了" + rule.name + "。", "平静", {"item": id})
        return true
    if rule.get("kind", "") == "ammo":
        return Firearms.begin_reload(self)
    # Materials and tools are never consumed by hand; they exist for crafting.
    if rule.get("kind", "") != "":
        return false
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
    if (candidate.schema != 1 and candidate.schema != 2 and candidate.schema != 3 and candidate.schema != 4 and candidate.schema != 5 and candidate.schema != 6) or not number(candidate.day, 1, 1000000) or candidate.day != floor(candidate.day):
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
    if not GroundDrops.valid(self,candidate): return false
    if not DoorDamage.valid(self,candidate): return false
    if candidate.has("world_revision") and not integer(candidate.world_revision,0,rules.world_revision):
        return false
    if not Firearms.valid(self,candidate):
        return false
    var load_weight := Firearms.extra_weight(self,candidate)
    for id in candidate.inventory:
        load_weight += rules.items[id].weight * candidate.inventory[id]
    if load_weight > rules.capacity + 0.0001:
        return false
    for b in rules.buildings:
        if int(b.get("introduced_revision",0))>int(candidate.get("world_revision",0)) and not candidate.doors.has(b.id) and not candidate.containers.has(b.id):
            continue
        if not candidate.doors.has(b.id) or not candidate.doors[b.id] is bool or not candidate.containers.has(b.id) or not candidate.containers[b.id] is Dictionary or not valid_items(candidate.containers[b.id]):
            return false
    for definition in rules.get("containers",[]):
        if candidate.schema >= 4 and int(candidate.get("world_revision",0))>=int(definition.get("introduced_revision",0)) and not candidate.containers.has(definition.id):
            return false
        if candidate.containers.has(definition.id) and (not candidate.containers[definition.id] is Dictionary or not valid_items(candidate.containers[definition.id])):
            return false
    for id in candidate.containers:
        var known: bool=candidate.get("ground_drops",{}).has(id)
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
        if e.kind in ["looted","recovered"] and (not e.payload.get("items") is Dictionary or not valid_items(e.payload.items)):
            return false
        if e.kind == "injured" and not number(e.payload.get("damage"), 0, 100):
            return false
        if e.kind in ["stored","retrieved"] and (not rules.items.has(e.payload.get("item", "")) or not integer(e.payload.get("count"),1,10000) or not candidate.containers.has(e.payload.get("container",""))):
            return false
    if candidate.has("house_light") and not candidate.house_light is bool:
        return false
    if candidate.has("building_lights"):
        if not candidate.building_lights is Dictionary:
            return false
        for id in candidate.building_lights:
            var known:=false
            for building in rules.buildings: known=known or (building.id==id and id!="home")
            if not known or not candidate.building_lights[id] is bool:
                return false
    if candidate.schema >= 2 and not valid_threats(candidate):
        return false
    if candidate.schema >= 3 and not valid_time(candidate):
        return false
    if candidate.schema >= 5 and not valid_craft(candidate):
        return false
    if candidate.schema >= 6 and not valid_sites(candidate):
        return false
    return true

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
    var appearance: String="civilian"
    for spawn in rules.zombie_spawns:
        if spawn.id==id:
            appearance=spawn.get("appearance","civilian")
    return {"id": id, "appearance":appearance, "position": pos.duplicate(), "health": rules.zombie.health,
        "mode": "wander", "target": pos.duplicate(), "heading": PI,
        "memory": 0.0, "alert_left": 0.0, "attack_cd": 0.0, "windup": 0.0, "attack_door":"",
        "last_noise": 0, "patrol_left": 0.0, "patrol_index": 0, "had_target": false}

func restore(candidate: Dictionary) -> void:
    state = candidate.duplicate(true)
    Firearms.ensure(self)
    GroundDrops.ensure(self)
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
    if state.schema == 4:
        add_base_state()
        event("migrated", "据点工事与制作已接入；原有门耐久与物资完整保留。", "平静")
    # A street snapshot or a pre-villa save can already be at the current schema yet
    # know nothing about the authored works, so the flags are filled on presence
    # rather than on the version number alone.
    var missing_sites: bool = not state.get("base_works") is Dictionary \
        or state.base_works.size() < sites().size()
    if state.schema == 5 or missing_sites:
        add_site_state()
        event("migrated", "别墅院子门、大门与泳池供水已接入；原有进度保留。", "平静")
    for zombie in state.zombies:
        if not zombie.has("appearance"):
            zombie.appearance="civilian"
    expand_world_state()
    DoorDamage.ensure(self)

func noise(pos: Vector3, radius: float, kind: String) -> void:
    state.noise_sequence += 1
    state.noises.append({"id": state.noise_sequence, "position": [pos.x, pos.y, pos.z],
        "radius": radius, "ttl": rules.noise.ttl, "kind": kind})

func tick_combat(delta: float) -> void:
    Firearms.tick(self,delta)
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
    Firearms.ensure(self)
    if state.firearms.reload_left>0:
        return false
    if weapon.get("ammo","")!="":
        if Firearms.loaded(self)<=0:
            return false
    if state.stats.stamina < weapon.stamina:
        return false
    state.stats.stamina -= weapon.stamina
    if weapon.get("ammo","")!="":
        state.firearms.loaded-=1
        event("fired","手枪射击，消耗1发9毫米弹药。","紧张",{"item":"pistol","rounds":1,"remaining":state.firearms.loaded})
    state.combat.attack_cd = weapon.cooldown
    return true

func damage_zombie(zombie: Dictionary, amount: float) -> bool:
    if zombie.health <= 0 or amount <= 0:
        return false
    zombie.health = maxf(0, zombie.health - amount)
    if zombie.health == 0:
        zombie.mode = "dead"
        zombie.windup = 0.0
        zombie.attack_door = ""
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
        if not Appearance.definitions().has(z.get("appearance","civilian")):
            return false
        var attack_door: Variant=z.get("attack_door","")
        if not attack_door is String or (attack_door!="" and (not candidate.doors.has(attack_door) or not number(z.get("windup"),0.0000001,rules.zombie.attack_windup))):
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
    refresh_pool()

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

func valid_craft(candidate: Dictionary) -> bool:
    if not candidate.get("craft") is Dictionary or not candidate.get("door_level") is Dictionary:
        return false
    var craft: Dictionary = candidate.craft
    if not craft.get("active") is bool or not craft.get("recipe") is String or not craft.get("door") is String:
        return false
    if not craft.get("spent") is Dictionary or not valid_items(craft.spent):
        return false
    for id in candidate.door_level:
        if not candidate.doors.has(id) or not integer(candidate.door_level[id], 0, DoorDamage.limit(self)):
            return false
    if craft.active:
        var entry: Dictionary = Crafting.recipe(craft.recipe)
        if entry.is_empty() or not number(craft.get("minutes_left"), 0.0000001, float(entry.minutes)):
            return false
        if str(entry.get("target", "item")) == "door" and not candidate.doors.has(craft.door):
            return false
    elif craft.recipe != "" or craft.door != "" or float(craft.get("minutes_left", 0.0)) != 0.0 or not craft.spent.is_empty():
        return false
    return true

## Site flags and the daily water counter are part of the save contract: a gate that
## is recorded as installed must own a door, and a gate that is not installed must
## not leave a stale entrance behind.
func valid_sites(candidate: Dictionary) -> bool:
    var works: Variant = candidate.get("base_works")
    var pool: Variant = candidate.get("pool")
    if not works is Dictionary or not pool is Dictionary:
        return false
    for id in works:
        if site(str(id)).is_empty() or not works[id] is bool:
            return false
    for definition in sites():
        var id := str(definition.id)
        if int(definition.get("introduced_revision", 0)) > int(candidate.get("world_revision", 0)):
            continue
        if not works.has(id):
            return false
        if str(definition.get("kind", "")) != "gate":
            continue
        if bool(works[id]):
            if not candidate.doors.has(id) or not candidate.doors[id] is bool:
                return false
            if not candidate.door_health.has(id) or not candidate.door_level.has(id):
                return false
        elif candidate.doors.has(id):
            return false
    if not integer(pool.get("day"), 1, 1000000) or not integer(pool.get("left"), 0, maxi(1, pool_capacity())):
        return false
    return true

## A claimable shelter is a place, not a door: the street houses come from the
## building list, and the connected model appends its authored interiors.
func zones() -> Array:
    var result: Array = []
    var room: Dictionary = rules.room
    var half: float = float(room.inner_half_width)
    for building in rules.buildings:
        var min_z: float = -float(building.depth) + 0.25 if building.has("depth") else float(room.min_z)
        result.append({"id": str(building.id), "name": str(building.name),
            "rect": Rect2(float(building.x) - half, min_z, half * 2.0, float(room.max_z) - min_z),
            "min_y": -0.5, "max_y": 0.5})
    return result

func base_at(position: Vector3) -> String:
    for zone in zones():
        var rect: Rect2 = zone.rect
        if rect.has_point(Vector2(position.x, position.z)) and position.y > float(zone.min_y) and position.y < float(zone.max_y):
            return str(zone.id)
    return ""

func base_name(id: String) -> String:
    for zone in zones():
        if str(zone.id) == id:
            return str(zone.name)
    return building_name(id)

func base_id() -> String:
    return str(state.get("base", "home"))

func set_base(id: String) -> bool:
    for zone in zones():
        if str(zone.id) == id:
            state.base = id
            event("base_set", "把" + base_name(id) + "设为据点。", "希望", {"building": id})
            return true
    return false

func in_base() -> bool:
    if not state.has("position"): return false
    return base_at(Vector3(state.position[0], state.position[1], state.position[2])) == base_id()
