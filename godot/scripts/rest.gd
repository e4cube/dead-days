extends RefCounted
const Timeline = preload("res://scripts/survival_time.gd")

static func empty() -> Dictionary:
    return {"active": false, "kind": "", "bed": "", "start": 0.0, "target": 0.0}

static func bed(model: RefCounted, id: String) -> Dictionary:
    for definition in model.rules.beds:
        if definition.id == id:
            return definition
    return {}

static func bed_position(model: RefCounted, definition: Dictionary) -> Vector3:
    for building in model.rules.buildings:
        if building.id == definition.building:
            return Vector3(building.x + definition.offset[0], 0, definition.offset[2])
    return Vector3.INF

static func reason(model: RefCounted, id: String) -> String:
    if model.state.stats.health <= 0:
        return "身体状况无法继续休息"
    var definition := bed(model, id)
    if definition.is_empty():
        return "附近没有可用的床"
    var player := Vector3(model.state.position[0], 0, model.state.position[2])
    var position := bed_position(model, definition)
    if player.distance_to(position) > float(definition.use_radius):
        return "需要靠近室内的床"
    if not inside(model, definition.building, Vector3(model.state.position[0], model.state.position[1], model.state.position[2])):
        return "必须进入室内，不能隔墙休息"
    if model.state.doors[definition.building]:
        return "先关上房门再休息"
    var radius: float = model.rules.rest.danger_radius
    for zombie in model.state.zombies:
        if zombie.health <= 0:
            continue
        var at := Vector3(zombie.position[0], 0, zombie.position[2])
        var target := Vector3(zombie.target[0], 0, zombie.target[2])
        if at.distance_to(player) <= radius or (zombie.mode in ["alert", "chase", "search"] and target.distance_to(player) <= radius):
            return "附近有僵尸或追击尚未结束"
    return ""

static func begin(model: RefCounted, id: String, kind: String) -> String:
    if model.state.rest.active:
        return "已经在休息"
    var blocked := reason(model, id)
    if not blocked.is_empty():
        return blocked
    if kind not in ["hour", "night"]:
        return "未知休息方式"
    var now := Timeline.absolute(model)
    var duration: float = model.rules.rest.hour_minutes
    if kind == "night":
        if model.state.minutes >= model.rules.time.dawn and model.state.minutes < model.rules.rest.night_start:
            return "尚未到夜间；可在床边按R休息一小时"
        duration = fposmod(float(model.rules.time.dawn) - float(model.state.minutes), 1440.0)
    model.state.rest = {"active": true, "kind": kind, "bed": id, "start": now, "target": now + duration}
    model.event("rest_started", "躺下睡到黎明。" if kind == "night" else "躺下休息一小时。", "疲惫", {"kind": kind, "bed": id, "planned_minutes": duration})
    return ""

static func cancel(model: RefCounted, blocked: String, danger: bool = false) -> void:
    if not model.state.rest.active:
        return
    var rest: Dictionary = model.state.rest.duplicate(true)
    model.state.rest = empty()
    model.event("sleep_danger" if danger else "rest_interrupted", "休息被危险打断：" + blocked if danger else "结束休息：" + blocked, "恐惧" if danger else "疲惫", {"kind": rest.kind, "minutes": maxf(0, Timeline.absolute(model) - float(rest.start)), "reason": blocked})

static func finish(model: RefCounted) -> void:
    var rest: Dictionary = model.state.rest.duplicate(true)
    model.state.rest = empty()
    model.event("rest_finished", "在安全室内睡到了黎明。" if rest.kind == "night" else "一小时休息结束。", "希望", {"kind": rest.kind, "minutes": Timeline.absolute(model) - float(rest.start)})


static func inside(model: RefCounted, id: String, position: Vector3) -> bool:
    var room: Dictionary = model.rules.room
    for building in model.rules.buildings:
        if building.id == id:
            var min_z: float = -float(building.depth)+0.25 if building.has("depth") else float(room.min_z)
            return absf(position.x - float(building.x)) < float(room.inner_half_width) and position.z > min_z and position.z < float(room.max_z) and absf(position.y) < 0.5
    return false
