extends RefCounted
## Door durability plus the two base-building actions that touch it.
##
## Base health comes from rules.door_damage.health; every reinforcement layer adds
## rules.door_build.reinforce_step to that door's own ceiling. The ceiling is per
## door, so a reinforced entrance stays reinforced after a reload while untouched
## houses keep the base value.
static func ensure(model):
    if not model.state.has("door_health"): model.state.door_health={}
    if not model.state.has("door_level"): model.state.door_level={}
    for id in model.state.doors:
        if not model.state.door_health.has(id): model.state.door_health[id]=float(model.rules.door_damage.health)
        if not model.state.door_level.has(id): model.state.door_level[id]=0
static func limit(model) -> int:
    return int(model.rules.get("door_build",{}).get("reinforce_limit",2))
static func step(model) -> float:
    return float(model.rules.get("door_build",{}).get("reinforce_step",50.0))
static func level(model,id: String) -> int:
    return int(model.state.get("door_level",{}).get(id,0))
static func max_health(model,id: String) -> float:
    return float(model.rules.door_damage.health)+float(level(model,id))*step(model)
static func health(model,id: String) -> float:
    return float(model.state.get("door_health",{}).get(id,max_health(model,id)))
static func valid(model,candidate: Dictionary) -> bool:
    if not candidate.has("door_health"): return true
    if not candidate.door_health is Dictionary or candidate.door_health.size()!=candidate.doors.size(): return false
    var levels: Variant=candidate.get("door_level",{})
    if not levels is Dictionary: return false
    for id in candidate.door_health:
        if not candidate.doors.has(id): return false
        var reinforcement: int=int(levels.get(id,0))
        if reinforcement<0 or reinforcement>limit(model): return false
        var ceiling: float=float(model.rules.door_damage.health)+float(reinforcement)*step(model)
        if not model.number(candidate.door_health[id],0,ceiling): return false
        if candidate.door_health[id]==0 and candidate.doors[id]!=true: return false
    for id in levels:
        if not candidate.doors.has(id): return false
    return true
static func broken(model,id: String) -> bool:
    return health(model,id)<=0
static func hit(model,id: String,amount: float,attacker: String) -> bool:
    ensure(model)
    if not model.state.doors.has(id) or model.state.doors[id] or broken(model,id) or amount<=0 or not is_finite(amount): return false
    model.state.door_health[id]=maxf(0,health(model,id)-amount)
    model.event("door_hit","僵尸撞击"+model.building_name(id)+"的门，耐久 %.0f/%.0f。"%[health(model,id),max_health(model,id)],"紧张",{"building":id,"attacker":attacker,"remaining":health(model,id)})
    if broken(model,id):
        model.state.doors[id]=true
        model.event("door_broken",model.building_name(id)+"的门被撞坏，入口已失守。","恐惧",{"building":id,"attacker":attacker})
    return true
## Puts the panel back and restores the current ceiling. A breached door stays
## open afterwards: the player still has to close it, so repair never grants a
## free safe room while a zombie is standing in the doorway.
static func repair(model,id: String) -> bool:
    ensure(model)
    if not model.state.doors.has(id): return false
    var ceiling := max_health(model,id)
    var before := health(model,id)
    if before>=ceiling-0.001: return false
    model.state.door_health[id]=ceiling
    var rebuilt := before<=0
    model.event("door_repaired",("重新装好了"+model.building_name(id)+"的门，耐久 %.0f/%.0f。" if rebuilt else "修补了"+model.building_name(id)+"的门，耐久 %.0f/%.0f。")%[ceiling,ceiling],"希望",{"building":id,"remaining":ceiling,"max":ceiling,"rebuilt":rebuilt})
    return true
## Adds one layer of boards and strap iron. The current hit points grow with the
## new ceiling instead of being refilled, so reinforcement is not a cheap repair.
static func reinforce(model,id: String) -> bool:
    ensure(model)
    if not model.state.doors.has(id) or broken(model,id): return false
    var current := level(model,id)
    if current>=limit(model): return false
    var before := health(model,id)
    model.state.door_level[id]=current+1
    var ceiling := max_health(model,id)
    model.state.door_health[id]=minf(ceiling,before+step(model))
    model.event("door_reinforced","给"+model.building_name(id)+"的门加了第%d层加固，耐久上限 %.0f。"%[current+1,ceiling],"希望",{"building":id,"level":current+1,"remaining":model.state.door_health[id],"max":ceiling})
    return true
