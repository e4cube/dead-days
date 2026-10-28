extends RefCounted
static func ensure(model):
    if not model.state.has("door_health"): model.state.door_health={}
    for id in model.state.doors:
        if not model.state.door_health.has(id): model.state.door_health[id]=float(model.rules.door_damage.health)
static func valid(model,candidate: Dictionary) -> bool:
    if not candidate.has("door_health"): return true
    if not candidate.door_health is Dictionary or candidate.door_health.size()!=candidate.doors.size(): return false
    for id in candidate.door_health:
        if not candidate.doors.has(id) or not model.number(candidate.door_health[id],0,model.rules.door_damage.health): return false
        if candidate.door_health[id]==0 and candidate.doors[id]!=true: return false
    return true
static func broken(model,id: String) -> bool:
    return model.state.get("door_health",{}).get(id,1)<=0
static func hit(model,id: String,amount: float,attacker: String) -> bool:
    ensure(model)
    if not model.state.doors.has(id) or model.state.doors[id] or broken(model,id) or amount<=0 or not is_finite(amount): return false
    model.state.door_health[id]=maxf(0,float(model.state.door_health[id])-amount)
    model.event("door_hit","僵尸撞击"+model.building_name(id)+"的门，耐久 %.0f/%.0f。"%[model.state.door_health[id],model.rules.door_damage.health],"紧张",{"building":id,"attacker":attacker,"remaining":model.state.door_health[id]})
    if broken(model,id):
        model.state.doors[id]=true
        model.event("door_broken",model.building_name(id)+"的门被撞坏，入口已失守。","恐惧",{"building":id,"attacker":attacker})
    return true
