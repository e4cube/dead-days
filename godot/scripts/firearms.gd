extends RefCounted
## Finite ammunition ledger. Reload moves existing rounds; it never creates them.
static func ensure(model) -> void:
    if not model.state.has("firearms"):
        model.state.firearms={"loaded":0,"reload_left":0.0}

static func valid(model, candidate: Dictionary) -> bool:
    if not candidate.has("firearms"):
        return true # Historical snapshots migrate in memory, without replenishing loot.
    var f: Variant=candidate.firearms
    if not f is Dictionary or not model.integer(f.get("loaded"),0,model.rules.weapons.pistol.magazine):
        return false
    if not model.number(f.get("reload_left"),0,model.rules.weapons.pistol.reload_seconds):
        return false
    return (f.loaded==0 or candidate.inventory.get("pistol",0)>0) and (f.reload_left==0 or candidate.get("combat",{}).get("equipped","")=="pistol")

static func loaded(model) -> int:
    return int(model.state.get("firearms",{}).get("loaded",0))

static func extra_weight(model, candidate: Dictionary) -> float:
    return float(candidate.get("firearms",{}).get("loaded",0))*model.rules.items.ammo_9mm.weight

static func begin_reload(model) -> bool:
    ensure(model)
    if model.state.combat.equipped!="pistol" or model.state.stats.health<=0 or model.state.rest.active or model.state.combat.attack_cd>0:
        return false
    if model.state.firearms.reload_left>0 or loaded(model)>=int(model.rules.weapons.pistol.magazine) or model.state.inventory.get("ammo_9mm",0)<=0:
        return false
    model.state.firearms.reload_left=model.rules.weapons.pistol.reload_seconds
    return true

static func tick(model, delta: float) -> void:
    ensure(model)
    if model.state.combat.equipped!="pistol" or model.state.stats.health<=0 or model.state.rest.active:
        model.state.firearms.reload_left=0.0
        return
    if model.state.firearms.reload_left<=0:
        return
    model.state.firearms.reload_left=maxf(0,model.state.firearms.reload_left-delta)
    if model.state.firearms.reload_left==0:
        var n: int=mini(int(model.rules.weapons.pistol.magazine)-loaded(model),int(model.state.inventory.get("ammo_9mm",0)))
        if n>0:
            model.state.inventory.ammo_9mm-=n
            model.state.firearms.loaded+=n
            model.event("reloaded","手枪装填了%d发9毫米弹药。"%n,"紧张",{"item":"pistol","rounds":n})

static func unload(model) -> bool:
    ensure(model)
    if model.state.combat.equipped!="pistol" or model.state.stats.health<=0 or model.state.rest.active or model.state.firearms.reload_left>0 or loaded(model)==0:
        return false
    var n:=loaded(model)
    if model.state.inventory.get("ammo_9mm",0)+n>10000:
        return false
    model.state.inventory.ammo_9mm=model.state.inventory.get("ammo_9mm",0)+n
    model.state.firearms.loaded=0
    model.event("unloaded","卸下手枪中的%d发弹药。"%n,"平静",{"rounds":n})
    return true
